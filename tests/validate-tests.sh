#!/usr/bin/env bash
# Deterministic workflow-validate integration tests; no external test framework.
set -euo pipefail
KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VALIDATE="$KIT/bin/workflow-validate"
WORKFLOW="$KIT/bin/workflow"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0
run() { (cd "$REPO" && "$VALIDATE" "$@"); }
check() {
  local name=$1 expected=$2 actual=0; shift 2
  "$@" > "$TMP/out" 2> "$TMP/err" || actual=$?
  if [ "$actual" = "$expected" ]; then printf 'ok - %s\n' "$name"; PASS=$((PASS+1)); else printf 'not ok - %s (exit %s, expected %s)\n' "$name" "$actual" "$expected"; cat "$TMP/out" "$TMP/err"; FAIL=$((FAIL+1)); fi
}
contains() {
  local name=$1 pattern=$2 file=$3
  if grep -qF -- "$pattern" "$file"; then printf 'ok - %s\n' "$name"; PASS=$((PASS+1)); else printf 'not ok - %s\n' "$name"; FAIL=$((FAIL+1)); fi
}
setup() {
  REPO="$TMP/$1"; mkdir -p "$REPO/.workflow/tasks" "$REPO/.workflow/efforts" "$REPO/sub/deep"
  git -C "$REPO" init -q; git -C "$REPO" config user.name Validator; git -C "$REPO" config user.email validator@example.com
  printf 'initial\n' > "$REPO/root.txt"; git -C "$REPO" add root.txt; git -C "$REPO" commit -qm initial
  printf '# Effort: api-v2\n' > "$REPO/.workflow/efforts/api-v2.md"
  cp "$KIT/tests/fixtures/validate/decision.fixture" "$REPO/.workflow/decisions.md"
}
task() {
  local filename=$1 number=$2 blocker=${3:-None} effort=${4:-api-v2} base=${5:-HEAD}
  printf '# %s: Test task\n**Effort:** %s\n**Base commit:** %s\n**Blocked by:** %s\n**Check:** tests pass\n' "$number" "$effort" "$base" "$blocker" > "$REPO/.workflow/tasks/$filename.md"
}
subdirectory() { (cd "$REPO/sub/deep" && "$VALIDATE" "$@"); }
main_dispatch() { (cd "$REPO" && "$WORKFLOW" validate "$@"); }
confirm_fix() { printf 'y\n' | run --fix; }
decline_fix() { printf 'n\n' | run --fix; }
closed_fix() { run --fix < /dev/null; }

check 'help' 0 "$VALIDATE" --help
check 'unknown option' 2 "$VALIDATE" --unknown
check 'missing format argument' 2 "$VALIDATE" --format
check 'unsupported output format' 2 "$VALIDATE" --format yaml
setup happy; task 01-first 01; task 02-second 02 1
check 'forward-independent valid references' 0 run
check 'subdirectory root discovery' 0 subdirectory
check 'main workflow dispatch' 0 main_dispatch
check 'machine-readable valid report' 0 run --format json
contains 'JSON valid flag' '"valid":true' "$TMP/out"
contains 'JSON task count' '"tasks":2' "$TMP/out"
check 'explicit text and no-color' 0 run --format text --no-color

setup missing-required
cp "$KIT/tests/fixtures/validate/missing-fields.fixture" "$REPO/.workflow/tasks/01-bad.md"
check 'required fields all collected' 2 run
contains 'required Task' 'required Task field' "$TMP/err"
contains 'required Effort' 'required Effort field' "$TMP/err"
contains 'required Check' 'required Check field' "$TMP/err"
contains 'file line context' '.workflow/tasks/01-bad.md:1:' "$TMP/err"
setup empty-fields; printf '# 01: \nEffort:\nCheck:\n' > "$REPO/.workflow/tasks/01-empty.md"
check 'empty fields invalid' 2 run
setup section-check; task 01-good 01
sed -i 's/\*\*Check:\*\* tests pass/## Check\n\n- Tests pass./' "$REPO/.workflow/tasks/01-good.md"
check 'multiline Check section' 0 run
setup plain; printf 'Task: Plain task\nEffort: api-v2\nBase: HEAD\nBlocked by: None, can start now\nCheck: run tests\n' > "$REPO/.workflow/tasks/01-plain.md"
check 'plain metadata and Base alias' 0 run

setup effort; task 01-bad 01 None missing-effort
check 'missing effort is warning' 1 run
contains 'effort creation suggestion' 'Run: workflow effort create missing-effort' "$TMP/err"
setup invalid-slug; task 01-bad 01 None '../escape'
check 'malformed effort slug' 2 run
setup archived-effort; task 01-good 01; rm "$REPO/.workflow/efforts/api-v2.md"; mkdir -p "$REPO/.workflow/done/api-v2"
check 'archive directory does not require effort definition' 1 run
setup task-effort; task 01-good 01; mv "$REPO/.workflow/efforts/api-v2.md" "$REPO/.workflow/tasks/api-v2.md"
check 'legacy task definition still warns for missing effort definition' 1 run

