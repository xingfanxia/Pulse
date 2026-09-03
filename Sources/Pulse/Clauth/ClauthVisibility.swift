import Foundation
import Observation

/// The rail visibility Pulse's `enabledAccounts` cannot hold.
///
/// `AppSettings.restored()` rebuilds `enabledAccounts` at launch as providers
/// ∪ (stored ∩ persisted `ExtraAccount` ids) and writes the pruned set back —
/// a clauth id stored there would be dropped every launch. So clauth rows are
/// gated here, by a hidden-set of our own, and `enabledAccounts` is never
/// touched. The two primaries clauth replaces (`claudeCode`, `codex`) are
/// hidden by a flag the clauth pane can flip.
///
/// Postcondition, whatever the flags say: an empty clauth roster — no feed,
/// an unsupported schema, the watcher not started — shows the primaries.
/// The rail must never be empty; there would be nothing to hover and
/// nothing to grab.
@Observable
final class ClauthVisibility {
    nonisolated(unsafe) static let shared: ClauthVisibility = {
        let shared = ClauthVisibility(defaults: .standard)
        // The initialiser bypasses didSet; the panel measures after this.
        PanelMetrics.showCaptions(shared.railCaptions)
        return shared
    }()

    /// Account ids (of clauth slots) the user took off the rail.
    var hiddenAccounts: Set<String> {
        didSet {
            guard hiddenAccounts != oldValue else { return }
            defaults?.set(hiddenAccounts.sorted(), forKey: Key.hidden)
        }
    }

    /// Whether the Claude Code and Codex primaries stay off the rail while
    /// clauth is reporting — on by default; the clauth pane offers the switch.
    var hidesPrimaries: Bool {
        didSet {
            guard hidesPrimaries != oldValue else { return }
            defaults?.set(hidesPrimaries, forKey: Key.hidesPrimaries)
        }
    }

    /// Whether inactive accounts — a cancelled or lapsed plan, a broken
    /// login (`ClauthMapping.isInactive`) — stay off the rail. On by default
    /// (AX 2026-09-02); the clauth pane offers the switch, and a hidden one
    /// still shows in the Settings Order rows as "Not shown".
    var hidesInactive: Bool {
        didSet {
            guard hidesInactive != oldValue else { return }
            defaults?.set(hidesInactive, forKey: Key.hidesInactive)
        }
    }

    /// The ids the feed currently reports inactive. Published by the
    /// watcher on every change; never persisted — the feed is the truth.
    var inactiveAccounts: Set<String> = []

    /// A name under every ring (AX 2026-09-03). Changes the rail's width and
    /// each item's length, so it is mirrored into `PanelMetrics` before the
    /// panel measures.
    var railCaptions: Bool {
        didSet {
            // Only a persisted instance drives the process-wide metric; the
            // in-memory instances tests build must not retune the rail.
            if defaults != nil { PanelMetrics.showCaptions(railCaptions) }
            guard railCaptions != oldValue else { return }
            defaults?.set(railCaptions, forKey: Key.railCaptions)
        }
    }

    /// The other unscoped window as a thinner arc inside the ring: weekly
    /// inside the 5h ring for claude, nothing for a weekly-only codex plan.
    var innerRing: Bool {
        didSet {
            guard innerRing != oldValue else { return }
            defaults?.set(innerRing, forKey: Key.innerRing)
        }
    }

    /// Where upstream's "CLI is working" mark spins. It reads transcript
    /// writes per PROVIDER, so on a rail of several accounts of one provider
    /// it would spin on every ring for as long as any agent runs.
    enum Activity: String, CaseIterable, Sendable {
        case off, activeOnly, all
    }

    var activity: Activity {
        didSet {
            guard activity != oldValue else { return }
            defaults?.set(activity.rawValue, forKey: Key.activity)
        }
    }

    /// What the caption reads: the account's email (its local part — the
    /// domain rarely tells two accounts apart and never fits) or the profile
    /// name. AX 2026-09-03: 「label 直接显示邮箱」.
    enum CaptionStyle: String, CaseIterable, Sendable {
        case email, name
    }

    var captionStyle: CaptionStyle {
        didSet {
            guard captionStyle != oldValue else { return }
            defaults?.set(captionStyle.rawValue, forKey: Key.captionStyle)
        }
    }

    private let defaults: UserDefaults?

