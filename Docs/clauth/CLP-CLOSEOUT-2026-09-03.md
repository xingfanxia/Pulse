# CLP-RUN closeout — 2026-09-03

Pulse fork `xingfanxia/Pulse`, `main` at the commits listed at the end (CLP-1 `b9b4801`, CLP-2 `d72c51c`, CLP-3 = this commit), on upstream `2ab2948`. Design: `PLAN.md` · contract: `GOAL-PROMPTS.md` · parity: `PARITY.md` · per-milestone evidence: `.agent/PROGRESS.md` and `evidence/clp{1,2,3}/`.

## What is running on this Mac now

- `/Applications/Pulse.app` (fork build 1.0.4, bundle id `io.github.qunqin24.Pulse`) is installed and running; `SUEnableAutomaticChecks = 0` so upstream's next release cannot replace it. Its login item is registered by upstream's own first-run logic (toggle in Pulse → Settings → General if unwanted).
- The rail shows one ring per clauth account, inactive accounts hidden by default (`clauth.hidesInactive`), Pulse's own Claude Code / Codex rings hidden while clauth reports (`clauth.hidesPrimaries`); both switches are in Settings → clauth.
- ccsbar is still running and untouched (CLP-4, human-gated).
- Nothing of clauth's was written, switched, renamed or deleted by this run: the snapshot oracle (profile set, both active slots, 14 profile dirs) matches the Task 0 baseline and `~/.clauth/daemon.log` carries no switch/rename/delete line stamped inside the run window; `~/.codex/config.toml` and `~/.claude/settings.json` keep their pre-run mtimes; both clauth LaunchAgents keep their pre-run pids.

## AX 首次手动动作清单 (in this order)

