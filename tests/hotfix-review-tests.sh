#!/usr/bin/env bash
# Hotfix review integration tests; implementation uses no Python dependency.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$KIT/bin/workflow-hotfix-review"
FIXTURES="$KIT/tests/fixtures/hotfix-review"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; OUT=; ERR=; STATUS=0

repo() { mkdir -p "$1/.workflow"; git -C "$1" init -q; }
run() {
  local dir=$1; shift
  STATUS=0
  (cd "$dir" && "$CLI" "$@") > "$TMP/out" 2> "$TMP/err" || STATUS=$?
  OUT=$(cat "$TMP/out"); ERR=$(cat "$TMP/err")
}
contains() { [[ "$OUT" == *"$1"* ]]; }
omits() { [[ "$OUT" != *"$1"* ]]; }
status() { [ "$STATUS" -eq "$1" ]; }
json_check() { python3 -c "import json,sys; data=json.loads(sys.argv[1]); $1" "$OUT"; }
check() {
  local label=$1; shift
  if "$@"; then PASS=$((PASS+1)); printf 'PASS %s\n' "$label"
  else FAIL=$((FAIL+1)); printf 'FAIL %s\n  stdout: %s\n  stderr: %s\n' "$label" "$OUT" "$ERR"; fi
}

project="$TMP/patterns"; repo "$project"
cp "$FIXTURES/patterns.md" "$project/.workflow/decisions.md"
git -C "$project" remote add origin git@example.test:org/project.git
run "$project"
check 'list succeeds' status 0
for id in 2025-01-01-emergency-patch 2025-02-01-temporary-choice 2025-04-01-mine-workaround 2025-05-01-quick-fix 2025-06-01-several-fixes 2025-08-01-repeated-title-2; do
  check "detects $id" contains "$id"
done
check 'Because-only hotfix mention is ignored' omits '2025-03-01-normal-change'
check 'fenced examples are ignored' omits '2025-01-01-example-hotfix'
check 'commented examples are ignored' omits '2025-01-01-commented-hotfix'
check 'resolved entries omitted by default' omits '2025-07-01-resolved-change'
check 'all fixes in one entry shown' contains 'Hotfix 3: Emergency patch to retry handling'
check 'contextual SHA reference extracted' contains 'Original commit: abcdef1234567'
check 'remote supplies original commit link' contains 'https://example.test/org/project/commit/abcdef1234567'
check 'explicit commit URL preserved' contains 'https://example.test/org/repo/commit/1234abc'
check 'old entries have age in months' contains 'months'
check 'non-TTY output has no ANSI escapes' omits $'\033'
run "$project" --format json
check 'JSON listing succeeds' status 0
check 'JSON contains only unresolved hotfix entries' json_check 'assert len(data)==7 and all(not item["resolved"] for item in data)'
check 'multiple hotfixes and commit references retained in JSON' json_check 'item=next(i for i in data if i["id"]=="2025-06-01-several-fixes"); assert len(item["hotfixes"])==3 and len(item["commits"])==2'
check 'JSON escapes quotation marks' json_check 'item=next(i for i in data if i["id"]=="2025-06-01-several-fixes"); assert "\"cache\"" in item["decided"]'
check 'ISO heading dates supply numeric age' json_check 'assert all(isinstance(i["age_days"],int) for i in data)'
run "$project" --all --format=json --no-color
check 'resolved entry included with --all' json_check 'assert len(data)==8 and next(i for i in data if i["id"]=="2025-07-01-resolved-change")["resolved"]'
check 'duplicate IDs stable across filtering' json_check 'assert any(i["id"]=="2025-08-01-repeated-title-2" for i in data)'
mkdir -p "$project/deep/subdir"
run "$project/deep/subdir" --format json
check 'finds git root from subdirectory' json_check 'assert len(data)==7'

run "$project" --mark-resolved 2025-01-01-emergency-patch
check 'resolution succeeds' status 0
check 'resolution reports ID' contains 'Marked hotfix resolved: 2025-01-01-emergency-patch'
check 'decision text preserved' grep -qF 'HOTFIX shipped (commit abcdef1234567).' "$project/.workflow/decisions.md"
check 'original revisit condition preserved' grep -qF 'durable implementation lands.' "$project/.workflow/decisions.md"
run "$project"
check 'marked entry omitted from default review' omits '2025-01-01-emergency-patch'
cp "$project/.workflow/decisions.md" "$TMP/once.md"
run "$project" --mark-resolved 2025-01-01-emergency-patch --format json
check 'repeat resolution remains successful' status 0
check 'resolution JSON is valid' json_check 'assert data=={"id":"2025-01-01-emergency-patch","resolved":True}'
check 'resolution is idempotent' cmp -s "$TMP/once.md" "$project/.workflow/decisions.md"
run "$project" --mark-resolved 2025-06-01-several-fixes
check 'entry containing multiple fixes can be resolved' status 0
run "$project" --format json
check 'all fixes in resolved entry filtered' json_check 'assert not any(i["id"]=="2025-06-01-several-fixes" for i in data)'
cp "$project/.workflow/decisions.md" "$TMP/before-invalid.md"
run "$project" --mark-resolved missing-id
check 'unknown ID errors' status 1
check 'failed resolution leaves decisions unchanged' cmp -s "$TMP/before-invalid.md" "$project/.workflow/decisions.md"
run "$project" --mark-resolved 2025-03-01-normal-change
check 'non-hotfix decision cannot be marked' status 1

