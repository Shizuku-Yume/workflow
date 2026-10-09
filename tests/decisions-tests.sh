#!/usr/bin/env bash
# Standalone integration tests: Bash drives the CLI; Python asserts actual JSON.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/workflow-decisions"
for dependency in python3 git; do
  command -v "$dependency" >/dev/null || { printf 'Missing test dependency: %s\n' "$dependency" >&2; exit 1; }
done
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
WORK="$TMP/fallback"
GITROOT="$TMP/project"
mkdir -p "$WORK/.workflow" "$GITROOT/.workflow" "$GITROOT/src/nested"
# Make fallback discovery independent of the caller's Git environment.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
export GIT_CEILING_DIRECTORIES="$TMP"
CWD="$WORK"
RUNNER=("$CLI")
OUT="$TMP/stdout"
ERR="$TMP/stderr"
STATUS=0
CHECKS=0
FAILURES=0
CASE=

fail() {
  FAILURES=$((FAILURES + 1))
  printf 'FAIL [%s]: %s\n' "$CASE" "$*" >&2
  printf '  status: %s\n  command:' "$STATUS" >&2
  printf ' %q' "${LAST_COMMAND[@]}" >&2
  printf '\n  cwd: %s\n--- stdout ---\n' "$CWD" >&2
  cat "$OUT" >&2
  printf '\n--- stderr ---\n' >&2
  cat "$ERR" >&2
  printf '\n--- end ---\n' >&2
}
check() {
  local description=$1
  shift
  CHECKS=$((CHECKS + 1))
  if ! "$@"; then fail "$description"; fi
}
run() {
  CASE=$1
  shift
  LAST_COMMAND=("${RUNNER[@]}" "$@")
  if (cd "$CWD" && "${LAST_COMMAND[@]}") >"$OUT" 2>"$ERR"; then
    STATUS=0
  else
    STATUS=$?
  fi
}
expect_status() { check "expected exit $1, received $STATUS" test "$STATUS" -eq "$1"; }
quiet() { check 'valid input must not warn on stderr' test ! -s "$ERR"; }
stdout_empty() { check 'usage/file errors must not write stdout' test ! -s "$OUT"; }
contains() { check "$1 must contain literal $2" grep -Fq -- "$2" "$1"; }
json() {
  local description=$1 source=$2
  CHECKS=$((CHECKS + 1))
  if ! python3 -c 'import json, pathlib, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
exec(compile(sys.argv[2], "JSON assertion", "exec"))
' "$OUT" "$source" "$ERR"; then fail "$description"; fi
}
listing() { run "$1" "${@:2}" --format json; expect_status 0; }
usage_error() {
  run "$@"
  expect_status 2
  stdout_empty
  contains "$ERR" 'Error:'
}
fixture() { cp "$ROOT/tests/fixtures/$1" "$WORK/.workflow/decisions.md"; }
count() { json "expected $1 result(s)" "assert isinstance(d, list) and len(d) == $1, d"; }

# Help works before any log exists, both directly and through dispatch.
for help in --help -h help; do
  run "help $help without a log" "$help"
  expect_status 0
  quiet
  contains "$OUT" 'Usage:'
  contains "$OUT" 'Examples:'
  contains "$OUT" 'search auth --field Because'
done
RUNNER=("$ROOT/bin/workflow" decisions)
run 'workflow decisions dispatch help' --help
expect_status 0
quiet
contains "$OUT" 'workflow decisions'
RUNNER=("$CLI")

# Invalid usage must fail independently of file existence.
usage_error 'unknown option' --unknown-option
usage_error 'unknown short option' -x
usage_error 'unknown command' unknown-command
usage_error 'unsupported output format' --format yaml
usage_error 'empty output format' --format ''
usage_error 'empty after value' --after ''
usage_error 'empty before value' --before ''
usage_error 'empty field value' search auth --field ''
usage_error 'apply without fix' --apply
usage_error 'field without search' --field Because
usage_error 'missing search term' search
usage_error 'empty search term' search ''
usage_error 'unquoted extra search term' search auth tokens
usage_error 'list extra argument' list extra
usage_error 'validate extra argument' validate extra
usage_error 'recent extra argument' recent 1 2
usage_error 'fix with search' search auth --fix
usage_error 'fix with recent' recent --fix
usage_error 'fix with date filter' --fix --after 2026-01-01
for option in --format --after --before --field; do
  usage_error "$option missing value" "$option"
  usage_error "$option option-as-value" "$option" --no-color
