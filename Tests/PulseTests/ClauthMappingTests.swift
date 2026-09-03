import XCTest
@testable import Pulse

final class ClauthMappingTests: XCTestCase {
    private let now = Date()

    // MARK: Identity

    func testEveryProfileMapsToAClauthSlotOfItsHarness() throws {
        let status = try ClauthFixture.status()
        for profile in status.profiles {
            let key = ClauthMapping.account(for: profile)
            XCTAssertEqual(key.slot, "clauth:\(profile.name)")
            XCTAssertEqual(key.provider, profile.harness == .codex ? .codex : .claudeCode)
            XCTAssertFalse(key.isPrimary)
            XCTAssertEqual(ClauthMapping.profileName(of: key), profile.name)
            XCTAssertEqual(ClauthMapping.harness(of: key), profile.harness)
            XCTAssertEqual(ClauthMapping.label(for: key), profile.name)
        }
        XCTAssertEqual(ClauthMapping.account(for: try ClauthFixture.profile("fx-main", in: status)).id, "claudeCode#clauth:fx-main")
        XCTAssertEqual(ClauthMapping.account(for: try ClauthFixture.profile("fx-codex-dev0", in: status)).id, "codex#clauth:fx-codex-dev0")
    }

    func testAccountKeyIDRoundTripsThroughStoredPreferences() {
        let key = AccountKey(.codex, slot: "clauth:fx-codex-xfx")
        XCTAssertEqual(AccountKey(id: key.id), key)
    }

    func testNonClauthAccountsHaveNoProfileName() {
        XCTAssertNil(ClauthMapping.profileName(of: AccountKey(.claudeCode)))
        XCTAssertNil(ClauthMapping.profileName(of: AccountKey(.codex, slot: "ABC-123")))
        XCTAssertNil(ClauthMapping.label(for: AccountKey(.cursor)))
        XCTAssertNil(ClauthMapping.harness(of: AccountKey(.claudeCode)))
    }

    func testThirdPartyProfileRidesClaudeCodeWithProviderAsPlan() throws {
        let profile = try ClauthFixture.profile(["name": "fx-relay", "provider": "moonshot", "tier": nil as String? as Any])
        XCTAssertTrue(profile.isThirdParty)
        XCTAssertEqual(ClauthMapping.account(for: profile).provider, .claudeCode)
        XCTAssertEqual(ClauthMapping.plan(for: profile), "moonshot")
    }

    func testPlanIsTheTierForFirstPartyProfiles() throws {
        let status = try ClauthFixture.status()
        XCTAssertEqual(ClauthMapping.plan(for: try ClauthFixture.profile("fx-main", in: status)), "Max 20x")
        XCTAssertEqual(ClauthMapping.plan(for: try ClauthFixture.profile("fx-codex-xfx", in: status)), "pro")
    }

    func testDefaultPinIsSessionForClaudeWeekForCodexNothingForOthers() {
        XCTAssertEqual(ClauthMapping.defaultPin(for: AccountKey(.claudeCode, slot: "clauth:fx-main")), "5h")
        XCTAssertEqual(ClauthMapping.defaultPin(for: AccountKey(.codex, slot: "clauth:fx-codex-dev0")), "7d")
        XCTAssertNil(ClauthMapping.defaultPin(for: AccountKey(.claudeCode)))
        XCTAssertNil(ClauthMapping.defaultPin(for: AccountKey(.codex, slot: "some-extra")))
    }

