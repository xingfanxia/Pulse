# CLP goal prompts

Authoring convention: `~/.claude/rules/workflow.md` § /goal (full-run default, zero mid-run sign-offs, 开工前置清单 + 收尾包). The executor reads `Docs/clauth/PLAN.md` for the design and THIS file for the contract. Nothing here asks AX anything mid-run; undecidables go to `.agent/BLOCKED.md` and the work continues on the rest. Reviewed 2026-09-02 by two adversarial passes (129 + 114 agents; 42 + 37 findings; 25 + 18 upheld — all folded in below).

## CLP-RUN — one goal, CLP-1 → CLP-3 (kickoff 2026-09-02)

### 开工前置清单 (all done by the authoring session, 2026-09-02)

1. Fork at `~/projects/devtools/Pulse`, `upstream` remote = qunqin24/Pulse @ `2ab2948` → done.
2. Xcode selected (`xcode-select -p` = Xcode) → done.
3. **Graders written and frozen** at commit `56754d6`: `Scripts/clauth-verify.sh`, `Scripts/clauth-hook-budget.sh` → done. The executor never edits them.
4. clauth contract doc completed (`docs/ccsbar/DESIGN.md` § socket now lists all 14 verbs, clauth `fa29c21`) → done.
5. Root `Makefile` (`make test` → the verify script) so the autonomous-grind clear hook recognises the verify → done.
6. Nothing from AX: no credentials, no params. The real daemon is only ever read.

### 启动 (two lines, in this order)

```
/goal <the predicate below>
Skill(skill="autonomous-grind", args="start <the same predicate>")
```
Before the final verdict: run `make test` (the clear hook only releases after a recognised test command), then `Skill(skill="autonomous-grind", args="clear")`.

### /goal 谓词 (paste verbatim)

