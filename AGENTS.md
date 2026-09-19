# Pulse — agent guide

## Project scale and verification

**Profile: personal quota-monitor app.** Swift macOS quota monitor. Inspect the affected native interaction or relevant provider/rule test. Keychain/session reads, notifications and updater changes need targeted checks. Preserve real-input requirements for hover/drag claims and the existing CI/release SDK; small edits need no broad platform campaign.

- The requested behavior/questions define completion. Reviews are read-only unless fixes are requested; report unrelated findings briefly without adding tasks or test backfill.
- Use the smallest existing check that proves the change. Add tests for a concrete regression or consequential boundary; do not impose blanket TDD, new coverage targets, full suites, plans or reviewers. Preserve configured CI and actual release gates; reuse still-valid results.
- Keep the existing structure. Internal contract errors should be clear; add retries, fallbacks or compatibility layers only for an observed external failure or supported contract. Keep secrets private and inspect security only at boundaries changed by this task.

AI entry for this repo. Human workflow, evidence rules, and the docs map live in [CONTRIBUTING.md](CONTRIBUTING.md) and [Docs/README.md](Docs/README.md). Update the **authoritative topic doc** when the patch changes its documented behavior; do not grow this file.

> **This fork (xingfanxia/Pulse) carries a clauth integration** — every clauth-managed account as a ring, plus clauth's control face. Design, rules and the frozen graders: `Docs/clauth/PLAN.md`; the running contract: `Docs/clauth/GOAL-PROMPTS.md`; ledgers under `.agent/`. Everything below is upstream's and stays theirs.

Pulse is a macOS menu-bar usage monitor. SwiftUI draws the panel; a transparent, non-activating AppKit `NSPanel` owns size, placement, and input. Sixteen providers, no Pulse backend, no Pulse account. Per-provider routes, auth, cookies, and extra logins: [Docs/providers/README.md](Docs/providers/README.md).

Sources sit in six directories under `Sources/Pulse`: **App** (lifecycle, settings store, updates), **Panel** (the window, its placement, and everything drawn in it), **Settings** (the settings window), **Usage** (store, cache, ledger, forecast, alerts), **Providers** (one service per product, plus their helpers), **Auth** (keys, logins, cookies). Swift has no directory namespace and SwiftPM recurses, so a file's directory is a claim about what it belongs to and nothing else — move a file when that claim stops being true.

## Commands

```bash
swift run Pulse
swift build
./Scripts/bundle.sh
./Scripts/dmg.sh
./Scripts/check-localization.sh
swift test
./build.noindex/Pulse.app/Contents/MacOS/Pulse --json
```

**`xcode-select` must point at Xcode, not CommandLineTools.** `#Preview` is expanded by an Xcode plugin; otherwise every build fails with `PreviewsMacros plugin not found`. Check with `xcode-select -p`. One-off: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`.

**Never strip `#Preview` blocks to make the build green.** That hides errors inside them and has already shipped a broken build. See [Docs/decisions/never-strip-previews.md](Docs/decisions/never-strip-previews.md).

A clean `swift build` is not the Xcode check. Actor-isolation mistakes can be warnings here and hard errors there (every `View` is `@MainActor`). Before claiming a change builds:

```bash
swift build -Xswiftc -swift-version -Xswiftc 6
```

Treat remaining warnings as failures. macOS 14+, Swift tools 6.0, no linter. **`swift test` exists** — rules, cache reconciliation and provider fixtures. Use the affected suite/filter for a rule change, adding a regression case when the changed behavior needs it; use the full suite for broad or release changes. [Docs/testing.md](Docs/testing.md). CI and release need the macOS 26 SDK (`glassEffect`).

## Do not violate

