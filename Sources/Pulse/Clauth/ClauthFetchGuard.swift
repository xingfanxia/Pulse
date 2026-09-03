import Foundation

/// Keeps Pulse's own fetch loop away from clauth's accounts.
///
/// A clauth account is an `AccountKey` whose slot starts with `clauth:`. It
/// is never an `ExtraAccount` — Pulse holds no token for it — so it must
/// never reach `UsageStore.fetchAdded`, which would look for a credential
/// Pulse does not have and report the account as signed out.
enum ClauthFetchGuard {
    static func isClauthSlot(_ account: AccountKey) -> Bool {
        account.slot.hasPrefix(ClauthMapping.slotPrefix)
    }

    static func isClauthID(_ id: String) -> Bool {
        AccountKey(id: id).map(isClauthSlot) ?? false
    }

    /// The accounts Pulse signed in to itself, from the rail's shown list —
    /// non-primary and not clauth's.
    static func extras(_ shown: [AccountKey]) -> [AccountKey] {
        shown.filter { !$0.isPrimary && !isClauthSlot($0) }
    }

    /// A ring click on a clauth account: re-read the feed now rather than
    /// asking a provider. (The daemon `refresh` verb arrives with CLP-2.)
    @MainActor
    static func refresh(_ account: AccountKey) {
        ClauthWatcher.current?.refresh(account)
    }
}
