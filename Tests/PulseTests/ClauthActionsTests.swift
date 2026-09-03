import XCTest
@testable import Pulse

@MainActor
final class ClauthActionsTests: XCTestCase {
    func testRenameValidation() {
        XCTAssertEqual(ClauthActions.renameValidationError("", old: "a", existing: []), "Enter a name.")
        XCTAssertEqual(ClauthActions.renameValidationError("a", old: "a", existing: ["a"]), "That is already its name.")
        XCTAssertEqual(ClauthActions.renameValidationError("a b", old: "a", existing: []), "Names can’t contain spaces or slashes.")
        XCTAssertEqual(ClauthActions.renameValidationError("a/b", old: "a", existing: []), "Names can’t contain spaces or slashes.")
        XCTAssertEqual(ClauthActions.renameValidationError("b", old: "a", existing: ["a", "b"]), "b already exists.")
        XCTAssertNil(ClauthActions.renameValidationError(" c ", old: "a", existing: ["a", "b"]))
    }

    func testLoginFailureMessages() {
        XCTAssertNil(ClauthActions.loginFailureMessage(.ok(stdout: "", stderr: ""), name: "x"))
        XCTAssertEqual(ClauthActions.loginFailureMessage(.failed(status: 1, stderr: "Error: no browser\n"), name: "x"), "Error: no browser")
        XCTAssertEqual(ClauthActions.loginFailureMessage(.failed(status: 2, stderr: ""), name: "x"), "clauth login exited 2")
        XCTAssertEqual(ClauthActions.loginFailureMessage(.unavailable(.sandboxed), name: "x"), "sandboxed — PULSE_CLAUTH_BIN is not set")
        XCTAssertEqual(ClauthActions.loginFailureMessage(.couldNotStart("nope"), name: "x"), "could not run clauth: nope")
    }

    func testReauthSpawnsTheRightArgvAndNudgesARefresh() async throws {
        let home = try FakeClauthDaemon.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FakeClauthDaemon.writeFixture(to: home, liveSession: false)
        let daemon = try FakeClauthDaemon(home: home)
        defer { daemon.stop() }
        let recorded = Recorder()
        let actions = ClauthActions(client: ClauthDaemonClient(home: home)) { program, arguments, stdin in
            recorded.append(program: program, arguments: arguments, stdin: stdin)
            return .ok(stdout: "", stderr: "")
        }
        actions.reauth("fx-main", codex: false)
        XCTAssertEqual(actions.loginInFlight, .init(name: "fx-main", codex: false, mode: .browser))
        let settled1 = await waitUntil(3) { actions.loginInFlight == nil }
        XCTAssertTrue(settled1)
        actions.reauth("fx-codex-xfx", codex: true, mode: .capture)
        let settled2 = await waitUntil(3) { actions.loginInFlight == nil }
        XCTAssertTrue(settled2)
        actions.reauth("fx-codex-xfx", codex: true, mode: .browser)
        let settled3 = await waitUntil(3) { actions.loginInFlight == nil && daemon.commands.count >= 3 }
        XCTAssertTrue(settled3)
        XCTAssertEqual(recorded.launches.map(\.arguments), [
            ["login", "fx-main"],
            ["login", "fx-codex-xfx", "--codex"],
            ["login", "fx-codex-xfx", "--codex", "--browser"],
        ])
        XCTAssertTrue(recorded.launches.allSatisfy { $0.program == "clauth" && $0.stdin == nil })
        XCTAssertEqual(daemon.commandNames, ["refresh", "refresh", "refresh"], "a successful login nudges the daemon to re-read that profile")
        XCTAssertEqual(daemon.commands.first?["profile"] as? String, "fx-main")
        XCTAssertNil(actions.lastError)
    }

    func testFailedLoginSurfacesTheCLIsOwnWords() async throws {
        let actions = ClauthActions(client: ClauthDaemonClient(socketPath: "/tmp/clp-nowhere/clauthd.sock")) { _, _, _ in
            .failed(status: 1, stderr: "Error: login timed out\n")
        }
        actions.reauth("fx-main", codex: false)
        let settled4 = await waitUntil(3) { actions.lastError != nil }
        XCTAssertTrue(settled4)
        XCTAssertEqual(actions.lastError, "Error: login timed out")
    }

    func testRenameGoesOverTheSocketAndTheFeedFollows() async throws {
        let home = try FakeClauthDaemon.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FakeClauthDaemon.writeFixture(to: home, liveSession: false)
        let daemon = try FakeClauthDaemon(home: home)
        defer { daemon.stop() }
        let settings = try ClauthFixture.settings(roster: false)
        let watcher = ClauthWatcher(settings: settings, store: UsageStore(settings: settings), home: home, visibility: ClauthVisibility(defaults: nil))
        watcher.tick()
        watcher.actions.rename("fx-backup", to: "fx-spare")
        let settled5 = await waitUntil(3) { watcher.status?.profile(named: "fx-spare") != nil }
        XCTAssertTrue(settled5)
        XCTAssertEqual(daemon.commands.first?["cmd"] as? String, "rename")
        XCTAssertEqual(daemon.commands.first?["new_name"] as? String, "fx-spare")
        XCTAssertNil(watcher.status?.profile(named: "fx-backup"))
        XCTAssertTrue(settings.clauthAccounts.contains(AccountKey(.claudeCode, slot: "clauth:fx-spare")))
        watcher.actions.rename("fx-main", to: "fx-spare")
        XCTAssertEqual(watcher.actions.lastError, "fx-spare already exists.")
        XCTAssertEqual(daemon.commands.count, 1, "a locally invalid rename never reaches the socket")
    }
}

final class Recorder: @unchecked Sendable {
    struct Launch: Equatable { let program: String; let arguments: [String]; let stdin: String? }
    private let lock = NSLock()
    private var stored: [Launch] = []
    var launches: [Launch] { lock.withLock { stored } }
    func append(program: String, arguments: [String], stdin: String?) {
        lock.withLock { stored.append(Launch(program: program, arguments: arguments, stdin: stdin)) }
    }
}
