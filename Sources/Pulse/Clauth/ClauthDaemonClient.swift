import Foundation

/// One command on the daemon socket, typed so every payload is a table test
/// against clauth's `src/daemon/socket.rs` dispatch arm (documented in
/// `docs/ccsbar/DESIGN.md` § socket).
enum ClauthCommand: Equatable, Sendable {
    case snapshot
    case `switch`(profile: String)
    case refresh(profile: String?)
    case fallbackAdd(profile: String)
    case fallbackRemove(profile: String)
    case fallbackMove(profile: String, up: Bool)
    case setThreshold(profile: String, value: Int)
    case setLastResort(profile: String, value: Bool)
    /// `nil` CLEARS — encoded as an explicit JSON null, never a dropped key.
    case setMemberWeekly(profile: String, value: Double?)
    case setCheckWeekly(profile: String, value: Bool)
    case setCheckScoped(profile: String, value: Bool)
    /// One global value on the deployed daemon.
    case setWrapOff(value: Bool)
    case setWeeklyThreshold(value: Double)
    case rename(profile: String, to: String)

    var json: [String: Any] {
        switch self {
        case .snapshot: ["cmd": "snapshot"]
        case .switch(let profile): ["cmd": "switch", "profile": profile]
        case .refresh(let profile):
            profile.map { ["cmd": "refresh", "profile": $0] } ?? ["cmd": "refresh"]
        case .fallbackAdd(let profile): ["cmd": "fallback_add", "profile": profile]
        case .fallbackRemove(let profile): ["cmd": "fallback_remove", "profile": profile]
        case .fallbackMove(let profile, let up): ["cmd": "fallback_move", "profile": profile, "dir": up ? "up" : "down"]
        case .setThreshold(let profile, let value): ["cmd": "set_threshold", "profile": profile, "value": value]
        case .setLastResort(let profile, let value): ["cmd": "set_last_resort", "profile": profile, "value": value]
        case .setMemberWeekly(let profile, let value): ["cmd": "set_member_weekly", "profile": profile, "value": value ?? NSNull()]
        case .setCheckWeekly(let profile, let value): ["cmd": "set_check_weekly", "profile": profile, "value": value]
        case .setCheckScoped(let profile, let value): ["cmd": "set_check_scoped", "profile": profile, "value": value]
        case .setWrapOff(let value): ["cmd": "set_wrap_off", "value": value]
        case .setWeeklyThreshold(let value): ["cmd": "set_weekly_threshold", "value": value]
        case .rename(let profile, let new): ["cmd": "rename", "profile": profile, "new_name": new]
        }
    }

    var payload: Data? { try? JSONSerialization.data(withJSONObject: json) }
}

/// The outcome of a daemon command. The three cases must not collapse: a
/// daemon REJECTION (`ok:false`) is authoritative and must never trigger the
/// daemon-absence CLI fallback, and it carries a message the UI surfaces.
enum ClauthOutcome: Equatable, Sendable {
    case ok
    case daemonError(code: String, message: String)
    /// No daemon reachable — nothing applied the command.
    case unreachable

    var errorMessage: String? {
        switch self {
        case .ok: nil
        case .daemonError(_, let message): message
        case .unreachable: "clauth daemon not reachable — is it running?"
        }
    }
}

/// Drives `clauthd.sock` (newline-delimited JSON) — the port of ccsbar's
/// `DaemonClient`. Blocking calls: run them off the main actor.
struct ClauthDaemonClient: Sendable {
    /// How a switch dispatch resolved. `accepted` still needs the daemon's
    /// next tick to LAND it (observed in status.json); `confirmedByCLI` is
    /// confirmed by the exit code and status.json will NOT move.
    enum SwitchDispatch: Equatable, Sendable {
        case accepted
        case confirmedByCLI
        case refused(code: String, message: String)
        case unreachable
    }

    let socketPath: String

    init(home: URL) {
        socketPath = ClauthPaths.socket(in: home).path
    }

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    // MARK: Commands

    func send(_ command: ClauthCommand) -> ClauthOutcome {
        guard let payload = command.payload else { return .unreachable }
        switch Self.sendRaw(payload, to: socketPath) {
        case .noSocket:
            return .unreachable
        case .connectedNoReply:
            // Delivered but unconfirmed is NOT absence: falling back to the
            // CLI here would double-apply an already-applied switch.
            return .daemonError(code: "no_reply", message: "the daemon didn't confirm in time — it may still be applying the change")
        case .reply(let data):
            return Self.classifyReply(data)
        }
    }

    /// The snapshot verb: the daemon's own view of status.json, read-only.
    func snapshot() -> Data? {
        guard let payload = ClauthCommand.snapshot.payload,
              case .reply(let data) = Self.sendRaw(payload, to: socketPath) else { return nil }
        return data
    }

    /// Socket first; on an UNREACHABLE daemon the CLI does the switch. A
    /// rejection never falls back.
    func switchTo(_ profile: String, cli: () async -> ClauthOutcome) async -> SwitchDispatch {
        await Self.switchTo(profile, send: { send($0) }, cli: cli)
    }

    /// The fallback POLICY, with both legs injectable.
    static func switchTo(
        _ profile: String,
        send: (ClauthCommand) async -> ClauthOutcome,
        cli: () async -> ClauthOutcome
    ) async -> SwitchDispatch {
        switch await send(.switch(profile: profile)) {
        case .ok:
            return .accepted
        case .daemonError(let code, let message):
            return .refused(code: code, message: message)
        case .unreachable:
            switch await cli() {
            case .ok: return .confirmedByCLI
            case .daemonError(let code, let message): return .refused(code: code, message: message)
            case .unreachable: return .unreachable
            }
        }
    }

    /// `ok:true` → ok; `ok:false` → the daemon's error; anything else is a
    /// transport failure.
    static func classifyReply(_ reply: Data?) -> ClauthOutcome {
        guard let reply, let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
            return .unreachable
        }
        let ok = (object["ok"] as? Bool) ?? (object["ok"] as? NSNumber)?.boolValue
        if ok == true { return .ok }
        let code = object["error_code"] as? String ?? "unknown"
        let message = object["error"] as? String ?? "the daemon rejected the command"
        return .daemonError(code: code, message: message)
    }

    // MARK: Socket

    enum RawReply: Equatable {
        /// Never connected, or the command could not be written: nothing was
        /// delivered, so a fallback is safe.
        case noSocket
        /// Connected and wrote, but no complete reply before the deadline.
        case connectedNoReply
        case reply(Data)
    }

    private static let ioTimeout = timeval(tv_sec: 2, tv_usec: 0)
    private static let maxReplyBytes = 1 << 20

    static func sendRaw(_ payload: Data, to path: String) -> RawReply {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .noSocket }
        defer { close(fd) }

        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        var tv = ioTimeout
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        // Refuse rather than truncate: a path that does not fit would
        // connect to the WRONG socket.
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return .noSocket }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let destination = raw.bindMemory(to: CChar.self)
            for index in 0..<min(pathBytes.count, destination.count) {
                destination[index] = pathBytes[index]
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else { return .noSocket }

        var line = payload
        line.append(0x0A)
        let wroteAll = line.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            var sent = 0
            while sent < line.count {
                let n = write(fd, base + sent, line.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
        guard wroteAll else { return .noSocket }

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while response.count < maxReplyBytes {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            response.append(contentsOf: chunk[0..<n])
            if chunk[0..<n].contains(0x0A) { break }
        }
        // Empty or truncated: delivered, unconfirmed — never "absent".
        if response.isEmpty || !response.contains(0x0A) { return .connectedNoReply }
        return .reply(response)
    }
}
