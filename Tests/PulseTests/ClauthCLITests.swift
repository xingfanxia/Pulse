import XCTest
@testable import Pulse

final class ClauthCLITests: XCTestCase {
    private let sandbox = ClauthCLI.Environment(sandboxHome: "/tmp/clp-sb", sandboxBin: nil)
    private let shimmed = ClauthCLI.Environment(sandboxHome: "/tmp/clp-sb", sandboxBin: "/tmp/clp-sb/bin/clauth")
    private let real = ClauthCLI.Environment(sandboxHome: nil, sandboxBin: nil)

    func testSandboxWithoutAShimRefusesEverySpawn() async {
        XCTAssertEqual(ClauthCLI.launch(program: ClauthCLI.clauth, arguments: ["fx-cl"], environment: sandbox), .failure(.sandboxed))
        XCTAssertEqual(ClauthCLI.launch(program: ClauthCLI.launchctl, arguments: ["list"], environment: sandbox), .failure(.sandboxed))
        for program in [ClauthCLI.clauth, ClauthCLI.launchctl] {
            let outcome = await ClauthCLI.run(program: program, arguments: ["x"], environment: sandbox) { launch, _, _ in
                XCTFail("the spawn closure must never be reached under the sandbox: \(launch)")
                return .ok(stdout: "", stderr: "")
            }
            XCTAssertEqual(outcome, .unavailable(.sandboxed))
        }
    }

    func testSandboxWithAShimHandsEveryProgramToTheShim() {
        XCTAssertEqual(
            ClauthCLI.launch(program: ClauthCLI.clauth, arguments: ["login", "fx-main"], environment: shimmed),
            .success(.init(executable: "/tmp/clp-sb/bin/clauth", arguments: ["clauth", "login", "fx-main"]))
        )
        XCTAssertEqual(
            ClauthCLI.launch(program: ClauthCLI.launchctl, arguments: ["bootstrap", "gui/501", "x.plist"], environment: shimmed),
            .success(.init(executable: "/tmp/clp-sb/bin/clauth", arguments: ["/bin/launchctl", "bootstrap", "gui/501", "x.plist"]))
        )
    }

    func testOutsideTheSandboxTheRealBinaryIsLocatedOrRefused() {
        XCTAssertEqual(
            ClauthCLI.launch(program: ClauthCLI.clauth, arguments: ["fx-cl"], environment: real, locate: { _ in "/opt/homebrew/bin/clauth" }),
            .success(.init(executable: "/opt/homebrew/bin/clauth", arguments: ["fx-cl"]))
        )
        XCTAssertEqual(
            ClauthCLI.launch(program: ClauthCLI.clauth, arguments: ["fx-cl"], environment: real, locate: { _ in nil }),
            .failure(.notInstalled("clauth"))
        )
        XCTAssertEqual(ClauthCLI.clauthBinary(program: "/bin/ls"), "/bin/ls")
        XCTAssertNil(ClauthCLI.clauthBinary(program: "/nonexistent/binary"))
    }

    func testRealSpawnCapturesOutputAndPipesStdin() async {
        let echo = await ClauthCLI.run(program: "/bin/echo", arguments: ["hello"], environment: real)
        XCTAssertEqual(echo, .ok(stdout: "hello\n", stderr: ""))
        let cat = await ClauthCLI.run(program: "/bin/cat", arguments: [], stdin: "down the pipe", environment: real)
        XCTAssertEqual(cat, .ok(stdout: "down the pipe\n", stderr: ""))
        let sh = await ClauthCLI.run(program: "/bin/sh", arguments: ["-c", "echo oops >&2; exit 3"], environment: real)
        XCTAssertEqual(sh, .failed(status: 3, stderr: "oops\n"))
    }

    func testWatchdogTerminatesAChildThatOutlivesItsTimeout() async {
        let outcome = await ClauthCLI.run(program: "/bin/sleep", arguments: ["30"], timeout: .milliseconds(300), environment: real)
        XCTAssertFalse(outcome.isOK)
    }

    func testArgvShapesMatchCcsbar() {
        XCTAssertEqual(ClauthCLI.loginArgs("fx-main", newOnly: false, codex: false, browser: true), ["login", "fx-main"])
        XCTAssertEqual(ClauthCLI.loginArgs("fx-new", newOnly: true, codex: false, browser: true), ["login", "--new", "fx-new"])
        XCTAssertEqual(ClauthCLI.loginArgs("fx-codex-xfx", newOnly: false, codex: true, browser: false), ["login", "fx-codex-xfx", "--codex"])
        XCTAssertEqual(ClauthCLI.loginArgs("fx-codex-xfx", newOnly: false, codex: true, browser: true), ["login", "fx-codex-xfx", "--codex", "--browser"])
        XCTAssertEqual(ClauthCLI.setupTokenArgs("fx-main"), ["login", "fx-main", "--setup-token", "--yes"])
        XCTAssertEqual(ClauthCLI.deleteArgs("fx-backup"), ["delete", "fx-backup", "--yes"])
        XCTAssertEqual(ClauthCLI.switchArgs("fx-cl"), ["fx-cl"])
        XCTAssertEqual(ClauthCLI.failureReason(stderr: "Error: profile 'x' not found\n  available: a, b\n", exitStatus: 1, verb: "delete"), "Error: profile 'x' not found — available: a, b")
        XCTAssertEqual(ClauthCLI.failureReason(stderr: "", exitStatus: 2, verb: "delete"), "clauth delete exited 2")
    }
}
