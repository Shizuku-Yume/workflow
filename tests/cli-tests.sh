#!/usr/bin/env bash
# Run the complete workflow CLI integration suite.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT"
failed=0

suite() {
  local name="$1"; shift
  printf '\n== %s ==\n' "$name"
  if "$@"; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    failed=$((failed + 1))
  fi
}

suite "workflow wrapper regression" "$KIT/tests/cli-regression.sh"
suite "workflow tasks" "$KIT/tests/tasks-tests.sh"
suite "workflow dependencies" "$KIT/tests/deps-tests.sh"
suite "workflow decisions" "$KIT/tests/decisions-tests.sh"
suite "workflow hotfix review" "$KIT/tests/hotfix-review-tests.sh"
suite "workflow validator" "$KIT/tests/validate-tests.sh"
suite "workflow next" "$KIT/tests/cli-next.sh"
suite "workflow effort" "$KIT/tests/effort-tests.sh"
suite "workflow debt" "$KIT/tests/debt-tests.sh"
suite "cross-command integration" "$KIT/tests/cli-integration.sh"
suite "parser consistency" "$KIT/tests/parser-consistency.sh"
suite "skills and template lint" "$KIT/tests/skills-lint.sh"
if (( failed )); then
  printf '\n%d CLI suite(s) failed.\n' "$failed" >&2
  exit 1
fi
printf '\nAll CLI suites passed.\n'
