import SwiftUI

/// What the rail says under a ring: the account's name, shortened for
/// clauth accounts by the prefix they all share (`ax-main` → `main`,
/// `ax-codex-dev0` → `codex-dev0`). The hover card keeps the full name.
enum ClauthCaption {
    /// The longest prefix every name shares, cut back to a separator, and
    /// only when it leaves every name with something — one profile, or a
    /// prefix that is a whole name, shortens nothing.
    static func shortNames(_ names: [String]) -> [String: String] {
        var out = Dictionary(names.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
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

    /// The caption for an account: a clauth profile's email (its local
    /// part) or its short name, by the caption style; Pulse's own label for
    /// its primaries and added accounts. A profile without an email falls
    /// back to the short name.
    @MainActor
    static func label(for account: AccountKey, settings: AppSettings, status: ClauthStatus?, style: ClauthVisibility.CaptionStyle = ClauthVisibility.shared.captionStyle) -> String {
        guard let name = ClauthMapping.profileName(of: account) else { return settings.label(for: account) }
        if style == .email, let email = status?.profile(named: name)?.accountEmail, let local = localPart(of: email) {
            return local
        }
        let siblings = status?.profiles.map(\.name) ?? [name]
        return shortNames(siblings)[name] ?? name
    }

    /// `xingfanxia@gmail.com` → `xingfanxia`; nil for anything that is not
    /// shaped like an address.
    static func localPart(of email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at > trimmed.startIndex else { return nil }
        return String(trimmed[..<at])
    }

    /// Whether this ring is its harness's active slot.
    static func isActive(_ account: AccountKey, status: ClauthStatus?) -> Bool {
        guard let name = ClauthMapping.profileName(of: account), let harness = ClauthMapping.harness(of: account) else { return false }
        return status?.activeName(for: harness) == name
    }
}

/// The name under a ring — one line inside the caption budget
/// `DockLayout.captionHeight`, which exists on a side rail only: across the
/// top there is no room under the menu bar, so the view draws nothing there
/// and the budget agrees. The harness's active account sits in an accent
/// capsule, the way a selected segment does; the others are plain dim type.
/// The ring itself carries no mark (AX 2026-09-03: a corner dot read as a
/// notification badge).
struct ClauthRailCaption: View {
    let account: AccountKey

    var body: some View {
        if ClauthVisibility.shared.railCaptions, PanelMetrics.showsCaptions,
           let watcher = ClauthWatcher.current, watcher.placement.edge.isVertical {
            let active = ClauthCaption.isActive(account, status: watcher.status)
            let scale = PanelMetrics.scale
            Text(ClauthCaption.label(for: account, settings: watcher.settings, status: watcher.status))
                .font(.system(size: 9 * scale, weight: active ? .bold : .regular, design: .rounded))
                .foregroundStyle(active ? Color.white : .primary.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, active ? 6 * scale : 0)
                .padding(.vertical, 1 * scale)
                .background {
                    if active {
                        // Solid, not tinted: a translucent accent on the
                        // rail's black read as navy and vanished (AX).
                        Capsule().fill(Color.accentColor.opacity(0.9))
                    }
                }
                .frame(maxWidth: DockLayout.thickness(on: .vertical) - DockLayout.horizontalPadding * 2)
                .frame(height: 13 * scale)
        }
    }
}

/// Drawn over a clauth ring: the other unscoped window as a thin inner arc.
/// Sized to the ring, aligned to where the ring sits in its item, and scaled
/// with it while pointed at. clauth rings only — a primary's headline is
/// "whichever window is fullest", so its inner and outer arcs would trade
/// places as usage crossed over.
struct ClauthRingExtras: View {
    let account: AccountKey
    var selected: Bool = false

    var body: some View {
        if let watcher = ClauthWatcher.current, ClauthMapping.harness(of: account) != nil {
            let usage = watcher.store.usage(for: account)
            let settings = watcher.settings
            ZStack {
                if ClauthVisibility.shared.innerRing,
                   let inner = Self.innerWindow(for: usage, pinned: settings.pinnedWindow(for: account) ?? ClauthMapping.defaultPin(for: account, in: usage)) {
                    innerArc(inner, showsRemaining: settings.showsRemaining)
                }
            }
            .frame(width: DockLayout.ringDiameter, height: DockLayout.ringDiameter)
            .scaleEffect(selected ? 1.06 : 1)
            .allowsHitTesting(false)
        }
    }

    /// The window the inner arc shows: the unscoped window that is not the
    /// headline — the 5h window inside the weekly ring by default; whichever
    /// is left when the user pins the other; the unscoped week when the pin
    /// is a per-model window, so the two gates that block the account are
    /// always the two on screen. Nil leaves a single ring.
    nonisolated static func innerWindow(for usage: ProviderUsage, pinned: String?) -> UsageWindow? {
        let headline = usage.headlineWindow(preferring: pinned)
        let candidates = usage.windows.filter { $0.scope == nil && $0.id != headline?.id }
        let preferred: UsageWindow.Kind = headline?.scope == nil ? .fiveHour : .weekly
        return candidates.first { $0.kind == preferred } ?? candidates.first { $0.kind == .weekly } ?? candidates.first { $0.kind == .fiveHour }
    }

    /// The inner arc's length. A spent window draws a full arc whichever
    /// way the figure is counted — upstream's `arcFraction` rule: the most
    /// urgent state must never be the one with the least ink.
    nonisolated static func arcFraction(_ window: UsageWindow, showsRemaining: Bool) -> Double {
        if window.isExhausted || window.usedFraction >= 1 { return 1 }
        return min(max(showsRemaining ? window.remainingFraction : window.usedFraction, 0), 1)
    }

    /// What the collapsed sliver's alert colour looks at for an entry: the
    /// headline, and for a clauth ring the inner window too — after the
    /// default pin moved to the week, the 5h limit that actually blocks a
    /// session is no longer the headline.
    @MainActor
    static func alertWindows(_ entry: RailEntry) -> [UsageWindow] {
        guard let headline = entry.headline else { return [] }
        guard ClauthMapping.harness(of: entry.usage.account) != nil, ClauthVisibility.shared.innerRing,
              let inner = innerWindow(for: entry.usage, pinned: headline.id) else { return [headline] }
        return [headline, inner]
    }

    private func innerArc(_ window: UsageWindow, showsRemaining: Bool) -> some View {
        let line = DockLayout.ringLineWidth * 0.6
        let diameter = DockLayout.ringDiameter - DockLayout.ringLineWidth * 2 - line - 3 * PanelMetrics.scale
        let fraction = Self.arcFraction(window, showsRemaining: showsRemaining)
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
}