done
for n in 0 -1 1.5 abc 1000000000; do usage_error "invalid recent count $n" recent "$n"; done
for label in Invalid 'Because:' 'Revisit'; do
  usage_error "invalid field $label" search auth --field "$label"
done
for command in list validate; do
  run "$command missing log" "$command" --format json
  expect_status 1
  stdout_empty
  contains "$ERR" 'Error:'
  contains "$ERR" 'decisions.md'
done
run 'fix missing log' --fix --format json
expect_status 1
stdout_empty
contains "$ERR" 'Error:'

# Empty files and an empty canonical template are valid, with no phantom entry.
: > "$WORK/.workflow/decisions.md"
listing 'empty file'
count 0
quiet
run 'empty file validate' validate --format json
expect_status 0
quiet
json 'valid empty report' 'assert d == {"valid": True, "decisions": 0, "errors": 0, "warnings": 0}, d'
cat > "$WORK/.workflow/decisions.md" <<'EOF'
# Decisions

Document fields here, not entries:
- **Decided:** example
- **Instead of:** example
- **Because:** example

## Entries

<!--
## 2099-01-01 - Hidden example
- **Decided:** not real
-->
```markdown
## 2099-01-02 - Fenced example
- **Decided:** not real
```
EOF
listing 'empty canonical template ignores field documentation and examples'
count 0
quiet
run 'empty canonical template validates' validate --format json
expect_status 0
quiet
json 'empty template report' 'assert d == {"valid": True, "decisions": 0, "errors": 0, "warnings": 0}, d'

# The rich fixture combines preamble, two fence styles, comments and subheadings.
fixture decisions-multiline.md
listing 'canonical rich fixture'
quiet
json 'complete canonical schema, append order, text and paragraphs' 'assert len(d) == 2, d
assert [x["id"] for x in d] == [2, 1], d
assert [x["line"] for x in d] == [40, 21], d
assert [x["date"] for x in d] == ["2026-02-01", "2026-01-01"], d
assert [x["title"] for x in d] == ["Persistence boundary", "Authentication boundary"], d
keys = {"Decided", "Instead of", "Because", "Mine", "Revisit when"}
assert all(set(x) == {"id", "line", "date", "title", "fields"} and set(x["fields"]) == keys for x in d), d
assert d[0]["fields"] == {"Decided": "Store auth records in files.", "Instead of": "A database.", "Because": "Volume is small.", "Mine": "yes", "Revisit when": "Volume grows."}, d[0]
assert d[1]["fields"] == {"Decided": "Use bearer tokens.\nKeep the token opaque.", "Instead of": "Session cookies.", "Because": "AUTH needs a stable interface.\nThis rationale spans multiple lines.\n\nA second paragraph mentions \"quotes\" and C:\\auth\\tokens.\n- A nested list supplies more evidence.", "Mine": "no", "Revisit when": "The threat model changes."}, d[1]'
cp "$OUT" "$TMP/rich.json"
run 'plain output retains multiline text' list --no-color
expect_status 0
quiet
contains "$OUT" 'This rationale spans multiple lines.'
contains "$OUT" 'A second paragraph mentions "quotes" and C:\auth\tokens.'
check 'no ANSI escapes with no-color' python3 -c 'import pathlib,sys; assert b"\x1b" not in pathlib.Path(sys.argv[1]).read_bytes()' "$OUT"
run 'canonical rich validation without warnings' validate --format json
expect_status 0
quiet
json 'canonical valid report' 'assert d == {"valid": True, "decisions": 2, "errors": 0, "warnings": 0}, d'
listing 'explicit recent one' recent 1
json 'newest append entry is Persistence' 'assert len(d) == 1 and d[0]["id"] == 2 and d[0]["title"] == "Persistence boundary", d'
listing 'search mixed case everywhere' search aUtH
count 2
quiet
listing 'Because auth matches only Authentication' search auth --field Because
json 'Because restrictions' 'assert len(d) == 1 and d[0]["id"] == 1, d'
listing 'Mine cannot match other fields' search auth --field Mine
count 0
listing 'Decided only' search auth --field dEcIdEd
json 'Decided restriction' 'assert len(d) == 1 and d[0]["id"] == 2, d'
listing 'Instead of multiword field' search cookies --field 'INSTEAD OF'
json 'Instead of restriction' 'assert len(d) == 1 and d[0]["id"] == 1, d'
listing 'Revisit when multiword field' search threat --field 'revisit WHEN'
json 'Revisit restriction' 'assert len(d) == 1 and d[0]["id"] == 1, d'
listing 'Mine actual match' search YES --field mine
json 'Mine value match' 'assert len(d) == 1 and d[0]["id"] == 2, d'
listing 'Title field search' search authentication --field TITLE
json 'Title restriction' 'assert len(d) == 1 and d[0]["id"] == 1, d'
listing 'Date field search' search 2026-02 --field date
json 'Date restriction' 'assert len(d) == 1 and d[0]["id"] == 2, d'
listing 'Title does not search rationale' search stable --field Title
count 0
listing 'literal backslash search' search 'C:\AUTH\TOKENS' --field Because
json 'literal backslash preserved through command arguments' 'assert len(d) == 1 and d[0]["id"] == 1, d'
listing 'literal quote search' search '"quotes"'
count 1
run 'literal nested-list punctuation' search --field Because --format json -- '- A nested list'
expect_status 0
count 1
for term in 'AUTH.*' '[Aa]UTH' '^AUTH' 'tokens$' 'C:\\auth\\tokens'; do
  listing "not regex: $term" search "$term"
  count 0
