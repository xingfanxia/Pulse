# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **This fork (xingfanxia/Pulse) carries a clauth integration** — every clauth-managed account as a ring, plus clauth's control face. Design, rules and the frozen graders: `Docs/clauth/PLAN.md`; the running contract: `Docs/clauth/GOAL-PROMPTS.md`; ledgers under `.agent/`. Everything below is upstream's and stays theirs.

## What this is

Pulse is a macOS menu-bar app: a floating AI usage monitor. SwiftUI renders the UI; a transparent, non-activating AppKit `NSPanel` anchors it to a side of the screen. It tracks three coding agents — Claude Code, Codex and Antigravity — reading each one's real limits by whatever route that agent offers. There is no backend and no account of its own.

## Commands

```bash
swift run Pulse         # build and run
swift build             # type-check everything, previews included
./Scripts/bundle.sh     # assemble build.noindex/Pulse.app (add --zip for a release)
./Scripts/dmg.sh        # the same, wrapped in build.noindex/Pulse-<version>.dmg
./Scripts/check-localization.sh   # the .strings files agree, and every key the source asks for exists
```

**`xcode-select` must point at Xcode, not CommandLineTools.** The `#Preview`
macro is expanded by a plugin that ships with Xcode; without it every build
fails with `PreviewsMacros plugin not found`. Check with `xcode-select -p`, and
fix a wrong one with:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

(`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` works
as a one-off if you can't change the system setting.) Do **not** "fix" this by
stripping the `#Preview` blocks before building: that produces a clean build
while leaving errors inside those blocks completely unreported, which has
already shipped a broken build to the user once.

**A clean `swift build` is not the same check Xcode runs.** Actor-isolation
mistakes can come out as warnings here and as hard errors in Xcode, where they
fail the whole module and every other file then reports "cannot find type X in
scope" — a wall of noise pointing anywhere but the cause. That has happened
once already, from a nonisolated helper reaching for a constant on a SwiftUI
`View` (every `View` is `@MainActor`). Before saying a change builds:

```bash
swift build -Xswiftc -swift-version -Xswiftc 6
```

and treat any remaining warning as a failure.

The package requires macOS 14+ and Swift tools 6.0 (see [Package.swift](Package.swift)). It can also be opened directly in Xcode via `Package.swift`. There is no test target and no linter configured.


## Detailed references

Read only the reference matching the work:

- Release, packaging, signing, Sparkle, or distribution:
  [`Docs/agent/shipping.md`](Docs/agent/shipping.md). Tagging, publishing, and
  release pushes require explicit authorization.
- Panel, SwiftUI/AppKit, geometry, input, or display behavior:
  [`Docs/agent/ui-architecture.md`](Docs/agent/ui-architecture.md).
- Settings, persistence, refresh scheduling, providers, or usage parsing:
  [`Docs/agent/state-and-provider-architecture.md`](Docs/agent/state-and-provider-architecture.md).
- Spending estimates, multiple accounts, localization, or resources:
  [`Docs/agent/accounts-localization-resources.md`](Docs/agent/accounts-localization-resources.md).

The clauth fork contract remains authoritative at `Docs/clauth/PLAN.md` and
`Docs/clauth/GOAL-PROMPTS.md`; do not treat these extracted upstream notes as
permission to change that integration.
