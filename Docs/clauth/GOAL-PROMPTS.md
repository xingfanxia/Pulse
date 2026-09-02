# CLP goal prompts

Authoring convention: `~/.claude/rules/workflow.md` § /goal (full-run default, zero mid-run sign-offs, 开工前置清单 + 收尾包). The executor reads `Docs/clauth/PLAN.md` for the design and THIS file for the contract. Nothing here asks AX anything mid-run; undecidables go to `.agent/BLOCKED.md` and the work continues on the rest. Reviewed 2026-09-02 by a 129-agent adversarial pass (42 findings, 25 upheld — all folded in below).

## CLP-RUN — one goal, CLP-1 → CLP-3 (kickoff 2026-09-02)

### 开工前置清单 (all done by the authoring session, 2026-09-02)

1. Fork at `~/projects/devtools/Pulse`, `upstream` remote = qunqin24/Pulse @ `2ab2948` → done.
2. Xcode selected (`xcode-select -p` = Xcode) → done.
3. **Graders written and frozen** at commit `e8342d3`: `Scripts/clauth-verify.sh`, `Scripts/clauth-hook-budget.sh` → done. The executor never edits them.
4. clauth contract doc completed (`docs/ccsbar/DESIGN.md` § socket now lists all 14 verbs, clauth `fa29c21`) → done.
5. Nothing from AX: no credentials, no params. The real daemon is only ever read.

### 启动 (two lines, in this order)

```
/goal <the predicate below>
Skill(skill="autonomous-grind", args="start <the same predicate>")
```
Before the final verdict: `Skill(skill="autonomous-grind", args="clear")`.

### /goal 谓词 (paste verbatim)

