import Foundation

/// Which agent harness a clauth profile switches. Two independent active
/// slots exist, one per case: `active_profile` (claude) and
/// `active_codex_profile` (codex). A profile without a `harness` field is a
/// claude profile — the field arrived after schema 1 was frozen.
enum ClauthHarness: String, Sendable, Equatable, CaseIterable {
    case claude, codex
}

/// Mirror of `~/.clauth/status.json` (schema 1), rewritten by `clauth daemon`
/// about once a second. Contract: clauth `docs/ccsbar/DESIGN.md`; wire
/// authority `src/daemon/status_json.rs`.
///
/// Decoded additively — only `schema`, `generated_at`, `profiles` and each
/// profile's `name` are required; everything else falls back to a benign
/// default so a status.json from an older or newer daemon still decodes and
/// the rail never goes blank over one renamed field. Pulse holds no token
/// for any of these accounts: this file is the whole data plane.
struct ClauthStatus: Decodable, Sendable, Equatable {
    /// The on-disk schema this build reads. A newer daemon bumps it; the
    /// watcher then publishes nothing rather than guessing at the shape.
    static let supportedSchema = 1

    let schema: Int
    let generatedAt: String
    let activeProfile: String?
    let activeCodexProfile: String?
    let fallbackChain: [String]
    let codexFallbackChain: [String]
    /// One global value: the deployed daemon has no `codex_wrap_off`.
    let wrapOff: Bool
    let weeklySwitchThreshold: Double?
    let burnAware: Bool?
    let forecast: Forecast?
    let pendingSwitch: String?
    let lastSwitch: LastSwitch?
    let lastError: LastError?
    let refreshIntervalMs: Int?
    let clauthVersion: String?
    let profiles: [Profile]

    var isSupported: Bool { schema == Self.supportedSchema }

    /// The published active slot for a harness. A codex switch is confirmed
    /// by THIS flipping — watching `active_profile` for one never confirms.
    func activeName(for harness: ClauthHarness) -> String? {
        harness == .codex ? activeCodexProfile : activeProfile
    }

    /// The harness's auto-switch chain, in walk order.
    func chain(for harness: ClauthHarness) -> [String] {
        harness == .codex ? codexFallbackChain : fallbackChain
    }

    func profile(named name: String) -> Profile? {
        profiles.first { $0.name == name }
    }

    struct Forecast: Decodable, Sendable, Equatable {
        let action: String
        let to: String?
    }

    struct LastSwitch: Decodable, Sendable, Equatable {
        let from: String?
        let to: String?
        let at: String?
        let trigger: String?
    }

    struct LastError: Decodable, Sendable, Equatable {
        let at: String?
        let message: String?
    }

    struct Fallback: Sendable, Equatable {
        let position: Int
        let threshold: Double
        let armed: Bool
        let lastResort: Bool
        let checkWeekly: Bool
        let checkScoped: Bool
        /// Per-member weekly line; nil follows the chain-wide one.
        let weeklyThreshold: Double?
    }

    struct Window: Sendable, Equatable {
        /// `"5h"`, `"7d"`, or `"7d <model>"` for a per-model weekly window.
        let label: String
        let utilizationPct: Double
        let resetsAt: String?
    }

    struct ThirdParty: Decodable, Sendable, Equatable {
        let available: Bool
    }

    struct Profile: Sendable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        let active: Bool
        let harness: ClauthHarness
        let provider: String
        let baseUrl: String?
        let tier: String?
        let accountEmail: String?
        let hasLiveSession: Bool
        /// `ok` | `expiring` | `broken`; absent reads as ok.
        let authStatus: String?
        /// `Fresh`, `Cached`, `RateLimited`, … or nil before the first fetch.
        let fetchStatus: String?
        let stale: Bool
        let fetchedAt: String?
        let nextRefreshAt: String?
        let autoStart: Bool
        let bellThreshold: Double?
        let fallback: Fallback?
        let windows: [Window]
        let thirdParty: ThirdParty?
        /// `rolling_token` (post-#59 spelling) falling back to `session_feed`
        /// (the deployed fork's spelling), so both daemons read the same.
        let rollingToken: Bool
        let codexSnapshotAt: String?
        /// Codex's own limiter verdict on the last request — a window name or
        /// a bare reason such as `rate_limit_reached`; nil when not limited.
        let codexRateLimitReached: String?
        /// Banked reset credits; nil until a poll has carried a count.
        let codexResetCredits: Int?

        var isThirdParty: Bool { !["anthropic", "openai"].contains(provider) }
        var authBroken: Bool { authStatus == "broken" }
        var inChain: Bool { fallback != nil }

        func window(_ label: String) -> Window? { windows.first { $0.label == label } }
    }
}

