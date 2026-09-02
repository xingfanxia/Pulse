# CLP goal prompts

Authoring convention: `~/.claude/rules/workflow.md` § /goal (full-run default,
zero mid-run sign-offs, 开工前置清单 + 收尾包). The executor reads
`Docs/clauth/PLAN.md` for the design and THIS file for the contract. Nothing
here asks AX anything mid-run; undecidables go to `.agent/BLOCKED.md` and the
work continues on the rest.

## CLP-RUN — one goal, CLP-1 → CLP-3 (kickoff 2026-09-02)

### 开工前置清单 (AX, before firing — all done 2026-09-02)

1. Fork cloned at `~/projects/devtools/Pulse` with `upstream` remote → done.
2. Xcode selected (`xcode-select -p` = Xcode) → done.
3. Nothing else: no credentials, no params. The real daemon is only ever read.

### /goal 谓词 (paste verbatim)

```
在 ~/projects/devtools/Pulse 仓完成 CLP-RUN：按 Docs/clauth/PLAN.md 顺序一次自治跑完 CLP-1 → CLP-2 → CLP-3，中途不向 AX 提问、不发消息给任何人；本文件 Docs/clauth/GOAL-PROMPTS.md 是唯一任务源，无法自决的事项写入 .agent/BLOCKED.md 后跳过继续。死规矩：clauth 逻辑只写在 Sources/Pulse/Clauth/ 与 Tests/PulseTests/，上游文件只留 ≤3 行调用钩子且总量受 Scripts/clauth-hook-budget.sh 预算约束；绝不读取任何 credentials/auth/session-token/Keychain 文件；开发与验证期间对真实 daemon 只允许只读（读 status.json、{"cmd":"snapshot"}），所有 switch/rename/delete/fallback_*/set_*/login/rolling-token 一律打到 PULSE_CLAUTH_HOME 沙箱里的 fixture + 假 socket；不改 .github/workflows、appcast.xml、VERSION、CHANGELOG.md、Scripts/{appcast.py,dmg.sh}，不打 tag，不 force-push。Task 0：先重跑基线并贴输出——DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -Xswiftc -swift-version -Xswiftc 6 必须 Build complete 且 warning 计数 0，Scripts/check-localization.sh 报 249 keys，git rev-parse upstream/main 为 2ab2948——不符即停并记 BLOCKED；然后把 ≤10 行理解回执（目标/顺序/最大风险）写进 .agent/PROGRESS.md。逐段验收（每段完成即更新 .agent/PROGRESS.md 并 git commit，命令与退出码逐条以透传输出形式贴入对话）：(1) CLP-1：Scripts/clauth-verify.sh exit 0（含 swift build 0 warning、swift test 全绿、localization 全绿、hook budget ≤20）；PULSE_CLAUTH_HOME 指向含 ccsbar Fixtures/status.json 副本的沙箱时启动 Pulse，截图（Scripts 内新增 clauth-snapshot 或 screencapture）显示 claude 与 codex 两个 harness 的全部 profile 各一环且百分比与 fixture 一致，Pulse 对这些账号 0 次网络请求（以 PULSE_LOG_REQUESTS=1 或等价日志断言）；把 fixture 的 generated_at 改成 2 小时前后，环的读数进入 stale 且卡片脚注写明 daemon 未运行；反向验证：故意把一个 window 的 label 改成未知值，断言该窗口被丢弃而非画成 0%，贴红/绿输出；(2) CLP-2：clauth-verify exit 0（hook budget ≤32）；假 socket 记录到 {"cmd":"switch","profile":...} 且在 fixture 中翻转对应 harness 的 active 槽后，settle ladder 判定 confirmed；翻转错误 harness 的槽（claude 切换却只动 active_codex_profile）必须判定 NOT confirmed 直至超时（反向验证贴输出）；右键菜单决策表测试覆盖：active 行无 Switch、auth_status=broken 行首项为 Re-authenticate、第三方行无 reauth；(3) CLP-3：clauth-verify exit 0（hook budget ≤40）；Docs/clauth/PARITY.md 里 ccsbar StatusModelActions.swift 的每个 func、CodexProxyRow 的开关、SessionToken 的装/换/清 三类动作逐项打勾并标注落地 commit 或写明不做的理由（允许"不做"，不允许空行）；假 socket + 沙箱 config.toml 下，链编辑（add/remove/move/set_threshold/set_last_resort/set_member_weekly/set_check_weekly/set_check_scoped/set_wrap_off/set_weekly_threshold）每个命令至少一条 XCTest 断言发出的 JSON 与 clauth docs/ccsbar/DESIGN.md § socket 的字面一致；proxy 开关只改沙箱 config.toml 并贴 diff；Scripts/bundle.sh 产出 build.noindex/Pulse.app，cp -R 到 /Applications/Pulse.app 并 open，ps 显示进程；对真实 daemon 只读冒烟：读 ~/.clauth/status.json 后 Pulse 环数 == 该文件 profiles 数，贴 clauth --version 与 generated_at；(4) 收尾包 Docs/clauth/HANDOFF-<date>.md：AX 首次手动动作清单（真机上切一次号验证 settle、开一次 proxy 开关、看一次 banked reset），每个新增 hook 的文件:行号表，回滚命令（git revert 范围 + rm -rf /Applications/Pulse.app + 重新 open ccsbar），BLOCKED 与 DECISIONS 全文，PARITY 未完成项；收尾前执行并贴输出：grep -rEn 'credentials\.json|codex-auth\.json|session-token|auth\.json' Sources/Pulse/Clauth 只允许出现在注释行（grep -v '^\s*//' 后为空），git log upstream/main..HEAD --oneline 全部带 clp/clauth 前缀。跳过条款：仅适用于 (3) 的 PARITY 非核心子项与 (4) 的截图，须先贴连续两次失败的原始输出并记 DECISIONS，最终判定如实标注；(1)(2) 与 (3) 的 verify/安装/只读冒烟为硬底，任一未达成必须逐字输出「CLP-RUN 未达成：<段>」，不得判成功。任何一段的验收连续 3 次失败即转下一段并记 BLOCKED；比基线更差（warning >0、localization 红、hook budget 超）一律回滚到该段起点再报告。or stop after 120 turns
```

