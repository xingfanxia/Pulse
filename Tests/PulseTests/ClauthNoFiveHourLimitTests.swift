import XCTest
@testable import Pulse

/// Claude's top plan has no 5-hour window (clauth `no_five_hour_limit`): its
/// reads carry only `7d` and `7d fable`, and the 5h threshold is inert.
final class ClauthNoFiveHourLimitTests: XCTestCase {
    /// fx-main reshaped into the no-5h plan: flag on, the 5h window gone.
    private func noFiveHour(_ names: [String], edit: (inout [String: Any]) -> Void = { _ in }) throws -> ClauthStatus {
        try ClauthFixture.status { object in
            for name in names {
                ClauthFixture.editProfile(&object, name) { profile in
                    profile["no_five_hour_limit"] = true
                    let windows = profile["windows"] as? [[String: Any]] ?? []
                    profile["windows"] = windows.filter { $0["label"] as? String != "5h" }
                }
            }
            edit(&object)
        }
    }

    func testFlagDecodesAndAbsentReadsFalse() throws {
        XCTAssertTrue(try ClauthFixture.profile(["no_five_hour_limit": true]).noFiveHourLimit)
        XCTAssertFalse(try ClauthFixture.profile(["no_five_hour_limit": false]).noFiveHourLimit)
        XCTAssertFalse(try ClauthFixture.profile([:]).noFiveHourLimit, "older daemons publish no key")
        let status = try ClauthFixture.status()
        XCTAssertTrue(status.profiles.allSatisfy { !$0.noFiveHourLimit }, "the fixture predates the flag")
    }

    func testFiveHourControlIsOfferedOnlyWithoutTheFlag() throws {
        let status = try noFiveHour(["fx-main"])
        XCTAssertFalse(ClauthChainEdit.offersFiveHourThreshold(try ClauthFixture.profile("fx-main", in: status)))
        XCTAssertTrue(ClauthChainEdit.offersFiveHourThreshold(try ClauthFixture.profile("fx-cl", in: status)))
        // A plan WITH the limit whose 5h window is merely missing this tick keeps its knob.
        let dropped = try ClauthFixture.profile(["windows": [["label": "7d", "utilization_pct": 40.0]]])
        XCTAssertTrue(ClauthChainEdit.offersFiveHourThreshold(dropped))
    }

    func testSectionRuleTurnsWeeklyOnlyWhenEveryChainMemberHasNoFiveHourLimit() throws {
        func rule(_ status: ClauthStatus) -> String {
            ClauthChainEdit.claudeLeaveRule(status.profiles.filter { $0.harness == .claude })
        }
        let fiveHour = "Auto-switch leaves an account at its 5h threshold."
        XCTAssertEqual(rule(try ClauthFixture.status()), fiveHour)
        XCTAssertEqual(rule(try noFiveHour(["fx-main"])), fiveHour, "fx-cl still leaves on its 5h")
        XCTAssertEqual(rule(try noFiveHour(["fx-main", "fx-cl"])), "Auto-switch leaves an account at its weekly line.",
                       "fx-backup is not in the chain, so it does not count")
        XCTAssertEqual(rule(try noFiveHour(["fx-backup"])), fiveHour)
    }

    func testStateLineQuotesTheMemberWeeklyLineInsteadOfTheInertFiveHourThreshold() throws {
        let status = try noFiveHour(["fx-main"])
        XCTAssertEqual(ClauthCardFooter.stateLine(for: try ClauthFixture.profile("fx-main", in: status), status: status),
                       "active · chain #1 · switches at 98% of the week · rolling token", "the chain-wide line")
        XCTAssertEqual(ClauthCardFooter.stateLine(for: try ClauthFixture.profile("fx-cl", in: status), status: status),
                       "chain #2 · switches at 90% · rolling token", "a plan with the limit is unchanged")

        let override = try noFiveHour(["fx-main"]) { object in
            ClauthFixture.editProfile(&object, "fx-main") { profile in
                var fallback = profile["fallback"] as? [String: Any] ?? [:]
                fallback["weekly_threshold"] = 92.5
                profile["fallback"] = fallback
            }
        }
        XCTAssertEqual(ClauthCardFooter.stateLine(for: try ClauthFixture.profile("fx-main", in: override), status: override),
                       "active · chain #1 · switches at 92.5% of the week · rolling token")

        let gateOff = try noFiveHour(["fx-main"]) { object in
            ClauthFixture.editProfile(&object, "fx-main") { profile in
                var fallback = profile["fallback"] as? [String: Any] ?? [:]
                fallback["check_weekly"] = false
                fallback["weekly_threshold"] = 92.5
                profile["fallback"] = fallback
            }
        }
        XCTAssertEqual(ClauthCardFooter.stateLine(for: try ClauthFixture.profile("fx-main", in: gateOff), status: gateOff),
                       "active · chain #1 · switches at 100% of the week · rolling token", "weekly gate off: only the hard cap")
    }

    func testRingDrawsNoFiveHourElement() throws {
        let status = try noFiveHour(["fx-main"])
        let usage = ClauthMapping.usage(for: try ClauthFixture.profile("fx-main", in: status), freshness: .live)
        XCTAssertEqual(usage.windows.map(\.id), ["7d", "7d fable"])
        XCTAssertNil(ClauthRingExtras.innerWindow(for: usage, pinned: "7d"), "a single weekly ring, no empty 5h arc")
        XCTAssertEqual(ClauthRingExtras.innerWindow(for: usage, pinned: "7d fable")?.id, "7d")
    }
}
