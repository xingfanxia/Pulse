#!/bin/bash
# The canonical verify for the clauth integration. Runs every gate in order
# and stops at the first red. CI-equivalent: the same command the goal
# contract's acceptance quotes.
#
#   CLP_HOOK_BUDGET=<n> Scripts/clauth-verify.sh
#
# Gates:
#   1. clean Swift 6 build, warnings are failures (a clean build, not an
#      incremental one — an incremental build reports warnings only for the
#      files it recompiled)
#   2. swift test
#   3. Scripts/check-localization.sh
#   4. Scripts/clauth-hook-budget.sh $CLP_HOOK_BUDGET
#   5. no credential-file names in clauth code outside comments
#   6. every process spawn in clauth code goes through ClauthCLI
#   7. no edits to upstream release machinery or brand assets
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
budget="${CLP_HOOK_BUDGET:?set CLP_HOOK_BUDGET=<n> (the milestone hook budget)}"

step() { printf '\n== %s ==\n' "$1"; }
fail() { echo "clauth-verify: FAIL — $1"; exit 1; }

step "1/7 clean Swift 6 build, warnings = failure"
swift package clean >/dev/null 2>&1 || true
build_log=$(mktemp)
swift build -Xswiftc -swift-version -Xswiftc 6 2>&1 | tee "$build_log" | grep -E "warning:|error:|Build complete" || true
grep -q "Build complete" "$build_log" || fail "build did not complete"
warnings=$(grep -c "warning:" "$build_log" || true)
echo "warnings: $warnings"
[ "$warnings" -eq 0 ] || fail "$warnings warning(s) — treat every warning as an error (upstream CLAUDE.md)"

step "2/7 swift test"
test_log=$(mktemp)
swift test 2>&1 | tee "$test_log" | grep -E "error:|Executed [0-9]+ tests|failed|passed after" | tail -6
rc=${PIPESTATUS[0]}
echo "swift test exit: $rc"
[ "$rc" -eq 0 ] || fail "swift test exited $rc"
# XCTest prints the Executed line PER SUITE, so a green suite line beside a red
# one is not a pass — any failure count anywhere is red.
if grep -qE "with [1-9][0-9]* (failure|failures|unexpected)" "$test_log"; then fail "a suite reported failures"; fi
grep -qE "Executed [1-9][0-9]* tests?, with 0 failures" "$test_log" || fail "no XCTest ran (the test target is not wired)"

step "3/7 localization"
./Scripts/check-localization.sh || fail "localization"

step "4/7 hook budget"
./Scripts/clauth-hook-budget.sh "$budget" || fail "hook budget"

# Gates 5 and 6 scan everything that is OURS: Sources/Pulse/Clauth, Tests,
# and the ADDED lines of every hook in an upstream-owned file (upstream's own
# code legitimately reads the CLIs' credentials for its primary accounts and
# spawns codex/app-server — that is theirs, not under these rails).
ours_added() {
  git diff upstream/main -- Sources/Pulse ':(exclude)Sources/Pulse/Clauth' | grep -E '^\+[^+]' | sed 's/^+/hook:+:/' || true
}
# A line is a comment when its CONTENT (after the file:line: prefix) starts
# with //, /* or *. Anchored to the prefix so a `://` inside a string never
# masquerades as a comment.
strip_comments() { grep -vE '^[^:]*:[0-9+]*:[[:space:]]*(//|/\*|\*)'; }

step "5/7 credential-file names in our code (comments allowed, code not)"
cred='credentials\.json|codex-auth\.json|session-token|auth\.json|Keychain|SecItem|\.claude/settings\.json'
hits=$( { grep -rEn "$cred" Sources/Pulse/Clauth Tests 2>/dev/null; ours_added | grep -E "$cred"; } | strip_comments || true)
if [ -n "$hits" ]; then echo "$hits"; fail "a credential file, the Keychain, or Claude's settings.json is named in our code"; fi
echo "none"

step "6/7 process spawns only inside ClauthCLI.swift"
spawn='Process\(|launchedProcess|NSTask|posix_spawn|NSWorkspace\.[a-zA-Z.]*(open|launch)'
spawns=$( { grep -rEn "$spawn" Sources/Pulse/Clauth Tests 2>/dev/null; ours_added | grep -E "$spawn"; } | strip_comments | grep -v '^Sources/Pulse/Clauth/ClauthCLI.swift:' || true)
if [ -n "$spawns" ]; then echo "$spawns"; fail "a process spawn outside ClauthCLI.swift — every spawn must pass the sandbox refusal"; fi
echo "none"

step "7/7 upstream release machinery and brand assets untouched"
if ! git diff --quiet upstream/main -- .github appcast.xml VERSION CHANGELOG.md Scripts/appcast.py Scripts/dmg.sh Scripts/bundle.sh 'Sources/Pulse/Resources/*.svg'; then
  git diff --stat upstream/main -- .github appcast.xml VERSION CHANGELOG.md Scripts/appcast.py Scripts/dmg.sh Scripts/bundle.sh 'Sources/Pulse/Resources/*.svg'
  fail "release machinery or brand assets edited"
fi
echo "untouched"

echo
echo "clauth-verify: OK (hook budget $budget)"