done
listing 'ignored examples not searchable' search '2099'
count 0
listing 'subheading context excluded from fields' search 'Context before the first field'
count 0
listing 'inline comment excluded' search 'inline comment'
count 0
listing 'canonical same-date inclusive bounds' --after 2026-01-01 --before 2026-01-01
json 'same-day selection' 'assert len(d) == 1 and d[0]["id"] == 1, d'

# Nested Git discovery must ignore a tempting local log and use the root log.
git init -q "$GITROOT"
cp "$WORK/.workflow/decisions.md" "$GITROOT/.workflow/decisions.md"
mkdir -p "$GITROOT/src/nested/.workflow"
: > "$GITROOT/src/nested/.workflow/decisions.md"
CWD="$GITROOT/src/nested"
listing 'direct binary resolves nested Git root'
quiet
check 'nested direct output equals fallback output' cmp -s "$OUT" "$TMP/rich.json"
RUNNER=("$ROOT/bin/workflow" decisions)
listing 'workflow dispatch resolves nested Git root'
quiet
check 'nested dispatch output equals fallback output' cmp -s "$OUT" "$TMP/rich.json"
run 'dispatch validates root log' validate --format json
expect_status 0
quiet
json 'dispatch validation report' 'assert d == {"valid": True, "decisions": 2, "errors": 0, "warnings": 0}, d'
usage_error 'dispatch rejects unknown option' --unknown-option
RUNNER=("$CLI")
CWD="$WORK"