legacy="$TMP/legacy"; repo "$legacy"
cp "$FIXTURES/legacy.md" "$legacy/.workflow/decisions.md"
run "$legacy" --all --format json
check 'legacy fields parse despite indentation' json_check 'assert len(data)==3'
check 'legacy ISO timestamp with timezone supplies age' json_check 'assert data[0]["date"]=="2025-01-01T12:30:00+02:00" and isinstance(data[0]["age_days"],int)'
check 'malformed timestamp safely reports unknown age' json_check 'assert data[2]["age_days"] is None and "unknown" in data[2]["age"]'
check 'empty Decided fields ignored' json_check 'assert not any("no actual decision" in i["decided"] for i in data)'
run "$legacy" --mark-resolved 2025-99-99-temporary-shim
check 'entry missing Revisit field can be resolved' status 0
run "$legacy" --format json
check 'new resolution field recognized in legacy entry' json_check 'assert len(data)==1'

# Generate relative ISO timestamps to exercise all age units without fixed-clock assumptions.
ages="$TMP/ages"; repo "$ages"
NOW=$(date +%s)
iso_epoch() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
for pair in '2 days' '14 weeks' '90 months'; do
  days=${pair%% *}; unit=${pair#* }; stamp=$(iso_epoch "$((NOW-days*86400))")
  printf '## 2025-01-01 - Age %s\n- **Decided:** %s temporary fix.\n- **Mine:** yes.\n\n' "$unit" "$stamp" >> "$ages/.workflow/decisions.md"
done
run "$ages"
check 'shows age in days' contains 'Age: 2 days'
check 'shows age in weeks' contains 'Age: 2 weeks'
check 'shows age in months' contains 'Age: 3 months'
run "$ages" --format json
check 'Decided timestamp takes precedence over heading date' json_check 'assert [i["age_days"] for i in data]==[2,14,90]'

empty="$TMP/empty"; repo "$empty"; : > "$empty/.workflow/decisions.md"
run "$empty"
check 'empty file handled' status 0
check 'empty file explains result' contains 'No unresolved hotfixes'
run "$empty" --format json
check 'empty file emits empty JSON array' json_check 'assert data==[]'
missing="$TMP/missing"; mkdir -p "$missing"
run "$missing"
check 'missing workflow directory handled outside git' status 0
check 'missing file explained' contains 'No decisions file'
mkdir "$missing/.workflow"
run "$missing" --format json
check 'missing decisions emits valid empty JSON' json_check 'assert data==[]'
run "$missing" --mark-resolved missing
check 'resolution requires a decisions file' status 1
check 'resolution error goes to stderr' test -n "$ERR"

fallback="$TMP/fallback"; mkdir -p "$fallback/.workflow"
printf '%s' '- **Decided:** quick fix without final newline' > "$fallback/.workflow/decisions.md"
run "$fallback" --format json
check 'pwd fallback and no-final-newline entry handled' json_check 'assert len(data)==1'
run "$fallback" --mark-resolved quick-fix-without-final-newline
check 'no-final-newline entry can be resolved' status 0
run "$fallback" --format json
check 'resolution recognized after no-final-newline update' json_check 'assert data==[]'
run "$fallback" --help
check 'help exits successfully' status 0
check 'help explains hotfixes and examples' contains 'Examples:'
run "$fallback" --unknown
check 'unknown flag returns usage error' status 2
check 'usage errors have no stdout' test -z "$OUT"
check 'usage errors go to stderr' test -n "$ERR"
run "$fallback" --mark-resolved
check 'missing resolution argument returns usage error' status 2
run "$fallback" --mark-resolved=
check 'empty resolution argument returns usage error' status 2
run "$fallback" --format xml
check 'invalid output format returns usage error' status 2
run "$fallback" --all --mark-resolved anything
check 'incompatible action flags return usage error' status 2
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