    /// `defaults: nil` keeps the state in memory only (tests).
    init(
        defaults: UserDefaults?,
        hiddenAccounts: Set<String>? = nil,
        hidesPrimaries: Bool? = nil,
        hidesInactive: Bool? = nil,
        railCaptions: Bool? = nil,
        innerRing: Bool? = nil,
        activity: Activity? = nil,
        captionStyle: CaptionStyle? = nil
    ) {
        self.defaults = defaults
        self.hiddenAccounts = hiddenAccounts ?? Set(defaults?.stringArray(forKey: Key.hidden) ?? [])
        self.hidesPrimaries = hidesPrimaries ?? (defaults?.object(forKey: Key.hidesPrimaries) as? Bool ?? true)
        self.hidesInactive = hidesInactive ?? (defaults?.object(forKey: Key.hidesInactive) as? Bool ?? true)
        self.railCaptions = railCaptions ?? (defaults?.object(forKey: Key.railCaptions) as? Bool ?? true)
        self.innerRing = innerRing ?? (defaults?.object(forKey: Key.innerRing) as? Bool ?? true)
        // Off by default (AX 2026-09-03): with an agent always running here
        // the mark never stopped, and it says nothing about the account.
        self.activity = activity ?? (defaults?.string(forKey: Key.activity)).flatMap(Activity.init(rawValue:)) ?? .off
        self.captionStyle = captionStyle ?? (defaults?.string(forKey: Key.captionStyle)).flatMap(CaptionStyle.init(rawValue:)) ?? .email
    }

    /// The rail's shown accounts, from the UNFILTERED user order so a drag
    /// that interleaves clauth rings among primaries survives.
    static func shown(_ ordered: [AccountKey], settings: AppSettings, state: ClauthVisibility = .shared) -> [AccountKey] {
        guard !settings.clauthAccounts.isEmpty else { return ordered.filter(settings.isEnabled) }
        let shown = ordered.filter { isShown($0, settings: settings, state: state) }
        // Everything hidden at once is still not an empty rail.
        return shown.isEmpty ? ordered.filter(settings.isEnabled) : shown
    }

    /// Whether one account is on the rail — the predicate the Settings
    /// Order rows subtitle with "Not shown".
    static func isShown(_ account: AccountKey, settings: AppSettings, state: ClauthVisibility = .shared) -> Bool {
        if ClauthFetchGuard.isClauthSlot(account) {
            guard settings.clauthAccounts.contains(account), !state.hiddenAccounts.contains(account.id) else { return false }
            return !(state.hidesInactive && state.inactiveAccounts.contains(account.id))
        }
        guard settings.isEnabled(account) else { return false }
        if account.isPrimary, [.claudeCode, .codex].contains(account.provider),
           state.hidesPrimaries, !settings.clauthAccounts.isEmpty {
            return false
        }
        return true
    }

    /// Hides or shows one clauth ring, and tells the panel to re-measure.
    static func setHidden(_ hidden: Bool, for account: AccountKey, settings: AppSettings, state: ClauthVisibility = .shared) {
        if hidden {
            state.hiddenAccounts.insert(account.id)
        } else {
            state.hiddenAccounts.remove(account.id)
        }
        settings.onChange?()
    }

    static func setHidesPrimaries(_ hides: Bool, settings: AppSettings, state: ClauthVisibility = .shared) {
        state.hidesPrimaries = hides
        settings.onChange?()
    }

    static func setHidesInactive(_ hides: Bool, settings: AppSettings, state: ClauthVisibility = .shared) {
        state.hidesInactive = hides
        settings.onChange?()
    }

    static func setRailCaptions(_ on: Bool, settings: AppSettings, state: ClauthVisibility = .shared) {
        state.railCaptions = on
        settings.onChange?()
    }

    /// Whether the activity mark may spin on this ring: a primary is its
    /// provider's live login, a clauth ring only when it is the harness's
    /// active slot — unless the mark is off, or wanted everywhere.
    @MainActor
    static func showsActivity(for account: AccountKey, settings: AppSettings, state: ClauthVisibility = .shared, status: ClauthStatus? = ClauthWatcher.current?.status) -> Bool {
        switch state.activity {
        case .off: return false
        case .all: return true
        case .activeOnly:
            guard let name = ClauthMapping.profileName(of: account), let harness = ClauthMapping.harness(of: account) else { return true }
            return status?.activeName(for: harness) == name
        }
    }

    /// The watcher's publish of what the feed calls inactive; announces a
    /// change so the panel re-measures a rail that just got shorter.
    static func publishInactive(_ ids: Set<String>, settings: AppSettings, state: ClauthVisibility = .shared) -> Bool {
        guard state.inactiveAccounts != ids else { return false }
        state.inactiveAccounts = ids
        return true
    }

    private enum Key {
        static let hidden = "clauth.hiddenAccounts"
        static let hidesPrimaries = "clauth.hidesPrimaries"
        static let hidesInactive = "clauth.hidesInactive"
        static let railCaptions = "clauth.railCaptions"
        static let innerRing = "clauth.innerRing"
        static let activity = "clauth.activity"
        static let captionStyle = "clauth.captionStyle"
    }
}
