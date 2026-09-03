# CLP progress ledger

Contract: Docs/clauth/GOAL-PROMPTS.md · design: Docs/clauth/PLAN.md

## CLP-0 — planned 2026-09-02
- Fork cloned at ~/projects/devtools/Pulse, upstream remote added (2ab2948).
- Baseline (2026-09-02): Swift 6 build clean, 0 warnings; localization 249 keys; no test target.
- Next: Task 0 (re-run baseline, understanding receipt), then CLP-1.

## Task 0 — baseline re-run 2026-09-03T05:40Z (HEAD e32e8e2)
- `git rev-parse --short upstream/main` = 2ab2948 ✓
- `swift package clean` + Swift 6 build: `Build complete! (6.88s)`, `grep -c warning:` = 0 ✓
- `Scripts/check-localization.sh`: 249 keys ✓
- Real-machine baseline snapshot (read-only): profiles = [ax-backup, ax-cl, ax-code-bk, ax-codex-cl, ax-codex-dev0, ax-codex-xfx, ax-main] (7); active_profile = ax-main; active_codex_profile = ax-codex-dev0; `ls ~/.clauth/profiles | sort` = ax ax-backup ax-cl ax-code-bk ax-codex-cl ax-codex-dev0 ax-codex-xfx ax-main cl-ax p xfx xfx-backup xfx-cl xfx2 (14); clauth 0.13.1; com.clauth.proxy loaded.
- `~/Library/LaunchAgents/com.pulse.launch-at-login.plist`: none ✓

### 理解回执
- 目标：Pulse 的悬浮 rail 成为每个 clauth 账号一环的常驻面，并吸收 ccsbar 的全部控制面；Pulse 零 token，只读 status.json + socket。
- 顺序：CLP-1 只读环（ClauthStatus/Watcher/Mapping/Visibility/FetchGuard + 7 账号 fx- fixture + 沙箱裸启动 + 网络/重启/stale/丢弃反向验证）→ CLP-2 右键菜单 spike + ClauthCLI 唯一 spawn 门 + DaemonClient + settle ladder 三腿 + 卡片脚注 → CLP-3 设置面板 + 链编辑十命令 + proxy/rolling-token + PARITY.md + 安装 + 自动更新关 + 只读冒烟 + 真机快照断言 → 收尾包 CLP-CLOSEOUT。
- 最大风险：(1) 对真实 daemon 误发写命令 —— 所有 spawn 经 ClauthCLI，沙箱下无 PULSE_CLAUTH_BIN 即拒绝，dev 全程 PULSE_CLAUTH_HOME 指向 fixture；(2) 逻辑漏进上游文件超 hook 预算 —— 一切在 Sources/Pulse/Clauth/；(3) 裸启动写 LaunchAgent —— 先 `defaults write Pulse settings.launchAtLogin.decided -bool YES`；(4) `enabledAccounts`/`restored()` 把 clauth id 剪掉 —— ClauthVisibility 接管 `shownAccounts`，绝不碰 enabledAccounts；(5) 评分器冻结在 56754d6，任何改动即失败。

## CLP-1 — clauth accounts on the rail (read-only) — DONE 2026-09-03
Files: `Sources/Pulse/Clauth/{ClauthStatus,ClauthMapping,ClauthLiveness,ClauthVisibility,ClauthFetchGuard,ClauthWatcher}.swift`, `Tests/PulseTests/*` (72 XCTest), `Tests/PulseTests/Fixtures/status.json` (7 `fx-` profiles, 3 claude / 4 codex), hooks: AppDelegate 2 · AppSettings 8 · FloatingUsagePanelView 2 · SettingsView 1 · UsageStore 5 = **18 / 32**.
Evidence (transcript; images `Docs/clauth/evidence/clp1/`):
- `CLP_HOOK_BUDGET=32 Scripts/clauth-verify.sh` → exit 0 — build 0 warnings · `Executed 72 tests, with 0 failures` · localization 251 keys · hook budget 18/32 · gates 5/6 `none` · gate 7 `untouched`.
- Sandbox bare launch (`PULSE_CLAUTH_HOME=<scratch>/clp-sandbox`, recipe + ticker in DECISIONS): exactly 7 rings (12 / 100 / 5 / 33 / 100 / 15 / 100) in roster order; hover cards titled `fx-main Usage` and `fx-codex-xfx Usage`; quit + relaunch → the same 7; `~/Library/LaunchAgents/com.pulse.launch-at-login.plist` absent before and after every run.
- Network: `lsof -nP -i -a -p <pid>` ×3 within 60 s all empty (22:58:08 / :28 / :48); cursor positive control: lsof 0/300 yet the fetch completed → `lsof` is blind to Network.framework flows (DECISIONS). `nettop` oracle: sandbox run — process never appears (0 samples with bytes); cursor run — 7096 B in / 3237 B out in the first second. Two-provider config restored and read back.
- Stale 反向: `generated_at` −2 h + `touch -t` −2 h → card footnote "As of 1 hour ago"; fixture restored + ticker → footnote gone. XCTest `testTwoHourOldFileReadsStaleThenRecovers`, `testStaleGeneratedAtWithFreshMtimeIsStillLive`.
- Drop 反向: fx-main `5h` → `3d` → card shows only the two Weekly rows, ring reads 12 % (7d, never the scoped fable window). XCTest `testFixtureWindowRelabelledThreeDaysDisappearsFromTheReading`, `testDefaultPinForAReadingFallsToTheOtherUnscopedWindowNeverAScopedOne`.
- Inactive accounts hidden by default (AX mid-run): fx-code-bk tier → `free` → 6 rings; restored → 7. XCTest `testInactiveIsCancelledOrFreePlanOrBrokenLogin`, `testInactiveSetNeverHoldsTheActiveSlot`, `testInactiveAccountsAreHiddenByDefaultAndShownWhenTheFlagIsOff`, `testInactiveProfilesLeaveTheRailWithoutLeavingTheRoster`.
- Graders: `git diff 56754d6 -- Scripts/clauth-verify.sh Scripts/clauth-hook-budget.sh Makefile` → empty.
Next: CLP-2 — step 1 the right-click spike (`.contextMenu` on a ring, glass off / on, screenshots → DECISIONS), then `ClauthCLI` / `ClauthDaemonClient` / `ClauthSwitchMachine` / `ClauthRingMenu` / `ClauthCardFooter`.
