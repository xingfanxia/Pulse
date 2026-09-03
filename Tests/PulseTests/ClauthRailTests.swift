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
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.claudeCode, slot: "clauth:fx-main"), settings: settings, status: status), "main")
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.codex, slot: "clauth:fx-codex-xfx"), settings: settings, status: status), "codex-xfx")
        XCTAssertEqual(ClauthCaption.label(for: AccountKey(.cursor), settings: settings, status: status), "Cursor")
        XCTAssertTrue(ClauthCaption.isActive(AccountKey(.claudeCode, slot: "clauth:fx-main"), status: status))
        XCTAssertTrue(ClauthCaption.isActive(AccountKey(.codex, slot: "clauth:fx-codex-dev0"), status: status))
        XCTAssertFalse(ClauthCaption.isActive(AccountKey(.claudeCode, slot: "clauth:fx-cl"), status: status))
        XCTAssertFalse(ClauthCaption.isActive(AccountKey(.claudeCode), status: status))
    }

    func testInnerWindowIsTheOtherUnscopedWindowWeeklyFirst() throws {
        let status = try ClauthFixture.status()
        let main = ClauthMapping.usage(for: try ClauthFixture.profile("fx-main", in: status), freshness: .live)
        XCTAssertEqual(ClauthRingExtras.innerWindow(for: main, pinned: "5h")?.id, "7d")
        XCTAssertEqual(ClauthRingExtras.innerWindow(for: main, pinned: "7d")?.id, "5h")
        XCTAssertEqual(ClauthRingExtras.innerWindow(for: main, pinned: "7d fable")?.id, "7d", "never a scoped window")
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
        let activeOnly = ClauthVisibility(defaults: nil)
        XCTAssertEqual(activeOnly.activity, .activeOnly, "the default")
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
        let plainWidth = DockLayout.width, plainLength = DockLayout.itemLength(on: .vertical), plainTop = DockLayout.itemLength(on: .horizontal)
        XCTAssertEqual(DockLayout.captionHeight(on: .vertical), 0)
        PanelMetrics.showCaptions(true)
        XCTAssertEqual(DockLayout.width, plainWidth + 24 * PanelMetrics.scale, "88pt rail for the names")
        XCTAssertEqual(DockLayout.captionHeight(on: .vertical), DockLayout.ringToTextSpacing + 11 * PanelMetrics.scale)
        XCTAssertEqual(DockLayout.itemLength(on: .vertical), plainLength + DockLayout.captionHeight(on: .vertical))
        XCTAssertEqual(DockLayout.captionHeight(on: .horizontal), 0)
        XCTAssertEqual(DockLayout.itemLength(on: .horizontal), plainTop, "no captions across the top")
        XCTAssertEqual(DockLayout.length(for: 7, on: .vertical), DockLayout.endPadding(docked: true) * 2 + DockLayout.itemLength(on: .vertical) * 7 + DockLayout.itemSpacing * 6)
    }

    func testRailSettingsPersistAndMirrorTheMetric() {
        let suite = "clp-rail-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let before = PanelMetrics.showsCaptions
        defer { PanelMetrics.showCaptions(before) }
        let fresh = ClauthVisibility(defaults: defaults)
        XCTAssertTrue(fresh.railCaptions); XCTAssertTrue(fresh.innerRing); XCTAssertEqual(fresh.activity, .activeOnly)
        XCTAssertTrue(PanelMetrics.showsCaptions, "the initialiser mirrors the metric")
        fresh.railCaptions = false; fresh.innerRing = false; fresh.activity = .all
        XCTAssertFalse(PanelMetrics.showsCaptions)
        let again = ClauthVisibility(defaults: defaults)
        XCTAssertFalse(again.railCaptions); XCTAssertFalse(again.innerRing); XCTAssertEqual(again.activity, .all)
    }
}
