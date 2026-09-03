import XCTest
@testable import Pulse

@MainActor
final class ClauthWatcherTests: XCTestCase {
    private var home: URL!

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory
            .appending(path: "clauth-watcher-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func write(generatedAt: Date, modified: Date) throws {
        var object = try ClauthFixture.json()
        object["generated_at"] = ClauthISO.string(generatedAt)
        let data = try JSONSerialization.data(withJSONObject: object)
        let file = ClauthPaths.statusFile(in: home)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    }

    private let visibility = ClauthVisibility(defaults: nil)

    private func make() throws -> (AppSettings, UsageStore, ClauthWatcher) {
        let settings = try ClauthFixture.settings(roster: false)
        let store = UsageStore(settings: settings)
        return (settings, store, ClauthWatcher(settings: settings, store: store, home: home, visibility: visibility))
    }

    func testInactiveProfilesLeaveTheRailWithoutLeavingTheRoster() throws {
        try write(generatedAt: Date(), modified: Date())
        let (settings, _, watcher) = try make()
        watcher.tick()
        XCTAssertEqual(visibility.inactiveAccounts, [])
        var announced = 0
        settings.onChange = { announced += 1 }
        var object = try ClauthFixture.json()
        ClauthFixture.editProfile(&object, "fx-code-bk") { $0["tier"] = "free" }
        try JSONSerialization.data(withJSONObject: object).write(to: ClauthPaths.statusFile(in: home))
        watcher.reload()
        XCTAssertEqual(visibility.inactiveAccounts, ["codex#clauth:fx-code-bk"])
        XCTAssertEqual(announced, 1, "a rail that got shorter is announced even though the roster did not move")
        XCTAssertEqual(settings.clauthAccounts.count, 7, "still in the roster, still in the Order rows")
        let shown = ClauthVisibility.shown(settings.orderedAccounts, settings: settings, state: visibility)
        XCTAssertEqual(shown.filter(ClauthFetchGuard.isClauthSlot).count, 6)
    }

    func testOneTickPublishesRosterAndReadingsFromTheFile() throws {
        try write(generatedAt: Date(), modified: Date())
        let (settings, store, watcher) = try make()
        watcher.tick()
        XCTAssertEqual(watcher.freshness, .live)
        XCTAssertEqual(settings.clauthAccounts.count, 7)
        XCTAssertEqual(settings.shownAccounts.filter(ClauthFetchGuard.isClauthSlot).count, 7)
        XCTAssertEqual(store.usage["claudeCode#clauth:fx-main"]?.windows.count, 3)
        XCTAssertEqual(store.usage["claudeCode#clauth:fx-main"]?.state, .live)
        XCTAssertEqual(store.usage["claudeCode#clauth:fx-cl"]?.state, .stale, "RateLimited reads stale even while the daemon ticks")
    }

    func testStaleGeneratedAtWithFreshMtimeIsStillLive() throws {
        try write(generatedAt: Date().addingTimeInterval(-7200), modified: Date())
        let (_, store, watcher) = try make()
        watcher.tick()
        XCTAssertEqual(watcher.freshness, .live)
        XCTAssertEqual(store.usage["claudeCode#clauth:fx-main"]?.state, .live)
    }

    func testTwoHourOldFileReadsStaleThenRecovers() throws {
        let old = Date().addingTimeInterval(-7200)
        try write(generatedAt: old, modified: old)
        let (_, store, watcher) = try make()
        watcher.tick()
        XCTAssertEqual(watcher.freshness, .dead)
        let main = try XCTUnwrap(store.usage["claudeCode#clauth:fx-main"])
        XCTAssertEqual(main.state, .stale)
        XCTAssertNotNil(main.observedAt, "the card footnote can say 'As of …'")

        try write(generatedAt: Date(), modified: Date())
        watcher.tick()
        XCTAssertEqual(watcher.freshness, .live)
        XCTAssertEqual(store.usage["claudeCode#clauth:fx-main"]?.state, .live)
    }

    func testMissingFileEmptiesTheRosterAndPrimariesReturn() throws {
        try write(generatedAt: Date(), modified: Date())
        let (settings, store, watcher) = try make()
        watcher.tick()
        XCTAssertEqual(settings.clauthAccounts.count, 7)
        try FileManager.default.removeItem(at: ClauthPaths.statusFile(in: home))
        watcher.tick()
        XCTAssertEqual(settings.clauthAccounts, [])
        XCTAssertEqual(watcher.freshness, .dead)
        XCTAssertEqual(store.usage.keys.filter(ClauthFetchGuard.isClauthID).count, 0)
        XCTAssertTrue(settings.shownAccounts.contains(AccountKey(.claudeCode)))
    }

    func testUnsupportedSchemaPublishesNothing() throws {
        var object = try ClauthFixture.json()
        object["schema"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: ClauthPaths.statusFile(in: home))
        let (settings, store, watcher) = try make()
        watcher.tick()
        XCTAssertEqual(settings.clauthAccounts, [])
        XCTAssertEqual(store.usage.keys.filter(ClauthFetchGuard.isClauthID).count, 0)
    }

    func testTornReadKeepsTheLastGoodFeed() throws {
        try write(generatedAt: Date(), modified: Date())
        let (settings, _, watcher) = try make()
        watcher.tick()
        XCTAssertEqual(settings.clauthAccounts.count, 7)
        try Data("{\"schema\": 1, \"gener".utf8).write(to: ClauthPaths.statusFile(in: home))
        watcher.tick()
        XCTAssertEqual(settings.clauthAccounts.count, 7, "a half-written file must not blank the rail")
    }

    func testRosterOrderFollowsTheActiveSlotUntilTheUserOrders() throws {
        try write(generatedAt: Date(), modified: Date())
        let (settings, _, watcher) = try make()
        watcher.tick()
        XCTAssertEqual(settings.clauthAccounts.first?.id, "claudeCode#clauth:fx-main")
        var object = try ClauthFixture.json()
        object["active_profile"] = "fx-cl"
        try JSONSerialization.data(withJSONObject: object).write(to: ClauthPaths.statusFile(in: home))
        watcher.reload()
        XCTAssertEqual(settings.clauthAccounts.first?.id, "claudeCode#clauth:fx-cl")
    }

    func testSandboxHomeComesFromTheEnvironmentOnly() {
        // The process running the tests has no override, so the default is
        // the real home — which the watcher under test never touches.
        XCTAssertEqual(ClauthPaths.home.lastPathComponent, ".clauth")
        XCTAssertEqual(ClauthPaths.statusFile(in: home).lastPathComponent, "status.json")
        XCTAssertEqual(ClauthPaths.socket(in: home).lastPathComponent, "clauthd.sock")
    }
}
