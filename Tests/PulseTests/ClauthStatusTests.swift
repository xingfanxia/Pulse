import XCTest
@testable import Pulse

final class ClauthStatusTests: XCTestCase {
    func testFixtureDecodesSevenProfilesThreeClaudeFourCodex() throws {
        let status = try ClauthFixture.status()
        XCTAssertEqual(status.schema, 1)
        XCTAssertTrue(status.isSupported)
        XCTAssertEqual(status.profiles.count, 7)
        XCTAssertEqual(status.profiles.filter { $0.harness == .claude }.count, 3)
        XCTAssertEqual(status.profiles.filter { $0.harness == .codex }.count, 4)
        XCTAssertTrue(status.profiles.allSatisfy { $0.name.hasPrefix("fx-") })
    }

    func testTopLevelFields() throws {
        let status = try ClauthFixture.status()
        XCTAssertEqual(status.activeProfile, "fx-main")
        XCTAssertEqual(status.activeCodexProfile, "fx-codex-dev0")
        XCTAssertEqual(status.activeName(for: .claude), "fx-main")
        XCTAssertEqual(status.activeName(for: .codex), "fx-codex-dev0")
        XCTAssertEqual(status.chain(for: .claude), ["fx-main", "fx-cl"])
        XCTAssertEqual(status.chain(for: .codex), ["fx-codex-dev0", "fx-codex-xfx", "fx-codex-cl"])
        XCTAssertFalse(status.wrapOff)
        XCTAssertEqual(status.weeklySwitchThreshold, 98)
        XCTAssertEqual(status.forecast, .init(action: "switch", to: "fx-cl"))
        XCTAssertEqual(status.clauthVersion, "0.13.1")
        XCTAssertEqual(status.refreshIntervalMs, 90_000)
        XCTAssertNil(status.pendingSwitch)
        XCTAssertEqual(status.lastSwitch?.to, "fx-main")
        XCTAssertNil(status.lastError)
    }

    func testSessionFeedSpellingFallsBackToRollingToken() throws {
        let status = try ClauthFixture.status()
        // The deployed fork's spelling, no `rolling_token` key at all.
        XCTAssertTrue(try ClauthFixture.profile("fx-backup", in: status).rollingToken)
        // The post-#59 spelling.
        XCTAssertTrue(try ClauthFixture.profile("fx-main", in: status).rollingToken)
        // Present and false.
        XCTAssertFalse(try ClauthFixture.profile("fx-codex-dev0", in: status).rollingToken)
    }

    func testRollingTokenKeyOutranksSessionFeed() throws {
        let profile = try ClauthFixture.profile(["rolling_token": false, "session_feed": true])
        XCTAssertFalse(profile.rollingToken)
    }

    func testHarnessAbsentReadsAsClaude() throws {
        let profile = try ClauthFixture.profile(["name": "fx-old"])
        XCTAssertEqual(profile.harness, .claude)
        XCTAssertEqual(profile.provider, "anthropic")
        XCTAssertFalse(profile.active)
        XCTAssertFalse(profile.stale)
        XCTAssertEqual(profile.windows, [])
        XCTAssertNil(profile.fallback)
    }

    func testOnlyNameIsRequiredOfAProfile() throws {
        let status = try ClauthFixture.status { object in
            object["profiles"] = [["name": "fx-bare"]]
        }
        XCTAssertEqual(status.profiles.map(\.name), ["fx-bare"])
    }

    func testTopLevelOptionalsMayBeAbsent() throws {
        let data = Data(#"{"schema":1,"generated_at":"2026-09-03T05:00:00+00:00","profiles":[]}"#.utf8)
        let status = try JSONDecoder().decode(ClauthStatus.self, from: data)
        XCTAssertEqual(status.fallbackChain, [])
        XCTAssertEqual(status.codexFallbackChain, [])
        XCTAssertFalse(status.wrapOff)
        XCTAssertNil(status.activeProfile)
        XCTAssertNil(status.activeCodexProfile)
    }

    func testSchemaTwoIsUnsupported() throws {
        let status = try ClauthFixture.status { $0["schema"] = 2 }
        XCTAssertFalse(status.isSupported)
        XCTAssertEqual(ClauthMapping.roster(status), [])
        XCTAssertEqual(ClauthMapping.readings(status, freshness: .live), [:])
    }

    func testFallbackDecodesWithNullWeeklyThresholdAndDefaults() throws {
        let status = try ClauthFixture.status()
        let main = try ClauthFixture.profile("fx-main", in: status)
        XCTAssertEqual(main.fallback?.position, 0)
        XCTAssertEqual(main.fallback?.threshold, 90)
        XCTAssertEqual(main.fallback?.armed, true)
        XCTAssertNil(main.fallback?.weeklyThreshold)
        let cl = try ClauthFixture.profile("fx-codex-cl", in: status)
        XCTAssertEqual(cl.fallback?.lastResort, true)
        XCTAssertEqual(cl.fallback?.checkScoped, false)
        XCTAssertEqual(cl.fallback?.weeklyThreshold, 97)
        let bare = try ClauthFixture.profile(["fallback": ["position": 3, "threshold": 80, "armed": false]])
        XCTAssertEqual(bare.fallback?.checkWeekly, true)
        XCTAssertEqual(bare.fallback?.checkScoped, true)
        XCTAssertEqual(bare.fallback?.lastResort, false)
    }

    func testCodexLimitedShapeDecodes() throws {
        let xfx = try ClauthFixture.profile("fx-codex-xfx", in: try ClauthFixture.status())
        XCTAssertEqual(xfx.codexRateLimitReached, "rate_limit_reached")
        XCTAssertEqual(xfx.codexResetCredits, 1)
        XCTAssertEqual(xfx.harness, .codex)
        XCTAssertEqual(xfx.tier, "pro")
    }

    func testISOParsesBothDaemonSpellings() {
        XCTAssertNotNil(ClauthISO.parse("2026-09-03T05:40:27+00:00"))
        XCTAssertNotNil(ClauthISO.parse("2026-08-06T17:00:00.195741+00:00"))
        XCTAssertNotNil(ClauthISO.parse("2026-09-07T02:26:04Z"))
        XCTAssertNil(ClauthISO.parse("yesterday"))
        XCTAssertNil(ClauthISO.parse(nil))
    }
}