# Timezone offsets, fractional seconds, UTC defaults and Gregorian leap dates.
fixture decisions-dates.md
listing 'all six date fixture entries'
count 6
quiet
json 'date strings retained and ordering is append rather than date sort' 'assert [x["id"] for x in d] == [6,5,4,3,2,1], d
assert d[0]["date"] == "2024-02-29" and d[-1]["date"] == "2025-12-31T23:30:00-02:00", d'
run 'date fixture validates' validate --format json
expect_status 0
quiet
json 'all date forms valid' 'assert d == {"valid": True, "decisions": 6, "errors": 0, "warnings": 0}, d'
listing 'UTC whole January day' --after 2026-01-01 --before 2026-01-01
json 'negative offset in day, positive offset out, fractional last second in' 'assert [x["id"] for x in d] == [4,3,1], d'
listing 'previous UTC day catches positive offset' --after 2025-12-31 --before 2025-12-31
json 'positive offset crosses midnight' 'assert [x["id"] for x in d] == [2], d'
listing 'before whole day includes fractional tail but not next midnight' --before 2026-01-01
json 'whole-day upper bound' 'assert [x["id"] for x in d] == [6,4,3,2,1], d'
listing 'after includes exact next midnight' --after 2026-01-02T00:00Z
json 'minute timestamp inclusive' 'assert [x["id"] for x in d] == [5], d'
listing 'offset bounds compare instants' --after 2026-01-01T03:30:00+02:00 --before 2025-12-31T23:30:00-02:00
json 'equal offset bounds inclusive' 'assert [x["id"] for x in d] == [1], d'
listing 'fractional equal bounds inclusive' --after 2026-01-01T23:59:59.5Z --before 2026-01-01T23:59:59.500Z
json 'fraction equality' 'assert [x["id"] for x in d] == [4], d'
listing 'fractional lower bound excludes earlier fraction' --after 2026-01-01T23:59:59.6Z --before 2026-01-01
count 0
listing 'timezone-less timestamp is UTC' --after 2026-01-01T00:00 --before 2026-01-01T00:00:00
json 'timezone-less equal bound' 'assert [x["id"] for x in d] == [3], d'
listing 'valid Gregorian leap day' --after 2024-02-29 --before 2024-02-29
json 'leap day selected' 'assert [x["id"] for x in d] == [6], d'
listing 'valid century leap bound' --after 2000-02-29 --before 2000-02-29
count 0
for date in 2026-02-30 2023-02-29 1900-02-29 0000-01-01 2026-00-01 2026-13-01 2026-01-00 2026-04-31 2026-1-01 2026-01-01junk 2026-01-01T24:00 2026-01-01T12:60 2026-01-01T12:00:60Z 2026-01-01T12:00:00.Z 2026-01-01T12:00+24:00 2026-01-01T12:00+01:60 2026-01-01T12:00+0100; do
  usage_error "invalid after date $date" --after "$date"
  usage_error "invalid before date $date" --before "$date"
done
usage_error 'reversed date-only range' --after 2026-02-02 --before 2026-02-01
usage_error 'reversed fractional timestamp range' --after 2026-01-01T00:00:00.2Z --before 2026-01-01T00:00:00.1Z

# No truncation at 100 entries; rationale paragraphs still searchable throughout.
fixture decisions-large.md
listing 'large complete listing'
quiet
json 'all 120 complete decisions, line references, multiline paragraphs' 'assert len(d) == 120, len(d)
assert [x["id"] for x in d] == list(range(120, 0, -1)), d
for x in d:
    n = x["id"]
    assert x["title"] == f"Decision {n:03d}", x
    assert x["line"] == 7 + (n - 1) * 11, x
    assert x["fields"]["Because"] == f"Measurement {n:03d} favors this approach.\nContinued rationale for decision {n:03d}.\n\nAuthentication appears in this paragraph.", x'
listing 'recent defaults to ten on large log' recent
json 'default ten newest append entries' 'assert [x["id"] for x in d] == list(range(120,110,-1)), d'
listing 'large explicit newest one' recent 1
json 'large recent one' 'assert len(d) == 1 and d[0]["id"] == 120, d'
listing 'large explicit subset thirty' recent 30
json 'thirty newest entries' 'assert [x["id"] for x in d] == list(range(120,90,-1)), d'
listing 'large count exceeding file size' recent 200
count 120
listing 'large multiline paragraph search' search authentication --field Because
count 120
quiet
listing 'large thirty-day date subset' --after 2026-01-01 --before 2026-01-30
json 'thirty date-bound entries' 'assert [x["id"] for x in d] == list(range(30,0,-1)), d'
run 'large validation' validate --format json
expect_status 0
quiet
json 'large valid report' 'assert d == {"valid": True, "decisions": 120, "errors": 0, "warnings": 0}, d'

