import XCTest
@testable import Pulse

@MainActor
final class ClauthSwitchControllerTests: XCTestCase {
    private var home: URL!
    private var daemon: FakeClauthDaemon?

    override func setUp() async throws {
        home = try FakeClauthDaemon.makeHome()
    }

    override func tearDown() async throws {
        daemon?.stop()
        try? FileManager.default.removeItem(at: home)
    }

    private func start(liveSession: Bool, mode: FakeClauthDaemon.Mode = .normal, socket: Bool = true) throws -> ClauthWatcher {
        try FakeClauthDaemon.writeFixture(to: home, liveSession: liveSession)
        if socket { daemon = try FakeClauthDaemon(home: home, mode: mode) }
        let settings = try ClauthFixture.settings(roster: false)
        let store = UsageStore(settings: settings)
        let watcher = ClauthWatcher(settings: settings, store: store, home: home, visibility: ClauthVisibility(defaults: nil))
        watcher.tick()
        return watcher
    }

    func testSocketSwitchConfirmsOnlyWhenTheHarnessOwnSlotFlips() async throws {
        let watcher = try start(liveSession: false)
        XCTAssertEqual(watcher.status?.activeProfile, "fx-main")
        watcher.switches.switchTo("fx-cl")
        XCTAssertEqual(watcher.switches.phase, .pending(target: "fx-cl"), "no live session ⇒ straight to pending")
        let confirmed = await waitUntil(4) { watcher.switches.phase == .confirmed(target: "fx-cl", viaCLI: false) }
        XCTAssertTrue(confirmed, "phase was \(watcher.switches.phase)")
        XCTAssertEqual(daemon?.commands.map { ($0["cmd"] as? String ?? "", $0["profile"] as? String ?? "") }.first?.0, "switch")
        XCTAssertEqual(daemon?.commands.first?["profile"] as? String, "fx-cl")
        XCTAssertEqual(watcher.status?.activeProfile, "fx-cl")
        XCTAssertEqual(watcher.status?.activeCodexProfile, "fx-codex-dev0", "the other harness's slot is untouched")
        print("settle: fake socket recorded \(daemon?.commands ?? []); active_profile flipped to \(watcher.status?.activeProfile ?? "nil"); phase \(watcher.switches.phase)")
    }

    func testWrongHarnessFlipNeverConfirmsUntilThePendingTimeout() async throws {
        let watcher = try start(liveSession: false, mode: .wrongHarness)
        watcher.switches.switchTo("fx-cl")
        XCTAssertEqual(watcher.switches.phase, .pending(target: "fx-cl"))
        let confirmedEarly = await waitUntil(3.5) { !watcher.switches.phase.isBusy }
        XCTAssertFalse(confirmedEarly, "a claude switch that only moved active_codex_profile must stay pending — phase \(watcher.switches.phase)")
        XCTAssertEqual(watcher.status?.activeCodexProfile, "fx-cl", "the fake flipped the WRONG slot")
        XCTAssertEqual(watcher.status?.activeProfile, "fx-main")
        let failed = await waitUntil(5) { if case .failed = watcher.switches.phase { return true } else { return false } }
        XCTAssertTrue(failed, "phase was \(watcher.switches.phase)")
        XCTAssertEqual(watcher.switches.phase, .failed(reason: "the switch didn’t take — the daemon may be busy"))
        print("reverse: wrong-harness flip → active_codex_profile=\(watcher.status?.activeCodexProfile ?? "nil"), active_profile=\(watcher.status?.activeProfile ?? "nil"), phase \(watcher.switches.phase)")
    }