```
在 ~/projects/devtools/Pulse 仓完成 CLP-RUN：按 Docs/clauth/PLAN.md 顺序一次自治跑完 CLP-1 → CLP-2 → CLP-3，中途不向 AX 提问、不发消息给任何人；Docs/clauth/GOAL-PROMPTS.md 是唯一任务源，无法自决的事项写入 .agent/BLOCKED.md 后跳过继续。死规矩：(a) clauth 逻辑只写在 Sources/Pulse/Clauth/ 与 Tests/PulseTests/，上游文件只留 ≤3 行调用钩子，总量由 Scripts/clauth-hook-budget.sh 判定；(b) Scripts/clauth-verify.sh、Scripts/clauth-hook-budget.sh、Makefile 是冻结的评分器——每段收尾执行 git diff 56754d6 -- Scripts/clauth-verify.sh Scripts/clauth-hook-budget.sh Makefile 必须无输出，改动评分器即判失败；(c) 绝不读取任何 credentials/auth/session-token/Keychain 文件，绝不碰 ~/.claude/settings.json（不 connect status line），进程启动只允许在 Sources/Pulse/Clauth/ClauthCLI.swift 内（verify 第 5/6 关）；(d) 开发与验证期间对真实 daemon/系统只允许只读（读 ~/.clauth/status.json、{"cmd":"snapshot"}，冒烟时环点击触发的 refresh 允许），所有 switch/rename/delete/fallback_*/set_*/login/rolling-token/launchctl 一律在 PULSE_CLAUTH_HOME=<沙箱> PULSE_CLAUTH_BIN=<沙箱>/bin/clauth（记录 argv 的 shim，launchctl 也走它）PULSE_CODEX_HOME=<沙箱>/codex 下打到 fixture + 假 socket + shim；沙箱只用 swift build 的裸产物，首次裸启动前先 defaults write Pulse settings.launchAtLogin.decided -bool YES 与 defaults write Pulse settings.enabledProviders -array claudeCode codex 并贴 defaults read Pulse 输出，每次运行前后贴 test ! -e ~/Library/LaunchAgents/com.pulse.launch-at-login.plist && echo none；(e) 不改 .github/workflows、appcast.xml、VERSION、CHANGELOG.md、Scripts/{appcast.py,dmg.sh,bundle.sh}、Resources/*.svg，不打 tag，不 force-push。Task 0：重跑基线并贴输出——git rev-parse --short upstream/main 为 2ab2948；swift package clean 后 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -Xswiftc -swift-version -Xswiftc 6 输出 Build complete 且 grep -c warning: 为 0；Scripts/check-localization.sh 报 249 keys；记录真机基线快照：python3 -c 打印 ~/.clauth/status.json 的 sorted profile 名集合、active_profile、active_codex_profile，及 ls ~/.clauth/profiles | sort；不符即停并记 BLOCKED；然后把 ≤10 行理解回执（目标/顺序/最大风险）写进 .agent/PROGRESS.md。逐段验收（每段完成即更新 .agent/PROGRESS.md 并 git commit，命令与退出码逐条以透传输出形式贴入对话）：(1) CLP-1：CLP_HOOK_BUDGET=32 Scripts/clauth-verify.sh exit 0（swift test 必须显示 Executed N tests, with 0 failures 且 N ≥ 25，且无任何 with [1-9] failure 行）；XCTest 断言：对 7 账号 fixture 花名册（fx- 前缀，3 claude/4 codex，按 PLAN 指定的五种特殊形状）ClauthVisibility.shown 恰含 7 个 clauth id 各一次且不含两个 primary、空花名册时 primary 回归、交错 providerOrder 存活，ClauthFetchGuard 过滤后的 extras 为空，RateLimited 档与 2 小时旧档 state == .stale，7d fable 档 headline 为 12%，parked codex 100%+过期 resets_at 不判 exhausted；沙箱裸产物启动后 screencapture 截图显示恰 7 个环（fx- 名字在 hover 卡片标题里各出现一次，截 2 张卡片即可）；退出并重启一次，环数不变；网络断言：lsof -nP -i -a -p $(pgrep -x Pulse) 在 60 秒内采样 3 次均为空，再 defaults write Pulse settings.enabledProviders -array claudeCode codex cursor 重启后重采样出现连接（阳性对照），四次输出全贴，之后恢复两 provider 配置；stale 反向验证：改写 fixture 的 generated_at 为 2 小时前并 touch -t $(date -v-2H +%Y%m%d%H%M) 该文件，XCTest/日志断言该环 state == .stale 且卡片脚注以 As of 开头，恢复后回到 live；丢弃反向验证：把一个 window 的 label 改成 "3d"，断言该窗口被丢弃（卡片不出现该行、环不画 0%）；(2) CLP-2：CLP_HOOK_BUDGET=40 Scripts/clauth-verify.sh exit 0；第一步 15 分钟 spike：在沙箱裸产物上对一个环右键，Liquid Glass 关与开各截图一次，结果与截图路径记入 .agent/DECISIONS.md，菜单不弹出则按 PLAN 已定的 sendEvent .rightMouseDown 回退实现并把那一行计入预算；假 socket 记录到 {"cmd":"switch","profile":...} 并在 fixture 中翻转对应 harness 的 active 槽后 settle ladder 判定 confirmed；反向验证：只翻转错误 harness 的槽（claude 切换却只动 active_codex_profile）必须保持 NOT confirmed 直至 pending 超时，贴输出；arming 测试：当前账号 has_live_session=true 时进入 arming，无确认则 5 秒后 idle 且假 socket 无记录，确认后才发出 switch；ClauthCLI 沙箱拒绝测试：设置 PULSE_CLAUTH_HOME 而不设 PULSE_CLAUTH_BIN 时注入的 spawn 闭包永不被调用；右键决策表测试覆盖 active 行无 Switch、auth_status=broken 行首项为 Re-authenticate、第三方行无 reauth；卡片 codex verdict 行测试：bare reason + 40% 窗口 → "is rate-limited" 且环不红，bare reason + 100% 存活窗口 → 点名该窗口；(3) CLP-3：CLP_HOOK_BUDGET=56 Scripts/clauth-verify.sh exit 0；Docs/clauth/PARITY.md 里 ccsbar StatusModelActions.swift 的每个 func、CodexProxyRow 的开关、SessionToken 的装/换/清 逐项打勾并标注落地 commit 或写明不做的理由（允许"不做"，不允许空行）；链编辑十个命令（fallback_add/remove/move、set_threshold、set_last_resort、set_member_weekly 含 null 清除、set_check_weekly、set_check_scoped、set_wrap_off、set_weekly_threshold）每个至少一条 XCTest 断言发出的 JSON 与 clauth src/daemon/socket.rs 分发臂（doc：docs/ccsbar/DESIGN.md § socket）字面一致；shim 记录的 argv 对 login/delete/setup-token 与 ccsbar DaemonClient.loginArgs/deleteArgs/setupTokenArgs 一致；proxy 开关只改 $PULSE_CODEX_HOME/config.toml 并贴 diff，shim 记录到 launchctl 而真机 launchctl list | grep com.clauth.proxy 状态前后不变；clauth: slot 的账号面板不含 Sign out / Remove account / rename 字段（XCTest 或截图）；Scripts/bundle.sh 产出 build.noindex/Pulse.app，cp -R 到 /Applications/Pulse.app，open -a 后 ps 显示进程，随即 defaults write io.github.qunqin24.Pulse SUEnableAutomaticChecks -bool false 并 defaults read 贴出（否则上游下个版本会把 fork 冲掉）；对真实 daemon 只读冒烟：读 ~/.clauth/status.json 后 id 以 clauth: 开头的环数 == 该文件 profiles 数（当前 7），贴 clauth --version 与 generated_at；真机变更断言：重跑 Task 0 的快照命令，profile 名集合与 profiles 目录列表必须与基线逐字相同，active 槽若变化须能对应到 ~/.clauth/daemon.log 中一行 "clauth daemon: … switched to"（daemon 自己的自动切换），否则判失败；(4) 收尾包 Docs/clauth/CLP-CLOSEOUT-<date>.md：AX 首次手动动作清单（确认自动更新已关、真机上切一次号验证 settle、开一次 proxy 开关、看一次 banked reset），每个新增 hook 的文件:行号表，回滚命令（git revert 范围 + rm -rf /Applications/Pulse.app + rm -f ~/Library/LaunchAgents/com.pulse.launch-at-login.plist + open -a ccsbar），BLOCKED 与 DECISIONS 全文，PARITY 未完成项；收尾前贴出 git log upstream/main..HEAD --oneline 全部带 clp( 前缀，以及最后一次 git diff 56754d6 -- Scripts/clauth-verify.sh Scripts/clauth-hook-budget.sh Makefile 为空，然后 make test 一次（clear 钩子只认它）。跳过条款：仅适用于 (3) 的 PARITY 非核心子项与各段截图，须先贴连续两次失败的原始输出并记 DECISIONS，最终判定如实标注；(1)(2)(3) 的 verify、(1) 的重启与网络断言、(2) 的错误 harness 反向验证与沙箱拒绝、(3) 的安装+自动更新关闭+只读冒烟+真机变更断言为硬底，任一未达成必须逐字输出「CLP-RUN 未达成：<段>」，不得判成功。任何一段的验收连续 3 次失败即转下一段并记 BLOCKED；比基线更差（warning >0、localization 红、hook budget 超、评分器被改、真机快照变化无法解释）一律回滚到该段起点再报告。or stop after 150 turns
```

