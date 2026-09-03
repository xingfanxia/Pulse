import Darwin
import Foundation

/// Codex "proxy mode": whether plain `codex` routes through clauth's localhost
/// proxy (per-request account injection, so switches apply to running
/// sessions and a rate-limited request rotates and replays). The toggle is
/// the user's hand on `config.toml`: ON writes the top-level
/// `model_provider = "clauth"` and ensures the provider block; OFF removes
/// that one line and leaves the block (sessions started under proxy mode
/// reference it by name). Port of ccsbar's `CodexProxyMode`, with the codex
/// home threaded through `PULSE_CODEX_HOME` so the sandbox edits its own file.
enum ClauthProxyMode {
    static let proxyPort: UInt16 = 4517
    static let launchAgentLabel = "com.clauth.proxy"

    static let providerBlock = """
    [model_providers.clauth]
    name = "openai"
    base_url = "http://127.0.0.1:4517/backend-api/codex"
    wire_api = "responses"
    requires_openai_auth = true
    """

    // MARK: Pure transforms

    static func isRouted(config: String) -> Bool {
        topLevelProviderLine(config)?.value == "clauth"
    }

    static func hasProviderBlock(config: String) -> Bool {
        config.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0.trimmingCharacters(in: .whitespaces) == "[model_providers.clauth]" }
    }

    /// ON: replace (or insert at the top) the top-level `model_provider` line
    /// and append the block when missing. OFF: drop the line only when it
    /// points at clauth — a user-set third provider is not ours to remove.
    static func setRouting(config: String, on: Bool) -> String {
        var lines = config.components(separatedBy: "\n")
        let found = topLevelProviderLine(config)
        if on {
            if let found {
                lines[found.index] = "model_provider = \"clauth\""
            } else {
                lines.insert("model_provider = \"clauth\"", at: 0)
            }
            var out = lines.joined(separator: "\n")
            if !hasProviderBlock(config: out) {
                if !out.hasSuffix("\n") { out += "\n" }
                out += "\n" + providerBlock + "\n"
            }
            return out
        }
        if let found, found.value == "clauth" {
            lines.remove(at: found.index)
        }
        return lines.joined(separator: "\n")
    }

    private static func topLevelProviderLine(_ config: String) -> (index: Int, value: String)? {
        for (index, raw) in config.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return nil }
            if line.hasPrefix("#") || line.isEmpty { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard key == "model_provider" else { continue }
            let value = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (index, value)
        }
        return nil
    }

    // MARK: IO

    /// `PULSE_CODEX_HOME` redirects the edit to a sandbox copy.
    static var codexHome: URL {
        if let override = ProcessInfo.processInfo.environment["PULSE_CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    static var configPath: URL { codexHome.appending(path: "config.toml") }
    static var backupPath: URL { codexHome.appending(path: "config.toml.bak-pulse") }

    static func routed(configPath: URL = configPath) -> Bool {
        guard let text = try? String(contentsOf: configPath, encoding: .utf8) else { return false }
        return isRouted(config: text)
    }

    /// Backup, transform, atomic rewrite. The proxy LaunchAgent is ensured
    /// loaded separately (`ensureProxyLoaded`) and never unloaded on OFF.
    static func apply(on: Bool, configPath: URL = configPath, backupPath: URL = backupPath) throws {
        let text = try String(contentsOf: configPath, encoding: .utf8)
        try? text.write(to: backupPath, atomically: true, encoding: .utf8)
        try setRouting(config: text, on: on).write(to: configPath, atomically: true, encoding: .utf8)
    }

    static var launchAgentPlist: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(launchAgentLabel).plist").path
    }

    /// `launchctl bootstrap gui/<uid> <plist>` through the one spawn door —
    /// best-effort (already loaded is a non-zero exit, ignored). Nil when the
    /// plist is absent: nothing to load.
    static func ensureProxyLoaded(plist: String = launchAgentPlist, environment: ClauthCLI.Environment = .current) async -> ClauthCLI.Outcome? {
        guard FileManager.default.fileExists(atPath: plist) else { return nil }
        return await ClauthCLI.run(program: ClauthCLI.launchctl, arguments: ["bootstrap", "gui/\(getuid())", plist], timeout: .seconds(15), environment: environment)
    }

    /// Whether anything listens on the proxy port. Loopback connect — call
    /// off the main actor.
    static func serving() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = proxyPort.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