```
在 ~/projects/devtools/Pulse 仓完成 CLP-RUN：按 Docs/clauth/PLAN.md 顺序一次自治跑完 CLP-1 → CLP-2 → CLP-3，中途不向 AX 提问、不发消息给任何人；Docs/clauth/GOAL-PROMPTS.md 是唯一任务源，无法自决的事项写入 .agent/BLOCKED.md 后跳过继续。死规矩：(a) clauth 逻辑只写在 Sources/Pulse/Clauth/ 与 Tests/PulseTests/，上游文件只留 ≤3 行调用钩子，总量由 Scripts/clauth-hook-budget.sh 判定；(b) Scripts/clauth-verify.sh 与 Scripts/clauth-hook-budget.sh 是冻结的评分器——每段收尾执行 git diff e8342d3 -- Scripts/clauth-verify.sh Scripts/clauth-hook-budget.sh 必须无输出，改动评分器即判失败；(c) 绝不读取任何 credentials/auth/session-token/Keychain 文件，进程启动只允许在 Sources/Pulse/Clauth/ClauthCLI.swift 内（verify 第 5/6 关）；(d) 开发与验证期间对真实 daemon/系统只允许只读（读 ~/.clauth/status.json、{"cmd":"snapshot"}），所有 switch/rename/delete/fallback_*/set_*/login/rolling-token/launchctl 一律在 PULSE_CLAUTH_HOME=<沙箱> PULSE_CLAUTH_BIN=<沙箱>/bin/clauth（记录 argv 的 shim）PULSE_CODEX_HOME=<沙箱>/codex 下打到 fixture + 假 socket + shim；沙箱运行只用 swift build 的裸产物，绝不用 /Applications/Pulse.app；(e) 不改 .github/workflows、appcast.xml、VERSION、CHANGELOG.md、Scripts/{appcast.py,dmg.sh,bundle.sh}、Resources/*.svg，不打 tag，不 force-push。Task 0：重跑基线并贴输出——git rev-parse --short upstream/main 为 2ab2948；swift package clean 后 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -Xswiftc -swift-version -Xswiftc 6 输出 Build complete 且 grep -c warning: 为 0；Scripts/check-localization.sh 报 249 keys；不符即停并记 BLOCKED；然后把 ≤10 行理解回执（目标/顺序/最大风险）写进 .agent/PROGRESS.md。逐段验收（每段完成即更新 .agent/PROGRESS.md 并 git commit，命令与退出码逐条以透传输出形式贴入对话）：(1) CLP-1：CLP_HOOK_BUDGET=28 Scripts/clauth-verify.sh exit 0（其中 swift test 必须显示 Executed N tests, with 0 failures 且 N ≥ 20）；XCTest 断言：对 7 账号 fixture 花名册 ClauthVisibility.shown 恰含 7 个 clauth id 各一次且不含两个 primary，ClauthFetchGuard 过滤后的 extras 为空；沙箱裸产物启动后 screencapture 截图显示以 fx- 开头的每个 fixture profile 各一环且百分比与 fixture 一致（fx- 前缀即证明读的是沙箱不是真机）；退出并重启一次，环数不变；网络断言：lsof -nP -i -a -p $(pgrep -x Pulse) 在 60 秒内采样 3 次均为空（仅 clauth 环可见时），再打开一个原生 provider 环重采样出现连接（阳性对照证明探针有效），四次输出全贴；stale 反向验证：改写 fixture 的 generated_at 为 2 小时前并 touch -t $(date -v-2H +%Y%m%d%H%M) 该文件，断言环读数进入 stale（卡片脚注 Reading may be out of date），恢复后回到 live；丢弃反向验证：把一个 window 的 label 改成 "3d"，断言该窗口被丢弃（卡片不出现该行、环不画 0%）；(2) CLP-2：CLP_HOOK_BUDGET=36 Scripts/clauth-verify.sh exit 0；第一步 15 分钟 spike：在沙箱裸产物上对一个环右键，Liquid Glass 关与开各截图一次，结果与截图路径记入 .agent/DECISIONS.md，菜单不弹出则按 PLAN 已定的 sendEvent .rightMouseDown 回退实现并把那一行计入预算；假 socket 记录到 {"cmd":"switch","profile":...} 并在 fixture 中翻转对应 harness 的 active 槽后 settle ladder 判定 confirmed；反向验证：只翻转错误 harness 的槽（claude 切换却只动 active_codex_profile）必须保持 NOT confirmed 直至超时，贴输出；ClauthCLI 沙箱拒绝测试：设置 PULSE_CLAUTH_HOME 而不设 PULSE_CLAUTH_BIN 时注入的 spawn 闭包永不被调用；右键决策表测试覆盖 active 行无 Switch、auth_status=broken 行首项为 Re-authenticate、第三方行无 reauth；(3) CLP-3：CLP_HOOK_BUDGET=52 Scripts/clauth-verify.sh exit 0；Docs/clauth/PARITY.md 里 ccsbar StatusModelActions.swift 的每个 func、CodexProxyRow 的开关、SessionToken 的装/换/清 逐项打勾并标注落地 commit 或写明不做的理由（允许"不做"，不允许空行）；链编辑十个命令（fallback_add/remove/move、set_threshold、set_last_resort、set_member_weekly 含 null 清除、set_check_weekly、set_check_scoped、set_wrap_off、set_weekly_threshold）每个至少一条 XCTest 断言发出的 JSON 与 clauth src/daemon/socket.rs 分发臂（doc：docs/ccsbar/DESIGN.md § socket）字面一致；shim 记录的 argv 对 login/delete/setup-token 与 ccsbar DaemonClient.loginArgs/deleteArgs/setupTokenArgs 一致；proxy 开关只改 $PULSE_CODEX_HOME/config.toml 并贴 diff，且 shim 记录到 launchctl 而真机 launchctl list | grep com.clauth.proxy 状态前后不变；clauth: slot 的账号面板不含 Sign out / Remove account / rename 字段（XCTest 或截图）；Scripts/bundle.sh 产出 build.noindex/Pulse.app，cp -R 到 /Applications/Pulse.app 并 open -a，ps 显示进程；对真实 daemon 只读冒烟：读 ~/.clauth/status.json 后 Pulse 环数 == 该文件 profiles 数（当前 7），贴 clauth --version 与 generated_at；grep -c "switch\|rename\|delete" 于运行窗口内的 ~/.clauth/daemon.log 行为 0；(4) 收尾包 Docs/clauth/CLP-CLOSEOUT-<date>.md：AX 首次手动动作清单（真机上切一次号验证 settle、开一次 proxy 开关、看一次 banked reset），每个新增 hook 的文件:行号表，回滚命令（git revert 范围 + rm -rf /Applications/Pulse.app + open -a ccsbar），BLOCKED 与 DECISIONS 全文，PARITY 未完成项；收尾前贴出 git log upstream/main..HEAD --oneline 全部带 clp( 前缀，以及最后一次 git diff e8342d3 -- Scripts/clauth-*.sh 为空。跳过条款：仅适用于 (3) 的 PARITY 非核心子项与各段截图，须先贴连续两次失败的原始输出并记 DECISIONS，最终判定如实标注；(1)(2)(3) 的 verify、(1) 的重启与网络断言、(2) 的错误 harness 反向验证与沙箱拒绝、(3) 的安装与只读冒烟为硬底，任一未达成必须逐字输出「CLP-RUN 未达成：<段>」，不得判成功。任何一段的验收连续 3 次失败即转下一段并记 BLOCKED；比基线更差（warning >0、localization 红、hook budget 超、评分器被改）一律回滚到该段起点再报告。or stop after 120 turns
```

