import Foundation
import Observation

/// The switch lifecycle as a PURE reducer — ccsbar's `SwitchMachine`,
/// verbatim — so every path (arm-confirm, refusal, accepted-then-dropped,
/// socket-observed confirm, CLI-exit confirm) is a table test with no daemon.
enum ClauthSwitchMachine {
    enum Phase: Equatable, Sendable {
        case idle
        /// Awaiting the user's confirm: the CURRENT account has a live
        /// session that the switch would log out.
        case arming(target: String)
        /// Accepted by the daemon; awaiting its next tick to LAND it —
        /// confirmed by observing the harness's OWN active slot.
        case pending(target: String)
        /// `viaCLI`: the daemon was dead and `clauth` did it.
        case confirmed(target: String, viaCLI: Bool)
        case failed(reason: String)

        var isBusy: Bool {
            switch self {
            case .arming, .pending: true
            case .idle, .confirmed, .failed: false
            }
        }

        var inFlightTarget: String? {
            switch self {
            case .arming(let target), .pending(let target): target
            default: nil
            }
        }
    }

    enum Event: Equatable, Sendable {
        case requestSwitch(target: String, currentHasLiveSession: Bool)
        case confirmArm
        case cancel
        case dispatched(ClauthDaemonClient.SwitchDispatch)
        case observedActive(String?)
        case armTimedOut
        case pendingTimedOut
        case dismiss
    }

    /// The most a pending switch may wait in total while the daemon's own
    /// queue still holds the target — under its 120s TTL, past a slow first
    /// usage fetch.
    static let pendingHardCeiling: TimeInterval = 30

    /// At a pending deadline: keep waiting while the daemon still holds this
    /// target (`pending_switch`) and the ceiling is not reached.
    static func shouldExtendPending(daemonPending: String?, target: String, elapsed: TimeInterval) -> Bool {
        daemonPending == target && elapsed < pendingHardCeiling
    }

    static func reduce(_ phase: Phase, _ event: Event) -> Phase {
        switch event {
        case .requestSwitch(let target, let live):
            if case .pending = phase { return phase }
            return live ? .arming(target: target) : .pending(target: target)
        case .confirmArm:
            if case .arming(let target) = phase { return .pending(target: target) }
            return phase
        case .cancel:
            return .idle
        case .dispatched(let dispatch):
            guard case .pending(let target) = phase else { return phase }
            switch dispatch {
            case .accepted: return phase
            case .confirmedByCLI: return .confirmed(target: target, viaCLI: true)
            case .refused(_, let message): return .failed(reason: message)
            case .unreachable: return .failed(reason: "clauth daemon not reachable — is it running?")
            }
        case .observedActive(let active):
            if case .pending(let target) = phase, active == target {
                return .confirmed(target: target, viaCLI: false)
            }
            return phase
        case .armTimedOut:
            if case .arming = phase { return .idle }
            return phase
        case .pendingTimedOut:
            if case .pending = phase { return .failed(reason: "the switch didn’t take — the daemon may be busy") }
            return phase
        case .dismiss:
            switch phase {
            case .confirmed, .failed: return .idle
            default: return phase
            }
        }
    }
}

/// The effects half — ccsbar's `StatusModelSwitch`: dispatch off the main
/// actor, the arm and pending timers, and the observe ladder over the
/// watcher's feed. Harness-aware: a codex switch is confirmed by
/// `active_codex_profile`, never `active_profile`.
@MainActor
@Observable
final class ClauthSwitchController {
    struct Timing: Sendable {
        var arm: Double = 5
        var pending: Double = 6
        var observe: [Double] = [0.5, 0.7, 1.0, 1.3, 1.6]
        var extend: Double = 2
        var dismissConfirmed: Double = 2
        var dismissFailed: Double = 6
    }

    private(set) var phase: ClauthSwitchMachine.Phase = .idle
    private(set) var harness: ClauthHarness = .claude
    /// Presents the live-session confirm: `(target, current)` — it is the
    /// CURRENT account's session the switch would log out. Nil (tests) lets
    /// the arm time out; the app installs an `NSAlert`.
    var onArm: ((_ target: String, _ current: String?) -> Void)?

    weak var watcher: ClauthWatcher?
    private let client: ClauthDaemonClient
    private let timing: Timing
    private let cli: @Sendable (String) async -> ClauthOutcome
    private var pendingSince: Date?
    private var armTimeout: Task<Void, Never>?
    private var pendingTimeout: Task<Void, Never>?
    private var observeTask: Task<Void, Never>?
    private var dispatchTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?

    init(
        client: ClauthDaemonClient,
        timing: Timing = Timing(),
        cli: @escaping @Sendable (String) async -> ClauthOutcome = { name in
            switch await ClauthCLI.run(program: ClauthCLI.clauth, arguments: ClauthCLI.switchArgs(name)) {
            case .ok: .ok
            case .failed(let status, let stderr): .daemonError(code: "cli_failed", message: ClauthCLI.failureReason(stderr: stderr, exitStatus: status, verb: "switch"))
            case .couldNotStart(let message): .daemonError(code: "cli_failed", message: "could not run clauth: \(message)")
            case .unavailable: .unreachable
            }
        }
    ) {
        self.client = client
        self.timing = timing
        self.cli = cli
    }