### 拍的板 (assumed decisions — each costs one line to overturn)

| # | Question | Default (assumed) | Cost if wrong |
|---|---|---|---|
| 1 | Where the fork lives | `~/projects/devtools/Pulse` (Law 0 + written bucket rule; `_forks/tokscale` precedent contradicts) | one `project-move` |
| 2 | Upstream tracking | `main` true-merges `upstream/main`; never rebase/force-push; commits `clp(N):` | none |
| 3 | Where our code lives | `Sources/Pulse/Clauth/` (SwiftPM recurses — verified) | a `git mv` |
| 4 | Account identity | `AccountKey(provider, slot: "clauth:<profile>")`, derived at runtime, never an `ExtraAccount` | one mapping file |
| 5 | Visibility | `ClauthVisibility` owns it (our UserDefaults keys); `shownAccounts` body becomes one call over the UNFILTERED order; `enabledAccounts` never touched; primaries hidden by a flag, re-enableable in the pane; empty roster ⇒ primaries return | flip the flag default |
| 6 | Daemon dead / stale | `.stale` whenever `fetch_status != Fresh` or `stale` or the ladder is dead (ccsbar's predicate); clauth footnote via a 2-line `footnote` hook (CLP-2); NO new `Unavailability` case | one enum hunk later |
| 7 | Names on the rail | none in CLP-1..3; shipped in CLP-5 the same day at AX's ask | done |
| 8 | Active-slot cue | active first in its harness group, card says "active"; CLP-5 adds the accent dot + semibold caption; still no ring-stroke change | done |
| 9 | Per-model weekly (`7d fable`) | `.weekly` with `scope`; never contributes to exhaustion; never the rail headline (default pin 5h/7d, user pin wins) | none |
| 10 | Codex verdict + banked resets | verdict is a CARD LINE with ccsbar's attribution, never a ring color; `creditBalance` = "1 reset banked" | relabel |
| 11 | Tests | `Tests/PulseTests` `@testable import Pulse` on the executable target — **verified working** 2026-09-02 | none |
| 12 | Verify command | `Scripts/clauth-verify.sh` (frozen) | none |
| 13 | Install | `/Applications/Pulse.app` from `Scripts/bundle.sh`; automatic updates switched OFF right after (the baked feed is upstream's); ccsbar left running; Pulse registers its own login item (upstream behavior) | AX toggles the login item |
| 14 | CLP-4 (retire ccsbar, rail captions) | NOT in this run — human-gated | none |
| 15 | Localization | every new string in both `.strings`; zh-Hans by the executor (wording = 半托) | wording edits |
| 16 | 半托 spot-checks | right-click presentation with glass on/off; card footer wording; pane layout at 340pt+; zh-Hans wording — AX eyeballs after install | polish commits |
| 17 | CLI containment | `PULSE_CLAUTH_BIN` shim + refusal when only `PULSE_CLAUTH_HOME` is set; `launchctl` through the same door | none — it is a rail |
| 18 | Codex home | `PULSE_CODEX_HOME` threads `config.toml` path; backup `config.toml.bak-pulse` | none |
| 19 | Wrap-off / weekly line / burn_aware / forecast | one chain-global section (the deployed daemon has no per-harness wrap-off) | split when the fork syncs #69 |
| 20 | Unknown window label | dropped, never drawn | a mapping row |
| 21 | Live-session confirm (arming leg) | `NSAlert` from the ring-menu action, 5s arm timeout as ccsbar | route to the pane instead |
| 22 | Real-machine mutation oracle | before/after snapshot of profile names + dirs + active slots (the daemon log is blind to rename/delete) | none — it is a rail |

### 保守默认 (mid-run rule)

Any two-way choice → the one that touches fewer upstream lines. Any unknown about Pulse internals → upstream's `CLAUDE.md` first (it documents the sharp edges: `#Preview` needs Xcode, `.accessory` activation, UserDefaults domain under a bundle, Spotlight and `build.noindex`, the non-activating panel's input rules). Any unknown about the clauth contract → clauth `src/daemon/socket.rs` for wire shape, `docs/ccsbar/DESIGN.md` for meaning; ccsbar's Swift is the reference implementation, its tests the oracle.