setup orphan; task 01-orphan 01 99
check 'missing blocker' 2 run
contains 'blocker line context' '.workflow/tasks/01-orphan.md:4:' "$TMP/err"
setup malformed-blocker; task 01-malformed 01 banana
check 'malformed blocker token' 2 run
setup blocker-title; task 01-first 01; task 02-titled 02 '01 Task title'
check 'blocker display titles are rejected' 2 run
setup blocker-trailing; task 01-first 01; task 02-trailing 02 '01,'
check 'blocker trailing comma is rejected' 2 run
setup cross; task 01-consumer 01 'other/0002'; task 02-other 02 None other; printf '# Effort: other\n' > "$REPO/.workflow/efforts/other.md"
check 'cross-effort and zero-padding references' 0 run
setup completed; task 02-consumer 02 01; task 01-done 01; mkdir -p "$REPO/.workflow/done/api-v2"; mv "$REPO/.workflow/tasks/01-done.md" "$REPO/.workflow/done/api-v2/"
check 'completed blocker resolves' 0 run
setup collision; task 01-first 1; task 0001-second 1
check 'same-effort number collision' 2 run
setup different-efforts; task 01-api 1; task 1-other 1 None other; printf '# Effort: other\n' > "$REPO/.workflow/efforts/other.md"
check 'same number different efforts is valid' 0 run
setup scoped-optional; task 01-api 01 None api; task 02-api 02 01 api; task 01-web 01 None web
check 'same numbers and local blockers with optional efforts produce only warnings' 1 run --format json
check_scoped_json() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["errors"] == 0 and d["warnings"] == 3; assert all(i["severity"] == "WARNING" and "effort definition missing" in i["message"] for i in d["issues"])' "$TMP/out"; }
if check_scoped_json; then printf 'ok - optional effort warnings contain no collision or orphan errors\n'; PASS=$((PASS+1)); else printf 'not ok - optional effort warnings contain no collision or orphan errors\n'; FAIL=$((FAIL+1)); fi
setup local-orphan; task 02-api 02 01 api; task 01-web 01 None web
check 'unqualified blocker does not resolve against another effort' 2 run
contains 'local orphan diagnostic' "orphaned blocker '01'" "$TMP/err"
setup self-cycle; task 01-self 01 1
check 'self-dependency cycle' 2 run
setup cycle; task 01-a 1 2; task 02-b 2 3; task 03-c 3 1
check 'three-task cycle' 2 run
contains 'cycle actionable suggestion' 'Remove or change one blocker' "$TMP/err"
setup huge-number; task 999999999999999999999999999999-first 999999999999999999999999999999
check 'large numbers do not overflow' 0 run

setup bad-base; task 01-bad 1 None api-v2 definitely-not-a-ref
check 'invalid Base commit' 2 run
contains 'Base line context' '.workflow/tasks/01-bad.md:3:' "$TMP/err"
setup draft; task 01-draft 1 None api-v2 '<commit-sha>'
check 'draft Base placeholder' 0 run
setup missing-base; printf '# 1: Task\nEffort: api-v2\nBlocked by: None\nCheck: tests\n' > "$REPO/.workflow/tasks/01-task.md"
check 'missing Base commit is tolerated' 0 run
setup missing-blocker; printf '# 1: Task\nEffort: api-v2\nCheck: tests\n' > "$REPO/.workflow/tasks/01-task.md"
check 'missing Blocked by is rejected' 2 run
contains 'required Blocked by diagnostic' 'required Blocked by field' "$TMP/err"
setup done-legacy; mkdir -p "$REPO/.workflow/done/api-v2"
printf '# 01: Legacy archive\n**Effort:** api-v2\n**Blocked by:** None\n' > "$REPO/.workflow/done/api-v2/01-legacy.md"
check 'archived missing fields warn instead of failing' 1 run
contains 'archived missing Check warning' 'missing or empty required Check field' "$TMP/err"
setup done-malformed; mkdir -p "$REPO/.workflow/done/api-v2"
printf '# 01: Legacy archive\n**Effort:** api-v2\n**Blocked by:** banana\n**Check:** x\n' > "$REPO/.workflow/done/api-v2/01-legacy.md"
check 'archived malformed blocker warns instead of failing' 1 run
contains 'archived malformed blocker warning' "malformed blocker 'banana'" "$TMP/err"
setup all-fields
cat > "$REPO/.workflow/tasks/01-contract.md" <<'EOF'
# 01: Full task contract
**Effort:** api-v2
**Task type:** spike
**Base commit:** <commit-sha>
**Started:** 2026-10-07T12:00:00Z
**Finished:** 2026-10-07T13:00:00Z
**Status:** paused
**Delivers:** Measured answer
**Blocked by:** None
**Files:** src/main.sh
**Read first:** src/main.sh
**Check:** `true` → ok
**Question:** Which option works?
**Time box:** 30 minutes

