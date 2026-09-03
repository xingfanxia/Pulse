import SwiftUI

/// One harness's block of the clauth pane: the active account, the chain in
/// walk order with every per-member control, the accounts with their verbs,
/// the add-account row, and codex's proxy row.
struct ClauthHarnessSection: View {
    let harness: ClauthHarness
    let status: ClauthStatus
    let watcher: ClauthWatcher
    let settings: AppSettings

    private var members: [ClauthStatus.Profile] { status.profiles.filter { $0.harness == harness } }
    private var title: String { harness == .codex ? "Codex" : "Claude Code" }

    var body: some View {
        SettingsGroup(String.localized("\(title) · chain")) {
            SettingsRow(
                String.localized("Active account"),
                subtitle: harness == .codex
                    ? String.localized("Rotates at the session boundary when the active login is limited.")
                    : String.localized("Auto-switch leaves an account at its 5h threshold.")
            ) {
                Text(status.activeName(for: harness) ?? "—")
                    .font(.system(size: 12, weight: .medium))
            }

            ForEach(ClauthChainEdit.chainOrdered(members, chain: status.chain(for: harness))) { profile in
                SettingsRowDivider()
                ClauthChainRow(profile: profile, status: status, watcher: watcher)
            }
        }

        SettingsGroup(String.localized("\(title) · accounts")) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, profile in
                if index > 0 { SettingsRowDivider() }
                ClauthAccountRow(profile: profile, status: status, watcher: watcher, settings: settings)
                if harness == .claude {
                    ClauthTokenRow(profile: profile, watcher: watcher)
                }
            }
            if !members.isEmpty { SettingsRowDivider() }
            ClauthAddAccountRow(harness: harness, watcher: watcher)
            if harness == .codex {
                SettingsRowDivider()
                ClauthProxyRow(watcher: watcher)
            }
        }
    }
}

/// A chain member's controls, or the add-to-chain button for a non-member.
struct ClauthChainRow: View {
    let profile: ClauthStatus.Profile
    let status: ClauthStatus
    let watcher: ClauthWatcher

    var body: some View {
        SettingsRow(
            profile.name,
            subtitle: ClauthCardFooter.stateLine(for: profile, status: status),
            icon: ClauthMapping.provider(for: profile.harness)
        ) {
            if let chain = profile.fallback {
                HStack(spacing: 6) {
                    thresholdMenu(chain)
                    weeklyMenu(chain)
                    gatesMenu(chain)
                    Button { watcher.actions.fallbackMove(profile.name, up: true) } label: { Image(systemName: "chevron.up") }
                        .disabled(chain.position == 0)
                        .accessibilityLabel(String.localized("Move \(profile.name) up"))
                    Button { watcher.actions.fallbackMove(profile.name, up: false) } label: { Image(systemName: "chevron.down") }
                        .disabled(chain.position >= status.chain(for: profile.harness).count - 1)
                        .accessibilityLabel(String.localized("Move \(profile.name) down"))
                    Button(String.localized("Remove")) { remove() }
                }
            } else {
                Button(String.localized("Add to chain")) { watcher.actions.fallbackAdd(profile.name) }
            }
        }
    }

    private func thresholdMenu(_ chain: ClauthStatus.Fallback) -> some View {
        Menu(ClauthChainEdit.percentLabel(chain.threshold)) {
            Text(localized: "Auto-switch leaves this account at this 5h usage.")
            ForEach(ClauthChainEdit.thresholdPresets, id: \.self) { preset in
                Button("\(preset)%") { watcher.actions.setThreshold(profile.name, preset) }
            }
            Divider()
            Button(String.localized("Custom…")) {
                guard let typed = ClauthPrompts.askText(
                    title: String.localized("5h threshold for \(profile.name)"),
                    message: String.localized("A whole percent between 0 and 100."),
                    initial: "\(Int(chain.threshold))",
                    button: String.localized("Set")
                ), let parsed = ClauthChainEdit.parseFiveHourThreshold(typed) else { return }
                watcher.actions.setThreshold(profile.name, parsed)
            }
        }
        .frame(width: 70)
        .help(String.localized("Auto-switch leaves this account at this 5h usage."))
    }

    private func weeklyMenu(_ chain: ClauthStatus.Fallback) -> some View {
        let chainDefault = status.weeklySwitchThreshold ?? ClauthChainEdit.defaultWeeklyLine
        let label = chain.weeklyThreshold.map { String.localized("week \(ClauthChainEdit.percentLabel($0))") }
            ?? String.localized("week default")
        return Menu(label) {
            Text(localized: "Weekly limit here")
            Button(String.localized("Follow chain default (\(ClauthChainEdit.percentLabel(chainDefault)))")) {
                watcher.actions.setMemberWeekly(profile.name, nil)
            }
            ForEach(ClauthChainEdit.weeklyPresets, id: \.self) { preset in
                Button(ClauthChainEdit.percentLabel(preset)) { watcher.actions.setMemberWeekly(profile.name, preset) }
            }
            Divider()
            Button(String.localized("Custom…")) {
                guard let typed = ClauthPrompts.askText(
                    title: String.localized("Weekly line for \(profile.name)"),
                    message: String.localized("A percent between 0 and 100; the chain-wide value stays the default."),
                    initial: chain.weeklyThreshold.map { "\($0)" } ?? "",
                    button: String.localized("Set")
                ), let parsed = ClauthChainEdit.parseMemberWeekly(typed) else { return }
                watcher.actions.setMemberWeekly(profile.name, parsed)
            }
        }
        .frame(width: 110)
    }