    func testDefaultPinForAReadingFallsToTheOtherUnscopedWindowNeverAScopedOne() throws {
        let status = try ClauthFixture.status { object in
            ClauthFixture.editProfile(&object, "fx-main") { profile in
                var windows = profile["windows"] as? [[String: Any]] ?? []
                windows[0]["label"] = "3d"
                profile["windows"] = windows
            }
        }
        let main = try ClauthFixture.profile("fx-main", in: status)
        let account = ClauthMapping.account(for: main)
        let usage = ClauthMapping.usage(for: main, freshness: .live, now: now)
        XCTAssertEqual(ClauthMapping.defaultPin(for: account, in: usage), "7d")
        XCTAssertEqual(usage.headlineWindow(preferring: ClauthMapping.defaultPin(for: account, in: usage))?.usedFraction ?? 0, 0.12, accuracy: 1e-9)
        // With the session window present it is preferred.
        let intact = ClauthMapping.usage(for: try ClauthFixture.profile("fx-main", in: try ClauthFixture.status()), freshness: .live, now: now)
        XCTAssertEqual(ClauthMapping.defaultPin(for: account, in: intact), "5h")
        // Only scoped windows left ⇒ nothing to pin, Pulse's rule applies.
        let scopedOnly = ClauthMapping.usage(for: try ClauthFixture.profile(["windows": [["label": "7d fable", "utilization_pct": 100]]]), freshness: .live, now: now)
        XCTAssertNil(ClauthMapping.defaultPin(for: AccountKey(.claudeCode, slot: "clauth:fx-synthetic"), in: scopedOnly))
        XCTAssertNil(ClauthMapping.defaultPin(for: AccountKey(.claudeCode), in: intact))
    }

    // MARK: Windows

    func testFiveHourWindow() throws {
        let window = try XCTUnwrap(ClauthMapping.window(ClauthFixture.window("5h", pct: 42, resets: ClauthFixture.far), now: now))
        XCTAssertEqual(window.id, "5h")
        XCTAssertEqual(window.kind, .fiveHour)
        XCTAssertNil(window.scope)
        XCTAssertEqual(window.usedFraction, 0.42, accuracy: 1e-9)
        XCTAssertEqual(window.windowSeconds, 18_000)
        XCTAssertTrue(window.reportsLength)
        XCTAssertFalse(window.isExhausted)
        XCTAssertEqual(window.resetsAt, ClauthISO.parse(ClauthFixture.far))
    }

    func testWeeklyWindow() throws {
        let window = try XCTUnwrap(ClauthMapping.window(ClauthFixture.window("7d", pct: 12, resets: nil), now: now))
        XCTAssertEqual(window.kind, .weekly)
        XCTAssertNil(window.scope)
        XCTAssertEqual(window.windowSeconds, 604_800)
        XCTAssertNil(window.resetsAt)
        XCTAssertEqual(window.usedFraction, 0.12, accuracy: 1e-9)
    }

    func testScopedWeeklyWindowCarriesTheModelAsScope() throws {
        let window = try XCTUnwrap(ClauthMapping.window(ClauthFixture.window("7d fable", pct: 100, resets: ClauthFixture.far), now: now))
        XCTAssertEqual(window.kind, .weekly)
        XCTAssertEqual(window.scope, "fable")
        XCTAssertEqual(window.id, "7d fable")
        XCTAssertEqual(ClauthMapping.window(ClauthFixture.window("7d fable 5", pct: 1, resets: nil), now: now)?.scope, "fable 5")
    }

    func testUnknownLabelsAreDroppedNeverInvented() {
        for label in ["3d", "1h", "7d ", "", "week", "5H", "30d"] {
            XCTAssertNil(ClauthMapping.window(ClauthFixture.window(label, pct: 50, resets: ClauthFixture.far), now: now), label)
        }
    }

    func testFixtureWindowRelabelledThreeDaysDisappearsFromTheReading() throws {
        let status = try ClauthFixture.status { object in
            ClauthFixture.editProfile(&object, "fx-main") { profile in
                var windows = profile["windows"] as? [[String: Any]] ?? []
                windows[0]["label"] = "3d"
                profile["windows"] = windows
            }
        }
        let usage = ClauthMapping.usage(for: try ClauthFixture.profile("fx-main", in: status), freshness: .live, now: now)
        XCTAssertEqual(usage.windows.map(\.id), ["7d", "7d fable"])
        XCTAssertFalse(usage.windows.contains { $0.usedFraction == 0 })
    }

