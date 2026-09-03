import XCTest
@testable import Pulse

final class ClauthRingMenuTests: XCTestCase {
    func testActiveRowHasNoSwitch() throws {
        let status = try ClauthFixture.status()
        let items = ClauthRingMenu.items(for: try ClauthFixture.profile("fx-main", in: status), status: status)
        XCTAssertFalse(items.contains { if case .switchTo = $0 { return true } else { return false } })
        XCTAssertEqual(items, [.refresh, .reauthenticate, .rename, .hide])
    }

    func testInactiveRowOffersSwitch() throws {
        let status = try ClauthFixture.status()
        let items = ClauthRingMenu.items(for: try ClauthFixture.profile("fx-cl", in: status), status: status)
        XCTAssertEqual(items, [.switchTo("fx-cl"), .refresh, .reauthenticate, .rename, .hide])
    }

    func testBrokenLoginLeadsWithReauthenticate() throws {
        let status = try ClauthFixture.status { object in
            ClauthFixture.editProfile(&object, "fx-cl") { $0["auth_status"] = "broken" }
        }
        let items = ClauthRingMenu.items(for: try ClauthFixture.profile("fx-cl", in: status), status: status)
        XCTAssertEqual(items.first, .reauthenticate)
        XCTAssertEqual(items.filter { $0 == .reauthenticate }.count, 1)
    }

    func testThirdPartyRowHasNoReauth() throws {
        let status = try ClauthFixture.status { object in
            ClauthFixture.editProfile(&object, "fx-backup") { $0["provider"] = "moonshot"; $0["auth_status"] = "broken" }
        }
        let items = ClauthRingMenu.items(for: try ClauthFixture.profile("fx-backup", in: status), status: status)
        XCTAssertFalse(items.contains(.reauthenticate))
        XCTAssertFalse(items.contains(.captureCodexLogin))
        XCTAssertEqual(items.first, .switchTo("fx-backup"))
    }

    func testCodexRowOffersCaptureAndEveryRowCanHide() throws {
        let status = try ClauthFixture.status()
        for profile in status.profiles {
            let items = ClauthRingMenu.items(for: profile, status: status)
            XCTAssertEqual(items.last, .hide, profile.name)
            XCTAssertEqual(items.contains(.captureCodexLogin), profile.harness == .codex, profile.name)
        }
        let active = ClauthRingMenu.items(for: try ClauthFixture.profile("fx-codex-dev0", in: status), status: status)
        XCTAssertEqual(active, [.refresh, .reauthenticate, .captureCodexLogin, .rename, .hide])
    }
}
