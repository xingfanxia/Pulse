import Foundation

/// THE only file in the clauth integration that spawns a process (gate 6 of
/// `Scripts/clauth-verify.sh`). Every CLI verb — `clauth login`, `clauth
/// delete`, the `clauth <name>` switch fallback, and `launchctl` for the
/// codex proxy — comes through `run`, and `run` refuses to spawn anything
/// under the sandbox unless the sandbox names its recording shim.
///
/// `clauth` reads `~/.clauth` unconditionally (no env var redirects the
/// CLI), which is why the containment is on the spawn and not on a path.
enum ClauthCLI {
    static let clauth = "clauth"
    static let launchctl = "/bin/launchctl"

    /// The two sandbox variables, read once per call so tests can inject.
    struct Environment: Sendable, Equatable {
        let sandboxHome: String?
        let sandboxBin: String?

        static var current: Environment { Environment(ProcessInfo.processInfo.environment) }

        init(_ environment: [String: String]) {
            sandboxHome = environment["PULSE_CLAUTH_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            sandboxBin = environment["PULSE_CLAUTH_BIN"].flatMap { $0.isEmpty ? nil : $0 }
        }

        init(sandboxHome: String?, sandboxBin: String?) {
            self.sandboxHome = sandboxHome
            self.sandboxBin = sandboxBin
        }
    }

    enum Refusal: Error, Equatable, Sendable {
        /// `PULSE_CLAUTH_HOME` is set and `PULSE_CLAUTH_BIN` is not: the
        /// sandbox has no shim, so nothing real may run.
        case sandboxed
        case notInstalled(String)

        var message: String {
            switch self {
            case .sandboxed: "sandboxed — PULSE_CLAUTH_BIN is not set"
            case .notInstalled(let program): "\(program) is not installed"
            }
        }
    }

    /// What would actually be executed.
    struct Launch: Equatable, Sendable {
        let executable: String
        let arguments: [String]
    }

    enum Outcome: Equatable, Sendable {
        case ok(stdout: String, stderr: String)
        case failed(status: Int32, stderr: String)
        case unavailable(Refusal)
        case couldNotStart(String)

        var isOK: Bool { if case .ok = self { return true } else { return false } }
    }

    /// Resolves a program to a launch, or refuses. Under the sandbox EVERY
    /// program — `clauth` and `/bin/launchctl` alike — is handed to the shim
    /// as `[program] + arguments`, so the shim records the intent and
    /// nothing real runs.
    static func launch(
        program: String,
        arguments: [String],
        environment: Environment = .current,
        locate: (String) -> String? = { clauthBinary(program: $0) }
    ) -> Result<Launch, Refusal> {
        if let bin = environment.sandboxBin {
            return .success(Launch(executable: bin, arguments: [program] + arguments))
        }
        if environment.sandboxHome != nil {
            return .failure(.sandboxed)
        }
        guard let executable = locate(program) else { return .failure(.notInstalled(program)) }
        return .success(Launch(executable: executable, arguments: arguments))
    }

    /// Where a program is on this Mac: an absolute path as given, or
    /// `clauth` from the usual install locations.
    static func clauthBinary(program: String = clauth) -> String? {
        if program.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: program) ? program : nil
        }
        let cargo = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/clauth").path
        for candidate in ["/opt/homebrew/bin/clauth", "/usr/local/bin/clauth", cargo]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    typealias Spawner = @Sendable (Launch, String?, Duration) async -> Outcome

    /// Runs a program and reports its outcome. `stdin`, when given, is written
    /// whole and closed — a pasted token goes ONLY down the pipe, never argv.
    /// `spawn` is injectable so tests assert it is never reached on a refusal.
    static func run(
        program: String,
        arguments: [String],
        stdin: String? = nil,
        timeout: Duration = .seconds(180),
        environment: Environment = .current,
        spawn: Spawner = { await spawnProcess($0, stdin: $1, timeout: $2) }
    ) async -> Outcome {
        switch launch(program: program, arguments: arguments, environment: environment) {
        case .failure(let refusal): return .unavailable(refusal)
        case .success(let launch): return await spawn(launch, stdin, timeout)
        }
    }

    /// The real spawn. stdout and stderr are drained concurrently with the
    /// wait, never only after exit: a child that fills the pipe blocks in
    /// `write()` and never terminates. A watchdog terminates a child that
    /// outlives `timeout`; the termination handler then fires normally.
    private static func spawnProcess(_ launch: Launch, stdin input: String?, timeout: Duration) async -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let inPipe = input == nil ? nil : Pipe()
        if let inPipe { process.standardInput = inPipe }
        let outEnd = out.fileHandleForReading, errEnd = err.fileHandleForReading
        let drainOut = Task.detached { outEnd.readDataToEndOfFile() }
        let drainErr = Task.detached { errEnd.readDataToEndOfFile() }

        enum Spawn { case exited(Int32), failed(String) }
        let spawn: Spawn = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: .exited($0.terminationStatus)) }
            do {
                try process.run()
                if let inPipe, let input {
                    inPipe.fileHandleForWriting.write(Data((input + "\n").utf8))
                    try? inPipe.fileHandleForWriting.close()
                }
                Task.detached {
                    try? await Task.sleep(for: timeout)
                    if process.isRunning { process.terminate() }
                }
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: .failed(error.localizedDescription))
            }
        }
        switch spawn {
        case .failed(let message):
            drainOut.cancel(); drainErr.cancel()
            return .couldNotStart(message)
        case .exited(let status):
            let stdout = String(decoding: await drainOut.value, as: UTF8.self)
            let stderr = String(decoding: await drainErr.value, as: UTF8.self)
            return status == 0 ? .ok(stdout: stdout, stderr: stderr) : .failed(status: status, stderr: stderr)
        }
    }

    // MARK: - argv shapes (pure; ccsbar's, verbatim)

    /// `clauth login [--new] <name> [--codex [--browser]]`. `--browser` is
    /// codex-only on the CLI — a claude login is always a browser flow.
    static func loginArgs(_ name: String, newOnly: Bool, codex: Bool, browser: Bool) -> [String] {
        var args = ["login"]
        if newOnly { args.append("--new") }
        args.append(name)
        if codex {
            args.append("--codex")
            if browser { args.append("--browser") }
        }
        return args
    }

    /// `--yes` because a non-TTY spawn can never answer the replace-confirm.
    static func setupTokenArgs(_ name: String) -> [String] {
        ["login", name, "--setup-token", "--yes"]
    }

    /// `--yes`, never `--force`: a profile with a live session must keep
    /// being refused, and that refusal is surfaced verbatim.
    static func deleteArgs(_ name: String) -> [String] {
        ["delete", name, "--yes"]
    }

    /// `clauth <name>` — the CLI switch, the fallback when the daemon is dead.
    static func switchArgs(_ name: String) -> [String] {
        [name]
    }

    /// `clauth feed <name> on|off` — the rolling-token flag.
    static func feedArgs(_ name: String, on: Bool) -> [String] {
        ["feed", name, on ? "on" : "off"]
    }

    /// The whole refusal, newlines flattened; empty stderr falls back to the
    /// exit status.
    static func failureReason(stderr: String, exitStatus: Int32, verb: String) -> String {
        let flattened = stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        return flattened.isEmpty ? "clauth \(verb) exited \(exitStatus)" : flattened
    }
}