1. **Confirm auto-updates are off**: `defaults read io.github.qunqin24.Pulse SUEnableAutomaticChecks` → `0`. (Also visible in Settings → About.) If you ever turn it on, upstream's appcast will offer vanilla Pulse and overwrite the fork.
2. **One real switch to verify settle**: right-click an inactive claude ring → "Switch to <name>". If the current account has a live session you get the alert naming it; the ring shows a spinner while pending, the card reads "Switching to …" then "Switched to …" once `active_profile` flips in status.json (the same settle ladder as ccsbar). Rail order updates (active first).
3. **Flip proxy mode once**: Settings → clauth → Codex · accounts → Proxy mode. ON writes `model_provider = "clauth"` to `~/.codex/config.toml` (backup `config.toml.bak-pulse`) and bootstraps `com.clauth.proxy`; OFF removes the line and keeps the provider block. Caption shows `serving :4517` / `direct`.
4. **Look at a banked reset**: hover the ax-codex-xfx ring — the card carries "hit its weekly window — auto-switch rotates at the session boundary · resets in …" and "1 free reset banked" (redeem in the Codex app; clauth only reads the count).
5. 半托 spot-checks (拍的板 #16): right-click presentation with Liquid Glass on/off, card footer wording, the clauth pane at the 720pt window width, zh-Hans wording (Settings → General → Language).

## Every hook in an upstream-owned file

| File:line | Added line |
|---|---|
| `AppDelegate.swift:13` | `private lazy var clauth = ClauthWatcher(settings: settings, store: store)` |
| `AppDelegate.swift:53` | `clauth.start()` |
| `AppDelegate.swift:75` | `if ClauthPaths.opensSettingsAtLaunch { showSettings() }` |
| `AppSettings.swift:66` | `/// Accounts clauth manages, published by `Clauth/ClauthWatcher` (fork); never persisted here.` |
| `AppSettings.swift:67` | `var clauthAccounts: [AccountKey] = [] {` |
| `AppSettings.swift:68` | `didSet { guard clauthAccounts != oldValue else { return }; PanelMetrics.makeRoom(for: allAccounts.count); onChange?() }` |
| `AppSettings.swift:69` | `}` |
| `AppSettings.swift:70` | `` |
| `AppSettings.swift:77` | `} + clauthAccounts` |
| `AppSettings.swift:105` | `extraAccounts.first { $0.key == account }?.label ?? ClauthMapping.label(for: account) ?? account.provider.displayName` |
| `AppSettings.swift:617` | `var shownAccounts: [AccountKey] { ClauthVisibility.shown(orderedAccounts, settings: self) }` |
| `FloatingUsagePanelView.swift:192` | `headline: usage.headlineWindow(preferring: settings.pinnedWindow(for: account) ?? ClauthMapping.defaultPin(for: accou…` |
| `FloatingUsagePanelView.swift:202` | `? usage.headlineWindow(preferring: settings.pinnedWindow(for: account) ?? ClauthMapping.defaultPin(for: account, in: …` |
| `SettingsView.swift:55` | `row(.clauth)` |
| `SettingsView.swift:77` | `case .clauth: ClauthSettingsPane(settings: settings, store: store)` |
| `SettingsView.swift:121` | `case .general, .about, .clauth:` |
| `SettingsView.swift:357` | `subtitle: ClauthVisibility.isShown(account, settings: settings) ? nil : String.localized("Not shown"),` |
| `SettingsView.swift:550` | `@ViewBuilder` |
| `SettingsView.swift:552` | `if ClauthFetchGuard.isClauthSlot(account) { ClauthAccountPane(account: account, settings: settings, store: store) } e…` |
| `SettingsView.swift:553` | `accountPaneBody(account, account.provider) }` |
| `SettingsView.swift:739` | `guard case .account(let account) = pane, !ClauthFetchGuard.isClauthSlot(account) else { return }` |
| `SettingsView.swift:1407` | `case clauth` |
| `SettingsView.swift:1416` | `case .clauth: "clauth"` |
| `SettingsView.swift:1427` | `case .clauth: "arrow.triangle.2.circlepath"` |
| `UsageDetailCard.swift:125` | `ClauthCardFooter(account: usage.account)` |
| `UsageDetailCard.swift:126` | `` |
| `UsageDetailCard.swift:176` | `if let footnote = ClauthCardFooter.footnote(for: usage) { return footnote }` |
| `UsageDetailCard.swift:177` | `return switch usage.state {` |
| `UsageDockView.swift:430` | `.modifier(ClauthRingMenuModifier(account: usage.account))` |
| `UsageStore.swift:306` | `let extras = ClauthFetchGuard.extras(settings.shownAccounts)` |
| `UsageStore.swift:448` | `if ClauthFetchGuard.isClauthSlot(account) { return ClauthFetchGuard.refresh(account) }` |
| `UsageStore.swift:588` | `/// clauth's readings replace every clauth slot at once (fork — `Clauth/ClauthWatcher`).` |
| `UsageStore.swift:589` | `func applyClauth(_ readings: [String: ProviderUsage]) { usage = usage.filter { !ClauthFetchGuard.isClauthID($0.key) }…` |
| `UsageStore.swift:590` | `` |

34 added lines in upstream-owned Swift files (budget 56; `Scripts/clauth-hook-budget.sh` counts the same set).

## Rollback

```bash
# code — the whole integration is the clp( commits on top of upstream 2ab2948
cd ~/projects/devtools/Pulse && git log upstream/main..HEAD --oneline   # the range below
git revert --no-edit 8a003f39e71f71ea34885f03f66fec1861d0ab68^..HEAD   # or: git reset --hard upstream/main (throws the fork away)
# the installed app + its defaults
osascript -e 'quit app "Pulse"'; rm -rf /Applications/Pulse.app
defaults delete io.github.qunqin24.Pulse
rm -f ~/Library/LaunchAgents/com.pulse.launch-at-login.plist   # only a loose build ever writes this; none exists now
# the bare build's sandbox defaults
defaults delete Pulse
# ccsbar was never stopped; if it was: open -a ccsbar
```

## BLOCKED (full text)

# CLP blocked items

Undecidable mid-run → one entry here, then the work continues on the rest.
Format: date · item · what was tried (commands + output) · the exact decision AX must make.

## DECISIONS (full text)

# CLP decisions ledger

Assumed decisions at kickoff live in Docs/clauth/GOAL-PROMPTS.md § 拍的板.
Mid-run deviations from a suggestion (never from a 死规矩) go here, one line
each: date · what · why · cost to reverse.

## CLP-1 (2026-09-03)
- 2026-09-03 · Sandbox launch recipe carries four `defaults` keys beyond the plan's two · `AppSettings.restored()` ignores a stored `enabledProviders` on a first run (`hasRunBefore` false ⇒ "what is installed") and, once `hasRun` is set, re-enables every no-setup provider not yet in `offeredProviders`; `StatusLineHook.offerOnFirstRun()` would put up a modal offering to edit `~/.claude/settings.json`; `autoCollapse NO` keeps the rail expanded for `screencapture` (the installed app keeps upstream's default ON — the sliver-until-hovered behaviour AX asked about is upstream's own) · reverse: `defaults delete Pulse <key>`.
- 2026-09-03 · The sandbox runs a 1 s `touch` ticker (`<sandbox>/bin/ticker.sh`) standing in for the daemon's status.json rewrite cadence · without it the liveness ladder reads dead after 15 s and every ring goes stale, which is the correct verdict for a daemon that stopped; the stale reverse-verification stops the ticker deliberately · reverse: none (sandbox only).
- 2026-09-03 · The fixture's `7d fable` profile (`fx-main`) reports 5h = 7d = 12 % · the contract asserts "headline 12 %" for that profile while the default pin is the 5h window; with both unscoped windows at 12 the assertion holds under either pin, and `ClauthMapping.defaultPin(for:in:)` falls to the other unscoped window when the harness's is missing (a pin that matches nothing would hand the ring to Pulse's max rule — the maxed scoped window) · reverse: one fixture number.
- 2026-09-03 · CLP-1 ring-click refresh on a clauth account = re-read of the feed, no spinner · `UsageStore.isRefreshing`/`refreshingAccount` are private, so showing the spinner would cost hook lines for a read that finishes within a frame; CLP-2 routes the click to the daemon `refresh` verb · reverse: two hook lines.
- 2026-09-03 · Inactive accounts are hidden from the rail by default (AX, mid-run 2026-09-02: 「别忘了隐藏 inactive 账号」) · `ClauthVisibility.hidesInactive` (default true) over `ClauthMapping.isInactive` = ccsbar's rule (tier `canceled`/`cancelled`/`free`, or `auth_status == broken`); a harness's ACTIVE slot is never hidden whatever its plan; hidden rows stay in the roster and the Settings Order rows ("Not shown"); the CLP-3 pane gets the switch · reverse: flip the default, or narrow the predicate to one clause.
- 2026-09-03 · Positive network control is Cursor as the contract says, sampled with a continuous `lsof` loop rather than 3 one-second samples · the ephemeral `URLSession` closes the connection within a second, so second-granularity sampling missed it (0/15) on the first attempt.
- 2026-09-03 · The contract's `lsof -nP -i -a -p` network oracle is BLIND to Pulse's traffic in both directions — `nettop` is the binding oracle · the cursor positive control fetched (its reading landed in `last-readings.json` at 23:06:53) while 300 back-to-back `lsof` samples showed nothing: URLSession/Network.framework flows on this macOS are not BSD sockets, so `lsof -i` never lists them. `nettop -P -L 18 -d -x -J bytes_in,bytes_out` sees them (cursor run: 7096 B in / 3237 B out in its first second; sandbox run: the process never appears). Both are pasted; the closeout tells AX the lsof line is decorative · reverse: none — an oracle finding.

## CLP-2 (2026-09-03)
- 2026-09-03 · Right-click spike PASSED — a SwiftUI `.contextMenu` on `UsageDockItem` presents on the non-activating panel with Liquid Glass OFF and ON (`Docs/clauth/evidence/clp2/spike-contextmenu-glass-{off,on}.jpg`, right-click posted by a CGEvent at the first ring, menu items "Spike A / Spike B" rendered beside the ring both times) · the `FloatingPanel.sendEvent … .rightMouseDown` fallback line is NOT needed and NOT added; the ring menu is a `.modifier(ClauthRingMenuModifier(account:))` — one hook line replacing the spike line · reverse: the fallback design stays in PLAN.md § CLP-2 if a future macOS breaks this.
- 2026-09-03 · The sandbox home is reached through a short symlink (`/tmp/clp-sb → <scratchpad>/clp-sandbox`) for every run from CLP-2 on · `sockaddr_un.sun_path` holds 104 bytes and the scratchpad path is ~150, so the fake socket could never be connected to (the client refuses over-long paths rather than truncating, as ccsbar does); XCTest fake daemons bind under `/tmp/clp-<hex>/` for the same reason · reverse: none — a rail.
- 2026-09-03 · Sandbox smoke drives the arming alert with a MOUSE click, never a synthetic key · a CGEvent Return (`keyDown 36`) posted from the shell never reached the modal (keyboard events need the poster to be Accessibility-trusted; mouse events do not), so the first smoke sat on "Waiting for confirmation…" with an empty socket log until the Switch button was clicked by coordinate · reverse: none.
- 2026-09-03 · The arming alert names the CURRENT account, not the target · the first cut read "fx-cl has a live session" while it is fx-main's session the switch logs out; `onArm` now carries `(target, current)` and the alert says "<current> has a live session — switching logs it out" (evidence image predates the fix) · reverse: none.

## CLP-3 (2026-09-03)
- 2026-09-03 · Config sends are SERIALISED in `ClauthActions.send` (one task chain) · fired concurrently, eleven verbs arrived at the fake socket out of order and two were dropped past its listen backlog — a real chain edit ("move up, then set the threshold of the row that moved") must land in click order, and the daemon serves one line per connection · reverse: none.
- 2026-09-03 · `PULSE_OPEN_SETTINGS=1` opens the Settings window at launch — one hook line in `AppDelegate` · the bare build's menu bar item is pushed off this crowded, notched menu bar (macOS 26 hosts status items under Control Center, so nothing identifies it by owner either), so a script cannot reach "Settings…"; `NSApp.delegate` is SwiftUI's adaptor proxy, not `AppDelegate`, so Clauth/ could not do it without the line · reverse: delete the line (the env var is sandbox-only; the installed app never sees it).
- 2026-09-03 · Rolling-token "clear" is `clauth feed <p> off` (restores the static mint) · the deployed 0.13.1 fork CLI has no sidecar-clear verb; upstream's `static-token --clear` arrives with the #59 sync — PARITY.md carries the row · reverse: swap the argv in `ClauthCLI.feedArgs` when the fork syncs.
- 2026-09-03 · The installed app is pre-seeded with `statusLine.offered = YES` in its own defaults domain before first launch · `StatusLineHook.offerOnFirstRun()` would otherwise put up a modal offering to edit `~/.claude/settings.json`, which this run must never touch; the toggle stays available in Settings for AX · reverse: `defaults delete io.github.qunqin24.Pulse statusLine.offered`.
- 2026-09-03 · The installed app's read-only smoke ran once with `clauth.hidesInactive = NO` (7 rings, one per published profile) and once at the default (3 rings: the two active slots + the one other live-plan codex account) · the contract's "ring count == profiles count" predates AX's mid-run hide-inactive ask; both states are pasted and the key is deleted afterwards so the installed app keeps AX's default · reverse: `defaults write io.github.qunqin24.Pulse clauth.hidesInactive -bool NO`.
- 2026-09-03 · Observation, no action: the real daemon rewrites status.json every ~1 s (20/20 samples under 1 s), but one 29 s gap was seen at 06:53:11→06:53:40Z, during which every clauth ring read stale ("As of …") — the same verdict ccsbar's ladder gives; the rail recovers on the next write · reverse: none.
- 2026-09-03 · Observation, no action: macOS showed an "App Background Activity — clauth can run in the background" notice at 23:53 local while the installed Pulse registered its own login item; `launchctl list` shows both clauth agents with their pre-run pids (daemon 25848, proxy 25853), so nothing of clauth's was loaded or restarted by this run · reverse: none.

## PARITY — not done

Legend: ✅ landed · ➖ not done, reason stated.
| `inspect` (ccsbar's focused-row view state) | ➖ | Pulse has no inspected-row concept: each account has its own Settings pane (`ClauthAccountPane`) reachable from the sidebar | — |
| Snapshot-render guard (`snapshotRender`) | ➖ | ccsbar's README-render fixture path; Pulse has no snapshot renderer | — |
| Sidecar STATUS line (`SessionToken.state` reads `session-token.json`) | ➖ by design | Pulse never reads the sidecar (gate 5); the flag comes from status.json `rolling_token` / `session_feed` (`ClauthTokenRow.subtitle`, card "rolling token") — expiry countdowns need the sidecar and stay ccsbar's | — |
| Mis-fill detection (`.misfilled`) | ➖ by design | Same reason: it needs the sidecar's `refreshToken` presence. clauth's own `doctor` reports it | — |

## Honest skip log

- Nothing in the contract's hard floor was skipped. Two evidence items were produced through a different instrument than the contract named, each explained in DECISIONS: the network oracle (`lsof` is blind to Network.framework flows — `nettop` was used beside it), and the pane smoke (driven through the accessibility tree with a window-ID capture, because a terminal-launched accessory app cannot come to the front of this crowded screen).
- The mid-run ask 「隐藏 inactive 账号」 was implemented (CLP-1) and changed the installed rail's default ring count from 7 to 3; both states are pasted.
- Deferred to the fork's next sync with upstream clauth (#59 merged form): the rolling-token "clear" verb (`static-token --clear`), `codex_wrap_off` as a per-harness value.

## Closing evidence

```
06f9aa1 clp(3): test — wait for the feed spawn before the delete spawn; the two landed in either order under load
02e7594 clp(3): the control pane, ccsbar parity, installed — chain editor over the ten socket verbs, proxy mode, rolling token, add/rename/delete, clauth account pane, closeout
d72c51c clp(2): switch from the ring, the card knows the chain — context menu, settle ladder, one spawn door
b9b4801 clp(1): clauth accounts on the rail, read-only — one ring per profile from status.json, zero tokens
daca967 clp(0): Task 0 baseline re-run + understanding receipt
e32e8e2 clp(0): plan + contract after review round 2 — 18 upheld folded (visibility takes the unfiltered order + empty-roster guard, stale = ccsbar's predicate, verdict off the ring, default headline pin, arming leg gets an NSAlert, sandbox launch recipe kills the LaunchAgent side effect, auto-updates off after install, snapshot oracle instead of daemon.log); graders re-pinned at 56754d6; 150 turns
56754d6 clp(0): graders hardened after review round 2 — gate 2 reads swift test's exit status and any per-suite failure count (the per-suite 'Executed N, 0 failures' line let a red suite pass), gates 5/6 scan our code + every hook line with an anchored comment filter and a wider spawn pattern; Makefile 'make test' for the grind hook; Makefile/CLAUDE.md exempt from the budget
8d2a326 clp(0): CLAUDE.md pointer to the clauth integration docs; plan dates the roster fact
442dff1 clp(0): contract pins the graders at e8342d3
e8342d3 clp(0): verify script — an apostrophe inside ${VAR:?msg} broke bash's parse
ee4b674 clp(0): plan + contract revised after the adversarial pass — visibility owned by Clauth/, CLI containment via PULSE_CLAUTH_BIN, frozen graders at 2c00886, contract facts corrected (session_feed, one global wrap-off, 7 published profiles)
2c00886 clp(0): the frozen graders — clauth-verify.sh (7 gates) and clauth-hook-budget.sh (added lines in upstream-owned files ≤ budget)
8a003f3 clp(0): CLP plan, goal contract and ledgers — Pulse absorbs ccsbar over the clauth data plane
(this ledger commit follows as one more clp(3) docs commit)

git diff 56754d6 -- Scripts/clauth-verify.sh Scripts/clauth-hook-budget.sh Makefile →
(empty above = graders untouched)
```
