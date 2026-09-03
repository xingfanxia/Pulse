import Foundation
import XCTest
@testable import Pulse

/// A stand-in for `clauthd` on a Unix socket: records every command, replies
/// `{"ok":true}`, and mutates the status.json next to it the way the daemon
/// would — a `switch` flips the profile's OWN harness slot (or, in
/// `.wrongHarness` mode, the other one, for the reverse verification).
final class FakeClauthDaemon: @unchecked Sendable {
    enum Mode: Sendable { case normal, wrongHarness }

    let home: URL
    let socketPath: String
    private let mode: Mode
    private let lock = NSLock()
    private var recorded: [[String: Any]] = []
    private var fd: Int32 = -1
    private var thread: Thread?

    var commands: [[String: Any]] { lock.withLock { recorded } }
    var commandNames: [String] { commands.compactMap { $0["cmd"] as? String } }

    /// A short home under /tmp: `sun_path` holds 104 bytes and the test
    /// bundle's temporary directory is longer than that on its own.
    static func makeHome() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/clp-\(UUID().uuidString.prefix(8).lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The fixture, with `fx-main`'s live session set as asked, written as
    /// `<home>/status.json` with a fresh `generated_at`.
    static func writeFixture(to home: URL, liveSession: Bool) throws {
        var object = try ClauthFixture.json()
        object["generated_at"] = ClauthISO.string(Date())
        ClauthFixture.editProfile(&object, "fx-main") { $0["has_live_session"] = liveSession }
        try JSONSerialization.data(withJSONObject: object).write(to: ClauthPaths.statusFile(in: home), options: .atomic)
    }

    init(home: URL, mode: Mode = .normal) throws {
        self.home = home
        self.mode = mode
        socketPath = ClauthPaths.socket(in: home).path
        unlink(socketPath)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: "fake", code: 1) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = socketPath.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw NSError(domain: "fake", code: 2) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let destination = raw.bindMemory(to: CChar.self)
            for index in 0..<bytes.count { destination[index] = bytes[index] }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, 64) == 0 else { throw NSError(domain: "fake", code: 3) }
        let thread = Thread { [self] in loop() }
        thread.name = "FakeClauthDaemon"
        self.thread = thread
        thread.start()
    }

    func stop() {
        let fd = self.fd
        self.fd = -1
        if fd >= 0 { close(fd) }
        unlink(socketPath)
    }

    private func loop() {
        while fd >= 0 {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var line = Data()
            while !line.contains(0x0A) {
                let n = read(client, &buffer, buffer.count)
                guard n > 0 else { break }
                line.append(contentsOf: buffer[0..<n])
            }
            let reply = handle(line)
            var out = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{\"ok\":false}".utf8)
            out.append(0x0A)
            _ = out.withUnsafeBytes { write(client, $0.baseAddress, out.count) }
            close(client)
        }
    }

    private func handle(_ line: Data) -> [String: Any] {
        guard let command = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return ["ok": false, "error_code": "bad_request", "error": "unparseable"]
        }
        lock.withLock { recorded.append(command) }
        return apply(command)
    }

    private func apply(_ command: [String: Any]) -> [String: Any] {
        let file = ClauthPaths.statusFile(in: home)
        guard let data = try? Data(contentsOf: file),
              var status = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var profiles = status["profiles"] as? [[String: Any]]
        else { return ["ok": false, "error_code": "no_status", "error": "no status.json"] }
        let name = command["profile"] as? String
        func index(of name: String?) -> Int? { profiles.firstIndex { $0["name"] as? String == name } }

        switch command["cmd"] as? String {
        case "snapshot":
            return ["ok": true, "status": status]
        case "switch":
            guard let name, let at = index(of: name) else {
                return ["ok": false, "error_code": "unknown_profile", "error": "unknown profile '\(name ?? "")'"]
            }
            var harness = (profiles[at]["harness"] as? String) ?? "claude"
            if mode == .wrongHarness { harness = harness == "codex" ? "claude" : "codex" }
            status[harness == "codex" ? "active_codex_profile" : "active_profile"] = name
            for i in profiles.indices where ((profiles[i]["harness"] as? String) ?? "claude") == harness {
                profiles[i]["active"] = profiles[i]["name"] as? String == name
            }
        case "refresh":
            for i in profiles.indices where name == nil || profiles[i]["name"] as? String == name {
                profiles[i]["fetched_at"] = ClauthISO.string(Date())
            }
        case "rename":
            guard let name, let at = index(of: name), let new = command["new_name"] as? String else {
                return ["ok": false, "error_code": "unknown_profile", "error": "unknown profile '\(name ?? "")'"]
            }
            profiles[at]["name"] = new
            for key in ["active_profile", "active_codex_profile"] where status[key] as? String == name { status[key] = new }
            for key in ["fallback_chain", "codex_fallback_chain"] {
                status[key] = (status[key] as? [String] ?? []).map { $0 == name ? new : $0 }
            }
        default:
            break
        }
        status["profiles"] = profiles
        status["generated_at"] = ClauthISO.string(Date())
        if let out = try? JSONSerialization.data(withJSONObject: status) {
            try? out.write(to: file, options: .atomic)
        }
        return ["ok": true]
    }
}

/// Polls a condition on the main actor, letting the controller's tasks run.
@MainActor
func waitUntil(_ timeout: Double, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}
