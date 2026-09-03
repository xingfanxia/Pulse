import Foundation
import Observation

/// The CLI- and socket-backed verbs behind the ring menu and (CLP-3) the
/// pane: re-authenticate, rename, refresh. Errors are loud — the last one is
/// shown on the card until it clears.
@MainActor
@Observable
final class ClauthActions {
    enum LoginMode: Equatable, Sendable {
        /// The browser OAuth / PKCE flow.
        case browser
        /// Codex only: copy the live `~/.codex` login into the profile.
        case capture
    }

    struct LoginFlight: Equatable, Sendable {
        let name: String
        let codex: Bool
        let mode: LoginMode

        var message: String {
            mode == .capture
                ? String.localized("Capturing the current Codex login into \(name)…")
                : String.localized("Signing in to \(name) — finish in your browser…")
        }
    }

    typealias Runner = @Sendable (_ program: String, _ arguments: [String], _ stdin: String?) async -> ClauthCLI.Outcome

    private(set) var loginInFlight: LoginFlight?
    private(set) var lastError: String?
    weak var watcher: ClauthWatcher?

    private let client: ClauthDaemonClient
    private let run: Runner
    private var errorClear: Task<Void, Never>?

    init(
        client: ClauthDaemonClient,
        run: @escaping Runner = { await ClauthCLI.run(program: $0, arguments: $1, stdin: $2) }
    ) {
        self.client = client
        self.run = run
    }

    /// `clauth login <name>` re-authenticates an existing profile. One login
    /// at a time; on success the feed is nudged so status.json reflects the
    /// cleared `auth_status` promptly.
    func reauth(_ name: String, codex: Bool, mode: LoginMode = .browser) {
        guard loginInFlight == nil else { return }
        let flight = LoginFlight(name: name, codex: codex, mode: codex ? mode : .browser)
        loginInFlight = flight
        clearError()
        let arguments = ClauthCLI.loginArgs(name, newOnly: false, codex: codex, browser: flight.mode == .browser)
        let run = run
        Task { [weak self] in
            let outcome = await run(ClauthCLI.clauth, arguments, nil)
            guard let self else { return }
            self.loginInFlight = nil
            if let message = Self.loginFailureMessage(outcome, name: name) {
                self.showError(message)
            } else {
                self.refresh(name)
            }
        }
    }

    /// Rename over the socket; the daemon validates and re-links.
    func rename(_ old: String, to new: String) {
        let existing = watcher?.status?.profiles.map(\.name) ?? []
        if let problem = Self.renameValidationError(new, old: old, existing: existing) {
            showError(problem)
            return
        }
        send(.rename(profile: old, to: new))
    }

    /// The daemon `refresh` verb; a missed one is harmless (the daemon
    /// refreshes on its own cadence), so unreachable is not an error here.
    func refresh(_ name: String?) {
        let client = client
        Task { [weak self] in
            let outcome = await Task.detached { client.send(.refresh(profile: name)) }.value
            guard let self else { return }
            if case .daemonError(_, let message) = outcome { self.showError(message) }
            self.watcher?.reload()
        }
    }

    /// Any other verb: sent off the main actor, then the feed re-read on a
    /// short ladder until `generated_at` advances and the change actually
    /// holds — without the predicate the first unrelated tick would stop it.
    func send(_ command: ClauthCommand, expecting predicate: (@Sendable (ClauthStatus) -> Bool)? = nil) {
        let client = client
        configInFlight += 1
        // Serialised: two edits to one chain must reach the daemon in the
        // order they were clicked (move up, then set the threshold of the
        // row that moved), and the socket serves one line per connection.
        let previous = lastSend
        lastSend = Task { [weak self] in
            await previous?.value
            let outcome = await Task.detached { client.send(command) }.value
            guard let self else { return }
            self.configInFlight = max(0, self.configInFlight - 1)
            if let message = outcome.errorMessage {
                self.showError(message)
                return
            }
            self.settle(expecting: predicate)
        }
    }

