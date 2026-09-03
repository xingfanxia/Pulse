import XCTest
@testable import Pulse

final class ClauthRailTests: XCTestCase {
    func testShortNamesDropTheSharedPrefixAtASeparator() {
        let live = ["ax-main", "ax-backup", "ax-cl", "ax-codex-dev0", "ax-codex-xfx", "ax-code-bk", "ax-codex-cl"]
        let short = ClauthCaption.shortNames(live)
        XCTAssertEqual(short["ax-main"], "main")
        XCTAssertEqual(short["ax-codex-dev0"], "codex-dev0")
        XCTAssertEqual(short["ax-code-bk"], "code-bk")
        XCTAssertEqual(ClauthCaption.shortNames(["fx-main", "fx-cl"]), ["fx-main": "main", "fx-cl": "cl"])
    }

    func testShortNamesLeaveNamesAloneWhenNothingSafeToCut() {
        XCTAssertEqual(ClauthCaption.shortNames(["ax-main"]), ["ax-main": "ax-main"], "one profile")
        XCTAssertEqual(ClauthCaption.shortNames(["work", "home"]), ["work": "work", "home": "home"], "no shared prefix")
        XCTAssertEqual(ClauthCaption.shortNames(["ax", "ax-1"]), ["ax": "ax", "ax-1": "ax-1"], "a prefix that is a whole name")
        XCTAssertEqual(ClauthCaption.shortNames(["abc1", "abc2"]), ["abc1": "abc1", "abc2": "abc2"], "no separator to cut at")
    }

