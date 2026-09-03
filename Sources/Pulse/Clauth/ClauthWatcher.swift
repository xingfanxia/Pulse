import Foundation

/// Where clauth's files are. `PULSE_CLAUTH_HOME` redirects everything to a
/// sandbox — a fixture feed, a fake socket, a recording shim — so development
/// never reads the real daemon's home, let alone writes to it.
enum ClauthPaths {
    static var home: URL {
        if let override = ProcessInfo.processInfo.environment["PULSE_CLAUTH_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".clauth", directoryHint: .isDirectory)
    }

    static var isSandboxed: Bool {
        !(ProcessInfo.processInfo.environment["PULSE_CLAUTH_HOME"] ?? "").isEmpty
    }

    static func statusFile(in home: URL) -> URL { home.appending(path: "status.json") }
    static func socket(in home: URL) -> URL { home.appending(path: "clauthd.sock") }
}

/// Reads `status.json` on a 2s clock and publishes it into Pulse: the
/// roster into `AppSettings.clauthAccounts`, the readings into
/// `UsageStore.applyClauth`. The file is decoded only when its mtime moves;
/// liveness is re-judged every tick regardless, because a dead daemon is
/// exactly a file that stopped moving.
@MainActor
final class ClauthWatcher {
    /// The running watcher, for the ring-click refresh hook.
    private(set) static var current: ClauthWatcher?

    static let pollInterval: TimeInterval = 2

    let home: URL
    private let settings: AppSettings
    private let store: UsageStore
    private let visibility: ClauthVisibility
    private var timer: Timer?
    private var lastModified: Date?
    private var lastReadings: [String: ProviderUsage] = [:]

    /// The last feed that decoded, kept through a torn read.
    private(set) var status: ClauthStatus?
    private(set) var freshness: ClauthLiveness.Freshness = .dead

    init(settings: AppSettings, store: UsageStore, home: URL = ClauthPaths.home, visibility: ClauthVisibility = .shared) {
        self.settings = settings
        self.store = store
        self.home = home
        self.visibility = visibility
    }

    /// Reads once, synchronously, then keeps reading. Called before
    /// `UsageStore.start()` so the first fetch pass already sees clauth's
    /// rings and leaves the primaries alone.
    func start() {
        guard timer == nil else { return }
        Self.current = self
        tick()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if Self.current === self { Self.current = nil }
    }

    /// Re-reads the file whether or not it moved.
    func reload() {
        lastModified = nil
        tick()
    }

    func refresh(_ account: AccountKey) {
        reload()
    }

    func tick(now: Date = Date()) {
        let file = ClauthPaths.statusFile(in: home)
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modified = attributes?[.modificationDate] as? Date

        if attributes == nil {
            status = nil
            lastModified = nil
        } else if modified != lastModified {
            lastModified = modified
            if let data = try? Data(contentsOf: file),
               let decoded = try? JSONDecoder().decode(ClauthStatus.self, from: data) {
                status = decoded
            }
            // A torn read — the daemon mid-write — keeps the last good feed.
        }

        let generatedAge = status.flatMap { ClauthISO.parse($0.generatedAt) }.map { now.timeIntervalSince($0) }
        let mtimeAge = modified.map { now.timeIntervalSince($0) }
        freshness = status == nil
            ? .dead
            : ClauthLiveness.freshness(generatedAtAge: generatedAge, statusMtimeAge: mtimeAge)

        publish(now: now)
    }

    private func publish(now: Date) {
        let readings = status.map { ClauthMapping.readings($0, freshness: freshness, now: now) } ?? [:]
        let roster = status.map(ClauthMapping.roster) ?? []
        // Readings before the roster, so a ring that appears has its number;
        // the inactive set before the roster too, so the roster's own change
        // announcement measures the rail that will actually be drawn.
        if readings != lastReadings {
            lastReadings = readings
            store.applyClauth(readings)
        }
        let inactiveMoved = ClauthVisibility.publishInactive(
            status.map(ClauthMapping.inactive) ?? [], settings: settings, state: visibility)
        if settings.clauthAccounts != roster {
            settings.clauthAccounts = roster
        } else if inactiveMoved {
            settings.onChange?()
        }
    }
}