- **Panel frame while a card opens:** do not resize the window and do not put card + rail in a shared stack. Axis change (side ↔ top) *may* resize. [Docs/ui/panel-geometry.md](Docs/ui/panel-geometry.md)
- **Hover:** SwiftUI `.onHover` does not work on this accessory, non-key panel. Enter from tracking areas, leave from sampling the pointer — never exit events. Drag and ring clicks belong to `FloatingPanel.sendEvent`. `hitTest` / synthesised events are not proof of real input. [Docs/ui/input.md](Docs/ui/input.md)
- **Percentages:** Pulse does not invent usage percentages. If a provider reports none, say so. **Two** labelled exceptions, both marked as inferred on screen: the money estimate, and Command Code's monthly plan grant — where the remainder is reported and only the plan's size is not. A plan that table cannot size draws nothing, never a zero. [Docs/refresh-and-data.md](Docs/refresh-and-data.md), [Docs/providers/command-code.md](Docs/providers/command-code.md)
- **Localization:** only `String.localized(_:)` / `Text(localized:)`. No implicit `Text("…")`. No conditionals inside `localized:`. Interpolate `String`, not `Int` (`%lld` vs `%@`). Run `./Scripts/check-localization.sh`. [Docs/development.md](Docs/development.md)
- **Notifications say nothing Pulse did not witness.** `spent` only when the provider says so, a reset only on unambiguous evidence, an unavailable reading is not automatically a failure, and a **push** route going quiet (Claude Code's status line) is not one either. A limit already past the line when the setting goes on **is** announced, once — silence then a wall is the feature failing. All off by default, all silent. `UNUserNotificationCenter` **raises without an app bundle** — every entry point is fenced by `UsageAlerts.isSupported`, so test from `./Scripts/bundle.sh`, never `swift run`. [Docs/notifications.md](Docs/notifications.md)
- **Disabled providers are not fetched.** Shared `Unavailability` copy names no provider.
- **Layout constants are budgets** (`PanelMetrics` computed `var`, never `static let`). Anything new on the panel takes size from them.
- **Do not fetch or document provider auth here.** [Docs/providers/README.md](Docs/providers/README.md)

## Read by task

| Task | Read |
|---|---|
| Shell, settings, login, defaults | [Docs/architecture.md](Docs/architecture.md) |
| Panel size, dock, overlay, scale | [Docs/ui/panel-geometry.md](Docs/ui/panel-geometry.md) |
| Drag, hover, clicks, hit testing | [Docs/ui/input.md](Docs/ui/input.md) |
| Glass, rings, colour, activity mark | [Docs/ui/rings-and-surface.md](Docs/ui/rings-and-surface.md) |
| Settings window copy/layout | [Docs/ui/settings.md](Docs/ui/settings.md) |
| Refresh, cache, activity, ledger | [Docs/refresh-and-data.md](Docs/refresh-and-data.md) |
| Notifications, alert rules | [Docs/notifications.md](Docs/notifications.md) |
| What is tested, fixtures | [Docs/testing.md](Docs/testing.md) |
| `--json` output contract | [Docs/json-output.md](Docs/json-output.md) |
| Localization, resources, adding UI | [Docs/development.md](Docs/development.md) |
| Bundle, tag, Sparkle, DMG | [Docs/releasing.md](Docs/releasing.md) / [Docs/build-from-source.md](Docs/build-from-source.md) |
| Why / failure lessons | [Docs/decisions/README.md](Docs/decisions/README.md) |
| Provider routes / extra accounts | [Docs/providers/README.md](Docs/providers/README.md) |

## Current facts (verify in code if they matter)

Sixteen `Provider` cases. Extra accounts: Claude Code, Codex, Grok, Grok Bot (`supportsMultipleAccounts`). Adaptive refresh is a **one-shot** timer, **2–30 minutes** (`AdaptiveRefresh.floor` 120s / `ceiling` 1800s) — not a 60s loop. Liquid Glass drag: historical “material swallows input” diagnosis is **uncertain**; current approach is a hit-testable `PanelSurface` plus window `sendEvent`. Real-input verification is not claimed. Settings still say to drag by a ring while glass is on.
