import XCTest
@testable import Pulse

final class ClauthCardFooterTests: XCTestCase {
    private let now = Date()

    private func codex(_ verdict: String?, week: (pct: Double, resets: String?)?, fiveHour: (pct: Double, resets: String?)? = nil) throws -> ClauthStatus.Profile {
        var windows: [[String: Any]] = []
        if let fiveHour { windows.append(["label": "5h", "utilization_pct": fiveHour.pct, "resets_at": fiveHour.resets as Any]) }
        if let week { windows.append(["label": "7d", "utilization_pct": week.pct, "resets_at": week.resets as Any]) }
        var fields: [String: Any] = ["name": "fx-x", "harness": "codex", "provider": "openai", "windows": windows]
        if let verdict { fields["codex_rate_limit_reached"] = verdict }
        return try ClauthFixture.profile(fields)
    }

    func testBareReasonWithAFortyPercentWindowIsGenericAndTheRingStaysGreen() throws {
        let profile = try codex("rate_limit_reached", week: (40, ClauthFixture.far))
        let line = try XCTUnwrap(ClauthCardFooter.verdictLine(for: profile, now: now))
        XCTAssertEqual(line.message, "fx-x is rate-limited")
        XCTAssertNil(line.resetsAt)
        let window = try XCTUnwrap(ClauthMapping.window(profile.windows[0], now: now))
        XCTAssertFalse(window.isExhausted)
        XCTAssertFalse(UsageTint.isSpent(window), "the verdict is a card line, never a ring colour")
        XCTAssertEqual(window.usedFraction, 0.4, accuracy: 1e-9)
    }

    func testBareReasonWithALiveFullWindowNamesThatWindow() throws {
        let week = try codex("rate_limit_reached", week: (100, ClauthFixture.far))
        XCTAssertEqual(ClauthCardFooter.verdictLine(for: week, now: now)?.message, "fx-x hit its weekly window")
        XCTAssertEqual(ClauthCardFooter.verdictLine(for: week, now: now)?.resetsAt, ClauthISO.parse(ClauthFixture.far))
        let session = try codex("rate_limit_reached", week: (30, ClauthFixture.far), fiveHour: (100, ClauthFixture.far))
        XCTAssertEqual(ClauthCardFooter.verdictLine(for: session, now: now)?.message, "fx-x hit its 5h window")
    }

    func testNamedVerdictsAndLapsedWindows() throws {
        XCTAssertEqual(ClauthCardFooter.verdictLine(for: try codex("primary", week: nil, fiveHour: (80, ClauthFixture.far)), now: now)?.message, "fx-x hit its 5h window")
        XCTAssertEqual(ClauthCardFooter.verdictLine(for: try codex("secondary", week: (80, ClauthFixture.far)), now: now)?.message, "fx-x hit its weekly window")
        XCTAssertNil(ClauthCardFooter.verdictLine(for: try codex("secondary", week: (100, ClauthFixture.past)), now: now), "a lapsed window says nothing")
        XCTAssertNil(ClauthCardFooter.verdictLine(for: try codex("rate_limit_reached", week: (100, ClauthFixture.past)), now: now))
        XCTAssertNil(ClauthCardFooter.verdictLine(for: try codex(nil, week: (100, ClauthFixture.far)), now: now))
    }

    func testFixtureLimitedProfileRendersVerdictAndBankedLines() throws {
        let status = try ClauthFixture.status()
        let xfx = try ClauthFixture.profile("fx-codex-xfx", in: status)
        let lines = ClauthCardFooter.lines(for: xfx, status: status, now: now)
        XCTAssertEqual(lines.map(\.id), ["state", "verdict", "banked"])
        XCTAssertTrue(lines[1].text.hasPrefix("fx-codex-xfx hit its weekly window — auto-switch rotates at the session boundary · resets in "), lines[1].text)
        XCTAssertEqual(lines[2].text, "1 free reset banked")
        XCTAssertEqual(ClauthCardFooter.bankedLine(for: try ClauthFixture.profile("fx-codex-cl", in: status)), "2 free resets banked")
        XCTAssertNil(ClauthCardFooter.bankedLine(for: try ClauthFixture.profile("fx-code-bk", in: status)))
        XCTAssertNil(ClauthCardFooter.bankedLine(for: try ClauthFixture.profile("fx-main", in: status)))
    }

