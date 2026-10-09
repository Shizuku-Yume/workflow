#!/usr/bin/env bash
# Focused integration coverage for workflow-deps. Fixtures are copied to isolated
# repositories so root discovery is exercised without changing project data.
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEPS="$BASE/bin/workflow-deps"
FIXTURES="$BASE/tests/fixtures/deps"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
COUNT=0
OUT="$TMP/output"
ERR="$TMP/errors"

fail() { printf 'FAIL: %s\n' "$*" >&2; cat "$OUT" "$ERR" >&2; exit 1; }
run() {
  local project=$1 expected=$2 actual=0
  shift 2
  if command -v timeout >/dev/null 2>&1; then
    (cd "$project" && timeout 20s bash "$DEPS" "$@") >"$OUT" 2>"$ERR" || actual=$?
  else
    (cd "$project" && bash "$DEPS" "$@") >"$OUT" 2>"$ERR" || actual=$?
  fi
  [ "$actual" -eq "$expected" ] || fail "expected exit $expected, got $actual: $*"
  COUNT=$((COUNT + 1))
}
has() { grep -Fq -- "$2" "$1" || fail "missing '$2' in $1"; COUNT=$((COUNT + 1)); }
lacks() { if grep -Fq -- "$2" "$1"; then fail "unexpected '$2' in $1"; fi; COUNT=$((COUNT + 1)); }
fixture() {
  local name=$1
  mkdir -p "$TMP/$name"
  cp -R "$FIXTURES/$name/.workflow" "$TMP/$name/"
  git -C "$TMP/$name" init -q
}
for name in cross circular missing malformed sparse duplicate; do fixture "$name"; done

for format in mermaid dot text; do
  run "$TMP/cross" 0 --format "$format"
  [ ! -s "$ERR" ] || fail "valid cross-effort graph produced warnings"
  has "$OUT" 'core/1'
  has "$OUT" 'payments/2'
  has "$OUT" 'payments/3'
  has "$OUT" 'archive/7'
  lacks "$OUT" 'archive/8'
  run "$TMP/cross" 0 --format "$format" --all
  has "$OUT" 'archive/8'
  run "$TMP/cross" 0 --format "$format" --effort payments
  has "$OUT" 'core/1'
  has "$OUT" 'archive/7'
  run "$TMP/cross" 0 --format "$format" --effort core
  lacks "$OUT" 'payments/2'
  run "$TMP/circular" 0 --format "$format"
  has "$ERR" 'circular dependency: alpha/1 -> beta/2 -> alpha/1'
  has "$ERR" 'circular dependency: alpha/3 -> alpha/3'
  has "$OUT" 'alpha/1'
  has "$OUT" 'beta/2'
  run "$TMP/missing" 0 --format "$format"
  has "$ERR" 'core/1 references missing blocker task: core/99'
  has "$ERR" 'core/1 references missing blocker task: absent/1'
  has "$OUT" 'core/99'
  has "$OUT" 'absent/1'
  run "$TMP/malformed" 0 --format "$format"
  has "$ERR" 'malformed Blocked by'
  run "$TMP/sparse" 0 --format "$format"
  has "$OUT" 'none/1'
  has "$OUT" 'Untitled'
done

run "$TMP/cross" 0 --format mermaid
has "$OUT" 'subgraph effort_'
has "$OUT" 'Effort: payments'
has "$OUT" 'subgraph legend["Legend"]'
has "$OUT" 'core/1: Build #quot;API#quot; &lt;gateway&gt; #91;draft#93;'
run "$TMP/missing" 0 --format mermaid
has "$OUT" ':::missing'
has "$OUT" 'classDef missing fill:#ffcccc,stroke:#cc0000'
run "$TMP/missing" 0 --format dot
has "$OUT" 'color=red'
if command -v dot >/dev/null 2>&1; then
  dot -Tdot "$OUT" -o "$TMP/rendered.dot"
  run "$TMP/cross" 0 --format dot
  dot -Tdot "$OUT" -o "$TMP/rendered.dot"
  COUNT=$((COUNT + 2))
