import SwiftUI

/// What the rail says under a ring: the account's name, shortened for
/// clauth accounts by the prefix they all share (`ax-main` → `main`,
/// `ax-codex-dev0` → `codex-dev0`). The hover card keeps the full name.
enum ClauthCaption {
    /// The longest prefix every name shares, cut back to a separator, and
    /// only when it leaves every name with something — one profile, or a
    /// prefix that is a whole name, shortens nothing.
    static func shortNames(_ names: [String]) -> [String: String] {
        var out = Dictionary(uniqueKeysWithValues: names.map { ($0, $0) })
        guard names.count >= 2, let first = names.first else { return out }
        var prefix = first
        for name in names.dropFirst() {
            while !name.hasPrefix(prefix) { prefix = String(prefix.dropLast()) }
            if prefix.isEmpty { return out }
        }
        // Back to the last separator so "ax-code" never becomes the cut
        // between "ax-codex-dev0" and "ax-code-bk".
        guard let cut = prefix.lastIndex(where: { "-_.".contains($0) }) else { return out }
        let stem = String(prefix[...cut])
        guard stem.count >= 2, names.allSatisfy({ $0.count > stem.count }) else { return out }
        for name in names { out[name] = String(name.dropFirst(stem.count)) }
        return out
    }

    /// The caption for an account: a clauth profile's short name, or
    /// Pulse's own label for its primaries and added accounts.
    @MainActor
    static func label(for account: AccountKey, settings: AppSettings, status: ClauthStatus?) -> String {
        guard let name = ClauthMapping.profileName(of: account) else { return settings.label(for: account) }
        let siblings = status?.profiles.map(\.name) ?? [name]
        return shortNames(siblings)[name] ?? name
    }

    /// Whether this ring is its harness's active slot.
    static func isActive(_ account: AccountKey, status: ClauthStatus?) -> Bool {
        guard let name = ClauthMapping.profileName(of: account), let harness = ClauthMapping.harness(of: account) else { return false }
        return status?.activeName(for: harness) == name
    }
}

/// The name under a ring — one line inside the caption budget
/// `DockLayout.captionHeight`, bold for the active account.
struct ClauthRailCaption: View {
    let account: AccountKey

    var body: some View {
        if ClauthVisibility.shared.railCaptions, PanelMetrics.showsCaptions, let watcher = ClauthWatcher.current {
            let active = ClauthCaption.isActive(account, status: watcher.status)
            Text(ClauthCaption.label(for: account, settings: watcher.settings, status: watcher.status))
                .font(.system(size: 9 * PanelMetrics.scale, weight: active ? .semibold : .regular, design: .rounded))
                .foregroundStyle(.primary.opacity(active ? 0.95 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: DockLayout.width - DockLayout.horizontalPadding * 2)
                .frame(height: 11 * PanelMetrics.scale)
        }
    }
}

/// Drawn over the ring: the other unscoped window as a thin inner arc, and
/// the active-slot badge. Sized to the ring, aligned to where the ring sits
/// in its item.
struct ClauthRingExtras: View {
    let account: AccountKey

    var body: some View {
        if let watcher = ClauthWatcher.current {
            let usage = watcher.store.usage(for: account)
            let settings = watcher.settings
            ZStack {
                if ClauthVisibility.shared.innerRing,
                   let inner = Self.innerWindow(for: usage, pinned: settings.pinnedWindow(for: account) ?? ClauthMapping.defaultPin(for: account, in: usage)) {
                    innerArc(inner, showsRemaining: settings.showsRemaining)
                }
                if ClauthCaption.isActive(account, status: watcher.status) {
                    activeBadge
                }
            }
            .frame(width: DockLayout.ringDiameter, height: DockLayout.ringDiameter)
            .allowsHitTesting(false)
        }
    }

    /// The window the inner arc shows: the unscoped window that is not the
    /// headline, weekly first. Nil leaves a single ring.
    nonisolated static func innerWindow(for usage: ProviderUsage, pinned: String?) -> UsageWindow? {
        let headline = usage.headlineWindow(preferring: pinned)
        let candidates = usage.windows.filter { $0.scope == nil && $0.id != headline?.id }
        return candidates.first { $0.kind == .weekly } ?? candidates.first { $0.kind == .fiveHour }
    }

    private func innerArc(_ window: UsageWindow, showsRemaining: Bool) -> some View {
        let line = DockLayout.ringLineWidth * 0.6
        let diameter = DockLayout.ringDiameter - DockLayout.ringLineWidth * 2 - line - 3 * PanelMetrics.scale
        let fraction = min(max(showsRemaining ? window.remainingFraction : window.usedFraction, 0), 1)
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(UsageTint.color(for: window.usedFraction, isExhausted: window.isExhausted), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    /// A small filled dot at the ring's top-right corner: this is the
    /// account the harness is signed in as.
    private var activeBadge: some View {
        let size = 7 * PanelMetrics.scale
        return Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(Color.black.opacity(0.9), lineWidth: 1.5 * PanelMetrics.scale))
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 1, y: -1)
            .accessibilityHidden(true)
    }
}