# Malformed entries are counted once each; unrelated valid entries survive.
fixture decisions-malformed.md
listing 'malformed listing warns and continues'
json 'all five entries retained, undated null, duplicate reason retained' 'assert [x["id"] for x in d] == [5,4,3,2,1], d
assert d[0]["title"] == "Valid after malformed" and d[-1]["title"] == "Valid before malformed", d
assert d[2]["date"] is None, d[2]
assert d[2]["fields"]["Because"] == "First reason.\nA duplicate reason must also be retained.", d[2]'
contains "$ERR" 'Warning:'
contains "$ERR" 'invalid ISO-8601 date'
contains "$ERR" 'duplicate Because field'
contains "$ERR" 'missing or empty Because field'
listing 'search still reaches final valid malformed-fixture entry' search 'Continue parsing the entire log' --field Because
json 'continued after malformed entries' 'assert len(d) == 1 and d[0]["id"] == 5, d'
listing 'date filter skips unusable dates' --after 2026-01-01
json 'invalid and null dates excluded only from date-filtered results' 'assert [x["id"] for x in d] == [5,4,1], d'
contains "$ERR" 'no usable date'
run 'malformed validation JSON' validate --format json
expect_status 1
json 'exactly three malformed entries, not number of diagnostics' 'assert set(d) == {"valid", "decisions", "errors", "warnings"}, d
assert d["valid"] is False and d["decisions"] == 5 and d["errors"] == 3, d
assert isinstance(d["warnings"], int) and d["warnings"] > d["errors"], d'
json 'warning count matches stderr diagnostics' 'assert d["warnings"] == sum(line.startswith("Warning:") for line in pathlib.Path(sys.argv[3]).read_text().splitlines()), d'
contains "$ERR" 'Warning:'
run 'malformed validation plain' validate --no-color
expect_status 1
contains "$OUT" '3 malformed'
contains "$ERR" 'Warning:'

# Legacy top-level Decided boundaries accept leading dates and optional Date.
cat > "$WORK/.workflow/decisions.md" <<'EOF'
# Legacy decisions

- **Decided:** 2026-05-01 - Preserve prefix date.
  - **Instead of:** Erase history.
  - **Because:** The first rationale.
    Continued legacy rationale.

    A second legacy paragraph.
  - **Mine:** no
  - **Revisit when:** Requirements change.

- **Decided:** Use an explicit date field.
  - **Date:** 2026-05-02T12:34:56.25Z
  - **Instead of:** Force dates into prose.
  - **Because:** Optional dates are supported.
  - **Mine:** yes
  - **Revisit when:** Review the format.

- **Decided:** Keep a genuinely undated choice.
  - **Instead of:** Invent a date.
  - **Because:** Missing optional dates are not malformed legacy entries.
  - **Mine:** no
  - **Revisit when:** A date is known.
EOF
listing 'legacy prefix, Date field and undated entry'
quiet
json 'legacy complete fields and nullable date' 'assert [x["id"] for x in d] == [3,2,1], d
assert [x["date"] for x in d] == [None, "2026-05-02T12:34:56.25Z", "2026-05-01"], d
assert all(set(x["fields"]) == {"Decided", "Instead of", "Because", "Mine", "Revisit when"} for x in d), d
assert d[2]["fields"]["Decided"] == "2026-05-01 - Preserve prefix date.", d[2]
assert d[2]["fields"]["Because"] == "The first rationale.\nContinued legacy rationale.\n\nA second legacy paragraph.", d[2]'
listing 'legacy Date field searchable' search 2026-05-02 --field Date
json 'legacy Date metadata' 'assert len(d) == 1 and d[0]["id"] == 2, d'
listing 'legacy filtered prefix date' --after 2026-05-01 --before 2026-05-01
json 'legacy prefix date filter' 'assert len(d) == 1 and d[0]["id"] == 1, d'
contains "$ERR" 'no usable date'
run 'legacy optional undated entry validates' validate --format json
expect_status 0
quiet
json 'legacy optional date is valid' 'assert d == {"valid": True, "decisions": 3, "errors": 0, "warnings": 0}, d'

# Optional Effort tags: filtering, field search, JSON, text, and validation.
cat > "$WORK/.workflow/decisions.md" <<'EOF'
# Decisions

## Entries

## 2026-06-01 - Tagged entry

- **Decided:** Use the queue.
- **Instead of:** Direct calls.
- **Because:** Load spikes.
- **Mine:** yes
- **Revisit when:** Load flattens.
- **Effort:** api-v2

## 2026-06-02 - Untagged entry