    // MARK: Exhaustion — ccsbar's three-part rule, verbatim

    func testSpentThresholdIsNinetyNinePointFive() {
        let below = ClauthFixture.window("5h", pct: 99.4, resets: ClauthFixture.far)
        let at = ClauthFixture.window("5h", pct: 99.5, resets: ClauthFixture.far)
        XCTAssertFalse(ClauthMapping.window(below, now: now)!.isExhausted)
        XCTAssertTrue(ClauthMapping.window(at, now: now)!.isExhausted)
    }

    func testParkedCodexAtHundredWithPastResetIsNotExhausted() throws {
        let bk = try ClauthFixture.profile("fx-code-bk", in: try ClauthFixture.status())
        let usage = ClauthMapping.usage(for: bk, freshness: .live, now: now)
        let week = try XCTUnwrap(usage.windows.first { $0.id == "7d" })
        XCTAssertEqual(week.usedFraction, 1, accuracy: 1e-9)
        XCTAssertFalse(week.isExhausted, "a cap whose reset has passed no longer binds")
        XCTAssertFalse(ClauthMapping.stillCapped(ClauthFixture.window("7d", pct: 100, resets: ClauthFixture.past), resets: ClauthISO.parse(ClauthFixture.past), now: now))
    }

    func testMissingOrUnparseableResetCountsAsSpent() {
        XCTAssertTrue(ClauthMapping.window(ClauthFixture.window("5h", pct: 100, resets: nil), now: now)!.isExhausted)
        XCTAssertTrue(ClauthMapping.window(ClauthFixture.window("7d", pct: 100, resets: "soon"), now: now)!.isExhausted)
    }

    func testScopedWindowNeverExhaustedEvenAtHundred() throws {
        let main = try ClauthFixture.profile("fx-main", in: try ClauthFixture.status())
        let usage = ClauthMapping.usage(for: main, freshness: .live, now: now)
        let fable = try XCTUnwrap(usage.windows.first { $0.scope == "fable" })
        XCTAssertEqual(fable.usedFraction, 1, accuracy: 1e-9)
        XCTAssertFalse(fable.isExhausted)
    }

    func testLimitedCodexWithFutureResetIsExhausted() throws {
        let xfx = try ClauthFixture.profile("fx-codex-xfx", in: try ClauthFixture.status())
        let usage = ClauthMapping.usage(for: xfx, freshness: .live, now: now)
        XCTAssertEqual(usage.windows.first?.isExhausted, true)
    }

    // MARK: State

    func testRateLimitedFetchIsStale() throws {
        let cl = try ClauthFixture.profile("fx-cl", in: try ClauthFixture.status())
        XCTAssertEqual(cl.fetchStatus, "RateLimited")
        XCTAssertFalse(cl.stale)
        XCTAssertEqual(ClauthMapping.state(for: cl, freshness: .live), .stale)
    }

    func testCachedFetchIsStale() throws {
        let bk = try ClauthFixture.profile("fx-code-bk", in: try ClauthFixture.status())
        XCTAssertEqual(ClauthMapping.state(for: bk, freshness: .live), .stale)
    }

    func testDaemonStaleFlagIsStale() throws {
        let profile = try ClauthFixture.profile(["fetch_status": "Fresh", "stale": true])
        XCTAssertEqual(ClauthMapping.state(for: profile, freshness: .live), .stale)
    }

    func testDeadDaemonMakesEveryReadingStale() throws {
        let status = try ClauthFixture.status()
        let readings = ClauthMapping.readings(status, freshness: .dead, now: now)
        XCTAssertEqual(readings.count, 7)
        XCTAssertTrue(readings.values.allSatisfy { $0.state == .stale })
    }