    func testArmingWithoutConfirmReturnsToIdleAfterFiveSecondsAndSendsNothing() async throws {
        let watcher = try start(liveSession: true)
        XCTAssertNil(watcher.switches.onArm, "no confirm surface in tests")
        watcher.switches.switchTo("fx-cl")
        XCTAssertEqual(watcher.switches.phase, .arming(target: "fx-cl"))
        XCTAssertEqual(watcher.switches.inFlightTarget, "fx-cl")
        let stillArmed = await waitUntil(4) { watcher.switches.phase != .arming(target: "fx-cl") }
        XCTAssertFalse(stillArmed, "still arming inside the 5 s window")
        let idle = await waitUntil(2) { watcher.switches.phase == .idle }
        XCTAssertTrue(idle, "phase was \(watcher.switches.phase)")
        XCTAssertEqual(daemon?.commands.count, 0, "an unconfirmed arm fires nothing — recorded \(daemon?.commands ?? [])")
        XCTAssertEqual(watcher.status?.activeProfile, "fx-main")
        print("arming: idle after 5 s, fake socket log \(daemon?.commands ?? [])")
    }

    func testConfirmedArmDispatchesAndConfirms() async throws {
        let watcher = try start(liveSession: true)
        watcher.switches.switchTo("fx-cl")
        XCTAssertEqual(watcher.switches.phase, .arming(target: "fx-cl"))
        watcher.switches.confirmArmedSwitch("fx-cl")
        XCTAssertEqual(watcher.switches.phase, .pending(target: "fx-cl"))
        let confirmed = await waitUntil(4) { watcher.switches.phase == .confirmed(target: "fx-cl", viaCLI: false) }
        XCTAssertTrue(confirmed, "phase was \(watcher.switches.phase)")
        XCTAssertEqual(daemon?.commandNames, ["switch"])
    }

    func testArmHandsTheConfirmBothNamesTargetAndCurrent() async throws {
        let watcher = try start(liveSession: true)
        var asked: (String, String?)?
        watcher.switches.onArm = { target, current in asked = (target, current) }
        watcher.switches.switchTo("fx-cl")
        XCTAssertEqual(asked?.0, "fx-cl")
        XCTAssertEqual(asked?.1, "fx-main", "the alert names the CURRENT account, whose session the switch logs out")
        watcher.switches.cancel()
    }

    func testCancelledArmSendsNothing() async throws {
        let watcher = try start(liveSession: true)
        watcher.switches.switchTo("fx-cl")
        watcher.switches.cancel()
        XCTAssertEqual(watcher.switches.phase, .idle)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(daemon?.commands.count, 0)
    }

    func testCodexSwitchNeverArmsAndConfirmsOnTheCodexSlot() async throws {
        let watcher = try start(liveSession: true)
        watcher.switches.switchTo("fx-codex-xfx")
        XCTAssertEqual(watcher.switches.phase, .pending(target: "fx-codex-xfx"))
        XCTAssertEqual(watcher.switches.harness, .codex)
        let confirmed = await waitUntil(4) { watcher.switches.phase == .confirmed(target: "fx-codex-xfx", viaCLI: false) }
        XCTAssertTrue(confirmed, "phase was \(watcher.switches.phase)")
        XCTAssertEqual(watcher.status?.activeCodexProfile, "fx-codex-xfx")
        XCTAssertEqual(watcher.status?.activeProfile, "fx-main")
    }

    func testDeadDaemonFallsBackToTheCLIAndConfirmsByExitCode() async throws {
        let watcher = try start(liveSession: false, socket: false)
        let controller = ClauthSwitchController(client: ClauthDaemonClient(home: home), cli: { _ in .ok })
        controller.watcher = watcher
        controller.switchTo("fx-cl")
        let confirmed = await waitUntil(3) { controller.phase == .confirmed(target: "fx-cl", viaCLI: true) }
        XCTAssertTrue(confirmed, "phase was \(controller.phase)")
    }

    func testARefusalNeverReachesTheCLI() async throws {
        let watcher = try start(liveSession: false)
        let controller = ClauthSwitchController(client: ClauthDaemonClient(home: home), cli: { _ in
            XCTFail("the CLI fallback must never run on a daemon rejection")
            return .ok
        })
        controller.watcher = watcher
        controller.switchTo("fx-ghost")
        let failed = await waitUntil(3) { controller.phase == .failed(reason: "unknown profile 'fx-ghost'") }
        XCTAssertTrue(failed, "phase was \(controller.phase)")
    }
}
