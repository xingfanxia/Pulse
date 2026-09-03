import Foundation
import XCTest
@testable import Pulse

/// The seven-profile feed every clauth test reads: 3 claude / 4 codex, named
/// `fx-…` so a ring wearing that name proves the sandbox is being read.
enum ClauthFixture {
    static var url: URL {
        guard let url = Bundle.module.url(forResource: "status", withExtension: "json", subdirectory: "Fixtures") else {
            fatalError("Fixtures/status.json is missing from the test bundle")
        }
        return url
    }

    static func data() throws -> Data { try Data(contentsOf: url) }

    static func status() throws -> ClauthStatus {
        try JSONDecoder().decode(ClauthStatus.self, from: data())
    }

    static func json() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data()) as? [String: Any])
    }

    /// The fixture with an edit applied, re-decoded.
    static func status(mutating edit: (inout [String: Any]) -> Void) throws -> ClauthStatus {
        var object = try json()
        edit(&object)
        return try JSONDecoder().decode(ClauthStatus.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func editProfile(_ object: inout [String: Any], _ name: String, _ edit: (inout [String: Any]) -> Void) {
        var profiles = object["profiles"] as? [[String: Any]] ?? []
        for index in profiles.indices where profiles[index]["name"] as? String == name {
            edit(&profiles[index])
        }
        object["profiles"] = profiles
    }

    static func profile(_ name: String, in status: ClauthStatus) throws -> ClauthStatus.Profile {
        try XCTUnwrap(status.profile(named: name), "profile \(name) missing from the fixture")
    }

    /// A profile built from a handful of fields, everything else defaulted
    /// by the additive decoder.
    static func profile(_ fields: [String: Any]) throws -> ClauthStatus.Profile {
        var object = fields
        if object["name"] == nil { object["name"] = "fx-synthetic" }
        return try JSONDecoder().decode(ClauthStatus.Profile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func window(_ label: String, pct: Double, resets: String?) -> ClauthStatus.Window {
        ClauthStatus.Window(label: label, utilizationPct: pct, resetsAt: resets)
    }

    static let far = "2030-01-01T00:00:00+00:00"
    static let past = "2026-01-01T00:00:00+00:00"

    /// All twelve providers enabled, the given rail order, and the fixture
    /// roster published — what `AppSettings` looks like after the watcher
    /// has run once.
    static func settings(order: [String] = [], roster: Bool = true) throws -> AppSettings {
        let settings = AppSettings(providerOrder: order)
        if roster { settings.clauthAccounts = ClauthMapping.roster(try status()) }
        return settings
    }

    static func ids(_ accounts: [AccountKey]) -> [String] { accounts.map(\.id) }
}