- **Decided:** Keep polling.
- **Instead of:** Webhooks.
- **Because:** Simplicity.
- **Mine:** no
- **Revisit when:** Latency budget shrinks.
EOF
listing 'effort filter selects tagged entries' --effort api-v2
quiet
count 1
json 'effort filter keeps the tagged entry with its tag' 'assert d[0]["id"] == 1 and d[0]["fields"]["Effort"] == "api-v2", d'
listing 'effort filter with no matches' --effort web
count 0
listing 'recent honours the effort filter' recent 5 --effort api-v2
count 1
listing 'field Effort search' search api-v2 --field effort
count 1
listing 'default search covers the Effort tag' search api-v2
count 1
listing 'untagged entries keep the five-field schema' recent 1
json 'untagged schema unchanged' 'assert set(d[0]["fields"]) == {"Decided", "Instead of", "Because", "Mine", "Revisit when"}, d'
run 'tagged log validates' validate --format json
expect_status 0
quiet
json 'tagged log valid report' 'assert d == {"valid": True, "decisions": 2, "errors": 0, "warnings": 0}, d'
run 'text output shows the tag' list --no-color
expect_status 0
contains "$OUT" 'Effort: api-v2'
for slug in Bad_Slug -alpha 'two words' ''; do usage_error "invalid effort slug '$slug'" --effort "$slug"; done
usage_error 'effort option missing value' --effort
usage_error 'effort option-as-value' --effort --no-color
usage_error 'effort with fix' --fix --effort api-v2
usage_error 'effort with apply' --fix --apply --effort api-v2
sed -i 's/\*\*Effort:\*\* api-v2/**Effort:** Bad_Slug/' "$WORK/.workflow/decisions.md"
run 'malformed effort tag is a validation error' validate --format json
expect_status 1
json 'invalid tag counted as a malformed entry' 'assert d["valid"] is False and d["decisions"] == 2 and d["errors"] == 1, d'
contains "$ERR" 'invalid Effort tag'

# Repair only recognized label syntax. Compare whole files, not partial snippets.
cat > "$WORK/.workflow/decisions.md" <<'EOF'
# Decisions
- Because: preamble example remains untouched

## Entries
<!--
## 2099-01-01 - Commented example
* **because**: do not normalize
-->
```markdown
## 2099-01-02 - Fenced example
  - Because: do not normalize
```

## 2026-06-01 - Repair syntax only
- **Decided:** Keep all contents.
* **instead of**: Rewrite arbitrary text.
  - Because: Preserve this rationale.
  A continued line stays indented.
  - Unknown: an unrecognized nested bullet stays untouched.

  A second paragraph stays indented.
  - **Mine:** no
- **revisit when**: The contents change.

## 2026-06-02 - Content is missing
- **Decided:** Do not fabricate rationale.
- **Instead of:** Guessing.
- **Mine:** yes
- **Revisit when:** The author supplies a reason.
EOF
cp "$WORK/.workflow/decisions.md" "$TMP/repair-before.md"
cat > "$TMP/repair-expected.md" <<'EOF'
# Decisions
- Because: preamble example remains untouched

## Entries
<!--
## 2099-01-01 - Commented example
* **because**: do not normalize
-->
```markdown
## 2099-01-02 - Fenced example
  - Because: do not normalize
```

## 2026-06-01 - Repair syntax only
- **Decided:** Keep all contents.
- **Instead of:** Rewrite arbitrary text.
- **Because:** Preserve this rationale.
  A continued line stays indented.
  - Unknown: an unrecognized nested bullet stays untouched.

  A second paragraph stays indented.
- **Mine:** no
- **Revisit when:** The contents change.