    func testFreshProfileIsLiveWhileTheDaemonTicks() throws {
        let main = try ClauthFixture.profile("fx-main", in: try ClauthFixture.status())
        XCTAssertEqual(ClauthMapping.state(for: main, freshness: .live), .live)
        XCTAssertEqual(ClauthMapping.state(for: main, freshness: .syncing), .live)
    }

    func testNeverFetchedProfileIsLiveWithNoWindows() throws {
        let profile = try ClauthFixture.profile(["name": "fx-new"])
        let usage = ClauthMapping.usage(for: profile, freshness: .live, now: now)
        XCTAssertEqual(usage.state, .live)
        XCTAssertEqual(usage.windows, [])
        XCTAssertNil(usage.observedAt)
    }

    // MARK: Reading

    func testObservedAtIsFetchedAt() throws {
        let main = try ClauthFixture.profile("fx-main", in: try ClauthFixture.status())
        XCTAssertEqual(ClauthMapping.usage(for: main, freshness: .live, now: now).observedAt, ClauthISO.parse("2026-09-03T04:59:30+00:00"))
    }

    func testHeadlineForTheFableProfileIsTwelvePercentNotTheMaxedScopedWindow() throws {
        let main = try ClauthFixture.profile("fx-main", in: try ClauthFixture.status())
        let usage = ClauthMapping.usage(for: main, freshness: .live, now: now)
        let account = ClauthMapping.account(for: main)
        let headline = try XCTUnwrap(usage.headlineWindow(preferring: ClauthMapping.defaultPin(for: account)))
        XCTAssertEqual(headline.usedFraction, 0.12, accuracy: 1e-9)
        XCTAssertNil(headline.scope)
        XCTAssertEqual(headline.percentText, "12%")
        // Unpinned, Pulse's own rule would pick the maxed scoped window — the
        // exact thing the default pin exists to steer around.
        XCTAssertEqual(usage.headlineWindow()?.scope, "fable")
        // A user's pin wins over the default.
        XCTAssertEqual(usage.headlineWindow(preferring: "7d fable")?.scope, "fable")
    }

    func testCreditBalanceWording() throws {
        let status = try ClauthFixture.status()
        XCTAssertEqual(ClauthMapping.creditBalance(for: try ClauthFixture.profile("fx-codex-xfx", in: status)), "1 reset banked")
        XCTAssertEqual(ClauthMapping.creditBalance(for: try ClauthFixture.profile("fx-codex-cl", in: status)), "2 resets banked")
        XCTAssertNil(ClauthMapping.creditBalance(for: try ClauthFixture.profile("fx-code-bk", in: status)), "zero says nothing")
        XCTAssertNil(ClauthMapping.creditBalance(for: try ClauthFixture.profile("fx-codex-dev0", in: status)), "nil says nothing")
        let claude = try ClauthFixture.profile(["harness": "claude", "codex_reset_credits": 3])
        XCTAssertNil(ClauthMapping.creditBalance(for: claude), "credits are codex's alone")
    }

    func testReadingsAreKeyedByAccountIDForEveryProfile() throws {
        let status = try ClauthFixture.status()
        let readings = ClauthMapping.readings(status, freshness: .live, now: now)
        XCTAssertEqual(Set(readings.keys), Set(ClauthMapping.roster(status).map(\.id)))
        XCTAssertEqual(readings["claudeCode#clauth:fx-main"]?.windows.count, 3)
        XCTAssertEqual(readings["codex#clauth:fx-codex-dev0"]?.windows.map(\.id), ["7d"])
        XCTAssertEqual(readings["codex#clauth:fx-codex-cl"]?.windows.map(\.id), ["5h", "7d"])
    }

    // MARK: Inactive