extension ClauthStatus {
    private enum CodingKeys: String, CodingKey {
        case schema, profiles, forecast
        case generatedAt = "generated_at"
        case activeProfile = "active_profile"
        case activeCodexProfile = "active_codex_profile"
        case fallbackChain = "fallback_chain"
        case codexFallbackChain = "codex_fallback_chain"
        case wrapOff = "wrap_off"
        case weeklySwitchThreshold = "weekly_switch_threshold"
        case burnAware = "burn_aware"
        case pendingSwitch = "pending_switch"
        case lastSwitch = "last_switch"
        case lastError = "last_error"
        case refreshIntervalMs = "refresh_interval_ms"
        case clauthVersion = "clauth_version"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        generatedAt = try c.decode(String.self, forKey: .generatedAt)
        activeProfile = try c.decodeIfPresent(String.self, forKey: .activeProfile)
        activeCodexProfile = try c.decodeIfPresent(String.self, forKey: .activeCodexProfile)
        fallbackChain = try c.decodeIfPresent([String].self, forKey: .fallbackChain) ?? []
        codexFallbackChain = try c.decodeIfPresent([String].self, forKey: .codexFallbackChain) ?? []
        wrapOff = try c.decodeIfPresent(Bool.self, forKey: .wrapOff) ?? false
        weeklySwitchThreshold = try c.decodeIfPresent(Double.self, forKey: .weeklySwitchThreshold)
        burnAware = try c.decodeIfPresent(Bool.self, forKey: .burnAware)
        forecast = try c.decodeIfPresent(Forecast.self, forKey: .forecast)
        pendingSwitch = try c.decodeIfPresent(String.self, forKey: .pendingSwitch)
        lastSwitch = try c.decodeIfPresent(LastSwitch.self, forKey: .lastSwitch)
        lastError = try c.decodeIfPresent(LastError.self, forKey: .lastError)
        refreshIntervalMs = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMs)
        clauthVersion = try c.decodeIfPresent(String.self, forKey: .clauthVersion)
        profiles = try c.decode([Profile].self, forKey: .profiles)
    }
}

extension ClauthStatus.Fallback: Decodable {
    private enum CodingKeys: String, CodingKey {
        case position, threshold, armed
        case lastResort = "last_resort"
        case checkWeekly = "check_weekly"
        case checkScoped = "check_scoped"
        case weeklyThreshold = "weekly_threshold"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0
        armed = try c.decodeIfPresent(Bool.self, forKey: .armed) ?? false
        lastResort = try c.decodeIfPresent(Bool.self, forKey: .lastResort) ?? false
        checkWeekly = try c.decodeIfPresent(Bool.self, forKey: .checkWeekly) ?? true
        checkScoped = try c.decodeIfPresent(Bool.self, forKey: .checkScoped) ?? true
        weeklyThreshold = try c.decodeIfPresent(Double.self, forKey: .weeklyThreshold)
    }
}

extension ClauthStatus.Window: Decodable {
    private enum CodingKeys: String, CodingKey {
        case label
        case utilizationPct = "utilization_pct"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        utilizationPct = try c.decodeIfPresent(Double.self, forKey: .utilizationPct) ?? 0
        resetsAt = try c.decodeIfPresent(String.self, forKey: .resetsAt)
    }
}

extension ClauthStatus.Profile: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, active, provider, tier, fallback, windows, harness, stale
        case baseUrl = "base_url"
        case accountEmail = "account_email"
        case hasLiveSession = "has_live_session"
        case authStatus = "auth_status"
        case fetchStatus = "fetch_status"
        case fetchedAt = "fetched_at"
        case nextRefreshAt = "next_refresh_at"
        case autoStart = "auto_start"
        case bellThreshold = "bell_threshold"
        case thirdParty = "third_party"
        case rollingToken = "rolling_token"
        case sessionFeed = "session_feed"
        case codexSnapshotAt = "codex_snapshot_at"
        case codexRateLimitReached = "codex_rate_limit_reached"
        case codexResetCredits = "codex_reset_credits"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        harness = try c.decodeIfPresent(String.self, forKey: .harness) == "codex" ? .codex : .claude
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "anthropic"
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl)
        tier = try c.decodeIfPresent(String.self, forKey: .tier)
        accountEmail = try c.decodeIfPresent(String.self, forKey: .accountEmail)
        hasLiveSession = try c.decodeIfPresent(Bool.self, forKey: .hasLiveSession) ?? false
        authStatus = try c.decodeIfPresent(String.self, forKey: .authStatus)
        fetchStatus = try c.decodeIfPresent(String.self, forKey: .fetchStatus)
        stale = try c.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        fetchedAt = try c.decodeIfPresent(String.self, forKey: .fetchedAt)
        nextRefreshAt = try c.decodeIfPresent(String.self, forKey: .nextRefreshAt)
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        bellThreshold = try c.decodeIfPresent(Double.self, forKey: .bellThreshold)
        fallback = try c.decodeIfPresent(ClauthStatus.Fallback.self, forKey: .fallback)
        windows = try c.decodeIfPresent([ClauthStatus.Window].self, forKey: .windows) ?? []
        thirdParty = try c.decodeIfPresent(ClauthStatus.ThirdParty.self, forKey: .thirdParty)
        rollingToken = try c.decodeIfPresent(Bool.self, forKey: .rollingToken)
            ?? c.decodeIfPresent(Bool.self, forKey: .sessionFeed)
            ?? false
        codexSnapshotAt = try c.decodeIfPresent(String.self, forKey: .codexSnapshotAt)
        codexRateLimitReached = try c.decodeIfPresent(String.self, forKey: .codexRateLimitReached)
        codexResetCredits = try c.decodeIfPresent(Int.self, forKey: .codexResetCredits)
    }
}

/// The daemon writes RFC 3339 with or without fractional seconds, and with a
/// `+00:00` offset rather than `Z`. Both formatter flavours are tried.
enum ClauthISO {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        return fractional.date(from: text) ?? whole.date(from: text)
    }

    static func string(_ date: Date) -> String {
        whole.string(from: date)
    }
}