## 2026-06-02 - Content is missing
- **Decided:** Do not fabricate rationale.
- **Instead of:** Guessing.
- **Mine:** yes
- **Revisit when:** The author supplies a reason.
EOF
run 'fix defaults to immutable dry run' --fix --format json
expect_status 0
json 'dry-run repair schema and exact known-label changes' 'assert set(d) == {"dry_run", "repairs", "unresolved_entries", "changes"}, d
assert d["dry_run"] is True and d["repairs"] == 4 and d["unresolved_entries"] == 1, d
assert [x["line"] for x in d["changes"]] == [16,17,22,23], d
assert [x["after"] for x in d["changes"]] == ["- **Instead of:** Rewrite arbitrary text.", "- **Because:** Preserve this rationale.", "- **Mine:** no", "- **Revisit when:** The contents change."], d
assert all(set(x) == {"line", "before", "after"} for x in d["changes"]), d'
check 'dry run preserves every byte' cmp -s "$WORK/.workflow/decisions.md" "$TMP/repair-before.md"
run 'apply safe repairs' --fix --apply --format json
expect_status 0
json 'apply report reflects unresolved content' 'assert d["dry_run"] is False and d["repairs"] == 4 and d["unresolved_entries"] == 1 and len(d["changes"]) == 4, d'
check 'applied file equals expected text including comments, fences and unknown labels' cmp -s "$WORK/.workflow/decisions.md" "$TMP/repair-expected.md"
listing 'repaired contents still complete and missing rationale remains empty'
json 'no invented content; multiline unknown bullet remains rationale' 'assert len(d) == 2 and d[0]["fields"]["Because"] == "", d
assert d[1]["fields"]["Because"] == "Preserve this rationale.\nA continued line stays indented.\n- Unknown: an unrecognized nested bullet stays untouched.\n\nA second paragraph stays indented.", d'
run 'repair apply is idempotent' --fix --apply --format json
expect_status 0
json 'second apply has no changes' 'assert d == {"dry_run": False, "repairs": 0, "unresolved_entries": 1, "changes": []}, d'
check 'idempotent apply preserves every byte' cmp -s "$WORK/.workflow/decisions.md" "$TMP/repair-expected.md"
run 'missing content stays a validation error after fix' validate --format json
expect_status 1
json 'missing content not fabricated' 'assert d["valid"] is False and d["decisions"] == 2 and d["errors"] == 1, d'
fixture decisions-multiline.md
cp "$WORK/.workflow/decisions.md" "$TMP/valid-before.md"
run 'canonical fix no-op' --fix --apply --format json
expect_status 0
quiet
json 'valid canonical repair no-op' 'assert d == {"dry_run": False, "repairs": 0, "unresolved_entries": 0, "changes": []}, d'
check 'no-op apply preserves valid log bytes' cmp -s "$WORK/.workflow/decisions.md" "$TMP/valid-before.md"
fixture decisions-malformed.md
cp "$WORK/.workflow/decisions.md" "$TMP/malformed-before.md"
run 'malformed repair preview cannot invent dates or missing contents' --fix --format json
expect_status 0
json 'malformed dry-run unresolved entry count' 'assert d == {"dry_run": True, "repairs": 0, "unresolved_entries": 3, "changes": []}, d'
check 'malformed dry run is immutable' cmp -s "$WORK/.workflow/decisions.md" "$TMP/malformed-before.md"
run 'malformed apply cannot invent dates or missing contents' --fix --apply --format json
expect_status 0
json 'malformed apply unresolved entry count' 'assert d == {"dry_run": False, "repairs": 0, "unresolved_entries": 3, "changes": []}, d'
check 'malformed no-op apply preserves invalid dates and missing content' cmp -s "$WORK/.workflow/decisions.md" "$TMP/malformed-before.md"

