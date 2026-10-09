#!/usr/bin/env bash
# Integration coverage for workflow-effort using isolated git projects.
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EFFORT="$BASE/bin/workflow-effort"
FIXTURES="$BASE/tests/fixtures/effort"
# Physical path: on macOS mktemp gives /var/..., git reports /private/var/....
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"
ERR="$TMP/err"
COUNT=0

fail() { printf 'FAIL: %s\n' "$*" >&2; cat "$OUT" "$ERR" >&2; exit 1; }
run() {
  local project=$1 expected=$2 actual=0
  shift 2
  if command -v timeout >/dev/null 2>&1; then
    (cd "$project" && timeout 20s bash "$EFFORT" "$@") >"$OUT" 2>"$ERR" || actual=$?
  else
    (cd "$project" && bash "$EFFORT" "$@") >"$OUT" 2>"$ERR" || actual=$?
  fi
  [ "$actual" -eq "$expected" ] || fail "expected exit $expected, got $actual: $*"
  COUNT=$((COUNT + 1))
}
has() { grep -Fq -- "$2" "$1" || fail "missing '$2' in $1"; COUNT=$((COUNT + 1)); }
lacks() { if grep -Fq -- "$2" "$1"; then fail "unexpected '$2' in $1"; fi; COUNT=$((COUNT + 1)); }
quiet() { [ ! -s "$1" ] || fail "expected empty $1"; COUNT=$((COUNT + 1)); }
same() { cmp -s "$1" "$2" || fail "files differ: $1 and $2"; COUNT=$((COUNT + 1)); }
absent() { [ ! -e "$1" ] || fail "unexpected path $1"; COUNT=$((COUNT + 1)); }
present() { [ -e "$1" ] || fail "missing path $1"; COUNT=$((COUNT + 1)); }
body_same() {
  awk '/^## / {body=1} body' "$1" >"$TMP/body-before"
  awk '/^## / {body=1} body' "$2" >"$TMP/body-after"
  same "$TMP/body-before" "$TMP/body-after"
}
fixture() {
  local name=$1 source=${2:-$FIXTURES}
  mkdir -p "$TMP/$name"
  cp -R "$source/.workflow" "$TMP/$name/"
  git -C "$TMP/$name" init -q
}
error_run() {
  run "$@"
  has "$ERR" 'Error:'
  quiet "$OUT"
}
fixture main

# Discovery, archived filtering, metadata formats, and help/flag placement.
run "$TMP/main" 0
quiet "$ERR"
for slug in alpha beta gamma planning; do has "$OUT" "$slug"; done
for slug in legacy released retrospective-only; do lacks "$OUT" "$slug"; done
has "$OUT" 'Tasks: 4 active, 2 done, 6 total'
run "$TMP/main" 0 --archived list
quiet "$ERR"
has "$OUT" 'legacy'
has "$OUT" 'released'
has "$OUT" 'Tasks: 2 active, 1 done, 3 total'
lacks "$OUT" 'retrospective-only'
cp "$OUT" "$TMP/archived-list"
run "$TMP/main" 0 list --archived
same "$OUT" "$TMP/archived-list"
run "$TMP/main" 0 --no-color list --archived
same "$OUT" "$TMP/archived-list"
if LC_ALL=C grep -q $'\033' "$OUT"; then fail '--no-color emitted ANSI escapes'; fi
run "$TMP/main" 0 list --archived --no-color
same "$OUT" "$TMP/archived-list"
run "$TMP/main" 0 --no-color status alpha
cp "$OUT" "$TMP/alpha-status"
run "$TMP/main" 0 status --no-color alpha
same "$OUT" "$TMP/alpha-status"
run "$TMP/main" 0 status alpha --no-color
same "$OUT" "$TMP/alpha-status"
for slug in Bad_Slug -alpha alpha- alpha--beta bad/slug 'two words' ''; do
  error_run "$TMP/main" 2 status "$slug"
  has "$ERR" 'invalid effort slug'
  error_run "$TMP/main" 2 create "$slug"
  error_run "$TMP/main" 2 complete "$slug"
  error_run "$TMP/main" 2 rename "$slug" valid-slug
  error_run "$TMP/main" 2 rename alpha "$slug"
