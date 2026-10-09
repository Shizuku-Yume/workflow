#!/usr/bin/env bash
# workflow-next coverage; invoke after all CLI changes have landed.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXT="$KIT/bin/workflow-next"
source "$KIT/tests/fixtures/next-fixtures.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASSED=0
FAILED=0

pass() { printf 'PASS %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
capture() {
  local directory="$1"; shift
  if (cd "$directory" && "$NEXT" "$@") > "$TMP/stdout" 2> "$TMP/stderr"; then CODE=0; else CODE=$?; fi
  OUTPUT="$(cat "$TMP/stdout")"
  ERRORS="$(cat "$TMP/stderr")"
}
status() { if [ "$CODE" -eq "$1" ]; then pass "$2"; else fail "$2 (exit $CODE, expected $1; $ERRORS)"; fi; }
contains() { if [[ "$OUTPUT" == *"$1"* ]]; then pass "$2"; else fail "$2 (missing: $1)"; fi; }
excludes() { if [[ "$OUTPUT" != *"$1"* ]]; then pass "$2"; else fail "$2 (unexpected: $1)"; fi; }
stderr_contains() { if [[ "$ERRORS" == *"$1"* ]]; then pass "$2"; else fail "$2 (stderr: $ERRORS)"; fi; }
json_check() {
  if python3 -c "import json,sys; data=json.load(open(sys.argv[1])); $1" "$TMP/stdout"; then
    pass "$2"
  else
    fail "$2"
  fi
}

mkdir -p "$TMP/missing"
capture "$TMP/missing" --help
status 0 'help works without workflow files'
contains 'workflow next --interactive' 'help includes interactive example'
capture "$TMP/missing" --bogus
status 2 'unknown option is a usage error'
stderr_contains 'unknown option' 'usage errors go to stderr'
capture "$TMP/missing" --format
status 2 'format requires an argument'
capture "$TMP/missing" --format xml
status 2 'unknown output format is a usage error'
capture "$TMP/missing" --format json --interactive
status 2 'JSON cannot be combined with interactive prompts'
capture "$TMP/missing"
status 1 'missing workflow returns an error'
stderr_contains "workflow init" 'missing workflow explains initialization'
mkdir "$TMP/missing/.workflow"
capture "$TMP/missing"
status 0 'missing tasks directory is handled gracefully'
contains 'No tasks found' 'missing tasks directory explains empty state'
mkdir "$TMP/missing/.workflow/tasks"
capture "$TMP/missing" --interactive < /dev/null
status 0 'empty interactive list does not prompt'
contains 'No tasks found' 'empty task directory is handled gracefully'
capture "$TMP/missing" --format json
status 0 'empty directory supports JSON'
json_check 'assert data["ready_tasks"] == [] and data["task_count"] == 0 and data["blockers"] == []' 'empty JSON output has consistent collection fields'

project="$TMP/priorities"
next_priority_fixture "$project"
capture "$project" --no-color
status 0 'priority fixture succeeds outside git'
expected=$'99\n02\n10\n01\n20'
actual="$(printf '%s\n' "$OUTPUT" | sed -n 's/^[1-5]) [a-z0-9-]*\/\([0-9]*\) .*/\1/p')"
if [ "$actual" = "$expected" ]; then pass 'effort priorities then numeric task numbers determine order'; else fail "priority ordering ($actual)"; fi
contains '6 total; showing up to 5' 'ready count and top-five limit are displayed'
excludes 'low/03' 'sixth ready task is not displayed'
excludes 'Not ready.' 'blocked tasks are not offered'
contains 'Goal: Ship high priority work.' 'effort goal is shown'
contains 'Check: Check task two.' 'bold Markdown Check field is shown'
contains 'Start: flow-implement high/02' 'task skill invocation includes effort-qualified reference'
excludes 'Scope must not' 'goal parsing stops at the next section'
excludes $'\033[' 'no-color emits no escape sequences'
capture "$project" --format json
status 0 'priority fixture supports JSON'
json_check 'assert [t["number"] for t in data["ready_tasks"]] == [99,2,10,1,20]; assert data["ready_count"] == 6 and data["task_count"] == 7 and data["blocked_count"] == 1; assert data["ready_tasks"][1]["goal"] == "Ship high priority work." and data["ready_tasks"][1]["check"] == "Check task two." and data["ready_tasks"][1]["start_command"] == "flow-implement high/02"' 'JSON carries sorted tasks and qualified start command'

mkdir -p "$project/.agents/skills/flow-implement"
printf '# Fixture skill\n' > "$project/.agents/skills/flow-implement/SKILL.md"
capture "$project" --interactive <<< '2'
status 0 'valid interactive selection succeeds'
contains 'Next task: high/02 - Task 02' 'selection follows displayed effort-qualified reference'
contains 'run flow-implement on task high/02' 'selection gives a manual AI-assistant invocation'
capture "$project" --interactive <<< 'q'
status 0 'interactive quit is successful'
contains 'Cancelled.' 'interactive cancellation is explicit'
capture "$project" --interactive <<< '99'
status 2 'invalid interactive selection is a usage error'
stderr_contains 'select one of' 'invalid selection error goes to stderr'
capture "$project" --interactive < /dev/null
status 1 'interactive EOF is a controlled error'
stderr_contains 'no selection received' 'EOF error is actionable'
rm "$project/.agents/skills/flow-implement/SKILL.md"
capture "$project" --interactive <<< '1'
status 1 'missing flow-implement skill is an error'
stderr_contains "flow-implement skill not installed. Run 'workflow init' first." 'missing skill explains initialization'

# Root resolution must work from a nested directory in a repository.
git -C "$project" init -q
mkdir -p "$project/src/nested"
capture "$project/src/nested"
status 0 'nested repository directory resolves project root'
contains 'Check: Check task two.' 'nested invocation reads root task files'

# Blocker lists count each dependency at most once per waiting task.
blocked="$TMP/blocked"
next_project "$blocked"
next_task "$blocked" 01-first.md core 'core/07, 7, cross/08' 'Check first.'
next_task "$blocked" 02-second.md core '07, cross/09' 'Check second.'
next_task "$blocked" 03-third.md core 'core/7' 'Check third.'
capture "$blocked"
status 0 'no ready tasks is not an error'
contains 'No ready tasks. 3 task(s) blocked.' 'no-ready state reports blocked task count'
contains 'core/07: 3 task(s) (tasks: core/01, core/02, core/03)' 'blocking counts normalize and deduplicate dependency numbers'
contains 'cross/08: 1 task(s)' 'cross-effort blockers are included'
first="$(printf '%s\n' "$OUTPUT" | sed -n '3p')"
if [[ "$first" == *'core/07: 3 task(s)'* ]]; then pass 'most consequential blocker is first'; else fail 'blocker ordering'; fi
capture "$blocked" --interactive < /dev/null
status 0 'no-ready interactive mode does not prompt'
capture "$blocked" --format json
status 0 'blocked workflow supports JSON'
json_check 'assert data["ready_tasks"] == []; assert data["blockers"][0] == {"dependency":"core/07", "count":3, "tasks":[1,2,3]}' 'JSON blocker ranking preserves deduplicated task identifiers'

circular="$TMP/circular"
next_project "$circular"
next_task "$circular" 01-cycle.md core '02' 'First.'
next_task "$circular" 02-cycle.md core '01' 'Second.'
capture "$circular"
status 0 'circular blockers do not crash or recurse'
contains 'core/01: 1 task(s)' 'circular first blocker is shown'
contains 'core/02: 1 task(s)' 'circular second blocker is shown'

# Missing and malformed fields are kept out of the ready list rather than guessed.
malformed="$TMP/malformed"
next_project "$malformed"
next_task "$malformed" 01-missing.md core '' ''
next_task "$malformed" 02-malformed.md core 'None, 01' ''
next_task "$malformed" 03-trailing.md core '01,' ''
printf 'Blocked by: None\n' > "$malformed/.workflow/tasks/not-a-task.md"
capture "$malformed"
status 0 'malformed metadata does not crash the command'
contains '(missing Blocked by field)' 'missing blockers are diagnosed'
contains '(malformed Blocked by field)' 'invalid blockers are diagnosed'
stderr_contains 'malformed Blocked by' 'malformed blockers are warned on stderr'
stderr_contains 'invalid filename' 'invalid task filename is ignored with a warning'

# A ready task can still be useful when context is incomplete.
incomplete="$TMP/incomplete"
next_project "$incomplete"
printf 'Blocked by: None\nEffort: missing\n' > "$incomplete/.workflow/tasks/01-minimal.md"
capture "$incomplete"
status 0 'missing optional context does not crash'
contains 'Untitled' 'missing title has a fallback'
contains 'Check: (not specified)' 'missing Check has a fallback'
contains 'Goal: (not specified)' 'missing effort goal has a fallback'
stderr_contains 'effort definition missing' 'missing effort definition is diagnosed'
capture "$incomplete" --interactive <<< '2'
status 2 'selection beyond displayed choices is rejected'

multiline="$TMP/multiline"
next_project "$multiline"
next_effort "$multiline" core unexpected $'Ship safely.\nKeep behavior compatible.'
cat > "$multiline/.workflow/tasks/01-context.md" <<'EOF'
# 01: Context with 100% coverage
Effort: core
Blocked by: None
Check:
  Run the unit tests.
  Confirm the integration result.
Files: src/main.sh
This text must not leak into Check.
EOF
capture "$multiline"
status 0 'multiline context and unknown priority do not crash'
contains 'Goal: Ship safely. Keep behavior compatible.' 'multiline effort goal is previewed'
contains 'Check: Run the unit tests. Confirm the integration result.' 'multiline Check is previewed'
contains 'Context with 100% coverage' 'task text is not interpreted as a printf format'
excludes 'must not leak' 'Check continuation stops at the next field'
stderr_contains 'unknown priority' 'unknown priority falls back with a warning'

check_field_boundary="$TMP/check-boundary"
next_project "$check_field_boundary"
cat > "$check_field_boundary/.workflow/tasks/01-check.md" <<'EOF'
# 01: Check boundary
Effort: core
Blocked by: None
**Check:** `true` → ok

- [ ] a
EOF
capture "$check_field_boundary" --no-color
status 0 'Check field boundary succeeds'
contains 'Check: `true` → ok' 'Check output contains only field value'
excludes '→ ok - [ ] a' 'checklist does not bleed into Check output'
capture "$check_field_boundary" --format json
json_check 'assert data["ready_tasks"][0]["check"] == "`true` → ok"' 'JSON Check field stops before checklist'

scoped="$TMP/scoped"
next_project "$scoped"
next_task "$scoped" 01-api.md api None 'API check.'
next_task "$scoped" 02-api.md api 01 'API follow-up check.'
next_task "$scoped" 01-web.md web None 'Web check.'
capture "$scoped" --no-color
status 0 'repeated numbers across efforts remain ready'
contains 'Start: flow-implement api/01' 'API start reference includes effort and zero-padding'
contains 'Start: flow-implement web/01' 'web start reference disambiguates repeated number'
excludes 'API follow-up check.' 'unqualified blocker keeps same-effort follow-up blocked'
stderr_contains 'using normal priority' 'missing effort definition retains normal priority'
capture "$scoped" --format json
json_check 'assert {t["start_command"] for t in data["ready_tasks"]} == {"flow-implement api/01", "flow-implement web/01"}; assert data["blocked_count"] == 1 and data["blockers"][0]["dependency"] == "api/01"' 'JSON ready list and blockers are effort-scoped'

cat > "$check_field_boundary/.workflow/tasks/01-check.md" <<'EOF'
# 01: Adjacent fields
Effort: core
Blocked by: None
**Check:** `true` → ok
**Finished:** 2026-10-07T12:00:00Z
**Question:** Does this work?
**Time box:** 30 minutes
**Read first:** src/main.sh
- [ ] a
EOF
capture "$check_field_boundary" --format json
json_check 'assert data["ready_tasks"][0]["check"] == "`true` → ok"' 'new metadata fields and adjacent checklist do not bleed into JSON Check'

escaped="$TMP/escaped"
next_project "$escaped"
printf '# 01: Quoted "task" \\slash\001\nEffort: none\nBlocked by: None\nCheck: "ok" \\path\n' > "$escaped/.workflow/tasks/01-escaped.md"
capture "$escaped" --format json
status 0 'control characters do not crash JSON output'
json_check 'assert data["ready_tasks"][0]["title"] == "Quoted \"task\" \\slash\x01"; assert data["ready_tasks"][0]["check"] == "\"ok\" \\path"' 'JSON escapes quotes, backslashes, and control characters'

# Blockers archived under done/<effort>/ are finished, so they stop gating tasks.
archived="$TMP/archived-blockers"
next_project "$archived"
mkdir -p "$archived/.workflow/done/core"
cat > "$archived/.workflow/done/core/01-core.md" <<'EOF'
# 01: Core
Effort: core
Blocked by: None
EOF
cat > "$archived/.workflow/tasks/02-dep.md" <<'EOF'
# 02: Dep
Effort: core
Blocked by: 01
EOF
cat > "$archived/.workflow/tasks/03-partial.md" <<'EOF'
# 03: Partial
Effort: core
Blocked by: 01, 07
EOF
capture "$archived" --no-color
status 0 'archived blocker is accepted'
contains 'flow-implement core/02' 'task blocked only by an archived task is ready'
excludes 'flow-implement core/03' 'task with an unarchived blocker stays blocked'
capture "$archived" --format json
json_check 'assert sorted(t["number"] for t in data["ready_tasks"]) == [2]; assert data["task_count"] == 2; assert data["blocked_count"] == 1' 'archived blockers drop out of counts and blocker list'
json_check 'assert [b["dependency"] for b in data["blockers"]] == ["core/07"]' 'only the unarchived blocker is reported'

# A blocker in another effort is resolved by that effort's archive directory.
cross_archived="$TMP/cross-archived"
next_project "$cross_archived"
mkdir -p "$cross_archived/.workflow/done/web"
cat > "$cross_archived/.workflow/done/web/01-page.md" <<'EOF'
# 01: Page
Effort: web
EOF
cat > "$cross_archived/.workflow/tasks/02-uses.md" <<'EOF'
# 02: Uses
Effort: core
Blocked by: web/01
EOF
capture "$cross_archived" --format json
json_check 'assert [t["start_command"] for t in data["ready_tasks"]] == ["flow-implement core/02"]' 'qualified blocker is satisfied by the named effort archive'

# Status: blocked waits for replanning even with no Blocked by entries; paused is
# offered so it gets resumed.
replan="$TMP/replan"
next_project "$replan"
cat > "$replan/.workflow/tasks/01-wrong.md" <<'EOF'
# 01: Wrong plan
**Effort:** core
**Status:** blocked
**Blocked by:** None
**Check:** Check wrong.
EOF
cat > "$replan/.workflow/tasks/02-paused.md" <<'EOF'
# 02: Paused work
**Effort:** core
**Status:** paused
**Blocked by:** None
**Check:** Check paused.
EOF
capture "$replan" --no-color
status 0 'status fixture succeeds'
excludes 'flow-implement core/01' 'Status: blocked task is not offered'
contains 'flow-implement core/02' 'Status: paused task is offered for resuming'
capture "$replan" --format json
json_check 'assert [t["number"] for t in data["ready_tasks"]] == [2]; assert data["blocked_count"] == 1; assert [b["dependency"] for b in data["blockers"]] == ["(Status: blocked, needs replanning)"]' 'Status: blocked is counted and reported as its own blocker'

# Exercise dispatcher once the integration owner has added next.
if (cd "$project" && "$KIT/bin/workflow" next --no-color) > "$TMP/stdout" 2> "$TMP/stderr"; then
  pass 'workflow dispatcher integrates next'
else
  fail "workflow dispatcher integrates next ($(cat "$TMP/stderr"))"
fi

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