### 拍的板 (assumed decisions — each costs one line to overturn)

| # | Question | Default (assumed) | Cost if wrong |
|---|---|---|---|
| 1 | Where the fork lives | `~/projects/devtools/Pulse` (Law 0 + written bucket rule; `_forks/tokscale` precedent contradicts) | one `project-move` |
| 2 | Upstream tracking | `main` true-merges `upstream/main`; never rebase/force-push; commits `clp(N):` | none |
| 3 | Where our code lives | `Sources/Pulse/Clauth/` (SwiftPM recurses — verified) | a `git mv` |
| 4 | Account identity | `AccountKey(provider, slot: "clauth:<profile>")`, derived at runtime, never an `ExtraAccount` | one mapping file |
| 5 | Visibility | `ClauthVisibility` owns it (our UserDefaults keys); `shownAccounts` body becomes one call; `enabledAccounts` never touched; primaries hidden by a flag, re-enableable in the pane | flip the flag default |
| 6 | Daemon dead / stale | `.stale` + clauth footnote via a 1-line `footnote` hook (CLP-2); NO new `Unavailability` case | one enum hunk later |
| 7 | Names on the rail | **none in this run** — name in the hover-card title, VoiceOver, per-account tint; captions = CLP-4 candidate (they touch `DockLayout` sizing) | a CLP-4 item |
| 8 | Active-slot cue | active account first in its harness group; card says "active"; no ring-stroke change | a CLP-4 tweak |
| 9 | Per-model weekly (`7d fable`) | `.weekly` with `scope`; never contributes to exhaustion | none |
| 10 | Codex banked resets | `creditBalance` = "1 reset banked" | relabel |
| 11 | Tests | `Tests/PulseTests` `@testable import Pulse` on the executable target — **verified working** 2026-09-02 | none |
| 12 | Verify command | `Scripts/clauth-verify.sh` (frozen) | none |
| 13 | Install | `/Applications/Pulse.app` from `Scripts/bundle.sh`; ccsbar left running; Pulse registers its own login item (upstream behavior) | AX toggles the login item |
| 14 | CLP-4 (retire ccsbar, rail captions) | NOT in this run — human-gated | none |
| 15 | Localization | every new string in both `.strings`; zh-Hans by the executor (wording = 半托) | wording edits |
| 16 | 半托 spot-checks | right-click presentation with glass on/off; card footer wording; pane layout at 340pt+; zh-Hans wording — AX eyeballs after install | polish commits |
| 17 | CLI containment | `PULSE_CLAUTH_BIN` shim + refusal when only `PULSE_CLAUTH_HOME` is set; `launchctl` through the same door | none — it is a rail |
| 18 | Codex home | `PULSE_CODEX_HOME` threads `config.toml` path; backup `config.toml.bak-pulse` | none |
| 19 | Wrap-off / weekly line / burn_aware / forecast | one chain-global section (the deployed daemon has no per-harness wrap-off) | split when the fork syncs #69 |
| 20 | Unknown window label | dropped, never drawn | a mapping row |

### 保守默认 (mid-run rule)

Any two-way choice → the one that touches fewer upstream lines. Any unknown about Pulse internals → upstream's `CLAUDE.md` first (it documents the sharp edges: `#Preview` needs Xcode, `.accessory` activation, UserDefaults domain under a bundle, Spotlight and `build.noindex`, the non-activating panel's input rules). Any unknown about the clauth contract → clauth `src/daemon/socket.rs` for wire shape, `docs/ccsbar/DESIGN.md` for meaning; ccsbar's Swift is the reference implementation, its tests the oracle.
