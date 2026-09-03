import SwiftUI

/// The clauth block under a card's limits: active-slot and chain state, the
/// codex limiter's verdict with ccsbar's attribution, banked resets, a
/// switch or login in flight, the last error. Everything is a pure `lines`
/// table so the wording is tested without a view.
struct ClauthCardFooter: View {
    let account: AccountKey

    var body: some View {
        if let name = ClauthMapping.profileName(of: account),
           let watcher = ClauthWatcher.current,
           let status = watcher.status,
           let profile = status.profile(named: name) {
            let lines = Self.lines(
                for: profile,
                status: status,
                phase: watcher.switches.phase,
                harness: watcher.switches.harness,
                login: watcher.actions.loginInFlight,
                error: watcher.actions.lastError
            )
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(line.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct Line: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable { case info, warning, codex, progress, error }
        let id: String
        let text: String
        let kind: Kind

        var color: Color {
            switch kind {
            case .info: .primary.opacity(0.55)
            case .warning: .pulseWarning
            case .codex: .primary.opacity(0.7)
            case .progress: .primary.opacity(0.7)
            case .error: .pulseExhausted
            }
        }
    }

    // MARK: Lines

    nonisolated static func lines(
        for profile: ClauthStatus.Profile,
        status: ClauthStatus,
        phase: ClauthSwitchMachine.Phase = .idle,
        harness: ClauthHarness = .claude,
        login: ClauthActions.LoginFlight? = nil,
        error: String? = nil,
        now: Date = Date()
    ) -> [Line] {
        var lines: [Line] = []
        lines.append(Line(id: "state", text: stateLine(for: profile, status: status), kind: .info))
        if let auth = authLine(for: profile) {
            lines.append(Line(id: "auth", text: auth, kind: .warning))
        }
        if let verdict = verdictLine(for: profile, now: now) {
            var text = verdict.message + " — " + String.localized("auto-switch rotates at the session boundary")
            if let hint = resetHint(verdict.resetsAt, now: now) { text += " · " + hint }
            lines.append(Line(id: "verdict", text: text, kind: .warning))
        }
        if let banked = bankedLine(for: profile) {
            lines.append(Line(id: "banked", text: banked, kind: .codex))
        }
        if let progress = phaseLine(for: profile, phase: phase, harness: harness) {
            lines.append(Line(id: "switch", text: progress.text, kind: progress.kind))
        }
        if let login, login.name == profile.name {
            lines.append(Line(id: "login", text: login.message, kind: .progress))
        }
        if let error {
            lines.append(Line(id: "error", text: error, kind: .error))
        }
        return lines
    }

    /// "active · chain #1 · switches at 90%" / "chain #2 · switches at 90% ·
    /// last resort" / "not in chain".
    nonisolated static func stateLine(for profile: ClauthStatus.Profile, status: ClauthStatus) -> String {
        var parts: [String] = []
        if status.activeName(for: profile.harness) == profile.name {
            parts.append(String.localized("active"))
        }
        if let chain = profile.fallback {
            parts.append(String.localized("chain #\("\(chain.position + 1)") · switches at \("\(Int(chain.threshold.rounded()))%")"))
            if chain.lastResort { parts.append(String.localized("last resort")) }
            if !chain.armed { parts.append(String.localized("disarmed")) }
        } else {
            parts.append(String.localized("not in chain"))
        }
        if profile.rollingToken { parts.append(String.localized("rolling token")) }
        return parts.joined(separator: " · ")
    }

    nonisolated static func authLine(for profile: ClauthStatus.Profile) -> String? {
        switch profile.authStatus {
        case "broken": String.localized("login broken — re-authenticate")
        case "expiring": String.localized("login expiring — re-authenticate soon")
        default: nil
        }
    }

    /// Codex's own limiter verdict, attributed the way ccsbar does: a named
    /// window is named; a bare reason names the live window reading full,
    /// else stays generic; a lapsed window says nothing.
    nonisolated static func verdictLine(for profile: ClauthStatus.Profile, now: Date = Date()) -> (message: String, resetsAt: Date?)? {
        func live(_ window: ClauthStatus.Window?) -> Bool {
            guard let resets = ClauthISO.parse(window?.resetsAt) else { return false }
            return resets > now
        }
        let fiveHour = profile.window("5h")
        let week = profile.window("7d")
        switch profile.codexRateLimitReached {
        case nil:
            return nil
        case "primary":
            guard live(fiveHour) else { return nil }
            return (String.localized("\(profile.name) hit its 5h window"), ClauthISO.parse(fiveHour?.resetsAt))
        case "secondary":
            guard live(week) else { return nil }
            return (String.localized("\(profile.name) hit its weekly window"), ClauthISO.parse(week?.resetsAt))
        case .some:
            if live(week), (week?.utilizationPct ?? 0) >= 100 {
                return (String.localized("\(profile.name) hit its weekly window"), ClauthISO.parse(week?.resetsAt))
            }
            if live(fiveHour), (fiveHour?.utilizationPct ?? 0) >= 100 {
                return (String.localized("\(profile.name) hit its 5h window"), ClauthISO.parse(fiveHour?.resetsAt))
            }
            guard live(fiveHour) || live(week) else { return nil }
            return (String.localized("\(profile.name) is rate-limited"), nil)
        }
    }

    /// Only worth a word beside a limit, and only when the daemon carried a
    /// count: nil and zero are both silent.
    nonisolated static func bankedLine(for profile: ClauthStatus.Profile) -> String? {
        guard profile.harness == .codex, let count = profile.codexResetCredits, count > 0 else { return nil }
        return count == 1
            ? String.localized("1 free reset banked")
            : String.localized("\("\(count)") free resets banked")
    }

    nonisolated static func phaseLine(for profile: ClauthStatus.Profile, phase: ClauthSwitchMachine.Phase, harness: ClauthHarness) -> (text: String, kind: Line.Kind)? {
        switch phase {
        case .idle:
            return nil
        case .arming(let target):
            return target == profile.name ? (String.localized("Waiting for confirmation…"), .progress) : nil
        case .pending(let target):
            return target == profile.name ? (String.localized("Switching to \(target)…"), .progress) : nil
        case .confirmed(let target, let viaCLI):
            guard target == profile.name else { return nil }
            return viaCLI
                ? (String.localized("Switched to \(target) via clauth — the daemon is down"), .progress)
                : (String.localized("Switched to \(target)"), .progress)
        case .failed(let reason):
            return harness == profile.harness ? (String.localized("Switch failed: \(reason)"), .error) : nil
        }
    }

    /// "resets in 5d 16h" — nil once past.
    nonisolated static func resetHint(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3_600, minutes = (seconds % 3_600) / 60
        let span: String = if days > 0 {
            hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        } else if hours > 0 {
            minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            "\(minutes)m"
        }
        return String.localized("resets in \(span)")
    }

    // MARK: Footnote

    /// The card's footnote for a clauth account whose daemon has stopped
    /// ticking; nil hands the line back to upstream's stale wording.
    static func footnote(for usage: ProviderUsage, watcher: ClauthWatcher? = .current, now: Date = Date()) -> String? {
        guard ClauthFetchGuard.isClauthSlot(usage.account), let watcher, watcher.freshness == .dead else { return nil }
        guard let observed = usage.observedAt else { return String.localized("clauth daemon not running") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let ago = formatter.localizedString(for: observed, relativeTo: now)
        return String.localized("clauth daemon not running · last reading \(ago)")
    }
}