done
error_run "$TMP/main" 2 rename alpha
has "$ERR" 'rename requires'
error_run "$TMP/main" 2 list alpha
has "$ERR" 'list takes no slug'
error_run "$TMP/main" 2 status alpha --archived
has "$ERR" '--archived is only supported'
error_run "$TMP/main" 2 status
error_run "$TMP/main" 2 create
error_run "$TMP/main" 2 complete
error_run "$TMP/main" 2 rename alpha beta gamma
error_run "$TMP/main" 2 --unknown
error_run "$TMP/main" 2 unknown-command

# Status progress and blockers, including nested tasks and completed/missing refs.
run "$TMP/main" 0 status alpha
quiet "$ERR"
has "$OUT" 'Status: active'
has "$OUT" 'Priority: high'
has "$OUT" 'Goal: Ship alpha safely.'
has "$OUT" 'Total: 6'
has "$OUT" 'Active: 4'
has "$OUT" 'Done: 2'
has "$OUT" 'Blocked: 2'
has "$OUT" 'Progress: [######--------------] 33%'
has "$OUT" '02-alpha-local.md (Blocked by: #001)'
has "$OUT" '03-alpha-cross.md (Blocked by: `beta/001`, [alpha/002])'
lacks "$OUT" '04-alpha-ready.md (Blocked by:'
has "$OUT" "Retrospective: $TMP/main/.workflow/done/alpha/retrospective.md"
run "$TMP/main" 0 status beta
has "$OUT" 'Total: 3'
has "$OUT" 'Active: 2'
has "$OUT" 'Done: 1'
has "$OUT" 'Blocked: 2'
has "$OUT" '02-beta-missing.md'
run "$TMP/main" 0 status gamma
has "$OUT" 'Total: 1'
has "$OUT" 'Blocked: 1'
run "$TMP/main" 0 status legacy
has "$OUT" 'Total: 1'
has "$OUT" 'Done: 1'
has "$OUT" 'Blocked: 0'
has "$OUT" 'Progress: [####################] 100%'
run "$TMP/main" 0 status released
has "$OUT" 'Total: 0'
has "$OUT" 'Progress: [--------------------] 0%'
mkdir -p "$TMP/main/src/deep"
run "$TMP/main/src/deep" 0 status alpha
has "$OUT" 'Total: 6'

# Lifecycle create/complete and filesystem definition shape.
run "$TMP/main" 0 create --no-color fresh-effort
has "$OUT" "$TMP/main/.workflow/efforts/fresh-effort.md"
present "$TMP/main/.workflow/efforts/fresh-effort.md"
has "$TMP/main/.workflow/efforts/fresh-effort.md" '# Effort: fresh-effort'
has "$TMP/main/.workflow/efforts/fresh-effort.md" 'Status: planning'
for heading in '## Goal' '## Scope' '## Success Criteria' '## Dependencies' '## Notes'; do
  has "$TMP/main/.workflow/efforts/fresh-effort.md" "$heading"
done
run "$TMP/main" 0 status fresh-effort
has "$OUT" 'Total: 0'
has "$OUT" 'Blocked: 0'
error_run "$TMP/main" 1 complete alpha
has "$ERR" '4 active tasks'
same "$FIXTURES/.workflow/efforts/alpha.md" "$TMP/main/.workflow/efforts/alpha.md"
error_run "$TMP/main" 1 create alpha
has "$ERR" 'already has a definition'
error_run "$TMP/main" 1 create fresh-effort
# Tasks naming an effort with no definition yet must not block creating one:
# flow-break writes the tasks first, and validate suggests exactly this command.
cp -R "$TMP/main" "$TMP/create-copy"
run "$TMP/create-copy" 0 create gamma
present "$TMP/create-copy/.workflow/efforts/gamma.md"
run "$TMP/create-copy" 0 create legacy
present "$TMP/create-copy/.workflow/efforts/legacy.md"
error_run "$TMP/main" 1 complete nonexistent
has "$ERR" 'not found'
error_run "$TMP/main" 1 status nonexistent
error_run "$TMP/main" 1 complete legacy
has "$ERR" 'no effort definition'
run "$TMP/main" 0 complete fresh-effort --no-color
has "$OUT" "Marked effort 'fresh-effort' as complete"
has "$TMP/main/.workflow/efforts/fresh-effort.md" 'Status: complete'
run "$TMP/main" 0 list
lacks "$OUT" 'fresh-effort'
run "$TMP/main" 0 list --archived
has "$OUT" 'fresh-effort'

