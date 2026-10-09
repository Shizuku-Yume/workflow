#!/usr/bin/env bash
# workflow-lib.bash - one reader for task and effort metadata.
#
# Sourced by the workflow-* commands; never executed directly. Bash 4.3+.
#
# Grammar (CONVENTIONS §2): fields are `Name: value` lines, plain, bulleted
# (`- Name: value`), or bolded (`**Name:** value`); fenced code blocks and HTML
# comments are ignored; indented or bulleted lines continue the previous field
# (`Blocked by` joins with ", ", other fields with a space); blank lines,
# headings, checklists, and new fields end a continuation. `## Goal` and
# `## Check` headings start sections whose lines join the same way. The first
# occurrence of a field wins; later duplicates are listed in WF_DUP_LINES.
#
# Functions communicate through WF_-prefixed globals to stay subshell-free.

WF_KNOWN_FIELDS="task effort task type base commit delivers blocked by files read first check done when priority status started finished question time box goal scope spec dependencies notes"
declare -gA WF_FIELD=() WF_LINE=()

wf_trim() {
  WF_TRIMMED="${1#"${1%%[![:space:]]*}"}"
  WF_TRIMMED="${WF_TRIMMED%"${WF_TRIMMED##*[![:space:]]}"}"
}

wf_normalize_number() {
  WF_NUMBER="$1"
  while [ "${#WF_NUMBER}" -gt 1 ] && [ "${WF_NUMBER:0:1}" = 0 ]; do
    WF_NUMBER="${WF_NUMBER:1}"
  done
}

wf_project_root() {
  local dir="${1:-$PWD}" root
  if root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "$dir"
  fi
}

# Collect every Markdown file under a task directory, at any depth, sorted, into
# WF_FILES. Active tasks live in .workflow/tasks/<effort>/<NN>-<slug>.md; files
# directly under tasks/ are the legacy flat layout and are still read. Every
# command discovers tasks through this one function so none of them can miss a
# file another one counts.
wf_task_files() {
  local dir="$1" f
  WF_FILES=()
  [ -d "$dir" ] || return 0
  while IFS= read -r -d '' f; do
    WF_FILES+=("$f")
  done < <(find "$dir" \( -type f -o -type l \) -name '*.md' -print0 | LC_ALL=C sort -z)
}

# Effort directory a task file sits in: the first path component below the
# tasks/ or done/ directory, or empty for a file directly inside it.
wf_dir_effort() {
  local base="$1" file="$2" rel
  rel="${file#"$base"/}"
  if [[ "$rel" == */* ]]; then WF_DIR_EFFORT="${rel%%/*}"; else WF_DIR_EFFORT=""; fi
}

# Format a task reference for display and for map keys: `<effort>/<NN>` with at
# least two digits, the spelling CONVENTIONS §2 uses. Padding the key also makes
# plain lexical sorts order 02 before 10.
wf_ref() {
  wf_normalize_number "$2"
  printf -v WF_REF '%s/%02d' "$1" "$((10#$WF_NUMBER))"
}

# Quote one string for JSON, escaping backslashes, quotes, and control bytes.
wf_json_string() {
  local value="$1" code control escaped
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  for ((code = 1; code < 32; code++)); do
    printf -v control '\\%03o' "$code"
    printf -v control '%b' "$control"
    printf -v escaped '\\u%04x' "$code"
    value="${value//"$control"/"$escaped"}"
  done
  printf '"%s"' "$value"
}

# Read one task or effort file into WF_FIELD[<name>] / WF_LINE[<name>] /
# WF_DUP_LINES ("<line>:<name>" per duplicate) plus WF_TITLE, WF_TITLE_NUMBER
# (normalized) and WF_TITLE_NUMBER_RAW (as written) from a `# NN: Title` heading.
wf_read_fields() {
  local file="$1"
  local line lineno=0 in_fence=0 in_comment=0
  local current="" current_kind="" section_content=0 title_seen=0
  local before after clean name key value h rawline
  unset WF_FIELD WF_LINE
  declare -gA WF_FIELD=() WF_LINE=()
  WF_DUP_LINES=()
  WF_TITLE=""; WF_TITLE_NUMBER=""; WF_TITLE_NUMBER_RAW=""
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    while :; do
      if [ "$in_comment" -eq 1 ]; then
        if [[ "$line" == *"-->"* ]]; then line="${line#*-->}"; in_comment=0; else line=""; break; fi
      elif [[ "$line" == *"<!--"* ]]; then
        before="${line%%<!--*}"; after="${line#*<!--}"
        if [[ "$after" == *"-->"* ]]; then line="$before${after#*-->}"; else line="$before"; in_comment=1; break; fi
      else
        break
      fi
    done
    if [[ "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
      in_fence=$((1 - in_fence)); current=""; current_kind=""
      continue
    fi
    [ "$in_fence" -eq 1 ] && continue
    rawline="$line"
    wf_trim "$line"; line="$WF_TRIMMED"
    if [ -z "$line" ]; then
      if [ -n "$current_kind" ]; then
        if [ "$current_kind" = field ] || [ "$section_content" -eq 1 ]; then
          current=""; current_kind=""
        fi
      fi
      continue
    fi
    if [[ "$line" =~ ^#[[:space:]]+([0-9]+):[[:space:]]*(.*)$ ]]; then
      if [ "$title_seen" -eq 0 ]; then
        title_seen=1
        WF_TITLE="${BASH_REMATCH[2]}"
        wf_trim "$WF_TITLE"; WF_TITLE="$WF_TRIMMED"
        WF_TITLE_NUMBER_RAW="${BASH_REMATCH[1]}"
        wf_normalize_number "${BASH_REMATCH[1]}"; WF_TITLE_NUMBER="$WF_NUMBER"
      fi
      current=""; current_kind=""
      continue
    fi
    if [[ "$line" =~ ^##[[:space:]]+(.*)$ ]]; then
      h="${BASH_REMATCH[1]}"; h="${h,,}"; h="${h%:}"
      wf_trim "$h"; h="$WF_TRIMMED"
      current=""; current_kind=""
      case "$h" in
        goal|check) current="$h"; current_kind=section; section_content=0 ;;
      esac
      continue
    fi
    if [[ "$line" =~ ^# ]]; then current=""; current_kind=""; continue; fi
    if [[ "$line" =~ ^[-*][[:space:]]+\[[[:space:]xX]\] ]]; then
      current=""; current_kind=""
      continue
    fi
    clean="$line"
    if [[ "$clean" =~ ^[-*][[:space:]]+(.*)$ ]]; then clean="${BASH_REMATCH[1]}"; fi
    name=""
    if [[ "$clean" =~ ^\*\*([^*]+)\*\*[[:space:]]*:?[[:space:]]*(.*)$ ]]; then
      name="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    elif [[ "$clean" =~ ^([A-Za-z][A-Za-z0-9_. -]*):[[:space:]]*(.*)$ ]]; then
      name="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    fi
    if [ -n "$name" ]; then
      key="${name,,}"; key="${key%:}"
      wf_trim "$key"; key="$WF_TRIMMED"
      case "$key" in
        base) key="base commit" ;;
        type) key="task type" ;;
      esac
      if [[ " $WF_KNOWN_FIELDS " == *" $key "* ]]; then
        wf_trim "$value"; value="$WF_TRIMMED"
        if [ -z "${WF_LINE[$key]:-}" ]; then
          WF_FIELD["$key"]="$value"; WF_LINE["$key"]="$lineno"
        else
          WF_DUP_LINES+=("$lineno:$key")
        fi
        current="$key"; current_kind=field
        continue
      fi
      current=""; current_kind=""
      continue
    fi
    if [ -n "$current" ] && [ "$current_kind" = section ]; then
      if [ -z "${WF_LINE[$current]:-}" ]; then
        WF_FIELD["$current"]="${WF_FIELD[$current]:+${WF_FIELD[$current]} }$line"
      else
        WF_FIELD["$current.section"]="${WF_FIELD["$current.section"]:+${WF_FIELD["$current.section"]} }$line"
      fi
      section_content=1
      continue
    fi
    if [ -n "$current" ] && [ "$current_kind" = field ]; then
      if [[ "$rawline" =~ ^[[:space:]] || "$line" =~ ^[-*][[:space:]] ]]; then
        if [ "$current" = "blocked by" ]; then
          WF_FIELD["$current"]="${WF_FIELD[$current]:+${WF_FIELD[$current]}, }$clean"
        else
          WF_FIELD["$current"]="${WF_FIELD[$current]:+${WF_FIELD[$current]} }$clean"
        fi
        continue
      fi
    fi
    current=""; current_kind=""
  done < "$file"
  if [ -z "${WF_FIELD[check]:-}" ] && [ -n "${WF_FIELD[check.section]:-}" ]; then
    WF_FIELD[check]="${WF_FIELD[check.section]}"
  fi
  unset 'WF_FIELD[check.section]'
}

# Tokenize a `Blocked by` value. Returns 0 for a valid value (WF_REFS holds
# normalized `NN` or `<effort>/NN` references; `None` yields none) and 1 for a
# malformed value with the offending token in WF_BAD. With strict_none=1 only
# the exact spellings `None` and `None, can start now` count as no blockers.
wf_parse_blockers() {
  local raw="$1" strict="${2:-0}" token effort num
  WF_REFS=(); WF_RAW_REFS=(); WF_REFS_COUNT=0; WF_BAD=""; WF_TRAILING_COMMA=0
  wf_trim "$raw"; raw="$WF_TRIMMED"
  if [ "$strict" = 1 ]; then
    case "$raw" in
      "None"|"None, can start now") return 0 ;;
    esac
  elif [[ "${raw,,}" =~ ^none([[:space:]]*,[[:space:]]*can[[:space:]]+start[[:space:]]+now)?$ ]]; then
    return 0
  fi
  if [ -z "$raw" ]; then WF_BAD=""; return 1; fi
  # `read -a` drops a trailing delimiter, so detect the empty last token here.
  if [[ "$raw" == *, ]]; then WF_TRAILING_COMMA=1; WF_BAD=""; return 1; fi
  local -a tokens=()
  IFS=',' read -r -a tokens <<< "$raw"
  for token in "${tokens[@]}"; do
    wf_trim "$token"; token="$WF_TRIMMED"
    if [[ "$token" =~ ^([a-z0-9]+(-[a-z0-9]+)*)/([0-9]+)$ ]]; then
      effort="${BASH_REMATCH[1]}/"
      wf_normalize_number "${BASH_REMATCH[3]}"; num="$WF_NUMBER"
    elif [[ "$token" =~ ^([0-9]+)$ ]]; then
      effort=""
      wf_normalize_number "${BASH_REMATCH[1]}"; num="$WF_NUMBER"
    else
      WF_BAD="$token"; return 1
    fi
    WF_REFS+=("$effort$num")
    WF_RAW_REFS+=("$token")
    WF_REFS_COUNT=$((WF_REFS_COUNT + 1))
  done
  return 0
}

# Classify a Base commit value: missing, placeholder, ok, or unresolved.
wf_base_commit_state() {
  local root="$1" value="$2"
  wf_trim "$value"; value="$WF_TRIMMED"
  if [ -z "$value" ]; then printf 'missing\n'; return 0; fi
  case "$value" in
    '<commit-sha>'|not-started) printf 'placeholder\n'; return 0 ;;
  esac
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1 &&
     git -C "$root" rev-parse --verify --end-of-options "$value^{commit}" >/dev/null 2>&1; then
    printf 'ok\n'; return 0
  fi
  printf 'unresolved\n'
}
