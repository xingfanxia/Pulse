import AppKit
import SwiftUI

/// What a clauth ring offers on right-click, as a pure decision table.
enum ClauthRingMenu {
    enum Item: Hashable, Sendable {
        case switchTo(String)
        case refresh
        case reauthenticate
        case captureCodexLogin
        case rename
        case hide
    }

    /// The active row has no "Switch to"; a broken login leads with
    /// "Re-authenticate"; third-party rows have no login to renew; every row
    /// can be hidden from the rail.
    static func items(for profile: ClauthStatus.Profile, status: ClauthStatus) -> [Item] {
        var items: [Item] = []
        let isActive = status.activeName(for: profile.harness) == profile.name
        let canReauth = !profile.isThirdParty
        if canReauth, profile.authBroken { items.append(.reauthenticate) }
        if !isActive { items.append(.switchTo(profile.name)) }
        items.append(.refresh)
        if canReauth, !profile.authBroken { items.append(.reauthenticate) }
        if canReauth, profile.harness == .codex { items.append(.captureCodexLogin) }
        items.append(.rename)
        items.append(.hide)
        return items
    }
}

/// The one hook on `UsageDockItem`: a context menu, an in-flight badge and
/// the profile name for VoiceOver — for clauth rings only, everything else
/// passes through untouched.
struct ClauthRingMenuModifier: ViewModifier {
    let account: AccountKey

    @ViewBuilder
    func body(content: Content) -> some View {
        if let name = ClauthMapping.profileName(of: account) {
            content
                .overlay { ClauthInFlightBadge(name: name) }
                .accessibilityLabel(String.localized("\(name) usage"))
                .contextMenu { ClauthRingMenuContent(account: account, name: name) }
        } else {
            content
        }
    }
}

/// A small spinner over the ring whose switch is in flight.
private struct ClauthInFlightBadge: View {
    let name: String

    var body: some View {
        if let watcher = ClauthWatcher.current, watcher.switches.inFlightTarget == name {
            ProgressView()
                .controlSize(.small)
                .allowsHitTesting(false)
        }
    }
}

private struct ClauthRingMenuContent: View {
    let account: AccountKey
    let name: String

    var body: some View {
        if let watcher = ClauthWatcher.current, let status = watcher.status, let profile = status.profile(named: name) {
            ForEach(ClauthRingMenu.items(for: profile, status: status), id: \.self) { item in
                button(item, watcher: watcher, profile: profile, status: status)
            }
        }
    }

    @ViewBuilder
    private func button(_ item: ClauthRingMenu.Item, watcher: ClauthWatcher, profile: ClauthStatus.Profile, status: ClauthStatus) -> some View {
        switch item {
        case .switchTo(let target):
            Button(String.localized("Switch to \(target)")) { watcher.switches.switchTo(target) }
                .disabled(watcher.switches.phase.isBusy)
        case .refresh:
            Button(String.localized("Refresh")) { watcher.refresh(account) }
        case .reauthenticate:
            Button(String.localized("Re-authenticate…")) {
                watcher.actions.reauth(name, codex: profile.harness == .codex, mode: .browser)
            }
        case .captureCodexLogin:
            Button(String.localized("Capture current Codex login")) {
                watcher.actions.reauth(name, codex: true, mode: .capture)
            }
        case .rename:
            Button(String.localized("Rename…")) {
                ClauthPrompts.rename(name) { new in watcher.actions.rename(name, to: new) }
            }
        case .hide:
            Button(String.localized("Hide from rail")) {
                ClauthVisibility.setHidden(true, for: account, settings: watcher.settings)
            }
        }
    }
}

/// The two modal questions the menu asks. An accessory app has to activate
/// for a modal to come to the front.
@MainActor
enum ClauthPrompts {
    /// The live-session arm: "<current> has a live session — switching logs
    /// it out. Switch anyway?" — the CURRENT account's session is the asset.
    static func confirmSwitch(to name: String, from current: String?) -> Bool {
        let alert = NSAlert()
        alert.messageText = String.localized("Switch to \(name)?")
        alert.informativeText = current.map { String.localized("\($0) has a live session — switching logs it out. Switch anyway?") }
            ?? String.localized("The current account has a live session — switching logs it out. Switch anyway?")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String.localized("Switch"))
        alert.addButton(withTitle: String.localized("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Installs the confirm on the switch controller's arming leg.
    static func installArmAlert(on controller: ClauthSwitchController) {
        controller.onArm = { [weak controller] target, current in
            guard let controller else { return }
            if confirmSwitch(to: target, from: current) {
                controller.confirmArmedSwitch(target)
            } else {
                controller.cancel()
            }
        }
    }

    static func rename(_ name: String, commit: (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = String.localized("Rename \(name)")
        alert.informativeText = String.localized("The daemon renames the profile everywhere; a live session keeps its login.")
        let field = NSTextField(string: name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        field.placeholderString = String.localized("New name")
        alert.accessoryView = field
        alert.addButton(withTitle: String.localized("Rename"))
        alert.addButton(withTitle: String.localized("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        commit(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