# Rename updates definition, active/archive fields and blocker references while preserving bodies.
run "$TMP/main" 0 rename alpha --no-color omega
has "$OUT" "Renamed effort 'alpha' to 'omega'"
present "$TMP/main/.workflow/efforts/omega.md"
present "$TMP/main/.workflow/done/omega/nested/09-design.md"
present "$TMP/main/.workflow/done/omega/retrospective.md"
absent "$TMP/main/.workflow/efforts/alpha.md"
absent "$TMP/main/.workflow/done/alpha"
has "$TMP/main/.workflow/efforts/omega.md" '# Effort: omega'
has "$TMP/main/.workflow/tasks/01-alpha-ready.md" 'Effort: omega'
has "$TMP/main/.workflow/tasks/02-alpha-local.md" '**Effort:** omega'
has "$TMP/main/.workflow/tasks/02-alpha-local.md" '**Blocked by:** #001'
has "$TMP/main/.workflow/tasks/04-alpha-ready.md" '**Effort**: omega'
has "$TMP/main/.workflow/tasks/04-alpha-ready.md" '#omega/008 Published contract'
has "$TMP/main/.workflow/done/omega/08-contract.md" '**Effort:** omega'
has "$TMP/main/.workflow/tasks/omega/nested/03-alpha-cross.md" 'Blocked by: `beta/001`, [omega/002]'
absent "$TMP/main/.workflow/tasks/alpha"
has "$TMP/main/.workflow/tasks/02-beta-missing.md" 'Blocked by: 099, omega/001'
has "$TMP/main/.workflow/done/beta/03-review.md" 'Blocked by: [omega/001], `omega/002`, gamma/001'
body_same "$FIXTURES/.workflow/efforts/alpha.md" "$TMP/main/.workflow/efforts/omega.md"
for task in 01-alpha-ready.md 02-alpha-local.md 04-alpha-ready.md 02-beta-missing.md; do
  body_same "$FIXTURES/.workflow/tasks/$task" "$TMP/main/.workflow/tasks/$task"
done
body_same "$FIXTURES/.workflow/tasks/alpha/nested/03-alpha-cross.md" "$TMP/main/.workflow/tasks/omega/nested/03-alpha-cross.md"
body_same "$FIXTURES/.workflow/done/alpha/08-contract.md" "$TMP/main/.workflow/done/omega/08-contract.md"
body_same "$FIXTURES/.workflow/done/beta/03-review.md" "$TMP/main/.workflow/done/beta/03-review.md"
same "$FIXTURES/.workflow/done/alpha/nested/09-design.md" "$TMP/main/.workflow/done/omega/nested/09-design.md"
same "$FIXTURES/.workflow/done/alpha/retrospective.md" "$TMP/main/.workflow/done/omega/retrospective.md"
same "$FIXTURES/.workflow/tasks/01-beta-cycle.md" "$TMP/main/.workflow/tasks/01-beta-cycle.md"
same "$FIXTURES/.workflow/tasks/gamma/01-gamma-cycle.md" "$TMP/main/.workflow/tasks/gamma/01-gamma-cycle.md"
run "$TMP/main" 0 status omega
has "$OUT" 'Total: 6'
has "$OUT" 'Blocked: 2'
has "$OUT" "Retrospective: $TMP/main/.workflow/done/omega/retrospective.md"
error_run "$TMP/main" 1 status alpha
error_run "$TMP/main" 2 rename omega omega
has "$ERR" 'identical'
error_run "$TMP/main" 1 rename omega beta
has "$ERR" 'already exists'
error_run "$TMP/main" 1 rename nope new
has "$ERR" 'not found'
mkdir -p "$TMP/main/.workflow/done/occupied"
error_run "$TMP/main" 1 rename omega occupied
has "$ERR" 'already exists'
present "$TMP/main/.workflow/efforts/omega.md"
present "$TMP/main/.workflow/done/omega"

