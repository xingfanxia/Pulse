# ccsbar → Pulse parity (CLP-3)

Every `func` in ccsbar `Sources/CCSBarKit/StatusModelActions.swift`, the `CodexProxyRow` switch and `SessionToken`'s install / replace / clear, checked against the Pulse fork. "Landed" names the Pulse surface and the commit; "Not done" carries the reason. No empty rows.

Legend: ✅ landed · ➖ not done, reason stated.

## StatusModelActions.swift

| ccsbar func | Pulse | Where | Commit |
|---|---|---|---|
| `fallbackAdd(_:)` | ✅ | `ClauthActions.fallbackAdd` → socket `fallback_add`; pane "Add to chain" (`ClauthChainRow`) | clp(3) |
| `fallbackRemove(_:)` | ✅ | `ClauthActions.fallbackRemove` → `fallback_remove`; pane "Remove" with the armed-member confirm (`ClauthChainEdit.removalConsequence`) | clp(3) |
| `fallbackMove(_:up:)` | ✅ | `ClauthActions.fallbackMove` → `fallback_move dir up|down`; pane chevrons | clp(3) |
| `setThreshold(_:_:)` | ✅ | `ClauthActions.setThreshold` → `set_threshold`; pane threshold menu (presets 50/80/90/95/100 + Custom…, band 0…100) | clp(3) |
| `setLastResort(_:_:)` | ✅ | `ClauthActions.setLastResort` → `set_last_resort`; pane gates menu toggle | clp(3) |
| `setMemberWeekly(_:_:)` | ✅ | `ClauthActions.setMemberWeekly` → `set_member_weekly` (`nil` ⇒ JSON null clears); pane "week …" menu incl. "Follow chain default" | clp(3) |
| `setCheckWeekly(_:_:)` | ✅ | `ClauthActions.setCheckWeekly` → `set_check_weekly`; gates menu | clp(3) |
| `setCheckScoped(_:_:)` | ✅ | `ClauthActions.setCheckScoped` → `set_check_scoped`; gates menu | clp(3) |
| `setWrapOff(_:)` | ✅ | `ClauthActions.setWrapOff` → `set_wrap_off` (one global value on the deployed daemon); pane "When the chain is spent" (outcome language, never the flag name) | clp(3) |
| `setWeeklyThreshold(_:)` | ✅ | `ClauthActions.setWeeklyThreshold` → `set_weekly_threshold`; pane "Weekly line" (presets 90/95/98/100 + Custom…, band 50…100) | clp(3) |
| `beginThresholdEdit` / `commitThresholdEdit` / `cancelThresholdEdit` | ✅ (as one step) | The inline edit banner is replaced by `ClauthPrompts.askText` "Custom…" dialogs on the threshold / weekly menus — Pulse's Settings has no inline banner idiom | clp(3) |
| `refresh()` | ✅ | `ClauthActions.refresh(nil)` → `refresh` (all profiles); reached after every login/delete | clp(2) |
| `refresh(_:)` | ✅ | `ClauthActions.refresh(name)` → `refresh profile`; ring click and ring-menu "Refresh" (`ClauthFetchGuard.refresh`) | clp(2) |
| `reauth(_:codex:mode:run:)` | ✅ | `ClauthActions.reauth` → `clauth login <name> [--codex [--browser]]` through `ClauthCLI`; ring menu + pane "Re-authenticate… / Capture current Codex login" | clp(2) |
| `beginAddAccount` / `cancelAddAccount` | ✅ (as a row) | `ClauthAddAccountRow` per harness — name field + Sign in… (+ Capture for codex); no open/close state needed | clp(3) |
| `addAccount(_:codex:mode:run:)` | ✅ | `ClauthActions.addAccount` → `clauth login --new <name> [--codex [--browser]]`; `ClauthNameValidation` mirrors clauth's `validate_profile_name` incl. reserved names + case-insensitive collision | clp(3) |
| `loginFailureMessage` | ✅ | `ClauthActions.loginFailureMessage` (the CLI's own stderr words; refusals name the sandbox) | clp(2) |
| `beginSetupToken` / `cancelSetupToken` | ✅ (as a dialog) | `ClauthTokenRow` "Install token…" → a secure `ClauthPrompts.askText` | clp(3) |
| `installSetupToken(_:token:run:)` | ✅ | `ClauthActions.installSetupToken` → `clauth login <name> --setup-token --yes`, mint on stdin only (`ClauthSetupToken` pre-validates) | clp(3) |
| `requestRemove` / `pendingRemovalPrompt` / `confirmRemoval` / `cancelRemoval` | ✅ | `ClauthChainRow.remove()` → `ClauthPrompts.confirm` with `RemovalConsequence.prompt` | clp(3) |
| `requestDelete` / `pendingDeletePrompt` / `deletePrompt` / `confirmDelete` / `cancelDelete` | ✅ | `ClauthAccountRow.delete()` → `ClauthPrompts.confirm` (`ClauthChainEdit.deletePrompt` names active + chain consequences) → `ClauthActions.delete` → `clauth delete <name> --yes` (never `--force`); one delete at a time, never while a login is in flight, refuses a vanished name | clp(3) |
| `beginRename` / `cancelRename` / `commitRename` / `renameValidationError` | ✅ | `ClauthPrompts.rename` → `ClauthActions.rename` → socket `rename`; local validation refuses empty / unchanged / spaces / slashes / collisions without a round trip | clp(2) |
| `run(_:shimmer:expecting:)` / `handle` / `settle` | ✅ | `ClauthActions.send(_:expecting:)` — serialised, off-main, loud errors, settle ladder until `generated_at` advances and the predicate holds; `configInFlight` for a shimmer | clp(3) |
| `inspect` (ccsbar's focused-row view state) | ➖ | Pulse has no inspected-row concept: each account has its own Settings pane (`ClauthAccountPane`) reachable from the sidebar | — |

## CodexProxyRow

| ccsbar | Pulse | Where | Commit |
|---|---|---|---|
| Proxy mode switch (routed ⇄ direct) | ✅ | `ClauthProxyRow` → `ClauthActions.setProxyRouting` → `ClauthProxyMode.apply` edits `${PULSE_CODEX_HOME:-~/.codex}/config.toml` (backup `config.toml.bak-pulse`); ON bootstraps `com.clauth.proxy` via `ClauthCLI` (`/bin/launchctl bootstrap gui/<uid> <plist>`), never unloaded on OFF | clp(3) |
| `serving :4517` / `proxy not running` / `direct · proxy idle` / `direct` caption | ✅ | `ClauthProxyRow.caption` over `ClauthProxyMode.serving()` loopback probe | clp(3) |
| Hover explainer | ✅ (as the row subtitle) | `ClauthProxyRow.explainer` | clp(3) |
| Snapshot-render guard (`snapshotRender`) | ➖ | ccsbar's README-render fixture path; Pulse has no snapshot renderer | — |

## SessionToken (install / replace / clear)

| ccsbar | Pulse | Where | Commit |
|---|---|---|---|
| Install a `claude setup-token` mint | ✅ | `ClauthTokenRow` "Install token…" → `installSetupToken` (`--setup-token --yes`, stdin) | clp(3) |
| Replace an existing mint | ✅ | Same door — `--yes` replaces unprompted (the CLI's own semantics) | clp(3) |
| Clear | ✅ (feed off) | `ClauthTokenRow` toggle → `clauth feed <name> off` restores the static mint; a full sidecar clear is upstream clauth's `static-token --clear`, which the deployed 0.13.1 fork CLI does not carry — flip to that verb when the fork syncs #59's merged form | clp(3) |
| Sidecar STATUS line (`SessionToken.state` reads `session-token.json`) | ➖ by design | Pulse never reads the sidecar (gate 5); the flag comes from status.json `rolling_token` / `session_feed` (`ClauthTokenRow.subtitle`, card "rolling token") — expiry countdowns need the sidecar and stay ccsbar's | — |
| Mis-fill detection (`.misfilled`) | ➖ by design | Same reason: it needs the sidecar's `refreshToken` presence. clauth's own `doctor` reports it | — |

## Not in ccsbar's action set, present here

- Hide from rail / hide inactive / hide primaries (`ClauthVisibility`) — Pulse's own rail concept.
- Per-account ring window pin, ring colour (`ClauthAccountPane`) — Pulse's own per-account rows, kept for clauth slots.
