import XCTest
@testable import Pulse

final class ClauthVisibilityTests: XCTestCase {
    private func state(hidden: Set<String> = [], hidesPrimaries: Bool = true) -> ClauthVisibility {
        ClauthVisibility(defaults: nil, hiddenAccounts: hidden, hidesPrimaries: hidesPrimaries)
    }

    func testSevenClauthIDsExactlyOnceAndNeitherPrimary() throws {
        let settings = try ClauthFixture.settings()
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: state())
        let clauth = shown.filter(ClauthFetchGuard.isClauthSlot).map(\.id)
        XCTAssertEqual(clauth.count, 7)
        XCTAssertEqual(Set(clauth).count, 7)
        XCTAssertEqual(Set(clauth), Set(ClauthMapping.roster(try ClauthFixture.status()).map(\.id)))
        XCTAssertFalse(shown.contains(AccountKey(.claudeCode)))
        XCTAssertFalse(shown.contains(AccountKey(.codex)))
        // Other enabled primaries are untouched by the flag.
        XCTAssertTrue(shown.contains(AccountKey(.cursor)))
    }

    func testInterleavedUserOrderSurvives() throws {
        let order = ["cursor", "claudeCode#clauth:fx-main", "antigravity", "codex#clauth:fx-codex-dev0", "claudeCode", "codex"]
        let settings = try ClauthFixture.settings(order: order)
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: state())
        XCTAssertEqual(Array(shown.prefix(4)).map(\.id), ["cursor", "claudeCode#clauth:fx-main", "antigravity", "codex#clauth:fx-codex-dev0"])
        XCTAssertEqual(shown.filter(ClauthFetchGuard.isClauthSlot).count, 7)
    }

    func testEmptyRosterReturnsThePrimariesWhateverTheFlagSays() throws {
        let settings = try ClauthFixture.settings(roster: false)
        XCTAssertTrue(settings.clauthAccounts.isEmpty)
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: state(hidesPrimaries: true))
        XCTAssertEqual(shown, settings.orderedAccounts.filter(settings.isEnabled))
        XCTAssertTrue(shown.contains(AccountKey(.claudeCode)))
        XCTAssertTrue(shown.contains(AccountKey(.codex)))
        XCTAssertFalse(shown.isEmpty)
    }

    func testHiddenClauthAccountLeavesTheRail() throws {
        let settings = try ClauthFixture.settings()
        let hidden = state(hidden: ["claudeCode#clauth:fx-backup"])
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: hidden)
        XCTAssertFalse(shown.contains(AccountKey(.claudeCode, slot: "clauth:fx-backup")))
        XCTAssertEqual(shown.filter(ClauthFetchGuard.isClauthSlot).count, 6)
    }

    func testPrimariesReturnWhenHidingIsSwitchedOff() throws {
        let settings = try ClauthFixture.settings()
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: state(hidesPrimaries: false))
        XCTAssertTrue(shown.contains(AccountKey(.claudeCode)))
        XCTAssertTrue(shown.contains(AccountKey(.codex)))
        XCTAssertEqual(shown.filter(ClauthFetchGuard.isClauthSlot).count, 7)
    }

    func testDisabledPrimaryStaysOffTheRail() throws {
        let settings = try ClauthFixture.settings()
        settings.setEnabled(false, for: AccountKey(.cursor))
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: state(hidesPrimaries: false))
        XCTAssertFalse(shown.contains(AccountKey(.cursor)))
    }

    func testEverythingHiddenIsStillNotAnEmptyRail() throws {
        let settings = AppSettings(enabledAccounts: ["claudeCode"])
        settings.clauthAccounts = ClauthMapping.roster(try ClauthFixture.status())
        let all = Set(settings.clauthAccounts.map(\.id))
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: state(hidden: all))
        XCTAssertEqual(shown, [AccountKey(.claudeCode)])
    }

    func testInactiveAccountsAreHiddenByDefaultAndShownWhenTheFlagIsOff() throws {
        let settings = try ClauthFixture.settings()
        let s = state()
        XCTAssertTrue(s.hidesInactive, "on by default")
        XCTAssertTrue(ClauthVisibility.publishInactive(["codex#clauth:fx-code-bk", "claudeCode#clauth:fx-cl"], settings: settings, state: s))
        XCTAssertFalse(ClauthVisibility.publishInactive(["codex#clauth:fx-code-bk", "claudeCode#clauth:fx-cl"], settings: settings, state: s), "unchanged set is not a change")
        let hidden = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: s)
        XCTAssertEqual(hidden.filter(ClauthFetchGuard.isClauthSlot).count, 5)
        XCTAssertFalse(hidden.contains(AccountKey(.codex, slot: "clauth:fx-code-bk")))
        XCTAssertFalse(ClauthVisibility.isShown(AccountKey(.claudeCode, slot: "clauth:fx-cl"), settings: settings, state: s))
        var announced = 0
        settings.onChange = { announced += 1 }
        ClauthVisibility.setHidesInactive(false, settings: settings, state: s)
        XCTAssertEqual(announced, 1)
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: s)
        XCTAssertEqual(shown.filter(ClauthFetchGuard.isClauthSlot).count, 7)
    }

    func testIsShownIsTheOrderRowPredicate() throws {
        let settings = try ClauthFixture.settings()
        let s = state(hidden: ["codex#clauth:fx-code-bk"])
        XCTAssertTrue(ClauthVisibility.isShown(AccountKey(.claudeCode, slot: "clauth:fx-main"), settings: settings, state: s))
        XCTAssertFalse(ClauthVisibility.isShown(AccountKey(.codex, slot: "clauth:fx-code-bk"), settings: settings, state: s))
        XCTAssertFalse(ClauthVisibility.isShown(AccountKey(.claudeCode), settings: settings, state: s))
        XCTAssertTrue(ClauthVisibility.isShown(AccountKey(.cursor), settings: settings, state: s))
        // A clauth id the feed no longer publishes is not shown either.
        XCTAssertFalse(ClauthVisibility.isShown(AccountKey(.claudeCode, slot: "clauth:fx-gone"), settings: settings, state: s))
    }

    func testSetHiddenMutatesStateAndAnnouncesAChange() throws {
        let settings = try ClauthFixture.settings()
        var announced = 0
        settings.onChange = { announced += 1 }
        let s = state()
        let key = AccountKey(.claudeCode, slot: "clauth:fx-cl")
        ClauthVisibility.setHidden(true, for: key, settings: settings, state: s)
        XCTAssertEqual(s.hiddenAccounts, [key.id])
        ClauthVisibility.setHidden(false, for: key, settings: settings, state: s)
        XCTAssertEqual(s.hiddenAccounts, [])
        ClauthVisibility.setHidesPrimaries(false, settings: settings, state: s)
        XCTAssertFalse(s.hidesPrimaries)
        XCTAssertEqual(announced, 3)
    }

    func testShownAccountsHookFeedsTheRail() throws {
        // `AppSettings.shownAccounts` is the one hook the rail draws from.
        let settings = try ClauthFixture.settings()
        XCTAssertEqual(settings.shownAccounts.filter(ClauthFetchGuard.isClauthSlot).count, 7)
        XCTAssertEqual(settings.allAccounts.filter(ClauthFetchGuard.isClauthSlot).count, 7)
        XCTAssertEqual(settings.label(for: AccountKey(.claudeCode, slot: "clauth:fx-main")), "fx-main")
        XCTAssertEqual(settings.label(for: AccountKey(.claudeCode)), "Claude Code")
    }
}