    /// Commands in flight, for a shimmer on the pane.
    private(set) var configInFlight = 0
    private(set) var deleteInFlight: String?
    private var settleTask: Task<Void, Never>?
    private var lastSend: Task<Void, Never>?

    private func settle(expecting predicate: (@Sendable (ClauthStatus) -> Bool)?) {
        let baseline = watcher?.status?.generatedAt
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            for sleep in [0.15, 0.2, 0.25, 0.35, 0.5, 0.7, 1.0, 1.3] {
                try? await Task.sleep(for: .seconds(sleep))
                guard let self, !Task.isCancelled else { return }
                self.watcher?.reload()
                if let status = self.watcher?.status, status.generatedAt != baseline, predicate?(status) ?? true { return }
            }
        }
    }

    // MARK: Chain edits — the ten socket verbs

    func fallbackAdd(_ name: String) {
        send(.fallbackAdd(profile: name), expecting: { $0.profile(named: name)?.fallback != nil })
    }

    func fallbackRemove(_ name: String) {
        send(.fallbackRemove(profile: name), expecting: { $0.profile(named: name)?.fallback == nil })
    }

    func fallbackMove(_ name: String, up: Bool) {
        send(.fallbackMove(profile: name, up: up))
    }

    func setThreshold(_ name: String, _ value: Int) {
        send(.setThreshold(profile: name, value: value), expecting: { $0.profile(named: name)?.fallback?.threshold == Double(value) })
    }

    func setLastResort(_ name: String, _ on: Bool) {
        send(.setLastResort(profile: name, value: on), expecting: { $0.profile(named: name)?.fallback?.lastResort == on })
    }

    /// `nil` clears the override (an explicit JSON null on the wire).
    func setMemberWeekly(_ name: String, _ value: Double?) {
        send(.setMemberWeekly(profile: name, value: value), expecting: { $0.profile(named: name)?.fallback?.weeklyThreshold == value })
    }

    func setCheckWeekly(_ name: String, _ on: Bool) {
        send(.setCheckWeekly(profile: name, value: on), expecting: { $0.profile(named: name)?.fallback?.checkWeekly == on })
    }

    func setCheckScoped(_ name: String, _ on: Bool) {
        send(.setCheckScoped(profile: name, value: on), expecting: { $0.profile(named: name)?.fallback?.checkScoped == on })
    }

    func setWrapOff(_ on: Bool) {
        send(.setWrapOff(value: on), expecting: { $0.wrapOff == on })
    }

    func setWeeklyThreshold(_ value: Double) {
        send(.setWeeklyThreshold(value: value), expecting: { $0.weeklySwitchThreshold == value })
    }

    // MARK: Accounts — CLI verbs through the one spawn door

    /// `clauth login --new <name> [--codex [--browser]]`: creates the profile;
    /// `--new` is the race-proof collision guard.
    func addAccount(_ name: String, codex: Bool, mode: LoginMode = .browser) {
        guard loginInFlight == nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let problem = ClauthNameValidation.error(trimmed, existing: watcher?.status?.profiles.map(\.name) ?? []) {
            showError(problem)
            return
        }
        let flight = LoginFlight(name: trimmed, codex: codex, mode: codex ? mode : .browser)
        loginInFlight = flight
        clearError()
        let arguments = ClauthCLI.loginArgs(trimmed, newOnly: true, codex: codex, browser: flight.mode == .browser)
        let run = run
        Task { [weak self] in
            let outcome = await run(ClauthCLI.clauth, arguments, nil)
            guard let self else { return }
            self.loginInFlight = nil
            if let message = Self.loginFailureMessage(outcome, name: trimmed) {
                self.showError(message)
            } else {
                self.refresh(nil)
            }
        }
    }

    /// Pipes a pasted `claude setup-token` mint into
    /// `clauth login <name> --setup-token --yes` — stdin only, never argv.
    func installSetupToken(_ name: String, token: String) {
        guard loginInFlight == nil else { return }
        guard let trimmed = ClauthSetupToken.trimmed(token) else {
            showError(String.localized("That paste doesn’t look like a claude setup-token mint."))
            return
        }
        loginInFlight = LoginFlight(name: name, codex: false, mode: .browser)
        clearError()
        let run = run
        Task { [weak self] in
            let outcome = await run(ClauthCLI.clauth, ClauthCLI.setupTokenArgs(name), trimmed)
            guard let self else { return }
            self.loginInFlight = nil
            if let message = Self.loginFailureMessage(outcome, name: name) {
                self.showError(message)
            } else {
                self.refresh(name)
            }
        }
    }

    /// `clauth feed <name> on|off` — the rolling-token flag on the deployed
    /// daemon (upstream's later spelling is `rolling-token`).
    func setFeed(_ name: String, on: Bool) {
        let run = run
        Task { [weak self] in
            let outcome = await run(ClauthCLI.clauth, ClauthCLI.feedArgs(name, on: on), nil)
            guard let self else { return }
            if let message = Self.loginFailureMessage(outcome, name: name) {
                self.showError(message)
            } else {
                self.refresh(name)
            }
        }
    }

    /// `clauth delete <name> --yes` — CLI only, never `--force`; the caller
    /// has already shown the consequence-aware confirm.
    func delete(_ name: String) {
        guard deleteInFlight == nil, loginInFlight == nil else { return }
        guard watcher?.status?.profile(named: name) != nil else { return }
        deleteInFlight = name
        clearError()
        let run = run
        Task { [weak self] in
            let outcome = await run(ClauthCLI.clauth, ClauthCLI.deleteArgs(name), nil)
            guard let self else { return }
            self.deleteInFlight = nil
            switch outcome {
            case .ok: self.refresh(nil)
            case .failed(let status, let stderr): self.showError(ClauthCLI.failureReason(stderr: stderr, exitStatus: status, verb: "delete"))
            case .couldNotStart(let message): self.showError("could not run clauth: \(message)")
            case .unavailable(let refusal): self.showError(refusal.message)
            }
        }
    }

    /// Proxy mode: the config.toml edit, then `launchctl bootstrap` through
    /// the spawn door when switching ON.
    func setProxyRouting(_ on: Bool) async -> String? {
        do {
            try ClauthProxyMode.apply(on: on)
        } catch {
            let message = String.localized("config.toml edit failed: \(error.localizedDescription)")
            showError(message)
            return message
        }
        if on { _ = await ClauthProxyMode.ensureProxyLoaded() }
        return nil
    }

    func showError(_ message: String) {
        lastError = message
        errorClear?.cancel()
        errorClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.lastError = nil
        }
    }

    func clearError() {
        errorClear?.cancel()
        lastError = nil
    }

    static func loginFailureMessage(_ outcome: ClauthCLI.Outcome, name: String) -> String? {
        switch outcome {
        case .ok: nil
        case .failed(let status, let stderr): ClauthCLI.failureReason(stderr: stderr, exitStatus: status, verb: "login")
        case .couldNotStart(let message): "could not run clauth: \(message)"
        case .unavailable(let refusal): refusal.message
        }
    }

    /// The daemon is authoritative; this catches the obvious before a round
    /// trip. Nil means "send it".
    static func renameValidationError(_ new: String, old: String, existing: [String]) -> String? {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return String.localized("Enter a name.") }
        if trimmed == old { return String.localized("That is already its name.") }
        if trimmed.contains(where: { $0.isWhitespace || $0 == "/" }) {
            return String.localized("Names can’t contain spaces or slashes.")
        }
        if existing.contains(trimmed) { return String.localized("\(trimmed) already exists.") }
        return nil
    }
}
