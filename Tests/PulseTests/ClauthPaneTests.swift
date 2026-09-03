import XCTest
@testable import Pulse

/// The clauth account pane's verb table and the pane rows' pure copy.
final class ClauthPaneTests: XCTestCase {
    func testClauthAccountPaneNeverOffersSignOutRemoveOrRename() throws {
        let status = try ClauthFixture.status()
        for profile in status.profiles {
            let actions = ClauthAccountPane.actions(for: profile, status: status)
            // The type has no such cases at all — this pins the table's shape.
            XCTAssertTrue(actions.allSatisfy { [.switchTo, .refresh, .reauthenticate, .captureCodexLogin].contains($0) }, profile.name)
            XCTAssertTrue(actions.contains(.refresh))
        }
        XCTAssertEqual(ClauthAccountPane.actions(for: try ClauthFixture.profile("fx-main", in: status), status: status), [.refresh, .reauthenticate])
        XCTAssertEqual(ClauthAccountPane.actions(for: try ClauthFixture.profile("fx-cl", in: status), status: status), [.switchTo, .refresh, .reauthenticate])
        XCTAssertEqual(ClauthAccountPane.actions(for: try ClauthFixture.profile("fx-codex-xfx", in: status), status: status), [.switchTo, .refresh, .reauthenticate, .captureCodexLogin])
        let thirdParty = try ClauthFixture.profile(["name": "fx-relay", "provider": "moonshot"])
        XCTAssertEqual(ClauthAccountPane.actions(for: thirdParty, status: status), [.switchTo, .refresh])
    }

    func testClauthAccountPaneSourceHasNoUpstreamAccountVerbs() throws {
        let source = try String(contentsOfFile: "Sources/Pulse/Clauth/ClauthAccountPane.swift", encoding: .utf8)
        for forbidden in ["\"Sign out\"", "\"Remove account\"", "settings.rename(", "removeAccount(", "AccountCredentialStore"] {
            XCTAssertFalse(source.contains(forbidden), "the clauth account pane must not carry \(forbidden)")
        }
    }

    func testTokenRowSubtitleFollowsTheStatusJsonFlagOnly() {
        XCTAssertTrue(ClauthTokenRow.subtitle(rolling: true).hasPrefix("Fed by the daemon"))
        XCTAssertTrue(ClauthTokenRow.subtitle(rolling: false).hasPrefix("Off"))
    }

    func testSettingsPaneHasAClauthCase() {
        XCTAssertEqual(SettingsPane.clauth.title, "clauth")
        XCTAssertFalse(SettingsPane.clauth.symbol.isEmpty)
    }
}