# JSON must escape controls, quotes and backslashes, tolerate CRLF and EOF.
# printf writes real control bytes; Python is used only for output assertions.
{
  printf '# Decisions\r\n\r\n## Entries\r\n\r\n'
  printf '## 2026-07-01T12:34:56.125 - Controls "quoted" \\path\r\n'
  printf -- '- **Decided:** Keep "quotes" and C:\\auth\\tokens.\r\n'
  printf -- '- **Instead of:** Losing bytes.\r\n'
  printf -- '- **Because:** tab\there; control\001byte; backspace\bbyte; formfeed\fbyte; carriage\rinside.\r\n'
  printf '  Continuation after CRLF.\r\n\r\n  Final paragraph.\r\n'
  printf -- '- **Mine:** no\r\n'
  printf -- '- **Revisit when:** No final newline.'
} > "$WORK/.workflow/decisions.md"
listing 'JSON controls, CRLF and final line without newline'
quiet
json 'JSON escaped strings decode to original values' 'assert len(d) == 1 and d[0]["line"] == 5, d
assert d[0]["title"] == "Controls \"quoted\" \\path", d
assert d[0]["date"] == "2026-07-01T12:34:56.125", d
assert d[0]["fields"]["Decided"] == "Keep \"quotes\" and C:\\auth\\tokens.", d
assert d[0]["fields"]["Because"] == "tab\there; control\x01byte; backspace\bbyte; formfeed\fbyte; carriage\rinside.\nContinuation after CRLF.\n\nFinal paragraph.", d
assert d[0]["fields"]["Revisit when"] == "No final newline.", d'
listing 'timezone-less entry timestamp compares in UTC' --after 2026-07-01T12:34:56.125Z --before 2026-07-01T12:34:56.125Z
quiet
count 1
run 'CRLF and no-final-newline fixture validates' validate --format json
expect_status 0
quiet
json 'control fixture is valid' 'assert d == {"valid": True, "decisions": 1, "errors": 0, "warnings": 0}, d'
cp "$WORK/.workflow/decisions.md" "$TMP/crlf-before.md"
run 'canonical CRLF fix no-op preserves final-no-newline bytes' --fix --apply --format json
expect_status 0
quiet
json 'CRLF no-op report' 'assert d == {"dry_run": False, "repairs": 0, "unresolved_entries": 0, "changes": []}, d'
check 'CRLF no-op is byte-identical including EOF' cmp -s "$WORK/.workflow/decisions.md" "$TMP/crlf-before.md"


# Regression coverage for Markdown indentation and multiline fields across fences.
cat > "$WORK/.workflow/decisions.md" <<'EOF'
# Decisions
  ## Entries
  ## 2026-08-01 - Indented first entry
- **Decided:** Preserve boundaries.
- **Instead of:** Merge the entries.
- **Because:** First paragraph.
  ```markdown
<!-- an example comment must not escape this fence
## 2099-01-01 - Not an entry
  ```
  Continuation after the ignored example.
- **Mine:** no
- **Revisit when:** Requirements change.
   ## 2026-08-02 - Indented second entry
- **Decided:** Keep the second entry.
- **Instead of:** Append its fields to the first entry.
- **Because:** Heading indentation is valid Markdown.
- **Mine:** yes
- **Revisit when:** Requirements change.
EOF
listing 'indented headings and field continuation after fences'
quiet
json 'two heading entries remain separate and fence does not discard rationale' 'assert len(d)==2 and [e["date"] for e in d]==["2026-08-02","2026-08-01"], d
assert d[1]["fields"]["Because"]=="First paragraph.\nContinuation after the ignored example.", d'

# Applied repairs retain a log symlink, target permissions and CRLF endings.
{
  printf '# Decisions\r\n## Entries\r\n## 2026-09-01 - Symlink repair\r\n'
  printf -- '* **Decided**: Normalize the label only.\r\n'
  printf -- '- **Instead of:** Replacing the link.\r\n'
  printf -- '- **Because:** Preserve evidence and metadata.\r\n'
  printf -- '- **Mine:** no\r\n'
  printf -- '- **Revisit when:** Requirements change.\r\n'
} > "$WORK/decision-target.md"
chmod 640 "$WORK/decision-target.md"
rm "$WORK/.workflow/decisions.md"
ln -s ../decision-target.md "$WORK/.workflow/decisions.md"
run 'apply repair to CRLF symlink target' --fix --apply --format json
expect_status 0
json 'single structural repair applied' 'assert d["repairs"]==1 and d["unresolved_entries"]==0 and not d["dry_run"], d'
check 'decision log symlink remains a symlink' test -L "$WORK/.workflow/decisions.md"
check 'target mode and CRLF bytes retained' python3 -c 'import pathlib,stat,sys
p=pathlib.Path(sys.argv[1]); b=p.read_bytes()
assert stat.S_IMODE(p.stat().st_mode)==0o640
assert b"- **Decided:** Normalize the label only.\r\n" in b
assert b"\n" not in b.replace(b"\r\n",b"")' "$WORK/decision-target.md"
listing 'repaired symlink remains readable'
quiet
count 1
printf 'workflow-decisions integration: %d checks, %d passed, %d failed\n' "$CHECKS" "$((CHECKS - FAILURES))" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then exit 1; fi