    func testInactiveIsCancelledOrFreePlanOrBrokenLogin() throws {
        XCTAssertTrue(ClauthMapping.isInactive(try ClauthFixture.profile(["tier": "canceled"])))
        XCTAssertTrue(ClauthMapping.isInactive(try ClauthFixture.profile(["tier": "Cancelled"])))
        XCTAssertTrue(ClauthMapping.isInactive(try ClauthFixture.profile(["tier": "free", "harness": "codex"])))
        XCTAssertTrue(ClauthMapping.isInactive(try ClauthFixture.profile(["tier": "Max 20x", "auth_status": "broken"])))
        XCTAssertFalse(ClauthMapping.isInactive(try ClauthFixture.profile(["tier": "Pro", "auth_status": "expiring"])))
        XCTAssertFalse(ClauthMapping.isInactive(try ClauthFixture.profile(["tier": "pro"])))
        XCTAssertFalse(ClauthMapping.isInactive(try ClauthFixture.profile(["name": "fx-untiered"])))
        // The whole fixture is active — the seven rings are all drawn.
        XCTAssertEqual(ClauthMapping.inactive(try ClauthFixture.status()), [])
    }

    func testInactiveSetNeverHoldsTheActiveSlot() throws {
        let status = try ClauthFixture.status { object in
            ClauthFixture.editProfile(&object, "fx-code-bk") { $0["tier"] = "free" }
            ClauthFixture.editProfile(&object, "fx-cl") { $0["auth_status"] = "broken" }
            ClauthFixture.editProfile(&object, "fx-main") { $0["tier"] = "canceled" }
            ClauthFixture.editProfile(&object, "fx-codex-dev0") { $0["auth_status"] = "broken" }
        }
        XCTAssertEqual(ClauthMapping.inactive(status), ["codex#clauth:fx-code-bk", "claudeCode#clauth:fx-cl"])
    }

    // MARK: Roster

    func testRosterOrderIsActiveThenChainThenRestPerHarness() throws {
        let roster = ClauthMapping.roster(try ClauthFixture.status())
        XCTAssertEqual(roster.map(\.id), [
            "claudeCode#clauth:fx-main",
            "claudeCode#clauth:fx-cl",
            "claudeCode#clauth:fx-backup",
            "codex#clauth:fx-codex-dev0",
            "codex#clauth:fx-codex-xfx",
            "codex#clauth:fx-codex-cl",
            "codex#clauth:fx-code-bk",
        ])
    }

    func testRosterIgnoresChainNamesThatAreNotPublished() throws {
        let status = try ClauthFixture.status { $0["fallback_chain"] = ["fx-ghost", "fx-cl"]; $0["active_profile"] = "fx-gone" }
        let claude = ClauthMapping.roster(status).filter { $0.provider == .claudeCode }.map(\.id)
        XCTAssertEqual(claude, ["claudeCode#clauth:fx-cl", "claudeCode#clauth:fx-main", "claudeCode#clauth:fx-backup"])
    }

    func testRosterDiffAddedRemovedAndRenameAsBoth() throws {
        let before = ClauthMapping.roster(try ClauthFixture.status())
        let after = ClauthMapping.roster(try ClauthFixture.status { object in
            ClauthFixture.editProfile(&object, "fx-backup") { $0["name"] = "fx-spare" }
            var profiles = object["profiles"] as? [[String: Any]] ?? []
            profiles.removeAll { $0["name"] as? String == "fx-code-bk" }
            profiles.append(["name": "fx-codex-new", "harness": "codex"])
            object["profiles"] = profiles
        })
        let diff = ClauthMapping.rosterDiff(old: before, new: after)
        XCTAssertEqual(Set(diff.added.map(\.id)), ["claudeCode#clauth:fx-spare", "codex#clauth:fx-codex-new"])
        XCTAssertEqual(Set(diff.removed.map(\.id)), ["claudeCode#clauth:fx-backup", "codex#clauth:fx-code-bk"])
        XCTAssertEqual(ClauthMapping.rosterDiff(old: before, new: before).added, [])
        XCTAssertEqual(ClauthMapping.rosterDiff(old: before, new: before).removed, [])
    }
}
