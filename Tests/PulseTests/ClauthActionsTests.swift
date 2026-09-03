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

extension ClauthActionsTests {
    /// Every chain verb, end to end through the fake socket: the recorded
    /// JSON is what clauth's dispatch arm reads.
    func testTheTenChainVerbsReachTheSocketWithTheDocumentedShapes() async throws {
        let home = try FakeClauthDaemon.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FakeClauthDaemon.writeFixture(to: home, liveSession: false)
        let daemon = try FakeClauthDaemon(home: home)
        defer { daemon.stop() }
        let settings = try ClauthFixture.settings(roster: false)
        let watcher = ClauthWatcher(settings: settings, store: UsageStore(settings: settings), home: home, visibility: ClauthVisibility(defaults: nil))
        watcher.tick()
        let actions = watcher.actions
        actions.fallbackAdd("fx-backup")
        actions.fallbackRemove("fx-cl")
        actions.fallbackMove("fx-main", up: false)
        actions.setThreshold("fx-main", 85)
        actions.setLastResort("fx-main", true)
        actions.setMemberWeekly("fx-main", 97.5)
        actions.setMemberWeekly("fx-main", nil)
        actions.setCheckWeekly("fx-main", false)
        actions.setCheckScoped("fx-main", false)
        actions.setWrapOff(true)
        actions.setWeeklyThreshold(95)
        let landed = await waitUntil(5) { daemon.commands.count == 11 }
        XCTAssertTrue(landed, "recorded \(daemon.commands.count): \(daemon.commandNames)")
        let expected: [[String: Any]] = [
            ["cmd": "fallback_add", "profile": "fx-backup"],
            ["cmd": "fallback_remove", "profile": "fx-cl"],
            ["cmd": "fallback_move", "profile": "fx-main", "dir": "down"],
            ["cmd": "set_threshold", "profile": "fx-main", "value": 85],
            ["cmd": "set_last_resort", "profile": "fx-main", "value": true],
            ["cmd": "set_member_weekly", "profile": "fx-main", "value": 97.5],
            ["cmd": "set_member_weekly", "profile": "fx-main", "value": NSNull()],
            ["cmd": "set_check_weekly", "profile": "fx-main", "value": false],
            ["cmd": "set_check_scoped", "profile": "fx-main", "value": false],
            ["cmd": "set_wrap_off", "value": true],
            ["cmd": "set_weekly_threshold", "value": 95],
        ]
        for (recorded, wanted) in zip(daemon.commands, expected) {
            XCTAssertEqual(recorded as NSDictionary, wanted as NSDictionary)
        }
        XCTAssertEqual(actions.configInFlight, 0)
        print("socket verbs recorded: \(daemon.commands.map { String(describing: $0["cmd"] ?? "") })")
    }

    func testAddAccountInstallTokenFeedAndDeleteUseCcsbarsArgv() async throws {
        let home = try FakeClauthDaemon.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FakeClauthDaemon.writeFixture(to: home, liveSession: false)
        let daemon = try FakeClauthDaemon(home: home)
        defer { daemon.stop() }
        let settings = try ClauthFixture.settings(roster: false)
        let watcher = ClauthWatcher(settings: settings, store: UsageStore(settings: settings), home: home, visibility: ClauthVisibility(defaults: nil))
        watcher.tick()
        let recorded = Recorder()
        let actions = ClauthActions(client: ClauthDaemonClient(home: home)) { program, arguments, stdin in
            recorded.append(program: program, arguments: arguments, stdin: stdin)
            return .ok(stdout: "", stderr: "")
        }
        actions.watcher = watcher
        let mint = "sk-ant-" + String(repeating: "m", count: 60)

        actions.addAccount("fx-new", codex: false)
        let a1 = await waitUntil(3) { actions.loginInFlight == nil }; XCTAssertTrue(a1)
        actions.addAccount("fx-codex-new", codex: true, mode: .capture)
        let a2 = await waitUntil(3) { actions.loginInFlight == nil }; XCTAssertTrue(a2)
        actions.addAccount("fx-codex-web", codex: true, mode: .browser)
        let a3 = await waitUntil(3) { actions.loginInFlight == nil }; XCTAssertTrue(a3)
        actions.installSetupToken("fx-main", token: "  \(mint)\n")
        let a4 = await waitUntil(3) { actions.loginInFlight == nil }; XCTAssertTrue(a4)
        actions.setFeed("fx-main", on: false)
        actions.delete("fx-backup")
        let a5 = await waitUntil(3) { actions.deleteInFlight == nil && recorded.launches.count == 6 }; XCTAssertTrue(a5)

        XCTAssertEqual(recorded.launches.map(\.arguments), [
            ["login", "--new", "fx-new"],
            ["login", "--new", "fx-codex-new", "--codex"],
            ["login", "--new", "fx-codex-web", "--codex", "--browser"],
            ["login", "fx-main", "--setup-token", "--yes"],
            ["feed", "fx-main", "off"],
            ["delete", "fx-backup", "--yes"],
        ])
        XCTAssertEqual(recorded.launches[3].stdin, mint, "the mint goes down the pipe, trimmed")
        XCTAssertTrue(recorded.launches.enumerated().allSatisfy { $0.offset == 3 || $0.element.stdin == nil })
        XCTAssertTrue(recorded.launches.allSatisfy { $0.program == "clauth" })
        // Refusals never spawn.
        actions.addAccount("fx-main", codex: false)
        XCTAssertEqual(actions.lastError, "fx-main already exists — re-authenticate that account instead.")
        actions.installSetupToken("fx-main", token: "junk")
        XCTAssertEqual(actions.lastError, "That paste doesn’t look like a claude setup-token mint.")
        actions.delete("fx-ghost")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(recorded.launches.count, 6, "an invalid name, a bad paste and an unknown profile never reach the CLI")
        print("shim argv: \(recorded.launches.map(\.arguments))")
    }

    func testARealShimRecordsTheArgvUnderTheSandboxEnvironment() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "clp-shim2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: "bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let shim = home.appending(path: "bin/clauth"), log = home.appending(path: "shim.log")
        try "#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"\(log.path)\"\ncat >/dev/null\n".write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let sandboxed = ClauthCLI.Environment(sandboxHome: home.path, sandboxBin: shim.path)
        for arguments in [ClauthCLI.loginArgs("fx-main", newOnly: false, codex: false, browser: true), ClauthCLI.setupTokenArgs("fx-main"), ClauthCLI.deleteArgs("fx-backup")] {
            let outcome = await ClauthCLI.run(program: ClauthCLI.clauth, arguments: arguments, stdin: arguments.contains("--setup-token") ? "sk-ant-secret" : nil, environment: sandboxed)
            XCTAssertTrue(outcome.isOK)
        }
        let recorded = try String(contentsOf: log, encoding: .utf8)
        XCTAssertEqual(recorded, "clauth login fx-main\nclauth login fx-main --setup-token --yes\nclauth delete fx-backup --yes\n")
        XCTAssertFalse(recorded.contains("sk-ant-secret"), "stdin is never in the shim's argv")
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
