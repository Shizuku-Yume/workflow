#!/usr/bin/env bash
# Cross-command consistency: every task-reading command must agree on the
# shared grammar. Policy differences are asserted explicitly: doctor reports
# exactly what validate reports (it runs validate), deps only judges the graph,
# and effort counts blocked tasks tolerantly.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="$KIT/bin/workflow"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
PASS=0 FAIL=0
ok() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
no() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
check() {
  local name=$1 expected=$2 actual=0; shift 2
  "$@" > "$TMP/out" 2> "$TMP/err" || actual=$?
  if [ "$actual" = "$expected" ]; then ok "$name"; else no "$name (exit $actual, expected $expected)"; cat "$TMP/out" "$TMP/err" >&2; fi
}
contains() { local name=$1 pattern=$2 file=$3; if grep -qF -- "$pattern" "$file"; then ok "$name"; else no "$name (missing '$pattern')"; cat "$file" >&2; fi; }
not_contains() { local name=$1 pattern=$2 file=$3; if grep -qF -- "$pattern" "$file"; then no "$name (unexpected '$pattern')"; cat "$file" >&2; else ok "$name"; fi; }
json() { local name=$1 expr=$2; if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); $expr" "$TMP/out"; then ok "$name"; else no "$name"; cat "$TMP/out" >&2; fi; }

REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.name Consistency
git -C "$REPO" config user.email consistency@example.com
printf 'root\n' > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm initial
(cd "$REPO" && "$WF" init >/dev/null 2>&1)
mkdir -p "$REPO/.workflow/efforts" "$REPO/.workflow/done/core"
printf '# Effort: core\nPriority: normal\nStatus: active\n' > "$REPO/.workflow/efforts/core.md"
cat > "$REPO/.workflow/tasks/01-a.md" <<'EOF'
# 01: Bold ready
**Effort:** core
**Blocked by:** None
**Check:** ok
EOF
cat > "$REPO/.workflow/tasks/02-b.md" <<'EOF'
# 02: Plain blocked by one
Effort: core
Blocked by: 01
Check: ok
EOF
cat > "$REPO/.workflow/tasks/03-c.md" <<'EOF'
# 03: Indented continuation
Effort: core
Blocked by:
  01
Check: ok
EOF
cat > "$REPO/.workflow/tasks/04-d.md" <<'EOF'
# 04: Lowercase none, colon outside bold
**Effort**: core
**Blocked by:** none
**Check:** ok
EOF
cat > "$REPO/.workflow/tasks/05-e.md" <<'EOF'
# 05: Missing blocker field
Effort: core
Check: ok
EOF
cat > "$REPO/.workflow/tasks/06-f.md" <<'EOF'
# 06: Missing target
Effort: core
Blocked by: 99
Check: ok
EOF
cat > "$REPO/.workflow/tasks/07-g.md" <<'EOF'
# 07: Archived target
Effort: core
Blocked by: 0008
Check: ok
EOF
cat > "$REPO/.workflow/done/core/08-h.md" <<'EOF'
# 08: Archived
Effort: core
Blocked by: None
Check: ok
EOF

run() { (cd "$REPO" && "$@"); }

check 'tasks json' 0 run "$WF" tasks --format json
json 'tasks blocked map' 'm = {t["number"]: t["blocked"] for t in d}; assert m == {1: False, 2: True, 3: True, 4: False, 5: True, 6: True, 7: False}, m'
json 'colon-outside-bold effort is read' 'assert next(t for t in d if t["number"] == 4)["effort"] == "core"'
json 'continuation reference blocks 03' 'assert next(t for t in d if t["number"] == 3)["blocked"] is True'

check 'next json' 0 run "$WF" next --format json
json 'next ready set matches tasks' 'assert sorted(t["number"] for t in d["ready_tasks"]) == [1, 4, 7], d'
json 'next counts match tasks' 'assert d["task_count"] == 7 and d["blocked_count"] == 4, d'

check 'validate fails on the two content problems' 2 run "$WF" validate --format json
json 'validate error and warning counts' 'assert d["errors"] == 2 and d["warnings"] == 0, d'
json 'validate issue files' 'files = sorted(i["file"] for i in d["issues"]); assert files == [".workflow/tasks/05-e.md", ".workflow/tasks/06-f.md"], files'
json 'validate required message' 'assert any("required Blocked by" in i["message"] for i in d["issues"])'
json 'validate orphan message' 'assert any("orphaned blocker" in i["message"] for i in d["issues"])'

check 'deps check fails for the missing target' 1 run "$WF" deps --check
contains 'deps reports the missing target' 'core/06 references missing blocker task: core/99' "$TMP/err"
check 'deps renders with warnings' 0 run "$WF" deps --format text
not_contains 'deps accepts lowercase none' 'malformed Blocked by' "$TMP/err"

check 'doctor fails' 1 run "$WF" doctor
not_contains 'doctor accepts lowercase none like validate' 'malformed blocker' "$TMP/err"
contains 'doctor reports the missing target' "orphaned blocker '99'" "$TMP/err"
contains 'doctor reports the missing Blocked by' 'required Blocked by' "$TMP/err"

check 'effort status succeeds' 0 run "$WF" effort status core --no-color
contains 'effort blocked count agrees' 'Blocked: 4' "$TMP/out"

check 'lib syntax' 0 bash -n "$KIT/bin/workflow-lib.bash"
for script in workflow workflow-tasks workflow-deps workflow-effort workflow-validate workflow-next; do
  check "sources shared library: $script" 0 grep -q 'workflow-lib.bash' "$KIT/bin/$script"
done

printf '\n%d passed; %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
