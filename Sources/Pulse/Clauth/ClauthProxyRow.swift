import SwiftUI

/// The codex proxy-mode switch: the user's hand on `config.toml`, the
/// proxy's LaunchAgent bootstrapped through the spawn door on ON, and a
/// loopback probe for the caption. State is re-read from disk on appear —
/// config.toml has other writers.
struct ClauthProxyRow: View {
    let watcher: ClauthWatcher
    @State private var routed = false
    @State private var serving = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        SettingsRow(String.localized("Proxy mode"), subtitle: error ?? explainer) {
            HStack(spacing: 8) {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(routed && !serving ? Color.pulseWarning : .secondary)
                if busy {
                    ProgressView().controlSize(.small)
                }
                Toggle("", isOn: Binding(get: { routed }, set: { setRouting($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(busy)
            }
        }
        .task { await probe() }
    }

    private var explainer: String {
        routed
            ? String.localized("New codex sessions route through clauth’s proxy (:4517): switches apply to running sessions and a rate-limited request rotates and replays. Restart codex to adopt.")
            : String.localized("Codex talks to OpenAI directly; account switches need a codex restart. Turn on for in-session hot-swap via clauth’s local proxy (:4517).")
    }

    private var caption: String {
        if routed { return serving ? String.localized("serving :4517") : String.localized("proxy not running") }
        return serving ? String.localized("direct · proxy idle") : String.localized("direct")
    }

    private func probe() async {
        routed = ClauthProxyMode.routed()
        serving = await Task.detached { ClauthProxyMode.serving() }.value
    }

    private func setRouting(_ on: Bool) {
        busy = true
        Task {
            error = await watcher.actions.setProxyRouting(on)
            try? await Task.sleep(for: .milliseconds(600))
            await probe()
            busy = false
        }
    }
}

/// A claude profile's rolling-token row: the flag as status.json reports it
/// (never the sidecar file), the feed switch, and the mint install.
struct ClauthTokenRow: View {
    let profile: ClauthStatus.Profile
    let watcher: ClauthWatcher

    var body: some View {
        SettingsRow(String.localized("Rolling token"), subtitle: Self.subtitle(rolling: profile.rollingToken)) {
            HStack(spacing: 8) {
                Button(String.localized("Install token…")) { install() }
                    .disabled(watcher.actions.loginInFlight != nil)
                    .help(String.localized("Paste a claude setup-token mint; it goes down a pipe to clauth login --setup-token, never through the shell."))
                Toggle("", isOn: Binding(
                    get: { profile.rollingToken },
                    set: { watcher.actions.setFeed(profile.name, on: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .help(String.localized("On: the daemon re-stamps the token from the usage chain. Off: the static mint is restored."))
            }
        }
        .padding(.leading, 31)
    }

    nonisolated static func subtitle(rolling: Bool) -> String {
        rolling
            ? String.localized("Fed by the daemon from the usage chain — full-scope, re-stamped ahead of expiry.")
            : String.localized("Off — sessions run on the static mint, or the rotating pair when none is installed.")
    }

    private func install() {
        guard let pasted = ClauthPrompts.askText(
            title: String.localized("Install a long-lived token for \(profile.name)"),
            message: String.localized("Run claude setup-token in a terminal, finish its browser flow, then paste the minted token here. It replaces any existing one."),
            placeholder: "sk-ant-…",
            button: String.localized("Install"),
            secure: true
        ) else { return }
        watcher.actions.installSetupToken(profile.name, token: pasted)
    }
}
