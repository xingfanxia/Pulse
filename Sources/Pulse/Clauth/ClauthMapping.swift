import Foundation

/// Pure translation from clauth's feed to Pulse's account and usage model.
/// No IO, no clock of its own — `now` is passed in so every rule is a table
/// test.
enum ClauthMapping {
    /// The slot prefix that marks an account as clauth's. Never an
    /// `ExtraAccount`: the identity is derived from the feed at runtime.
    static let slotPrefix = "clauth:"

    /// At/above this percent a window counts as spent — `99.5`, not `100`,
    /// so it agrees with the integer the ring shows (both round to 100%).
    static let spentThreshold = 99.5

    static let fiveHourSeconds = 5 * 3_600
    static let weekSeconds = 7 * 86_400

    // MARK: Identity

    static func provider(for harness: ClauthHarness) -> Provider {
        harness == .codex ? .codex : .claudeCode
    }

    /// Third-party (non-Anthropic) claude profiles ride the Claude Code
    /// provider: they are switched by the same harness and draw its mark.
    static func account(for profile: ClauthStatus.Profile) -> AccountKey {
        AccountKey(provider(for: profile.harness), slot: slotPrefix + profile.name)
    }

    static func profileName(of account: AccountKey) -> String? {
        guard account.slot.hasPrefix(slotPrefix) else { return nil }
        return String(account.slot.dropFirst(slotPrefix.count))
    }

    static func harness(of account: AccountKey) -> ClauthHarness? {
        guard profileName(of: account) != nil else { return nil }
        return account.provider == .codex ? .codex : .claude
    }

    /// What the card and the Settings rows call a clauth account: the
    /// profile name. Nil for anything that is not clauth's.
    static func label(for account: AccountKey) -> String? {
        profileName(of: account)
    }

    /// The window the ring shows when the user has pinned nothing: the
    /// session window for claude, the week for codex. Never a scoped
    /// per-model window — a maxed `7d fable` would paint the ring red while
    /// the account is perfectly usable.
    static func defaultPin(for account: AccountKey) -> String? {
        guard let harness = harness(of: account) else { return nil }
        return harness == .codex ? "7d" : "5h"
    }

    /// The default pin for the reading actually on hand: the harness's
    /// window when it is reported, else whichever unscoped window is — a
    /// pin that matches nothing would fall back to Pulse's own rule, which
    /// is the maxed scoped window this exists to steer around.
    static func defaultPin(for account: AccountKey, in usage: ProviderUsage) -> String? {
        guard let preferred = defaultPin(for: account) else { return nil }
        let unscoped = usage.windows.filter { $0.scope == nil }
        if unscoped.contains(where: { $0.id == preferred }) { return preferred }
        return unscoped.first?.id
    }

    // MARK: Windows

    /// One clauth window as Pulse's, or nil when the label is not one of
    /// the three shapes clauth documents. Pulse's own rule: never invent a
    /// length, so an unknown label is dropped rather than drawn.
    static func window(_ window: ClauthStatus.Window, now: Date = Date()) -> UsageWindow? {
        let kind: UsageWindow.Kind
        let scope: String?
        let seconds: Int
        if window.label == "5h" {
            kind = .fiveHour; scope = nil; seconds = fiveHourSeconds
        } else if window.label == "7d" {
            kind = .weekly; scope = nil; seconds = weekSeconds
        } else if window.label.hasPrefix("7d ") {
            let model = window.label.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard !model.isEmpty else { return nil }
            kind = .weekly; scope = model; seconds = weekSeconds
        } else {
            return nil
        }
        let resets = ClauthISO.parse(window.resetsAt)
        return UsageWindow(
            id: window.label,
            kind: kind,
            scope: scope,
            usedFraction: window.utilizationPct / 100,
            windowSeconds: seconds,
            resetsAt: resets,
            reportsLength: true,
            // A scoped window never counts: a maxed per-model cap only
            // blocks that model, so the account is still usable otherwise.
            isExhausted: scope == nil && stillCapped(window, resets: resets, now: now)
        )
    }

    /// Whether a window's cap still BINDS: maxed AND its recorded reset is
    /// still ahead. A cached 100% whose `resets_at` has passed is yesterday's
    /// news — the limit lifted server-side and only the snapshot is stale
    /// (the parked-codex case). A missing or unparseable `resets_at` keeps
    /// counting as spent — never optimistic on unknown data. ccsbar's rule,
    /// verbatim.
    static func stillCapped(_ window: ClauthStatus.Window, resets: Date?, now: Date) -> Bool {
        guard window.utilizationPct >= spentThreshold else { return false }
        guard let resets else { return true }
        return resets > now
    }

