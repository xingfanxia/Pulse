import XCTest
@testable import Pulse

final class ClauthProxyModeTests: XCTestCase {
    private let direct = """
    model = "gpt-5"
    approval_policy = "never"

    [projects."/Users/x/repo"]
    trust_level = "trusted"
    """

    func testDirectConfigIsNotRouted() {
        XCTAssertFalse(ClauthProxyMode.isRouted(config: direct))
        XCTAssertFalse(ClauthProxyMode.hasProviderBlock(config: direct))
    }

    func testEnableInsertsRoutingLineAndProviderBlock() {
        let on = ClauthProxyMode.setRouting(config: direct, on: true)
        XCTAssertTrue(ClauthProxyMode.isRouted(config: on))
        XCTAssertTrue(ClauthProxyMode.hasProviderBlock(config: on))
        XCTAssertTrue(on.hasPrefix("model_provider = \"clauth\"\n"), on)
        XCTAssertTrue(on.contains("base_url = \"http://127.0.0.1:4517/backend-api/codex\""))
        XCTAssertTrue(on.contains("[projects.\"/Users/x/repo\"]"), "other tables untouched")
    }

    func testEnableReplacesAnExistingTopLevelProvider() {
        let foreign = "model_provider = \"azure\"\n" + direct
        let on = ClauthProxyMode.setRouting(config: foreign, on: true)
        XCTAssertTrue(ClauthProxyMode.isRouted(config: on))
        XCTAssertEqual(on.components(separatedBy: "model_provider =").count - 1, 1, "one top-level line, replaced")
    }

    func testDisableRemovesOnlyTheClauthRoutingLineAndKeepsTheBlock() {
        let on = ClauthProxyMode.setRouting(config: direct, on: true)
        let off = ClauthProxyMode.setRouting(config: on, on: false)
        XCTAssertFalse(ClauthProxyMode.isRouted(config: off))
        XCTAssertTrue(ClauthProxyMode.hasProviderBlock(config: off), "sessions started under proxy mode reference the block by name")
        XCTAssertTrue(off.contains("approval_policy = \"never\""))
    }

    func testDisableLeavesAForeignProviderAlone() {
        let foreign = "model_provider = \"azure\"\n" + direct
        XCTAssertEqual(ClauthProxyMode.setRouting(config: foreign, on: false), foreign)
    }

    func testTableScopedAndCommentedProviderLinesDoNotCount() {
        let scoped = direct + "\n[model_providers.clauth]\nmodel_provider = \"clauth\"\n"
        XCTAssertFalse(ClauthProxyMode.isRouted(config: scoped))
        let commented = "# model_provider = \"clauth\"\n" + direct
        XCTAssertFalse(ClauthProxyMode.isRouted(config: commented))
    }

    func testRoundTripIsStable() {
        let on = ClauthProxyMode.setRouting(config: direct, on: true)
        XCTAssertEqual(ClauthProxyMode.setRouting(config: on, on: true), on)
        let off = ClauthProxyMode.setRouting(config: on, on: false)
        XCTAssertEqual(ClauthProxyMode.setRouting(config: off, on: false), off)
    }

    func testApplyEditsOnlyTheGivenConfigAndWritesAPulseBackup() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "clp-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: "config.toml")
        let backup = home.appending(path: "config.toml.bak-pulse")
        try direct.write(to: config, atomically: true, encoding: .utf8)

        try ClauthProxyMode.apply(on: true, configPath: config, backupPath: backup)
        XCTAssertTrue(ClauthProxyMode.routed(configPath: config))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), direct, "the backup is the pre-edit file")
        try ClauthProxyMode.apply(on: false, configPath: config, backupPath: backup)
        XCTAssertFalse(ClauthProxyMode.routed(configPath: config))
        XCTAssertTrue(ClauthProxyMode.hasProviderBlock(config: try String(contentsOf: config, encoding: .utf8)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.path).sorted(), ["config.toml", "config.toml.bak-pulse"])
    }

    func testLaunchctlGoesThroughTheShimUnderTheSandbox() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "clp-shim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: "bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let shim = home.appending(path: "bin/clauth")
        let log = home.appending(path: "shim.log")
        try "#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"\(log.path)\"\n".write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let plist = home.appending(path: "com.clauth.proxy.plist")
        try "<plist/>".write(to: plist, atomically: true, encoding: .utf8)

        let sandboxed = ClauthCLI.Environment(sandboxHome: home.path, sandboxBin: shim.path)
        let outcome = await ClauthProxyMode.ensureProxyLoaded(plist: plist.path, environment: sandboxed)
        XCTAssertEqual(outcome?.isOK, true)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "/bin/launchctl bootstrap gui/\(getuid()) \(plist.path)\n")

        let refused = await ClauthProxyMode.ensureProxyLoaded(plist: plist.path, environment: .init(sandboxHome: home.path, sandboxBin: nil))
        XCTAssertEqual(refused, .unavailable(.sandboxed))
        let missing = await ClauthProxyMode.ensureProxyLoaded(plist: home.appending(path: "missing.plist").path, environment: sandboxed)
        XCTAssertNil(missing)
    }

    func testCodexHomeFollowsTheEnvironmentDefault() {
        XCTAssertEqual(ClauthProxyMode.configPath.lastPathComponent, "config.toml")
        XCTAssertEqual(ClauthProxyMode.backupPath.lastPathComponent, "config.toml.bak-pulse")
        XCTAssertTrue(ClauthProxyMode.launchAgentPlist.hasSuffix("Library/LaunchAgents/com.clauth.proxy.plist"))
    }
}
