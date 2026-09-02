#!/bin/bash
# The one architectural rule of the clauth integration, made executable:
# clauth logic lives under Sources/Pulse/Clauth/ and Tests/PulseTests/;
# upstream-owned Swift files receive call-site hooks only, and the TOTAL of
# added lines across those files must stay under a budget. Localizable
# .strings, Package.swift (the one test-target hunk) and Docs/ are exempt.
#
#   Scripts/clauth-hook-budget.sh <budget> [<upstream-ref>]
#
# Exit 0 when added lines ≤ budget, 1 otherwise; always prints the per-file
# table so the number is in the transcript, not just the verdict.
set -euo pipefail
cd "$(dirname "$0")/.."

budget="${1:?usage: clauth-hook-budget.sh <budget> [upstream-ref]}"
ref="${2:-upstream/main}"

git rev-parse --verify -q "$ref" >/dev/null || { echo "hook-budget: ref '$ref' not found (git fetch upstream)"; exit 2; }

total=0
printf '%-48s %6s %6s\n' "upstream-owned file" "added" "removed"
while IFS=$'\t' read -r added removed path; do
  case "$path" in
    Sources/Pulse/Clauth/*|Tests/*|Package.swift|Docs/*|Scripts/clauth-*|*.strings|.agent/*) continue ;;
  esac
  [ "$added" = "-" ] && continue   # binary
  printf '%-48s %6s %6s\n' "$path" "$added" "$removed"
  total=$((total + added))
done < <(git diff --numstat "$ref" -- . ':(exclude)Sources/Pulse/Clauth' ':(exclude)Tests' ':(exclude)Docs' ':(exclude).agent')

echo "hook-budget: $total added line(s) in upstream-owned files, budget $budget"
if [ "$total" -gt "$budget" ]; then
  echo "hook-budget: FAIL — logic leaked into upstream files; move it into Sources/Pulse/Clauth/"
  exit 1
fi
echo "hook-budget: OK"