    func testStateLines() throws {
        let status = try ClauthFixture.status()
        XCTAssertEqual(ClauthCardFooter.stateLine(for: try ClauthFixture.profile("fx-main", in: status), status: status), "active · chain #1 · switches at 90% · rolling token")
        XCTAssertEqual(ClauthCardFooter.stateLine(for: try ClauthFixture.profile("fx-backup", in: status), status: status), "not in chain · rolling token")
        XCTAssertEqual(ClauthCardFooter.stateLine(for: try ClauthFixture.profile("fx-codex-cl", in: status), status: status), "chain #3 · switches at 95% · last resort")
        XCTAssertEqual(ClauthCardFooter.authLine(for: try ClauthFixture.profile("fx-backup", in: status)), "login expiring — re-authenticate soon")
        XCTAssertEqual(ClauthCardFooter.authLine(for: try ClauthFixture.profile(["auth_status": "broken"])), "login broken — re-authenticate")
        XCTAssertNil(ClauthCardFooter.authLine(for: try ClauthFixture.profile("fx-main", in: status)))
    }

    func testPhaseLoginAndErrorLines() throws {
        let status = try ClauthFixture.status()
        let cl = try ClauthFixture.profile("fx-cl", in: status)
        let main = try ClauthFixture.profile("fx-main", in: status)
        XCTAssertEqual(ClauthCardFooter.phaseLine(for: cl, phase: .pending(target: "fx-cl"), harness: .claude)?.text, "Switching to fx-cl…")
        XCTAssertNil(ClauthCardFooter.phaseLine(for: main, phase: .pending(target: "fx-cl"), harness: .claude))
        XCTAssertEqual(ClauthCardFooter.phaseLine(for: cl, phase: .confirmed(target: "fx-cl", viaCLI: true), harness: .claude)?.text, "Switched to fx-cl via clauth — the daemon is down")
        XCTAssertEqual(ClauthCardFooter.phaseLine(for: main, phase: .failed(reason: "busy"), harness: .claude)?.text, "Switch failed: busy")
        XCTAssertNil(ClauthCardFooter.phaseLine(for: try ClauthFixture.profile("fx-codex-dev0", in: status), phase: .failed(reason: "busy"), harness: .claude))
        let lines = ClauthCardFooter.lines(for: cl, status: status, phase: .arming(target: "fx-cl"), login: .init(name: "fx-cl", codex: false, mode: .browser), error: "boom", now: now)
        XCTAssertEqual(lines.map(\.id), ["state", "switch", "login", "error"])
        XCTAssertEqual(lines[1].text, "Waiting for confirmation…")
        XCTAssertEqual(lines[2].text, "Signing in to fx-cl — finish in your browser…")
        XCTAssertEqual(lines[3].kind, .error)
    }

    func testResetHint() {
        XCTAssertEqual(ClauthCardFooter.resetHint(now.addingTimeInterval(5 * 86_400 + 16 * 3_600), now: now), "resets in 5d 16h")
        XCTAssertEqual(ClauthCardFooter.resetHint(now.addingTimeInterval(2 * 3_600 + 5 * 60), now: now), "resets in 2h 5m")
        XCTAssertEqual(ClauthCardFooter.resetHint(now.addingTimeInterval(90), now: now), "resets in 1m")
        XCTAssertNil(ClauthCardFooter.resetHint(now.addingTimeInterval(-1), now: now))
        XCTAssertNil(ClauthCardFooter.resetHint(nil, now: now))
    }

    @MainActor
    func testDeadDaemonFootnote() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "clp-footer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = try ClauthFixture.settings(roster: false)
        let watcher = ClauthWatcher(settings: settings, store: UsageStore(settings: settings), home: home, visibility: ClauthVisibility(defaults: nil))
        watcher.tick()
        XCTAssertEqual(watcher.freshness, .dead)
        let main = try ClauthFixture.profile("fx-main", in: try ClauthFixture.status())
        let usage = ClauthMapping.usage(for: main, freshness: .dead, now: now)
        let footnote = try XCTUnwrap(ClauthCardFooter.footnote(for: usage, watcher: watcher, now: now))
        XCTAssertTrue(footnote.hasPrefix("clauth daemon not running · last reading "), footnote)
        XCTAssertNil(ClauthCardFooter.footnote(for: ProviderUsage.unavailable(.claudeCode, reason: .loading), watcher: watcher, now: now), "not clauth's account")
        try FakeClauthDaemon.writeFixture(to: home, liveSession: false)
        watcher.tick()
        XCTAssertEqual(watcher.freshness, .live)
        XCTAssertNil(ClauthCardFooter.footnote(for: usage, watcher: watcher, now: now), "a live daemon hands the line back to upstream")
    }
}
