import XCTest
@testable import Pulse

final class ClauthFetchGuardTests: XCTestCase {
    func testExtrasFromTheFixtureRosterIsEmpty() throws {
        let settings = try ClauthFixture.settings()
        XCTAssertEqual(ClauthFetchGuard.extras(settings.shownAccounts), [])
    }

    func testAnAccountPulseSignedInToIsStillAnExtra() throws {
        let settings = try ClauthFixture.settings()
        let added = settings.addAccount(.codex, label: "Second", slot: "9F1C")
        XCTAssertEqual(ClauthFetchGuard.extras(settings.shownAccounts), [added])
    }

    func testSlotAndIDPredicates() {
        XCTAssertTrue(ClauthFetchGuard.isClauthSlot(AccountKey(.claudeCode, slot: "clauth:fx-main")))
        XCTAssertFalse(ClauthFetchGuard.isClauthSlot(AccountKey(.claudeCode)))
        XCTAssertFalse(ClauthFetchGuard.isClauthSlot(AccountKey(.claudeCode, slot: "clauthy")))
        XCTAssertTrue(ClauthFetchGuard.isClauthID("codex#clauth:fx-codex-dev0"))
        XCTAssertFalse(ClauthFetchGuard.isClauthID("codex"))
        XCTAssertFalse(ClauthFetchGuard.isClauthID("nonsense#clauth:x"))
    }

    @MainActor
    func testApplyClauthReplacesEveryClauthSlotAndLeavesTheRestAlone() throws {
        let settings = try ClauthFixture.settings()
        let store = UsageStore(settings: settings)
        let readings = ClauthMapping.readings(try ClauthFixture.status(), freshness: .live)
        store.applyClauth(readings)
        XCTAssertEqual(store.usage.keys.filter(ClauthFetchGuard.isClauthID).count, 7)
        XCTAssertNotNil(store.usage["claudeCode"], "the primary's placeholder survives")
        // A second publish with one profile gone drops that slot.
        var fewer = readings
        fewer["codex#clauth:fx-code-bk"] = nil
        store.applyClauth(fewer)
        XCTAssertNil(store.usage["codex#clauth:fx-code-bk"])
        XCTAssertEqual(store.usage.keys.filter(ClauthFetchGuard.isClauthID).count, 6)
    }
}