# Rename and completion retain CRLF bytes, including appending a missing Status.
fixture crlf "$FIXTURES/crlf"
run "$TMP/crlf" 0 rename transport transit
has "$OUT" "Renamed effort 'transport' to 'transit'"
printf '# Effort: transit\r\n\r\n**Status:** active\r\n\r\n## Goal\r\nPreserve transport/01 in this body.\r\n' >"$TMP/expected-crlf"
same "$TMP/expected-crlf" "$TMP/crlf/.workflow/efforts/transit.md"
printf '# 01: Wire transport\r\n\r\n**Effort:** transit\r\n**Blocked by:** transit/002\r\n\r\n## Notes\r\nKeep transport and transport/002 in prose.\r\n' >"$TMP/expected-crlf"
same "$TMP/expected-crlf" "$TMP/crlf/.workflow/tasks/01-active.md"
printf '# 02: Publish transport contract\r\n\r\nEffort: transit\r\nBlocked by: None\r\n\r\n## Notes\r\nLeave transport/02 unchanged.\r\n' >"$TMP/expected-crlf"
same "$TMP/expected-crlf" "$TMP/crlf/.workflow/done/transit/02-contract.md"
run "$TMP/crlf" 0 complete no-status
cat "$FIXTURES/crlf/.workflow/efforts/no-status.md" >"$TMP/expected-crlf"
printf 'Status: complete\r\n' >>"$TMP/expected-crlf"
same "$TMP/expected-crlf" "$TMP/crlf/.workflow/efforts/no-status.md"

# Missing workflow runtime error, malformed metadata, absent directories and empty workflow.
mkdir -p "$TMP/absent" "$TMP/empty/.workflow" "$TMP/no-tasks/.workflow/efforts" "$TMP/empty-dirs/.workflow/tasks" "$TMP/empty-dirs/.workflow/done" "$TMP/empty-dirs/.workflow/efforts"
for project in absent empty no-tasks empty-dirs; do git -C "$TMP/$project" init -q; done
run "$TMP/absent" 0 --help
has "$OUT" 'Usage:'
quiet "$ERR"
run "$TMP/absent" 0 status Bad_Slug --help
has "$OUT" 'Usage:'
run "$TMP/absent" 0 --no-color status --help Bad_Slug
run "$TMP/absent" 0 rename --help
run "$TMP/absent" 0 status Bad_Slug -h
run "$TMP/absent" 0 help
run "$TMP/absent" 0 --unknown --help
error_run "$TMP/absent" 1
has "$ERR" 'missing .workflow directory'
error_run "$TMP/absent" 1 create missing-workflow
error_run "$TMP/absent" 2 status Bad_Slug
for project in empty empty-dirs; do
  run "$TMP/$project" 0 list
  quiet "$ERR"
  has "$OUT" 'No efforts found'
  run "$TMP/$project" 0 --archived
  has "$OUT" 'No efforts found'
  error_run "$TMP/$project" 1 status missing
done
cp "$FIXTURES/.workflow/efforts/planning.md" "$TMP/no-tasks/.workflow/efforts/"
run "$TMP/no-tasks" 0 list
has "$OUT" 'planning'
run "$TMP/no-tasks" 0 status planning
has "$OUT" 'Total: 0'
has "$OUT" 'Blocked: 0'
run "$TMP/no-tasks" 0 complete planning
has "$TMP/no-tasks/.workflow/efforts/planning.md" 'Status: complete'
body_same "$FIXTURES/.workflow/efforts/planning.md" "$TMP/no-tasks/.workflow/efforts/planning.md"
run "$TMP/empty" 0 create first-effort
present "$TMP/empty/.workflow/efforts/first-effort.md"
run "$TMP/empty" 0 complete first-effort
run "$TMP/empty" 0 list
lacks "$OUT" 'first-effort'
fixture malformed "$FIXTURES/malformed"
run "$TMP/malformed" 0 list
has "$OUT" 'rough'
lacks "$OUT" 'Bad/Slug'
lacks "$ERR" 'bad array subscript'
lacks "$ERR" 'unbound variable'
run "$TMP/malformed" 0 status rough
has "$OUT" 'Total: 1'
has "$OUT" 'Blocked: 1'
error_run "$TMP/malformed" 1 status missing
printf 'ok - %d assertions\n' "$COUNT"
