#!/usr/bin/env bash
# Run every workflow test suite; exit 1 if any failed.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT" || exit 1
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

suite "workflow CLI regression" bash "$KIT/tests/cli-regression.sh"
suite "validate and next core" python3 "$KIT/tests/test_core.py"
suite "skills and template lint" python3 "$KIT/tests/skills_lint.py"

if [ "$failed" -gt 0 ]; then
  printf '\n%d suite(s) failed.\n' "$failed" >&2
  exit 1
fi
printf '\nAll suites passed.\n'
