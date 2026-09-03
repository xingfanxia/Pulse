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

    /// Any other verb: sent off the main actor, the feed re-read after.
    func send(_ command: ClauthCommand) {
        let client = client
        Task { [weak self] in
            let outcome = await Task.detached { client.send(command) }.value
            guard let self else { return }
            if let message = outcome.errorMessage { self.showError(message) }
            self.watcher?.reload()
        }
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
