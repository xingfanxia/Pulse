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
grep -qE "Executed [0-9]+ tests, with 0 failures" "$test_log" || fail "tests red or no XCTest ran"
if grep -qE "Executed 0 tests" "$test_log"; then fail "0 tests executed — the test target is not wired"; fi

step "3/7 localization"
./Scripts/check-localization.sh || fail "localization"

step "4/7 hook budget"
./Scripts/clauth-hook-budget.sh "$budget" || fail "hook budget"

step "5/7 credential-file names in clauth code (comments allowed, code not)"
hits=$(grep -rEn 'credentials\.json|codex-auth\.json|session-token|auth\.json|Keychain|SecItem' Sources/Pulse/Clauth 2>/dev/null | grep -vE ':[[:space:]]*(//|/\*|\*)' || true)
if [ -n "$hits" ]; then echo "$hits"; fail "a credential file or the Keychain is named in code"; fi
echo "none"

step "6/7 process spawns only inside ClauthCLI.swift"
spawns=$(grep -rln 'Process()' Sources/Pulse/Clauth 2>/dev/null | grep -v 'Sources/Pulse/Clauth/ClauthCLI.swift' || true)
if [ -n "$spawns" ]; then echo "$spawns"; fail "Process() outside ClauthCLI.swift — every spawn must pass the sandbox refusal"; fi
echo "none"

step "7/7 upstream release machinery and brand assets untouched"
if ! git diff --quiet upstream/main -- .github appcast.xml VERSION CHANGELOG.md Scripts/appcast.py Scripts/dmg.sh Scripts/bundle.sh 'Sources/Pulse/Resources/*.svg'; then
  git diff --stat upstream/main -- .github appcast.xml VERSION CHANGELOG.md Scripts/appcast.py Scripts/dmg.sh Scripts/bundle.sh 'Sources/Pulse/Resources/*.svg'
  fail "release machinery or brand assets edited"
fi
echo "untouched"

echo
echo "clauth-verify: OK (hook budget $budget)"
