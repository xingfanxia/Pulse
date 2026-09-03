import SwiftUI

/// Settings → clauth: everything ccsbar's panel controls, in Pulse's grouped
/// cards. Daemon state and the two visibility switches, the chain-global
/// auto-switch settings, then one section per harness with its chain
/// editor, its accounts and — for codex — proxy mode.
struct ClauthSettingsPane: View {
    let settings: AppSettings
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let watcher = ClauthWatcher.current {
                daemonGroup(watcher)
                railGroup
                if let status = watcher.status {
                    autoSwitchGroup(status, watcher: watcher)
                    ClauthHarnessSection(harness: .claude, status: status, watcher: watcher, settings: settings)
                    ClauthHarnessSection(harness: .codex, status: status, watcher: watcher, settings: settings)
                }
            } else {
                SettingsGroup(String.localized("clauth")) {
                    SettingsRow(String.localized("Not running"), subtitle: String.localized("The clauth watcher starts with the app.")) { EmptyView() }
                }
            }
        }
    }

    private func daemonGroup(_ watcher: ClauthWatcher) -> some View {
        SettingsGroup(String.localized("clauth daemon")) {
            SettingsRow(String.localized("Daemon"), subtitle: daemonSubtitle(watcher)) {
                Text(daemonState(watcher.freshness))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(watcher.freshness == .dead ? Color.pulseExhausted : .secondary)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Show Claude Code and Codex rings"),
                subtitle: String.localized("Pulse’s own rings for the two CLIs, beside the clauth accounts.")
            ) {
                Toggle("", isOn: Binding(
                    get: { !ClauthVisibility.shared.hidesPrimaries },
                    set: { ClauthVisibility.setHidesPrimaries(!$0, settings: settings) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Hide inactive accounts"),
                subtitle: String.localized("Cancelled or lapsed plans and broken logins stay off the rail; the active account always shows.")
            ) {
                Toggle("", isOn: Binding(
                    get: { ClauthVisibility.shared.hidesInactive },
                    set: { ClauthVisibility.setHidesInactive($0, settings: settings) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if let error = watcher.actions.lastError {
                SettingsRowDivider()
                SettingsRow(String.localized("Last error"), subtitle: error) {
                    Button(String.localized("Dismiss")) { watcher.actions.clearError() }
                }
            }
        }
    }

    private var railGroup: some View {
        SettingsGroup(String.localized("Rail")) {
            SettingsRow(
                String.localized("Names under rings"),
                subtitle: String.localized("The account under each ring; clauth names lose the prefix they all share. Widens the rail.")
            ) {
                Toggle("", isOn: Binding(
                    get: { ClauthVisibility.shared.railCaptions },
                    set: { ClauthVisibility.setRailCaptions($0, settings: settings) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Weekly as an inner ring"),
                subtitle: String.localized("A thinner arc inside the ring for the other limit — weekly inside the 5-hour ring. Single ring when there is only one.")
            ) {
                Toggle("", isOn: Binding(
                    get: { ClauthVisibility.shared.innerRing },
                    set: { ClauthVisibility.shared.innerRing = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Working mark"),
                subtitle: String.localized("The white mark that turns while a claude or codex process is writing. It cannot tell accounts apart, so by default only the active account’s ring shows it.")
            ) {
                Picker("", selection: Binding(
                    get: { ClauthVisibility.shared.activity },
                    set: { ClauthVisibility.shared.activity = $0 }
                )) {
                    Text(localized: "Off").tag(ClauthVisibility.Activity.off)
                    Text(localized: "Active").tag(ClauthVisibility.Activity.activeOnly)
                    Text(localized: "All").tag(ClauthVisibility.Activity.all)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
            }
        }
    }

    private func daemonState(_ freshness: ClauthLiveness.Freshness) -> String {
        switch freshness {
        case .live: String.localized("Live")
        case .syncing: String.localized("Syncing…")
        case .dead: String.localized("Not running")
        }
    }

    private func daemonSubtitle(_ watcher: ClauthWatcher) -> String {
        guard let status = watcher.status else { return String.localized("No status.json yet — is the daemon installed?") }
        let version = status.clauthVersion ?? "?"
        let written = ClauthISO.parse(status.generatedAt).map { date -> String in
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: date, relativeTo: Date())
        } ?? status.generatedAt
        return String.localized("clauth \(version) · status written \(written)")
    }

    private func autoSwitchGroup(_ status: ClauthStatus, watcher: ClauthWatcher) -> some View {
        SettingsGroup(String.localized("Auto-switch")) {
            SettingsRow(
                String.localized("When the chain is spent"),
                subtitle: status.wrapOff
                    ? String.localized("Credentials cleared; resumes automatically when a window resets.")
                    : String.localized("Stays on the last account even past its limit.")
            ) {
                Picker("", selection: Binding(
                    get: { status.wrapOff },
                    set: { watcher.actions.setWrapOff($0) }
                )) {
                    Text(localized: "Stay on last").tag(false)
                    Text(localized: "Switch off").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Weekly line"),
                subtitle: String.localized("Auto-switch treats an account past this share of its weekly window as spent — it leaves early instead of sitting at 100% for days.")
            ) {
                ClauthWeeklyLinePicker(
                    value: status.weeklySwitchThreshold ?? ClauthChainEdit.defaultWeeklyLine,
                    commit: { watcher.actions.setWeeklyThreshold($0) }
                )
            }

            SettingsRowDivider()

            SettingsRow(String.localized("Next move"), subtitle: forecastText(status)) {
                if status.burnAware == true {
                    Text(localized: "burn-aware")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func forecastText(_ status: ClauthStatus) -> String {
        switch (status.forecast?.action, status.forecast?.to) {
        case ("switch", .some(let to)): String.localized("The daemon would switch to \(to) next.")
        case ("off", _): String.localized("The daemon would switch everything off next.")
        default: String.localized("No rotation target — the chain has nothing to move to.")
        }
    }
}

/// Presets plus a typed custom value, for the chain-wide weekly line.
struct ClauthWeeklyLinePicker: View {
    let value: Double
    let commit: (Double) -> Void

    var body: some View {
        Menu(ClauthChainEdit.percentLabel(value)) {
            ForEach(ClauthChainEdit.weeklyPresets, id: \.self) { preset in
                Button(ClauthChainEdit.percentLabel(preset)) { commit(preset) }
            }
            Divider()
            Button(String.localized("Custom…")) {
                guard let typed = ClauthPrompts.askText(
                    title: String.localized("Weekly line"),
                    message: String.localized("A percent between 50 and 100."),
                    initial: ClauthChainEdit.percentLabel(value).replacingOccurrences(of: "%", with: ""),
                    button: String.localized("Set")
                ), let parsed = ClauthChainEdit.parseWeeklyLine(typed) else { return }
                commit(parsed)
            }
        }
        .frame(width: 90)
    }
}