    // MARK: Readings

    /// `.stale` whenever the numbers are not a live read: the daemon says
    /// so, the fetch was not `Fresh` (ccsbar's predicate), or the daemon
    /// itself has stopped ticking. Otherwise `.live`.
    static func state(for profile: ClauthStatus.Profile, freshness: ClauthLiveness.Freshness) -> ProviderUsage.State {
        if profile.stale { return .stale }
        if let fetched = profile.fetchStatus, fetched != "Fresh" { return .stale }
        if freshness == .dead { return .stale }
        return .live
    }

    /// The plan line: the tier, or for a third-party claude profile the
    /// provider it goes through (there is no tier to name).
    static func plan(for profile: ClauthStatus.Profile) -> String? {
        profile.isThirdParty ? profile.provider : profile.tier
    }

    /// Banked codex reset credits, worded for the card; nil when there is
    /// nothing to say. The badge is redeemed on OpenAI's side, never here.
    static func creditBalance(for profile: ClauthStatus.Profile) -> String? {
        guard profile.harness == .codex, let count = profile.codexResetCredits, count > 0 else { return nil }
        return count == 1
            ? String.localized("1 reset banked")
            : String.localized("\("\(count)") resets banked")
    }

    static func usage(for profile: ClauthStatus.Profile, freshness: ClauthLiveness.Freshness, now: Date = Date()) -> ProviderUsage {
        ProviderUsage(
            account: account(for: profile),
            windows: profile.windows.compactMap { window($0, now: now) },
            observedAt: ClauthISO.parse(profile.fetchedAt),
            state: state(for: profile, freshness: freshness),
            plan: plan(for: profile),
            creditBalance: creditBalance(for: profile)
        )
    }

    /// Every profile's reading, keyed by account id. Empty for a schema this
    /// build does not read.
    static func readings(_ status: ClauthStatus, freshness: ClauthLiveness.Freshness, now: Date = Date()) -> [String: ProviderUsage] {
        guard status.isSupported else { return [:] }
        var out: [String: ProviderUsage] = [:]
        for profile in status.profiles {
            let reading = usage(for: profile, freshness: freshness, now: now)
            out[reading.id] = reading
        }
        return out
    }

    // MARK: Inactive accounts

    /// ccsbar's rule for an account not worth a place on the rail: a
    /// cancelled or lapsed plan (the claude side labels a cancelled
    /// subscription's tier `canceled`, a codex account whose plan lapsed
    /// reads `free`), or a login the daemon reports broken.
    static func isInactive(_ profile: ClauthStatus.Profile) -> Bool {
        if profile.authBroken { return true }
        guard let tier = profile.tier?.lowercased() else { return false }
        return ["canceled", "cancelled", "free"].contains(tier)
    }

    /// The inactive accounts' ids — never a harness's active slot, whatever
    /// its plan looks like: what you are running on is always shown.
    static func inactive(_ status: ClauthStatus) -> Set<String> {
        guard status.isSupported else { return [] }
        return Set(status.profiles
            .filter { isInactive($0) && status.activeName(for: $0.harness) != $0.name }
            .map { account(for: $0).id })
    }

    // MARK: Roster

    /// The rail's default order for clauth's accounts: per harness, the
    /// active account first, then its chain in walk order, then the rest as
    /// published. The user's own drag order wins once stored.
    static func roster(_ status: ClauthStatus) -> [AccountKey] {
        guard status.isSupported else { return [] }
        return ClauthHarness.allCases.flatMap { harness -> [AccountKey] in
            let members = status.profiles.filter { $0.harness == harness }
            var names: [String] = []
            if let active = status.activeName(for: harness), members.contains(where: { $0.name == active }) {
                names.append(active)
            }
            for name in status.chain(for: harness)
            where !names.contains(name) && members.contains(where: { $0.name == name }) {
                names.append(name)
            }
            for member in members where !names.contains(member.name) {
                names.append(member.name)
            }
            return names.compactMap { name in members.first { $0.name == name } }.map(account(for:))
        }
    }

    /// What changed between two rosters. A renamed profile has no stable id
    /// beyond its name, so it reads as one removed and one added.
    static func rosterDiff(old: [AccountKey], new: [AccountKey]) -> (added: [AccountKey], removed: [AccountKey]) {
        let before = Set(old), after = Set(new)
        return (new.filter { !before.contains($0) }, old.filter { !after.contains($0) })
    }
}