    @MainActor
    func testCaptionLabelAndActive() throws {
        let status = try ClauthFixture.status()
        let settings = try ClauthFixture.settings()
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.claudeCode, slot: "clauth:fx-main"), settings: settings, status: status, style: .email), "fx-main", "the email's local part")
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.codex, slot: "clauth:fx-codex-xfx"), settings: settings, status: status, style: .email), "fx-xfx")
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.claudeCode, slot: "clauth:fx-main"), settings: settings, status: status, style: .name), "main")
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.codex, slot: "clauth:fx-codex-xfx"), settings: settings, status: status, style: .name), "codex-xfx")
        let noEmail = try ClauthFixture.status { object in ClauthFixture.editProfile(&object, "fx-cl") { $0["account_email"] = nil } }
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.claudeCode, slot: "clauth:fx-cl"), settings: settings, status: noEmail, style: .email), "cl", "no email ⇒ the short name")
        XCTAssertEqual(ClauthCaption.localPart(of: " xingfanxia@gmail.com "), "xingfanxia")
        XCTAssertNil(ClauthCaption.localPart(of: "@nope"))
        XCTAssertNil(ClauthCaption.localPart(of: "not-an-address"))
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.cursor), settings: settings, status: status, style: .email), "Cursor")
        XCTAssertTrue(ClauthCaption.isActive(AccountKey(.claudeCode, slot: "clauth:fx-main"), status: status))
        XCTAssertTrue(ClauthCaption.isActive(AccountKey(.codex, slot: "clauth:fx-codex-dev0"), status: status))
        XCTAssertFalse(ClauthCaption.isActive(AccountKey(.claudeCode, slot: "clauth:fx-cl"), status: status))
        XCTAssertFalse(ClauthCaption.isActive(AccountKey(.claudeCode), status: status))
    }

    func testInnerWindowIsTheOtherUnscopedWindowFiveHourInsideTheWeek() throws {
        let status = try ClauthFixture.status()
        let main = ClauthMapping.usage(for: try ClauthFixture.profile("fx-main", in: status), freshness: .live)
        let account = AccountKey(.claudeCode, slot: "clauth:fx-main")
        XCTAssertEqual(ClauthMapping.defaultPin(for: account, in: main), "7d", "outer ring = the week")
        XCTAssertEqual(ClauthRingExtras.innerWindow(for: main, pinned: "7d")?.id, "5h", "inner arc = the 5h window")
        XCTAssertEqual(ClauthRingExtras.innerWindow(for: main, pinned: "5h")?.id, "7d", "a user pin on 5h flips them")
        XCTAssertEqual(ClauthRingExtras.innerWindow(for: main, pinned: "7d fable")?.id, "7d", "under a per-model pin the unscoped week is the gate to show")
        let codex = ClauthMapping.usage(for: try ClauthFixture.profile("fx-codex-dev0", in: status), freshness: .live)
        XCTAssertNil(ClauthRingExtras.innerWindow(for: codex, pinned: "7d"), "weekly-only stays a single ring")
        let both = ClauthMapping.usage(for: try ClauthFixture.profile("fx-codex-cl", in: status), freshness: .live)
        XCTAssertEqual(ClauthRingExtras.innerWindow(for: both, pinned: "7d")?.id, "5h")
    }

    @MainActor
    func testActivityMarkPolicy() throws {
        let status = try ClauthFixture.status()
        let settings = try ClauthFixture.settings()
        let active = AccountKey(.claudeCode, slot: "clauth:fx-main"), idle = AccountKey(.claudeCode, slot: "clauth:fx-cl"), primary = AccountKey(.claudeCode)
        let off = ClauthVisibility(defaults: nil, activity: .off)
        let all = ClauthVisibility(defaults: nil, activity: .all)
        let activeOnly = ClauthVisibility(defaults: nil, activity: .activeOnly)
        XCTAssertEqual(ClauthVisibility(defaults: nil).activity, .off, "off by default — the mark says nothing about the account")
        XCTAssertEqual(ClauthVisibility(defaults: nil).captionStyle, .email, "labels read the email by default")
        for account in [active, idle, primary] {
            XCTAssertFalse(ClauthVisibility.showsActivity(for: account, settings: settings, state: off, status: status))
            XCTAssertTrue(ClauthVisibility.showsActivity(for: account, settings: settings, state: all, status: status))
        }
        XCTAssertTrue(ClauthVisibility.showsActivity(for: active, settings: settings, state: activeOnly, status: status))
        XCTAssertFalse(ClauthVisibility.showsActivity(for: idle, settings: settings, state: activeOnly, status: status))
        XCTAssertTrue(ClauthVisibility.showsActivity(for: primary, settings: settings, state: activeOnly, status: status), "a primary is its provider's live login")
    }

    func testCaptionsChangeTheRailBudgetOnTheVerticalAxisOnly() {
        let before = PanelMetrics.showsCaptions
        defer { PanelMetrics.showCaptions(before) }
        PanelMetrics.showCaptions(false)
        let plainWidth = DockLayout.width, plainThick = DockLayout.thickness(on: .vertical), plainLength = DockLayout.itemLength(on: .vertical)
        let plainTop = DockLayout.itemLength(on: .horizontal), plainTopThick = DockLayout.thickness(on: .horizontal)
        XCTAssertEqual(DockLayout.captionHeight(on: .vertical), 0)
        PanelMetrics.showCaptions(true)
        XCTAssertEqual(DockLayout.width, plainWidth, "the berth's own width is upstream's")
        XCTAssertEqual(DockLayout.thickness(on: .vertical), plainThick + 24 * PanelMetrics.scale, "88pt side rail for the names")
        XCTAssertEqual(DockLayout.thickness(on: .horizontal), plainTopThick, "the top rail is not widened for captions it never draws")
        XCTAssertEqual(DockLayout.captionHeight(on: .vertical), DockLayout.ringToTextSpacing + 13 * PanelMetrics.scale)
        XCTAssertEqual(DockLayout.itemLength(on: .vertical), plainLength + DockLayout.captionHeight(on: .vertical))
        XCTAssertEqual(DockLayout.captionHeight(on: .horizontal), 0)
        XCTAssertEqual(DockLayout.itemLength(on: .horizontal), plainTop, "no captions across the top")
        XCTAssertEqual(DockLayout.length(for: 7, on: .vertical), DockLayout.endPadding(docked: true) * 2 + DockLayout.itemLength(on: .vertical) * 7 + DockLayout.itemSpacing * 6)
    }

    func testCaptionBudgetHoldsWithSidePercentagesOffAndWithTheLabelLeading() {
        let captions = PanelMetrics.showsCaptions, side = PanelMetrics.sideRailShowsPercentages, leads = PanelMetrics.labelAboveRing
        defer { PanelMetrics.showCaptions(captions); PanelMetrics.showSidePercentages(side); PanelMetrics.putLabelAboveRing(leads) }
        PanelMetrics.showCaptions(true)
        PanelMetrics.showSidePercentages(false)
        PanelMetrics.putLabelAboveRing(false)
        // The caption still draws when the percent label is off, so the budget still holds it.
        XCTAssertEqual(DockLayout.itemLength(on: .vertical), DockLayout.ringDiameter + DockLayout.captionHeight(on: .vertical))
        XCTAssertEqual(DockLayout.ringOffsetInItem(on: .vertical), 0)
        PanelMetrics.putLabelAboveRing(true)
        XCTAssertEqual(DockLayout.ringOffsetInItem(on: .vertical), DockLayout.captionHeight(on: .vertical), "the caption leads the ring with the label")
        PanelMetrics.showSidePercentages(true)
        XCTAssertEqual(DockLayout.ringOffsetInItem(on: .vertical), DockLayout.percentTextHeight + DockLayout.ringToTextSpacing + DockLayout.captionHeight(on: .vertical))
        XCTAssertEqual(DockLayout.ringOffsetInItem(on: .horizontal), PanelMetrics.topRailShowsPercentages ? DockLayout.percentTextHeight + DockLayout.ringToTextSpacing : 0, "no caption term across the top")
    }

    @MainActor
    func testSliverAlertSeesBothWindowsOfTheActiveClauthRingAndIgnoresBackups() throws {
        let status = try ClauthFixture.status()
        // fx-main is the active claude slot: weekly outside, 5h inside — both count.
        let main = ClauthMapping.usage(for: try ClauthFixture.profile("fx-main", in: status), freshness: .live)
        let active = RailEntry(usage: main, headline: try XCTUnwrap(main.headlineWindow(preferring: "7d")))
        XCTAssertEqual(ClauthRingExtras.alertWindows(active, status: status).map(\.id), ["7d", "5h"])
        // fx-cl is a spent BACKUP: the daemon's rotation business, never an alarm.
        let cl = ClauthMapping.usage(for: try ClauthFixture.profile("fx-cl", in: status), freshness: .live)
        let backup = RailEntry(usage: cl, headline: try XCTUnwrap(cl.headlineWindow(preferring: "7d")))
        XCTAssertTrue(cl.windows.contains { $0.isExhausted })
        XCTAssertEqual(ClauthRingExtras.alertWindows(backup, status: status), [])
        // A spent active codex slot still alarms.
        let flipped = try ClauthFixture.status { $0["active_codex_profile"] = "fx-codex-xfx" }
        let xfx = ClauthMapping.usage(for: try ClauthFixture.profile("fx-codex-xfx", in: flipped), freshness: .live)
        let codex = RailEntry(usage: xfx, headline: try XCTUnwrap(xfx.headlineWindow(preferring: "7d")))
        XCTAssertEqual(ClauthRingExtras.alertWindows(codex, status: flipped).map(\.id), ["7d"])
        XCTAssertEqual(ClauthRingExtras.alertWindows(codex, status: status), [], "the same ring, not active ⇒ silent")
        // Pulse's own rings keep upstream's rule: the headline.
        let primary = RailEntry(usage: .unavailable(.cursor, reason: .loading), headline: nil)
        XCTAssertEqual(ClauthRingExtras.alertWindows(primary, status: status), [])
    }

    func testInnerArcDrawsFullForASpentWindowEitherWayRound() throws {
        let cl = ClauthMapping.usage(for: try ClauthFixture.profile("fx-cl", in: try ClauthFixture.status()), freshness: .live)
        let spent = try XCTUnwrap(cl.windows.first { $0.id == "5h" })
        XCTAssertTrue(spent.isExhausted)
        XCTAssertEqual(ClauthRingExtras.arcFraction(spent, showsRemaining: true), 1)
        XCTAssertEqual(ClauthRingExtras.arcFraction(spent, showsRemaining: false), 1)
        let weekly = try XCTUnwrap(cl.windows.first { $0.id == "7d" })
        XCTAssertEqual(ClauthRingExtras.arcFraction(weekly, showsRemaining: false), 0.67, accuracy: 1e-9)
        XCTAssertEqual(ClauthRingExtras.arcFraction(weekly, showsRemaining: true), 0.33, accuracy: 1e-9)
    }

    func testShortNamesToleratesADuplicateName() {
        XCTAssertEqual(ClauthCaption.shortNames(["ax-main", "ax-main", "ax-cl"]), ["ax-main": "main", "ax-cl": "cl"])
    }

    func testTestInstancesDoNotRetuneTheRail() {
        let before = PanelMetrics.showsCaptions
        defer { PanelMetrics.showCaptions(before) }
        PanelMetrics.showCaptions(false)
        let throwaway = ClauthVisibility(defaults: nil)
        throwaway.railCaptions = true
        XCTAssertFalse(PanelMetrics.showsCaptions, "an in-memory instance never writes the process-wide metric")
    }

    func testRailSettingsPersistAndMirrorTheMetric() {
        let suite = "clp-rail-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let before = PanelMetrics.showsCaptions
        defer { PanelMetrics.showCaptions(before) }
        let fresh = ClauthVisibility(defaults: defaults)
        XCTAssertTrue(fresh.railCaptions); XCTAssertTrue(fresh.innerRing); XCTAssertEqual(fresh.activity, .off); XCTAssertEqual(fresh.captionStyle, .email); XCTAssertTrue(fresh.frostedSurface)
        fresh.railCaptions = false; fresh.innerRing = false; fresh.activity = .all; fresh.captionStyle = .name; fresh.frostedSurface = false
        XCTAssertFalse(PanelMetrics.showsCaptions, "a persisted instance mirrors the metric on change")
        let again = ClauthVisibility(defaults: defaults)
        XCTAssertFalse(again.railCaptions); XCTAssertFalse(again.innerRing); XCTAssertEqual(again.activity, .all); XCTAssertEqual(again.captionStyle, .name); XCTAssertFalse(again.frostedSurface)
    }

    func testSliverWidthIsClampedPersistedAndDrivesTheCollapsedSizes() {
        let suite = "clp-sliver-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = ClauthVisibility(defaults: defaults)
        XCTAssertEqual(state.sliverWidth, 10, "wider than upstream's 6 by default")
        state.sliverWidth = 40
        XCTAssertEqual(state.sliverWidth, 24, "clamped to the range")
        state.sliverWidth = 1
        XCTAssertEqual(state.sliverWidth, 4)
        state.sliverWidth = 16
        XCTAssertEqual(ClauthVisibility(defaults: defaults).sliverWidth, 16, "persisted")
        // The shared instance is what DockLayout reads; the hit area never shrinks below upstream's 20pt.
        let before = ClauthVisibility.shared.sliverWidth
        defer { ClauthVisibility.shared.sliverWidth = before }
        ClauthVisibility.shared.sliverWidth = 6
        XCTAssertEqual(DockLayout.collapsedWidth, 6 * PanelMetrics.scale)
        XCTAssertEqual(DockLayout.collapsedHitWidth, 20 * PanelMetrics.scale)
        ClauthVisibility.shared.sliverWidth = 24
        XCTAssertEqual(DockLayout.collapsedWidth, 24 * PanelMetrics.scale)
        XCTAssertEqual(DockLayout.collapsedHitWidth, 32 * PanelMetrics.scale, "the hit area grows with the sliver")
        XCTAssertTrue(PanelHitArea.stripIsContainedInRail(), "the sliver's hit area still sits inside the rail")
    }
}
