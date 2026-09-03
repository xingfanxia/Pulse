import XCTest
@testable import Pulse

final class ClauthDaemonClientTests: XCTestCase {
    func testClassifyReply() {
        XCTAssertEqual(ClauthDaemonClient.classifyReply(Data(#"{"ok":true}"#.utf8)), .ok)
        XCTAssertEqual(ClauthDaemonClient.classifyReply(Data(#"{"ok":1}"#.utf8)), .ok)
        XCTAssertEqual(
            ClauthDaemonClient.classifyReply(Data(#"{"ok":false,"error_code":"unknown_profile","error":"unknown profile 'x'"}"#.utf8)),
            .daemonError(code: "unknown_profile", message: "unknown profile 'x'")
        )
        XCTAssertEqual(ClauthDaemonClient.classifyReply(Data(#"{"ok":false}"#.utf8)), .daemonError(code: "unknown", message: "the daemon rejected the command"))
        XCTAssertEqual(ClauthDaemonClient.classifyReply(Data("garbage".utf8)), .unreachable)
        XCTAssertEqual(ClauthDaemonClient.classifyReply(nil), .unreachable)
    }

    func testSwitchPolicyNeverShellsOnARejection() async {
        let accepted = await ClauthDaemonClient.switchTo("fx-cl", send: { _ in .ok }, cli: { XCTFail("cli reached"); return .ok })
        XCTAssertEqual(accepted, .accepted)
        let refused = await ClauthDaemonClient.switchTo("fx-cl", send: { _ in .daemonError(code: "busy", message: "busy") }, cli: { XCTFail("cli reached on a rejection"); return .ok })
        XCTAssertEqual(refused, .refused(code: "busy", message: "busy"))
        let viaCLI = await ClauthDaemonClient.switchTo("fx-cl", send: { _ in .unreachable }, cli: { .ok })
        XCTAssertEqual(viaCLI, .confirmedByCLI)
        let cliFailed = await ClauthDaemonClient.switchTo("fx-cl", send: { _ in .unreachable }, cli: { .daemonError(code: "cli_failed", message: "clauth exited 1") })
        XCTAssertEqual(cliFailed, .refused(code: "cli_failed", message: "clauth exited 1"))
        let nothing = await ClauthDaemonClient.switchTo("fx-cl", send: { _ in .unreachable }, cli: { .unreachable })
        XCTAssertEqual(nothing, .unreachable)
    }

    /// Every verb's payload, literal against clauth `src/daemon/socket.rs`
    /// (the dispatch arm's header comment lists each shape).
    func testEveryCommandPayloadMatchesTheSocketDispatchArm() {
        let cases: [(ClauthCommand, [String: Any])] = [
            (.snapshot, ["cmd": "snapshot"]),
            (.switch(profile: "work"), ["cmd": "switch", "profile": "work"]),
            (.refresh(profile: "work"), ["cmd": "refresh", "profile": "work"]),
            (.refresh(profile: nil), ["cmd": "refresh"]),
            (.fallbackAdd(profile: "work"), ["cmd": "fallback_add", "profile": "work"]),
            (.fallbackRemove(profile: "work"), ["cmd": "fallback_remove", "profile": "work"]),
            (.fallbackMove(profile: "work", up: true), ["cmd": "fallback_move", "profile": "work", "dir": "up"]),
            (.fallbackMove(profile: "work", up: false), ["cmd": "fallback_move", "profile": "work", "dir": "down"]),
            (.setThreshold(profile: "work", value: 90), ["cmd": "set_threshold", "profile": "work", "value": 90]),
            (.setLastResort(profile: "work", value: true), ["cmd": "set_last_resort", "profile": "work", "value": true]),
            (.setMemberWeekly(profile: "work", value: 90), ["cmd": "set_member_weekly", "profile": "work", "value": 90.0]),
            (.setMemberWeekly(profile: "work", value: nil), ["cmd": "set_member_weekly", "profile": "work", "value": NSNull()]),
            (.setCheckWeekly(profile: "work", value: false), ["cmd": "set_check_weekly", "profile": "work", "value": false]),
            (.setCheckScoped(profile: "work", value: false), ["cmd": "set_check_scoped", "profile": "work", "value": false]),
            (.setWrapOff(value: true), ["cmd": "set_wrap_off", "value": true]),
            (.setWeeklyThreshold(value: 98), ["cmd": "set_weekly_threshold", "value": 98.0]),
            (.rename(profile: "work", to: "work2"), ["cmd": "rename", "profile": "work", "new_name": "work2"]),
        ]
        for (command, expected) in cases {
            XCTAssertEqual(command.json as NSDictionary, expected as NSDictionary, "\(command)")
            XCTAssertNotNil(command.payload)
        }
        // A real JSON bool and a real JSON null on the wire, as the daemon validates with as_bool / is_null.
        let member = String(decoding: ClauthCommand.setMemberWeekly(profile: "w", value: nil).payload!, as: UTF8.self)
        XCTAssertTrue(member.contains("\"value\":null"), member)
        let resort = String(decoding: ClauthCommand.setLastResort(profile: "w", value: true).payload!, as: UTF8.self)
        XCTAssertTrue(resort.contains("\"value\":true"), resort)
    }

    func testRoundTripWithTheFakeDaemon() throws {
        let home = try FakeClauthDaemon.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FakeClauthDaemon.writeFixture(to: home, liveSession: false)
        let daemon = try FakeClauthDaemon(home: home)
        defer { daemon.stop() }
        let client = ClauthDaemonClient(home: home)
        XCTAssertEqual(client.send(.refresh(profile: "fx-main")), .ok)
        XCTAssertEqual(client.send(.switch(profile: "fx-ghost")), .daemonError(code: "unknown_profile", message: "unknown profile 'fx-ghost'"))
        XCTAssertEqual(daemon.commandNames, ["refresh", "switch"])
        XCTAssertEqual(daemon.commands.first?["profile"] as? String, "fx-main")
        let snapshot = try XCTUnwrap(client.snapshot())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertNotNil(object["status"])
    }

    func testNoSocketAndAnOverlongPathAreUnreachable() {
        XCTAssertEqual(ClauthDaemonClient(socketPath: "/tmp/clp-nowhere/clauthd.sock").send(.snapshot), .unreachable)
        let long = "/tmp/" + String(repeating: "x", count: 150) + "/clauthd.sock"
        XCTAssertEqual(ClauthDaemonClient(socketPath: long).send(.snapshot), .unreachable)
    }
}
