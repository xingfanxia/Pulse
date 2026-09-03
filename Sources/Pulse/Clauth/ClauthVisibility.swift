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
    nonisolated(unsafe) static let shared = ClauthVisibility(defaults: .standard)

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

    private let defaults: UserDefaults?

    /// `defaults: nil` keeps the state in memory only (tests).
    init(defaults: UserDefaults?, hiddenAccounts: Set<String>? = nil, hidesPrimaries: Bool? = nil, hidesInactive: Bool? = nil) {
        self.defaults = defaults
        self.hiddenAccounts = hiddenAccounts ?? Set(defaults?.stringArray(forKey: Key.hidden) ?? [])
        self.hidesPrimaries = hidesPrimaries ?? (defaults?.object(forKey: Key.hidesPrimaries) as? Bool ?? true)
        self.hidesInactive = hidesInactive ?? (defaults?.object(forKey: Key.hidesInactive) as? Bool ?? true)
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
    }
}