- [ ] Investigate
EOF
check 'all contract fields and draft Base are accepted without warnings' 0 run
for task_type in feature bugfix refactor; do
  printf '# 02: Enum check\n**Effort:** api-v2\n**Task type:** %s\n**Blocked by:** None\n**Check:** passes\n' "$task_type" > "$REPO/.workflow/tasks/02-type.md"
  check "Task type $task_type accepted" 0 run
done
printf '# 02: Enum check\n**Effort:** api-v2\n**Task type:** invalid\n**Blocked by:** None\n**Check:** passes\n' > "$REPO/.workflow/tasks/02-type.md"
check 'invalid Task type enum rejected' 2 run
contains 'Task type diagnostic' "invalid Task type 'invalid'" "$TMP/err"
setup empty-check-list; printf '# 01: Empty Check\n**Effort:** api-v2\n**Check:**\n\n- [ ] unrelated\n' > "$REPO/.workflow/tasks/01-empty.md"
check 'unrelated checklist cannot satisfy empty required Check' 2 run

setup invalid-date; sed -i 's/2026-01-31/2026-02-30/' "$REPO/.workflow/decisions.md"
check 'invalid calendar date' 2 run
setup timestamp; sed -i 's/2026-01-31/2026-01-31T12:34:56.123+02:00/' "$REPO/.workflow/decisions.md"
check 'ISO8601 timestamp decision heading' 0 run
setup bad-mine; sed -i 's/Mine:\*\* yes/Mine:** maybe/' "$REPO/.workflow/decisions.md"
check 'invalid decision owner' 2 run
setup missing-decision-field; sed -i '/Instead of:/d' "$REPO/.workflow/decisions.md"
check 'decision missing required field' 2 run
setup empty-decision-field; sed -i 's/Because:\*\* .*/Because:**/' "$REPO/.workflow/decisions.md"
check 'empty decision field' 2 run
setup duplicate-decision; printf '\n- **Mine:** no\n' >> "$REPO/.workflow/decisions.md"
check 'duplicate decision field' 2 run
setup no-entries; printf '# Decisions\n' > "$REPO/.workflow/decisions.md"
check 'missing Entries section' 2 run
setup empty-entries; printf '# Decisions\n\n## Entries\n' > "$REPO/.workflow/decisions.md"
check 'empty workflow and decision entries' 0 run
setup examples; cat >> "$REPO/.workflow/decisions.md" <<'EOF'

```markdown
## malformed example
- **Mine:** invalid
```
<!--
## malformed comment
-->
### Notes
More context.
EOF
check 'fenced examples comments and subsections ignored' 0 run
setup missing-decisions; rm "$REPO/.workflow/decisions.md"
check 'missing decisions warning' 1 run
check 'strict promotes warnings' 2 run --strict
check 'JSON warning diagnostics' 1 run --format=json
contains 'structured issue context' '"file":".workflow/decisions.md","line":1' "$TMP/out"
setup missing-tasks; rmdir "$REPO/.workflow/tasks"
check 'missing task directory warning' 1 run
REPO="$TMP/absent"; mkdir -p "$REPO"
check 'missing workflow directory error' 2 run
REPO="$TMP/non-git"; mkdir -p "$REPO/.workflow/tasks"; printf '# Decisions\n\n## Entries\n' > "$REPO/.workflow/decisions.md"
check 'pwd fallback outside git' 0 run

setup crlf; task 01-crlf 1
awk '{printf "%s\r\n",$0}' "$REPO/.workflow/tasks/01-crlf.md" > "$REPO/crlf.tmp"; mv "$REPO/crlf.tmp" "$REPO/.workflow/tasks/01-crlf.md"
check 'CRLF warning' 1 run
check 'confirmation decline' 1 decline_fix
check 'EOF confirmation decline' 1 closed_fix
check 'confirmed formatting repair' 0 confirm_fix
check 'repair remains valid' 0 run
if grep -q $'\r$' "$REPO/.workflow/tasks/01-crlf.md"; then printf 'not ok - repair removed CRLF\n'; FAIL=$((FAIL+1)); else printf 'ok - repair removed CRLF\n'; PASS=$((PASS+1)); fi
setup semantic-fix; task 01-bad 1 99
check '--fix does not invent semantic repairs' 2 run --fix

printf '\n%d passed; %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
