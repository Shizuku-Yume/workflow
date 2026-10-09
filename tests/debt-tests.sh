#!/usr/bin/env bash
# Dedicated workflow-debt integration suite; invoked by tests/cli-tests.sh.
set -euo pipefail
KIT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$KIT/bin/workflow-debt"
FIXTURES="$KIT/tests/fixtures/debt"
TEMP=$(mktemp -d)
trap 'rm -rf -- "$TEMP"' EXIT
PROJECT="$TEMP/project"
mkdir -p "$PROJECT"
PASSED=0 FAILED=0 OUTPUT='' EDITOR_TEST=''
pass() { printf 'PASS: debt %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: debt %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
expect() {
  local expected=$1 label=$2 actual=0; shift 2
  if OUTPUT=$(cd "$PROJECT" && env EDITOR="$EDITOR_TEST" VISUAL= NO_COLOR= "$CLI" "$@" 2>"$TEMP/stderr"); then actual=0; else actual=$?; fi
  if [ "$actual" -eq "$expected" ]; then pass "$label"; else
    fail "$label (expected exit $expected, got $actual)"
    printf '%s\n' "$OUTPUT" >&2
    cat "$TEMP/stderr" >&2
  fi
}
contains() { if [[ "$OUTPUT" == *"$2"* ]]; then pass "$1"; else fail "$1 (missing '$2')"; fi; }
not_contains() { if [[ "$OUTPUT" != *"$2"* ]]; then pass "$1"; else fail "$1 (unexpected '$2')"; fi; }
unchanged() { if cmp -s "$TEMP/before" "$PROJECT/.workflow/technical-debt.md"; then pass "$1"; else fail "$1"; fi; }
file_contains() { local text; text=$(cat "$PROJECT/.workflow/technical-debt.md"); if [[ "$text" == *"$2"* ]]; then pass "$1"; else fail "$1 (missing '$2')"; fi; }
fixture() { mkdir -p "$PROJECT/.workflow"; cp "$FIXTURES/technical-debt.md" "$PROJECT/.workflow/technical-debt.md"; }

expect 0 'global help succeeds without workflow directory' --help
contains 'help includes editor instructions' '$EDITOR'
contains 'help includes resolution examples' '--commit abc1234 --pr 42'
expect 0 'subcommand help ignores missing ID' resolve --help
expect 0 'missing file list is graceful' list
contains 'missing list describes next step' 'No debt file'
expect 0 'default list accepts no-color' --no-color
expect 0 'missing list JSON is empty array' --format json
if [ "$OUTPUT" = '[]' ]; then pass 'empty JSON array'; else fail 'empty JSON array'; fi
expect 2 'unknown command is usage error' unknown
expect 2 'unknown flag is usage error' list --unknown
expect 2 'missing priority value is usage error' list --priority
expect 2 'unknown priority is usage error' list --priority urgent
expect 2 'missing format value is usage error' list --format
expect 2 'unsupported format is usage error' list --format yaml
if [[ "$(cat "$TEMP/stderr")" == Error:* ]]; then pass 'usage errors go to stderr with Error prefix'; else fail 'usage error prefix'; fi

expect 0 'add creates missing directory and file' add --title 'Repeated Handler!' --location src/api --problem $'First line\nSecond line with literal \\n and C:\\tools' --priority fix-now
file_contains 'title automatically suggests slug ID' '## [repeated-handler] Repeated Handler!'
file_contains 'multiline description preserves backslashes' 'Second line with literal \n and C:\tools'
file_contains 'add writes Added timestamp' '**Added:** '
expect 0 'automatic IDs avoid collisions' add --title 'Repeated Handler!' --location src/db --problem 'Another issue' --priority worth-doing
file_contains 'second slug is unique' '## [repeated-handler-2]'
expect 0 'third priority supported' add --id small --title 'Small issue' --location src/api --problem 'Only matters later' --priority only-if-grows
expect 0 'all priorities list' list
contains 'fix-now listed' 'Priority: fix-now'
contains 'worth-doing listed' 'Priority: worth-doing'
contains 'only-if-grows listed' 'Priority: only-if-grows'
expect 0 'priority filter works' list --priority fix-now
contains 'filter retains requested ID' '[repeated-handler]'
not_contains 'filter omits other priorities' '[small]'
expect 0 'unknown slug fallback is valid' add --title '!!!' --location src/api --problem 'Punctuation-only title'
file_contains 'fallback ID is debt' '## [debt] !!!'
cp "$PROJECT/.workflow/technical-debt.md" "$TEMP/before"
expect 1 'duplicate explicit ID rejected' add --id small --title 'Duplicate ID' --location src/api --problem 'Must not write'
unchanged 'duplicate ID leaves file unchanged'
expect 2 'invalid ID rejected' add --id 'bad[id]' --title 'Invalid ID' --location src/api --problem 'Must not write'
unchanged 'invalid ID leaves file unchanged'
expect 2 'invalid add priority rejected' add --title 'Invalid priority' --location src/api --priority invalid --problem 'Must not write'
unchanged 'invalid priority leaves file unchanged'
expect 2 'empty problem rejected' add --title 'Empty description' --location src/api --problem ' '
unchanged 'empty description leaves file unchanged'
expect 2 'structural metadata injection rejected' add --title 'Injected metadata' --location src/api --problem $'Evidence\n**Status:** resolved'
unchanged 'metadata injection leaves file unchanged'
expect 1 'missing description file rejected' add --title 'Missing description' --location src/api --description-file nonexistent
unchanged 'unreadable description leaves file unchanged'
expect 2 'description source conflict rejected' add --title Conflict --location src/api --description-file - --problem text
expect 2 'missing add option value is usage error' add --title

printf 'Heredoc first line\nHeredoc second line\n' > "$TEMP/description"
expect 0 'description file supports multiple lines' add --title 'Description File' --location src/docs --description-file "$TEMP/description"
file_contains 'file multiline content preserved' $'Heredoc first line\nHeredoc second line'
expect 0 'heredoc stdin description supported' add --title 'Stdin Description' --location src/docs --description-file - < "$TEMP/description"
file_contains 'stdin description created' '## [stdin-description]'

EDITOR_TEST="$FIXTURES/editor.sh --multiline"
expect 0 'editor with arguments supplies multiline description' add --title 'Editor Description' --location src/editor
file_contains 'editor multiline content preserved' 'Editor supplied the second line with literal \n and C:\tools\bin.'
file_contains 'Markdown code fence remains intact' '## [sample] This is code, not a real debt entry.'
expect 0 'editor entry resolves without losing Markdown' resolve editor-description --resolution $'Fixed first line\nFixed second line with \\n' --commit abc1234 --pr https://example.test/team/repo/pull/42
file_contains 'internal Markdown rule preserved on close' $'---\n\nFurther Markdown evidence.'
file_contains 'resolution preserves multiline backslashes' 'Fixed second line with \n'
file_contains 'commit reference recorded' '**Commit:** abc1234'
file_contains 'PR URL recorded' '**PR:** https://example.test/team/repo/pull/42'
EDITOR_TEST=false
cp "$PROJECT/.workflow/technical-debt.md" "$TEMP/before"
expect 1 'editor failure returns runtime error' add --title 'Editor Failed' --location src/editor
unchanged 'editor failure leaves file unchanged'
EDITOR_TEST=''
expect 0 'interactive add supports multiline fallback and default slug' add <<'INPUT'
Interactive multiline

src/interactive

First interactive line.
Second interactive line.
.
Changes become expensive.
Share the implementation.
Small change.
INPUT
file_contains 'interactive title slug generated' '## [interactive-multiline] Interactive multiline'
file_contains 'interactive multiline content preserved' $'First interactive line.\nSecond interactive line.'
expect 0 'noninteractive fallback supports EOF heredoc' add --title 'EOF description' --location src/eof <<'INPUT'
First EOF line.
Second EOF line.
INPUT
file_contains 'EOF multiline content preserved' $'First EOF line.\nSecond EOF line.'
expect 1 'missing interactive input is graceful' add </dev/null

expect 0 'resolve accepts commit and numeric PR' resolve small --resolution 'Shared adapter' --commit deadbeef --pr 17
file_contains 'numeric PR stored with hash prefix' '**PR:** #17'
expect 0 'accept records reason and status' accept repeated-handler-2 --reason 'Required for compatibility'
file_contains 'accepted status written' '**Status:** accepted'
file_contains 'accepted reason written' 'Required for compatibility'
expect 1 'unknown ID resolve fails before prompting' resolve absent </dev/null
expect 1 'unknown ID accept fails before prompting' accept absent </dev/null
expect 1 'closed debt cannot resolve twice' resolve small --resolution Again
expect 2 'resolve needs ID' resolve
expect 2 'accept needs ID' accept
expect 2 'resolve validates commit' resolve debt --resolution Fixed --commit nonhex
expect 2 'resolve validates PR number' resolve debt --resolution Fixed --pr 0
expect 2 'resolve rejects missing PR value' resolve debt --pr
expect 2 'accept rejects resolve-only refs' accept debt --reason Compatibility --commit deadbeef
expect 2 'blank acceptance reason rejected' accept debt --reason ' '
expect 0 'resolve can prompt for resolution' resolve debt <<'INPUT'
Fixed through prompted resolution.
INPUT
file_contains 'prompted resolution persisted' 'Fixed through prompted resolution.'

fixture
expect 0 'grouping and aging parse date-only and offset timestamps' list --by-file --age --no-color
contains 'API location group present' 'Location: src/api'
contains 'database group present' 'Location: src/db'
contains 'legacy group present' 'Location: src/legacy'
contains 'resolved items listed' '[resolved]'
contains 'accepted items listed' '[accepted]'
not_contains 'fenced entry template ignored' '[ID]'
not_contains 'non-TTY output has no ANSI escapes' $'\033'
DAYS=$(( $(date +%s) / 86400 ))
contains 'ISO timestamp age is days since epoch' "Age: $DAYS days"
GROUPS_COUNT=$(printf '%s\n' "$OUTPUT" | awk '/^Location: / {count++} END {print count+0}')
if [ "$GROUPS_COUNT" -eq 3 ]; then pass 'one heading per location'; else fail 'one heading per location'; fi
expect 0 'structured JSON includes metadata and age' list --format json --age
contains 'JSON is an array of objects' '[{"id":'
contains 'JSON location alias parsed' '"location":"src/db"'
contains 'JSON age numeric' "\"age_days\":$DAYS"
contains 'JSON includes multiline description escape' 'routes.\nEvidence'
contains 'JSON includes commit reference' '"commit":"abc1234"'
AGE_COUNT=$(printf '%s\n' "$OUTPUT" | awk -v expected="$DAYS" '{text=$0; while (match(text, /"age_days":[0-9]+/)) {value=substr(text,RSTART,RLENGTH); sub(/.*:/,"",value); if (value+0 == expected) count++; text=substr(text,RSTART+RLENGTH)}} END {print count+0}')
if [ "$AGE_COUNT" -eq 5 ]; then pass 'all ISO date variants have equivalent age'; else fail 'all ISO date variants have equivalent age'; fi
expect 0 'JSON supports grouped option and filtering' list --by-file --priority fix-now --format json
contains 'filtered JSON includes urgent' '"id":"urgent"'
not_contains 'filtered JSON excludes medium' '"id":"medium"'
expect 0 'text format explicit accepted' list --format text

# Resolve/accept are stored under their matching status sections, not just relabeled.
expect 0 'fixture active entry resolves' resolve urgent --resolution 'Refactored validation' --pr '#9'
expect 0 'fixture active entry accepted' accept medium --reason 'Not planned to fix'
if awk '/^## Status:/ {section=$0} /^## \[urgent\]/ && section != "## Status: Resolved" {bad=1} /^## \[medium\]/ && section != "## Status: Accepted" {bad=1} END {exit bad}' "$PROJECT/.workflow/technical-debt.md"; then pass 'closed records move to corresponding sections'; else fail 'closed records move to corresponding sections'; fi

# Every operation validates existing input and must leave malformed files untouched.
cp "$FIXTURES/malformed.md" "$PROJECT/.workflow/technical-debt.md"
cp "$PROJECT/.workflow/technical-debt.md" "$TEMP/before"
expect 1 'malformed priority/status/date list rejected' list --age
if [ -z "$OUTPUT" ] && [ -s "$TEMP/stderr" ]; then pass 'malformed input emits stderr only'; else fail 'malformed input emits stderr only'; fi
expect 1 'malformed file rejects add' add --title Repair --location src/api --problem 'Do not overwrite'
unchanged 'malformed file unchanged by add'
expect 1 'malformed file rejects resolve' resolve broken --resolution Fixed
unchanged 'malformed file unchanged by resolve'
expect 1 'malformed file rejects accept' accept broken --reason 'Do not overwrite'
unchanged 'malformed file unchanged by accept'
expect 1 'malformed file rejects init' init
unchanged 'malformed file unchanged by init'
fixture
awk '!/^\*\*Added:/ {print}' "$PROJECT/.workflow/technical-debt.md" > "$TEMP/missing-added"
cp "$TEMP/missing-added" "$PROJECT/.workflow/technical-debt.md"
expect 1 'missing required date rejected' list
fixture
awk '{print} /^\*\*Status:\*\* active/ && !done {print; done=1}' "$PROJECT/.workflow/technical-debt.md" > "$TEMP/duplicate-status"
cp "$TEMP/duplicate-status" "$PROJECT/.workflow/technical-debt.md"
expect 1 'duplicate metadata rejected' list
fixture
awk '{sub(/\[medium\]/,"[urgent]"); print}' "$PROJECT/.workflow/technical-debt.md" > "$TEMP/duplicate-id"
cp "$TEMP/duplicate-id" "$PROJECT/.workflow/technical-debt.md"
expect 1 'duplicate IDs rejected' list
printf '# Technical Debt\n\n**Priority:** fix-now\n' > "$PROJECT/.workflow/technical-debt.md"
expect 1 'metadata without item heading rejected' list
printf 'This is not a debt file.\n' > "$PROJECT/.workflow/technical-debt.md"
expect 1 'missing document heading rejected' list
printf '# Technical Debt\n\n## [missing-close Malformed heading\n' > "$PROJECT/.workflow/technical-debt.md"
expect 1 'malformed item heading rejected' list
printf '# Technical Debt\n\n```markdown\nunclosed\n' > "$PROJECT/.workflow/technical-debt.md"
expect 1 'unclosed fence rejected' list

: > "$PROJECT/.workflow/technical-debt.md"
expect 0 'empty file list succeeds' list
contains 'empty file shows no items' 'No debt items found'
expect 0 'empty file init creates headings' init
expect 1 'init will not overwrite existing debt document' init
: > "$PROJECT/.workflow/technical-debt.md"
expect 0 'add initializes empty file' add --title 'Fresh Item' --location src/fresh --problem 'Fresh debt'
file_contains 'empty file receives active heading' '## Status: Active'
expect 0 'newly initialized debt lists' list
contains 'fresh item listed' '[fresh-item]'
printf ' \n\t\n' > "$PROJECT/.workflow/technical-debt.md"
expect 0 'whitespace-only file is initialized' add --title 'Whitespace Item' --location src/fresh --problem 'Whitespace file'

# Git-root discovery is exercised independently from the pwd fallback above.
PROJECT="$TEMP/git-project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
fixture
mkdir -p "$PROJECT/nested/deeper"
PROJECT="$PROJECT/nested/deeper"
expect 0 'finds git root from nested subdirectory' list --priority fix-now
contains 'nested invocation reads root debt' '[urgent]'

printf '\nDebt tests: %s passed, %s failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
