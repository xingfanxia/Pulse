# CLP — Pulse × clauth: the rail absorbs ccsbar

Status: **CLP-0 planned 2026-09-02** · executes as one `/goal` (see
`GOAL-PROMPTS.md`) · milestones CLP-1 → CLP-3 in this run, CLP-4 human-gated.

## Objective

Pulse's floating rail becomes the one always-on surface for every account
clauth manages — **every claude profile and every codex profile, one ring
each** — and gains clauth's full control face (switch, chain, thresholds,
proxy mode, rolling token, add/rename/delete) so ccsbar can retire. Pulse
holds **zero tokens** for these accounts: clauth's daemon is the data plane
(`~/.clauth/status.json` + `~/.clauth/clauthd.sock`), Pulse renders and
sends commands.

Why this shape (decided 2026-09-02, AX): the menu-bar label ccsbar owns has
a 12-character budget — N accounts × 2 harnesses cannot fit, and every
rotation/abbreviation scheme is a compromise. A ring per account on a rail
is the correct display, and Pulse already built it (floating `NSPanel`,
edge docking, sliver fold, multi-display memory, ~2.5k LOC of edge cases).
Porting that into ccsbar would mean maintaining a fork of it by hand;
consuming it as a fork means upstream fixes arrive by merge.

## The one architectural rule — all logic in new files, hooks are one-liners

Upstream `qunqin24/Pulse` was born 2026-08-30 and has landed 100 commits in
four days; `SettingsView.swift` (1434 LOC) changed 35 times in that window,
`UsageStore.swift` 19, `AppSettings.swift` 18, `UsageDockView.swift` 14,
`UsageDetailCard.swift` 13 (measured `git log --since='60 days ago'`,
2026-09-02). Anything we write *inside* those files is a merge conflict
every week. Therefore:

- Every clauth file lives under `Sources/Pulse/Clauth/` (SwiftPM includes
  subdirectories of the target path). Upstream never touches that folder.
- Upstream-owned files receive **call-site hooks only**: an appended
  array, a `case`, a modifier, a guard — each ≤3 lines, each calling into
  `Clauth/`. The budget is enforced by `Scripts/clauth-hook-budget.sh`
  (fails when added lines in upstream-owned files exceed the budget).
- `main` tracks `upstream/main` by **true merge**, weekly or before each
  milestone; never rebased, never force-pushed (same contract as the clauth
  fork, `docs/fork-sync/SYNC.md` there). Our commits carry a `clauth:` or
  `clp(N):` prefix so `git log --grep` separates the two lines.
- No release tags on the fork (a tag drives upstream's Sparkle release
  workflow); the app is installed from a local `Scripts/bundle.sh` build.

## Grounded facts (2026-09-02)