    var inFlightTarget: String? { phase.inFlightTarget }

    /// Begin a switch. The target's own harness decides which slot the
    /// confirm ladder watches; a claude switch arms when the CURRENT claude
    /// account has a live session (codex sessions are isolated — nothing to
    /// protect, straight to pending).
    func switchTo(_ name: String) {
        if case .pending = phase { return }
        let status = watcher?.status
        let target = status?.profile(named: name)
        harness = target?.harness ?? .claude
        let current = status?.activeName(for: .claude).flatMap { status?.profile(named: $0) }
        let live = harness == .claude && (current?.hasLiveSession ?? false)
        dispatch(.requestSwitch(target: name, currentHasLiveSession: live))
    }

    /// The user confirmed the live-session alert. If the arm already timed
    /// out while the alert was up, the confirm still counts — the question
    /// was answered.
    func confirmArmedSwitch(_ name: String) {
        if case .arming(let target) = phase, target == name {
            dispatch(.confirmArm)
        } else if case .idle = phase {
            dispatch(.requestSwitch(target: name, currentHasLiveSession: false))
        }
    }

    func cancel() { dispatch(.cancel) }
    func dismiss() { dispatch(.dismiss) }

    /// The watcher's feed landed: observe the harness's own active slot.
    func observed(_ status: ClauthStatus?) {
        guard case .pending = phase else { return }
        dispatch(.observedActive(status?.activeName(for: harness)))
    }

    func dispatch(_ event: ClauthSwitchMachine.Event) {
        let before = phase
        let after = ClauthSwitchMachine.reduce(before, event)
        guard after != before else { return }
        phase = after
        enter(after)
    }

    private func enter(_ phase: ClauthSwitchMachine.Phase) {
        switch phase {
        case .idle:
            cancelTimers()
        case .arming(let target):
            armTimeout?.cancel()
            armTimeout = after(timing.arm) { $0.dispatch(.armTimedOut) }
            onArm?(target, watcher?.status?.activeName(for: harness))
        case .pending(let target):
            armTimeout?.cancel()
            fire(target)
            observe(target)
            pendingSince = Date()
            armPendingDeadline(target, in: timing.pending)
        case .confirmed:
            cancelTimers(keepDismiss: true)
            dismissTask?.cancel()
            dismissTask = after(timing.dismissConfirmed) { $0.dispatch(.dismiss) }
        case .failed:
            cancelTimers(keepDismiss: true)
            dismissTask?.cancel()
            dismissTask = after(timing.dismissFailed) { $0.dispatch(.dismiss) }
        }
    }

    private func armPendingDeadline(_ target: String, in seconds: Double) {
        pendingTimeout?.cancel()
        pendingTimeout = after(seconds) { controller in
            controller.watcher?.reload()
            controller.dispatch(.observedActive(controller.watcher?.status?.activeName(for: controller.harness)))
            guard case .pending = controller.phase else { return }
            let elapsed = Date().timeIntervalSince(controller.pendingSince ?? .distantPast)
            if ClauthSwitchMachine.shouldExtendPending(
                daemonPending: controller.watcher?.status?.pendingSwitch, target: target, elapsed: elapsed
            ) {
                controller.armPendingDeadline(target, in: controller.timing.extend)
                return
            }
            controller.dispatch(.pendingTimedOut)
        }
    }

    private func fire(_ target: String) {
        dispatchTask?.cancel()
        let client = client, cli = cli
        dispatchTask = Task { [weak self] in
            let dispatch = await Task.detached { await client.switchTo(target, cli: { await cli(target) }) }.value
            guard let self, !Task.isCancelled else { return }
            self.dispatch(.dispatched(dispatch))
        }
    }

    /// Re-read the feed on a backoff ladder so a socket-accepted switch
    /// confirms as soon as the daemon's tick lands it.
    private func observe(_ target: String) {
        observeTask?.cancel()
        let steps = timing.observe
        observeTask = Task { [weak self] in
            for sleep in steps {
                try? await Task.sleep(for: .seconds(sleep))
                guard let self, !Task.isCancelled else { return }
                self.watcher?.reload()
                self.dispatch(.observedActive(self.watcher?.status?.activeName(for: self.harness)))
                if case .pending = self.phase {} else { return }
            }
        }
    }

    private func after(_ seconds: Double, _ body: @escaping @MainActor (ClauthSwitchController) -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            body(self)
        }
    }

    private func cancelTimers(keepDismiss: Bool = false) {
        dispatchTask?.cancel()
        observeTask?.cancel()
        armTimeout?.cancel()
        pendingTimeout?.cancel()
        if !keepDismiss { dismissTask?.cancel() }
    }
}
