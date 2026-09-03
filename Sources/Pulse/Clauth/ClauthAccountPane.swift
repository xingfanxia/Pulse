import SwiftUI

/// Settings → a clauth account. Pulse's own per-account rows (rail, ring
/// window, colour) plus the reading and the account's verbs — and none of
/// upstream's Sign out / rename field / Remove account: clauth owns the
/// login, and renaming or deleting lives in the clauth pane's confirms.
struct ClauthAccountPane: View {
    let account: AccountKey
    let settings: AppSettings
    let store: UsageStore

    enum Action: Equatable, Sendable { case switchTo, refresh, reauthenticate, captureCodexLogin }

    /// The verbs this pane offers — a table so the absence of sign-out /
    /// remove / rename is asserted, not assumed.
    nonisolated static func actions(for profile: ClauthStatus.Profile, status: ClauthStatus) -> [Action] {
        var actions: [Action] = []
        if status.activeName(for: profile.harness) != profile.name { actions.append(.switchTo) }
        actions.append(.refresh)
        if !profile.isThirdParty {
            actions.append(.reauthenticate)
            if profile.harness == .codex { actions.append(.captureCodexLogin) }
        }
        return actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            panelGroup
            if let watcher = ClauthWatcher.current, let status = watcher.status,
               let name = ClauthMapping.profileName(of: account), let profile = status.profile(named: name) {
                accountGroup(profile, status: status, watcher: watcher)
            }
            usageGroup
            Text(localized: "Chain position, proxy mode, tokens and deletion are in the clauth pane.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var panelGroup: some View {
        let usage = store.usage(for: account)
        return SettingsGroup(String.localized("Panel")) {
            SettingsRow(String.localized("Show in panel")) {
                Toggle("", isOn: Binding(
                    get: { !ClauthVisibility.shared.hiddenAccounts.contains(account.id) },
                    set: { ClauthVisibility.setHidden(!$0, for: account, settings: settings) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingsRowDivider()

            SettingsRow(String.localized("Ring shows"), subtitle: String.localized("Which limit the rail's ring tracks.")) {
                Picker("", selection: Binding(
                    get: {
                        let pinned = settings.pinnedWindow(for: account)
                        return usage.windows.contains { $0.id == pinned } ? pinned : nil
                    },
                    set: { settings.setPinnedWindow($0, for: account) }
                )) {
                    Text(localized: "Highest usage").tag(String?.none)
                    ForEach(usage.windows) { window in
                        Text(window.name).tag(String?.some(window.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                .disabled(usage.windows.isEmpty)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Ring colour"),
                subtitle: settings.ringTint(for: account) == nil
                    ? String.localized("Coloured by how much is left.")
                    : String.localized("A colour of your own, whatever the usage.")
            ) {
                HStack(spacing: 8) {
                    if let chosen = settings.ringTint(for: account) {
                        ColorPicker("", selection: Binding(
                            get: { chosen },
                            set: { settings.setRingTint($0, for: account) }
                        ), supportsOpacity: false)
                        .labelsHidden()
                    }
                    Picker("", selection: Binding(
                        get: { settings.ringTint(for: account) != nil },
                        set: { custom in settings.setRingTint(custom ? RingTint.suggestions.first : nil, for: account) }
                    )) {
                        Text(localized: "Automatic").tag(false)
                        Text(localized: "Custom").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }
        }
    }

    private func accountGroup(_ profile: ClauthStatus.Profile, status: ClauthStatus, watcher: ClauthWatcher) -> some View {
        SettingsGroup(String.localized("Account")) {
            SettingsRow(profile.name, subtitle: ClauthCardFooter.stateLine(for: profile, status: status)) {
                HStack(spacing: 6) {
                    ForEach(Self.actions(for: profile, status: status), id: \.self) { action in
                        switch action {
                        case .switchTo:
                            Button(String.localized("Switch")) { watcher.switches.switchTo(profile.name) }
                                .disabled(watcher.switches.phase.isBusy)
                        case .refresh:
                            Button(String.localized("Refresh")) { watcher.refresh(account) }
                        case .reauthenticate:
                            Button(String.localized("Re-authenticate…")) {
                                watcher.actions.reauth(profile.name, codex: profile.harness == .codex, mode: .browser)
                            }
                        case .captureCodexLogin:
                            Button(String.localized("Capture")) { watcher.actions.reauth(profile.name, codex: true, mode: .capture) }
                        }
                    }
                }
            }
            ForEach(ClauthCardFooter.lines(for: profile, status: status, phase: watcher.switches.phase, harness: watcher.switches.harness, login: watcher.actions.loginInFlight, error: watcher.actions.lastError).dropFirst()) { line in
                SettingsRowDivider()
                SettingsRow(line.text) { EmptyView() }
            }
        }
    }

    private var usageGroup: some View {
        let usage = store.usage(for: account)
        return SettingsGroup(String.localized("Current usage")) {
            if usage.windows.isEmpty {
                SettingsRow(String.localized("No limits reported.")) { EmptyView() }
            }
            ForEach(Array(usage.windows.enumerated()), id: \.element.id) { index, window in
                if index > 0 { SettingsRowDivider() }
                SettingsRow(window.name, subtitle: window.resetsAt.map { String.localized("Resets \($0.formatted(date: .abbreviated, time: .shortened))") }) {
                    Text(window.percentText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(UsageTint.isSpent(window) ? Color.pulseExhausted : .primary)
                        .monospacedDigit()
                }
            }
            if case .stale = usage.state, let observed = usage.observedAt {
                SettingsRowDivider()
                SettingsRow(String.localized("As of \(observed.formatted(date: .abbreviated, time: .shortened))")) { EmptyView() }
            }
        }
    }
}