    private func gatesMenu(_ chain: ClauthStatus.Fallback) -> some View {
        Menu {
            Toggle(String.localized("Last resort"), isOn: Binding(
                get: { chain.lastResort },
                set: { watcher.actions.setLastResort(profile.name, $0) }
            ))
            Text(localized: "The chain parks here when nothing else has headroom — even over its own limit.")
            Divider()
            Toggle(String.localized("Check weekly usage"), isOn: Binding(
                get: { chain.checkWeekly },
                set: { watcher.actions.setCheckWeekly(profile.name, $0) }
            ))
            Text(localized: "Off: only the 100% hard cap blocks this account.")
            Toggle(String.localized("Check per-model weekly"), isOn: Binding(
                get: { chain.checkScoped },
                set: { watcher.actions.setCheckScoped(profile.name, $0) }
            ))
            Text(localized: "On: a spent per-model week takes this account out of rotation.")
        } label: {
            Image(systemName: chain.lastResort ? "flag.fill" : "slider.horizontal.3")
        }
        .frame(width: 44)
        .accessibilityLabel(String.localized("Gates for \(profile.name)"))
    }

    private func remove() {
        if let consequence = ClauthChainEdit.removalConsequence(of: profile.name, in: status) {
            guard ClauthPrompts.confirm(
                title: String.localized("Remove \(profile.name) from the chain?"),
                message: consequence.prompt,
                button: String.localized("Remove")
            ) else { return }
        }
        watcher.actions.fallbackRemove(profile.name)
    }
}

/// An account with its verbs: Switch, Re-authenticate (or capture), Rename,
/// Delete (with the consequence-aware confirm).
struct ClauthAccountRow: View {
    let profile: ClauthStatus.Profile
    let status: ClauthStatus
    let watcher: ClauthWatcher
    let settings: AppSettings

    private var isActive: Bool { status.activeName(for: profile.harness) == profile.name }
    private var account: AccountKey { ClauthMapping.account(for: profile) }

    var body: some View {
        SettingsRow(
            profile.name,
            subtitle: subtitle,
            icon: ClauthMapping.provider(for: profile.harness)
        ) {
            HStack(spacing: 6) {
                if let flight = watcher.actions.loginInFlight, flight.name == profile.name {
                    ProgressView().controlSize(.small)
                } else if watcher.actions.deleteInFlight == profile.name {
                    ProgressView().controlSize(.small)
                }
                if !isActive {
                    Button(String.localized("Switch")) { watcher.switches.switchTo(profile.name) }
                        .disabled(watcher.switches.phase.isBusy)
                }
                Menu {
                    if !profile.isThirdParty {
                        Button(String.localized("Re-authenticate…")) {
                            watcher.actions.reauth(profile.name, codex: profile.harness == .codex, mode: .browser)
                        }
                        if profile.harness == .codex {
                            Button(String.localized("Capture current Codex login")) {
                                watcher.actions.reauth(profile.name, codex: true, mode: .capture)
                            }
                        }
                    }
                    Button(String.localized("Rename…")) {
                        ClauthPrompts.rename(profile.name) { watcher.actions.rename(profile.name, to: $0) }
                    }
                    Toggle(String.localized("Show on rail"), isOn: Binding(
                        get: { !ClauthVisibility.shared.hiddenAccounts.contains(account.id) },
                        set: { ClauthVisibility.setHidden(!$0, for: account, settings: settings) }
                    ))
                    Divider()
                    Button(String.localized("Delete…"), role: .destructive) { delete() }
                        .disabled(watcher.actions.loginInFlight != nil || watcher.actions.deleteInFlight != nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .frame(width: 44)
                .accessibilityLabel(String.localized("Actions for \(profile.name)"))
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if isActive { parts.append(String.localized("active")) }
        if let plan = ClauthMapping.plan(for: profile) { parts.append(plan) }
        if let email = profile.accountEmail { parts.append(email) }
        if let auth = ClauthCardFooter.authLine(for: profile) { parts.append(auth) }
        if ClauthMapping.isInactive(profile) { parts.append(String.localized("inactive")) }
        return parts.joined(separator: " · ")
    }

    private func delete() {
        let prompt = ClauthChainEdit.deletePrompt(profile.name, active: isActive, inChain: profile.inChain)
        guard ClauthPrompts.confirm(
            title: String.localized("Delete \(profile.name)?"),
            message: prompt,
            button: String.localized("Delete"),
            destructive: true
        ) else { return }
        watcher.actions.delete(profile.name)
    }
}

/// Create a profile: a name plus the harness's sign-in doors — claude: the
/// browser; codex: capture the login codex already holds, or a browser PKCE
/// sign-in. `--new` on the spawn is the race-proof collision guard.
struct ClauthAddAccountRow: View {
    let harness: ClauthHarness
    let watcher: ClauthWatcher
    @State private var name = ""

    var body: some View {
        SettingsRow(
            String.localized("Add account"),
            subtitle: subtitle
        ) {
            HStack(spacing: 6) {
                TextField(String.localized("name"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit { commit(harness == .codex ? .capture : .browser) }
                if harness == .codex {
                    Button(String.localized("Capture")) { commit(.capture) }
                        .disabled(!canAdd)
                        .help(String.localized("Copies the login codex is signed in with right now — instant, no browser."))
                }
                Button(String.localized("Sign in…")) { commit(.browser) }
                    .disabled(!canAdd)
            }
        }
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && watcher.actions.loginInFlight == nil
    }

    private var subtitle: String {
        if let flight = watcher.actions.loginInFlight { return flight.message }
        return harness == .codex
            ? String.localized("Capture copies the login codex already has; Sign in opens your browser. Either creates the profile.")
            : String.localized("Opens your browser to sign in; creates the profile on success.")
    }

    private func commit(_ mode: ClauthActions.LoginMode) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        watcher.actions.addAccount(trimmed, codex: harness == .codex, mode: mode)
        name = ""
    }
}