fi
run "$TMP/missing" 0 --format text
has "$OUT" 'Depends on: core/99 (MISSING)'
run "$TMP/cross" 0 --check
has "$OUT" 'Dependencies valid (4 tasks checked).'
run "$TMP/cross" 0 --check --all
has "$OUT" 'Dependencies valid (5 tasks checked).'
run "$TMP/cross" 0 --check --effort core
has "$OUT" 'Dependencies valid (1 tasks checked).'
run "$TMP/circular" 1 --check
has "$ERR" 'circular dependency'
[ ! -s "$OUT" ] || fail '--check must not render a graph on failure'
run "$TMP/missing" 1 --check
run "$TMP/malformed" 1 --check
run "$TMP/duplicate" 1 --check
has "$ERR" 'duplicate task reference: core/1'
run "$TMP/cross" 0 --no-color --format text
if LC_ALL=C grep -q $'\033' "$OUT"; then fail '--no-color emitted ANSI escapes'; fi
run "$TMP/cross" 2 --format invalid
run "$TMP/cross" 2 --format
run "$TMP/cross" 2 --effort
run "$TMP/cross" 2 --format --check
run "$TMP/cross" 2 --effort 'bad/slug'
run "$TMP/cross" 2 --unknown
for blocked in '2,' 'None, 2' '2,,3' '2;3' 'core/not-a-number' '2 Title' 'core/2 Title' '2, prose' 'None.' 'None can start now'; do
  printf '# 01: Invalid dependencies\nEffort: core\nBlocked by: %s\n' "$blocked" > "$TMP/malformed/.workflow/tasks/01-invalid.md"
  run "$TMP/malformed" 1 --check
  has "$ERR" 'malformed Blocked by'
done
mkdir -p "$TMP/scoped/.workflow/tasks"
printf '# 01: API one\nEffort: api\nBlocked by: None\n' > "$TMP/scoped/.workflow/tasks/01-api.md"
printf '# 02: API two\nEffort: api\nBlocked by: 01\n' > "$TMP/scoped/.workflow/tasks/02-api.md"
printf '# 01: Web one\nEffort: web\nBlocked by: None\n' > "$TMP/scoped/.workflow/tasks/01-web.md"
git -C "$TMP/scoped" init -q
run "$TMP/scoped" 0 --check
has "$OUT" '3 tasks checked'
run "$TMP/scoped" 0 --format text --effort api
has "$OUT" 'Depends on: api/1'
lacks "$OUT" '[web/1]'
rm "$TMP/scoped/.workflow/tasks/01-api.md"
run "$TMP/scoped" 1 --check
has "$ERR" 'api/2 references missing blocker task: api/1'
printf '# 02: API two\nEffort: api\nBlocked by: web/01\n' > "$TMP/scoped/.workflow/tasks/02-api.md"
run "$TMP/scoped" 0 --check
run "$TMP/scoped" 0 --format text --effort api
has "$OUT" 'Depends on: web/1'
has "$OUT" '[web/1]'
mkdir -p "$TMP/metadata/.workflow/tasks"
for separator in '' '- [ ] Checklist' '## Goal' 'Files: source.py' $'```text\nexample\n```'; do
  printf 'Task: Boundary task\n- **Effort:** core\n- **Blocked by:** None\n%s\n  01\n' "$separator" > "$TMP/metadata/.workflow/tasks/01-boundary.md"
  run "$TMP/metadata" 0 --check
  run "$TMP/metadata" 0 --format text
  has "$OUT" '[core/1] Boundary task'
  lacks "$OUT" 'Depends on:'
done
mkdir -p "$TMP/absent" "$TMP/empty/.workflow/tasks" "$TMP/no-tasks/.workflow"
run "$TMP/absent" 0 --help
has "$OUT" 'Examples:'
run "$TMP/absent" 1
has "$ERR" 'no .workflow directory found'
run "$TMP/empty" 0 --format text
has "$OUT" 'No tasks'
run "$TMP/empty" 0 --check
has "$OUT" '0 tasks checked'
run "$TMP/no-tasks" 0 --check
mkdir -p "$TMP/cross/src/deep"
run "$TMP/cross/src/deep" 0 --check
has "$OUT" '4 tasks checked'

# A 150-task chain plus shared blockers exercises depth and graph reuse. Runtime
# is bounded by timeout where available; fixtures are generated deterministically.
mkdir -p "$TMP/large/.workflow/tasks"
for ((i=1; i<=150; i++)); do
  printf -v num '%03d' "$i"
  blockers=None
  if [ "$i" -gt 1 ]; then blockers="$((i - 1)), 001"; fi
  printf '# %s: Large task %s\nEffort: large\nBlocked by: %s\n' "$num" "$i" "$blockers" > "$TMP/large/.workflow/tasks/$num-task.md"
done
for format in mermaid dot text; do
  run "$TMP/large" 0 --format "$format"
  has "$OUT" 'large/150'
  [ ! -s "$ERR" ] || fail "large graph produced warnings"
done
run "$TMP/large" 0 --check
has "$OUT" '150 tasks checked'
printf '# 001: Large task 1\nEffort: large\nBlocked by: 150\n' > "$TMP/large/.workflow/tasks/001-task.md"
run "$TMP/large" 1 --check
has "$ERR" 'circular dependency'

printf 'Dependency CLI tests passed (%s assertions).\n' "$COUNT"