### 拍的板 (assumed decisions — read these before firing, each costs one line to overturn)

| # | Question | Default (assumed) | Cost if wrong |
|---|---|---|---|
| 1 | Where does the fork live | `~/projects/devtools/Pulse` (Law 0 + written bucket rule; `_forks/tokscale` precedent contradicts) | one `project-move` |
| 2 | Upstream tracking | `main` true-merges `upstream/main`; never rebase/force-push; commits prefixed `clp(N):`/`clauth:` | none — reversible policy |
| 3 | Where our code lives | `Sources/Pulse/Clauth/` subfolder (upstream is flat; SwiftPM recurses) | a `git mv` |
| 4 | Account identity | `AccountKey(provider, slot: "clauth:<profile>")`, derived from status.json at runtime, never persisted as `ExtraAccount` | rewrite of one mapping file |
| 5 | Pulse's own Claude/Codex primary rings when clauth is present | hidden once on first detection, user-re-enableable; never auto-touched again | two duplicate rings until toggled |
| 6 | Daemon dead / stale | `.stale` + card footnote; NO new `Unavailability` case (keeps ProviderUsage.swift untouched) | one enum hunk later |
| 7 | Names on the rail | `RailEntry.caption` under the %, clauth rings only, 1 hook line | remove the line |
| 8 | Active-slot cue on the ring | active account first in its harness group + caption suffix "·" (dot); no ring-stroke change | a visual tweak in CLP-4 territory |
| 9 | Per-model weekly (`7d fable`) | mapped as `.weekly` with `scope` (Pulse already renders scoped rows) | none |
| 10 | Codex banked resets | `creditBalance` = "1 reset banked" (Pulse renders creditBalance in the card) | relabel |
| 11 | Tests | new `Tests/PulseTests` target (`@testable import Pulse`, executable-target testing), Package.swift hunk excluded from hook budget | if executable testing fails to link: split a `PulseClauth` library target — bigger Package.swift hunk, logged in DECISIONS |
| 12 | Verify command | `Scripts/clauth-verify.sh` (ours), not a Makefile | none |
| 13 | Install | `/Applications/Pulse.app` from `Scripts/bundle.sh`; ccsbar left running; Pulse registers its own login item (upstream behavior) | AX toggles login item |
| 14 | CLP-4 (retire ccsbar) | NOT in this run — human-gated | none |
| 15 | Localization | every new string in both `.strings`; zh-Hans by the executor (AX is bilingual; wording is a 半托 spot-check) | wording edits |
| 16 | 半托 spot-checks (not machine-checkable) | ring caption legibility at Small/Standard/Large; card footer wording; pane layout at 340pt+ — AX eyeballs after install | polish commits |

### 保守默认 (mid-run rule)

Any two-way choice → the one that touches fewer upstream lines. Any unknown
about Pulse internals → read upstream's `CLAUDE.md` first (it documents the
sharp edges: `#Preview` needs Xcode, `.accessory` activation, UserDefaults
domain under a bundle, Spotlight and `build.noindex`). Any unknown about the
clauth contract → clauth repo `docs/ccsbar/DESIGN.md` is the source of truth;
ccsbar's Swift is the reference implementation, its tests the oracle.