- Pulse `main` = upstream `2ab2948` ("Offer 1.0.4 to Sparkle"), fork 0
  ahead / 0 behind. Builds clean: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -Xswiftc -swift-version -Xswiftc 6` → `Build complete!`, **0 warnings**. `Scripts/check-localization.sh` → "249 keys". No test target, no linter (`CLAUDE.md`).
- Local toolchain: `xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`, Swift 6.3.3. `#Preview` blocks require Xcode (CLAUDE.md) — never strip them.
- Pulse account identity: `AccountKey(provider, slot)` (`MonitoredAccount.swift`); the first account's id is the bare provider raw value, extras are `provider#slot`. `AppSettings.allAccounts` = primaries + `extraAccounts` (persisted `ExtraAccount` list in UserDefaults). `UsageStore.refresh()` fans out per provider; non-primary accounts go through `fetchAdded` with Pulse-held OAuth credentials (`AccountCredentialStore`).
- Pulse rail: `RailEntry{usage, headline, isRunning, isRefreshing, tint, elapsed, showsRemaining}` → `UsageDockItem` → `UsageRingView`. No `contextMenu` anywhere in the target today.
- Pulse settings: `SettingsPane {general, account(AccountKey), about}`; sidebar sections Panel / Accounts / Application.
- Pulse usage model: `ProviderUsage{account, windows:[UsageWindow], observedAt, state(live|stale|unavailable), plan, creditBalance}`; `UsageWindow{id, kind(fiveHour|weekly|spend|monthly|other), scope, usedFraction, windowSeconds, resetsAt, reportsLength, isExhausted}`.
- Localization: every user string goes through `String.localized(...)` with entries in `Sources/Pulse/Resources/{en,zh-Hans}.lproj/Localizable.strings`; `Scripts/check-localization.sh` fails on a missing key.
- clauth feed: `~/.clauth/status.json` schema 1 (contract: clauth repo `docs/ccsbar/DESIGN.md`). Per profile: `name, active, harness(claude|codex), provider(anthropic|openai|…), tier, account_email, has_live_session, auth_status, fetch_status, fetched_at, next_refresh_at, fallback{position,threshold,armed,last_resort,…}, windows[{label:"5h"|"7d"|"7d <model>", utilization_pct, resets_at}], third_party, rolling_token, codex_snapshot_at, codex_rate_limit_reached, codex_reset_credits`. Top level: `active_profile, active_codex_profile, fallback_chain, codex_fallback_chain, wrap_off, codex_wrap_off, weekly_switch_threshold, forecast, generated_at, refresh_interval_ms, last_switch, pending_switch, clauth_version`.
- clauth socket `~/.clauth/clauthd.sock`, newline-delimited JSON (`docs/ccsbar/DESIGN.md` § socket): `snapshot, switch, refresh, fallback_add/remove/move, set_threshold, set_last_resort, set_member_weekly, set_check_weekly, set_check_scoped, set_wrap_off, set_weekly_threshold, rename`. Not on the socket (ccsbar shells `clauth`): `login <name> [--codex] [--browser] [--new]`, `login <name> --setup-token --yes` (rolling token), `delete <name>`, `rolling-token <p> on|off`. Proxy mode = `~/.codex/config.toml` edit + `launchctl bootstrap` of the proxy LaunchAgent (`ccsbar/Sources/CCSBarKit/CodexProxyMode.swift`).
- Reference implementation to port (ours, `~/projects/devtools/ccsbar/Sources/CCSBarKit/`): `DaemonClient.swift` 667 LOC (socket + CLI fallback + reply classification), `SwitchMachine.swift` 130 + `StatusModelSwitch.swift` 150 (settle ladder: a switch is confirmed only when the harness's own active slot flips), `LivenessLadder.swift` 34 (fresh/aging/stalled/dead from `generated_at` age), `Exhaustion.swift` 55, `ChainEdit.swift` 245, `CodexProxyMode.swift` 159, `SessionToken.swift` 163, `MachineTokens.swift` 272, `StatusModelActions.swift` 525. Their tests under `Tests/CCSBarKitTests/` (230 XCTest) are the port's characterization suite.
- Real machine roster (read-only fact, never a test fixture): 14 profiles, 4 codex; `ax-codex-xfx` is weekly-spent with 1 banked reset as of 2026-09-02.

## Milestones

### CLP-1 — clauth accounts on the rail (read-only)

Deliverable: launch Pulse → one ring per clauth profile, both harnesses,
numbers identical to `status.json`, no network call from Pulse for them.

- `Clauth/ClauthStatus.swift` — `Codable` mirror of status.json (decodeIfPresent everywhere, schema ≠ 1 → unsupported). Port from ccsbar `DaemonStatus.swift`, drop ccsbar-only view helpers.
- `Clauth/ClauthWatcher.swift` — mtime-polled (2s, like ccsbar) reader of `${PULSE_CLAUTH_HOME:-~/.clauth}/status.json`; publishes roster + per-account `ProviderUsage`. `PULSE_CLAUTH_HOME` is the test/sandbox seam — the executor runs the app against a fixture dir, never against the live daemon for anything but read-only smoke.
- `Clauth/ClauthMapping.swift` — pure: profile → `AccountKey(provider, slot: "clauth:<name>")` (`.claudeCode` for harness claude, `.codex` for codex; third-party providers → `.claudeCode` with `plan` = provider name); windows → `UsageWindow` (`5h`→`.fiveHour`/18000s, `7d`→`.weekly`/604800s, `7d <model>`→`.weekly` scope=`<model>`; `isExhausted` = pct ≥ 100 ∨ codex verdict live); `state` = `.live` when `fetch_status == Fresh` and the daemon is fresh/aging on the liveness ladder, `.stale` otherwise (daemon dead ⇒ stale + card footnote, no new `Unavailability` case); `observedAt` = `fetched_at`; `plan` = tier; codex `creditBalance` = "N reset(s) banked" when `codex_reset_credits > 0`.
- Hooks: `AppSettings` gains a stored `clauthAccounts: [AccountKey]` (set by the watcher) appended in `allAccounts`, and `label(for:)` returns the profile name for a `clauth:` slot; `UsageStore.refresh()` excludes `clauth:` slots from `extras` and `refresh(_:)` routes a `clauth:` slot to the daemon `refresh` command; `UsageStore` gains `applyClauth(_ readings: [String: ProviderUsage])` (new method, called by the watcher). Detail-card title = profile name (already `settings.label(for:)`).
- Primary-ring dedupe: Pulse's own primary `.claudeCode`/`.codex` rings read the same logins clauth's active profiles hold. On the **first** detection of a clauth feed, hide those two primaries once (`clauthHidPrimariesOnce` flag) — the user can re-enable them in Settings; never touch `enabledAccounts` again after that.
- Order: active claude, its chain order, other claude; then active codex, its chain, other codex — applied as the default `orderedAccounts` seed for the `clauth:` group; the user's drag order wins afterwards.
- Tests (new `Tests/PulseTests`, `@testable import Pulse`): decode fixture (ccsbar's `Fixtures/status.json` copied, plus the 2026-09 codex-limited shape), every mapping rule above as a table test, roster diff (added / removed / renamed profile), liveness ladder port.

### CLP-2 — switch from the ring, the card knows the chain

Deliverable: right-click a clauth ring → "Switch to <name>" / "Refresh" /
"Re-authenticate…" / "Rename…" / "Remove from Pulse view"; the hover card
shows active-slot state, chain position, threshold, `rotates at the session
boundary`, `1 free reset banked`; a switch is reported settled only when
the harness's active slot flips in status.json (settle ladder), with the
in-flight state visible on the ring.

- `Clauth/ClauthDaemonClient.swift` — port of ccsbar `DaemonClient` (socket first, CLI fallback for switch, reply classification, `clauthBinary()` lookup). Test seam: injectable `send`.
- `Clauth/ClauthSwitchMachine.swift` — port of `SwitchMachine` + `StatusModelSwitch` (pending → confirmed/failed/timeout against the harness's own active slot).
- `Clauth/ClauthRingMenu.swift` — the `contextMenu` content view + a pure decision table (which verbs for which row: active row has no "Switch to"; auth-broken row leads with "Re-authenticate"; third-party rows have no reauth).
- `Clauth/ClauthCardFooter.swift` — the card's clauth block.
- Hooks: `UsageDockItem` gets `.modifier(ClauthRingMenuModifier(account:))` (1 line); `RailEntry` gains `caption: String?` rendered under the % for `clauth:` rings (1 field + 1 line) — a rail of six identical claude glyphs needs names; `UsageDetailCard` appends `ClauthCardFooter(account:)` after the windows (1 line); `RailEntry.isRefreshing` doubles as the switch-in-flight cue.
- Tests: decision table, settle ladder (port ccsbar's), reply classification.

### CLP-3 — the control pane, ccsbar parity

Deliverable: Settings → sidebar "clauth" pane with everything ccsbar's panel
does, and Pulse installed in `/Applications` from the fork build.

- `Clauth/ClauthSettingsPane.swift` (+ `ClauthChainEditor.swift`, `ClauthProxyRow.swift`, `ClauthTokenRow.swift`, `ClauthAddAccount.swift`): daemon liveness + version header; per harness: active account, chain rail with add/remove/move/threshold/last-resort/member-weekly/check-weekly/check-scoped, wrap-off toggle, weekly line; codex proxy-mode toggle (port `CodexProxyMode`); rolling-token install/replace/clear per claude profile (port `SessionToken` + `installSetupToken`); add account (capture / browser, claude / codex), rename, delete (with ccsbar's confirm shape); show/hide of Pulse's own primaries.
- Hooks: `SettingsPane` gains `case clauth` (+ title/symbol), the sidebar gets `row(.clauth)` under Accounts, the detail `switch` gets `case .clauth: ClauthSettingsPane(...)` — three one-line hunks.
- Parity checklist (`Docs/clauth/PARITY.md`, checked off with the commit that lands each): every ccsbar verb in `StatusModelActions.swift` + `CodexProxyRow` + `SessionToken` has a Pulse home, or a written reason it does not.
- `Scripts/bundle.sh` → `build.noindex/Pulse.app` → `/Applications/Pulse.app`; ccsbar keeps running (retirement is CLP-4).

### CLP-4 — retire ccsbar (human-gated, NOT in this goal)

After AX has lived on the Pulse rail: README pointer in ccsbar, login item
off, `/Applications/ccsbar.app` removed, ccsbar repo archived. Needs AX's
say-so — it deletes a working tool.

## Verification (the canonical command)

`Scripts/clauth-verify.sh` (new, ours) runs, in order, failing on the first
red: Swift 6 build with warnings-as-failure · `swift test` · `Scripts/check-localization.sh` · `Scripts/clauth-hook-budget.sh` (added lines in upstream-owned files ≤ budget: CLP-1 20, CLP-2 32, CLP-3 40; `Package.swift` test-target hunk excluded) · `git diff --quiet upstream/main -- Sources/Pulse/Resources/*.svg` (no asset edits).

## Safety rails (死规矩)

- Pulse reads `status.json`, `tokens.json`, `~/.codex/config.toml`, and the socket. It NEVER reads `~/.clauth/profiles/*/credentials.json`, `codex-auth.json`, `session-token*`, `~/.claude/.credentials.json`, the Keychain, or `~/.codex/auth.json` for a clauth account. A clauth account is never a Pulse `ExtraAccount` with copied tokens.
- During development the executor never sends `switch`, `rename`, `delete`, `fallback_*`, `set_*`, `login`, or `rolling-token` to the REAL daemon. All interactive verification runs against `PULSE_CLAUTH_HOME=<sandbox>` with a fixture `status.json` and a fake socket (`Tests/PulseTests/FakeClauthDaemon.swift`, a Unix socket that records commands and mutates the fixture). Read-only smoke against the real daemon is allowed: reading status.json, `{"cmd":"snapshot"}`.
- Live switches and browser OAuth on AX's real accounts are AX-manual (project rule) — the 收尾包 lists them as the first thing AX does after install.
- No edits to `.github/workflows/*`, `appcast.xml`, `Scripts/appcast.py`, `Scripts/dmg.sh`, `VERSION`, `CHANGELOG.md` (upstream release machinery); no tags.
