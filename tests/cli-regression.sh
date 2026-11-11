#!/usr/bin/env bash
# cli-regression.sh - deterministic CLI regression suite for workflow
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$KIT/bin/workflow"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

passed=0
failed=0

pass() { printf '✓ %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf '✗ %s\n' "$1"; failed=$((failed + 1)); }
portable_sed() {
  local expression="$1" file="$2" tmp="${2}.workflow-tmp.$$"
  if sed "$expression" "$file" > "$tmp"; then
    cat "$tmp" > "$file"
    rm -f "$tmp"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Every `workflow` call below uses $WORKFLOW, never a copy on PATH. doctor warns
# (and fails) when another workflow on PATH is newer than the project's (contract
# §6), so a developer's global install must not leak into these scenarios: PATH
# keeps only directories without a workflow binary. The PATH scenario at the end
# builds its own to test that warning.
TEST_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ -x "$p/workflow" ]; then continue; fi
  printf '%s:' "$p"
done)"
PATH="${TEST_PATH%:}"
export PATH

# Helper to initialize a clean git repo with workflow
setup_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test User"
  echo "root" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "initial"
  # --no-hook: most scenarios are not about the hook, and a hook would run on
  # the commits they make. The hook scenarios install it explicitly.
  (cd "$dir" && "$WORKFLOW" init --no-hook >/dev/null 2>&1)
  # Fill template placeholders in standards.md so standards.md passes doctor
  portable_sed 's/<[^>]*>/placeholder/g' "$dir/.workflow/standards.md"
}

# --- Scenario 1: draft placeholder accepted & doctor exit 0 ---
test_draft_placeholder_accepted() {
  local repo="$TMPDIR/repo1"
  setup_repo "$repo"

  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "draft placeholder accepted and doctor exits 0"
  else
    fail "draft placeholder should be accepted with exit 0"
  fi
}

# --- Scenario 2: invalid concrete SHA rejected ---
test_invalid_concrete_sha_rejected() {
  local repo="$TMPDIR/repo1"

  # Non-existent concrete SHA in git
  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** 0000000000000000000000000000000000000000
**Blocked by:** None, can start now
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "non-existent concrete SHA should be rejected"
  else
    pass "non-existent concrete SHA rejected"
  fi

  # Malformed concrete SHA
  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** not-a-sha
**Blocked by:** None, can start now
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "malformed SHA should be rejected"
  else
    pass "malformed concrete SHA rejected"
  fi

  # Missing Base commit: optional (CONVENTIONS §2), and doctor now agrees with validate
  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Blocked by:** None, can start now
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1) && (cd "$repo" && "$WORKFLOW" validate >/dev/null 2>&1 || [ $? -eq 1 ]); then
    pass "missing Base commit accepted by doctor and validate alike"
  else
    fail "missing Base commit is optional and should be accepted"
  fi
}

# --- Scenario 3: grouped invalid dependencies rejected ---
test_invalid_dependencies_rejected() {
  local repo="$TMPDIR/repo1"

  # Self-dependency
  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 01
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "self-reference dependency should be rejected"
  else
    pass "self-reference dependency rejected"
  fi

  # Missing dependency target
  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 99
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "missing dependency target should be rejected"
  else
    pass "missing dependency target rejected"
  fi

  # Nonnumeric prose in Blocked by
  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** waiting for review
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "nonnumeric prose in Blocked by should be rejected"
  else
    pass "nonnumeric prose in Blocked by rejected"
  fi

  # Cross-effort number isolation (unqualified NN must not match other effort)
  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** effort-a
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF
  cat > "$repo/.workflow/tasks/02-other.md" <<'EOF'
# 02: Other Task
**Effort:** effort-b
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 01
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "unqualified cross-effort dependency should not be satisfied by different effort"
  else
    pass "unqualified cross-effort dependency rejected"
  fi
  rm -f "$repo/.workflow/tasks/02-other.md"
}

# --- Scenario 4: explicit archived cross-effort dependency accepted ---
test_explicit_archived_cross_effort() {
  local repo="$TMPDIR/repo1"

  mkdir -p "$repo/.workflow/done/archived-effort"
  # An archived task may not carry a placeholder Base commit; use the real HEAD.
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  cat > "$repo/.workflow/done/archived-effort/01-done.md" <<EOF
# 01: Done Task
**Effort:** archived-effort
**Check:** \`true\` passes
**Base commit:** $head_sha
**Blocked by:** None, can start now

## Progress

Check after: \`true\` passed on the final code
Review: pass (base abc1234)
EOF

  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** active-effort
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** archived-effort/01
EOF

  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "explicit archived cross-effort dependency accepted"
  else
    fail "explicit archived cross-effort dependency should be accepted"
  fi
}

# --- Scenario: only strict blocker references and None forms are accepted ---
test_blocked_by_strict_grammar() {
  local repo="$TMPDIR/repo1"
  rm -rf "$repo/.workflow/done"
  rm -f "$repo/.workflow/tasks"/*.md
  cat > "$repo/.workflow/tasks/01-prereq.md" <<'EOF'
# 01: Prereq Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None
EOF

  local blocker out
  for blocker in '01 Task' '01 Task, with commas in title' '01 Foo, bar, 02 Baz, qux' \
      'core-work/01 Task' 'None.' 'None can start now' 'None, can start now.' \
      ',01' '01,' '01,,01' '01, None' '01 02' \
      'bad_effort/01' './01' '-01' '01.md'; do
    cat > "$repo/.workflow/tasks/02-child.md" <<EOF
# 02: Child Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** $blocker
EOF
    if out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1)"; then
      fail "strict Blocked by grammar should reject '$blocker'"
    elif [[ "$out" == *"malformed blocker"* ]]; then
      pass "strict Blocked by grammar rejects '$blocker'"
    else
      fail "invalid blocker should produce a Blocked by diagnostic: $out"
    fi
  done

  # Every command reads None case-insensitively (one parser); doctor follows.
  for blocker in 'none' 'NONE, can start now'; do
    cat > "$repo/.workflow/tasks/02-child.md" <<EOF
# 02: Child Task
**Effort:** core-work
**Check:** \`true\` passes
**Blocked by:** $blocker
EOF
    if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
      pass "Blocked by accepts '$blocker' as no blockers"
    else
      fail "Blocked by should accept '$blocker' like the other commands"
    fi
  done
}

# --- Scenario: lists resolve numbers within each referenced effort ---
test_blocked_by_multiple_references() {
  local repo="$TMPDIR/repo1"
  rm -f "$repo/.workflow/tasks"/*.md
  cat > "$repo/.workflow/tasks/01-foo.md" <<'EOF'
# 01: Foo Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None
EOF
  cat > "$repo/.workflow/tasks/01-baz.md" <<'EOF'
# 01: Baz Task
**Effort:** other-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF
  cat > "$repo/.workflow/tasks/02-dep.md" <<'EOF'
# 02: Dependent Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 01, other-work/01
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "mixed local and qualified blockers accept repeated numbers across efforts"
  else
    fail "mixed local and qualified blockers should resolve per effort"
  fi

  rm -f "$repo/.workflow/tasks/01-baz.md"
  local out
  if out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1)"; then
    fail "qualified blocker should not resolve to the same number in another effort"
  elif [[ "$out" == *"orphaned blocker 'other-work/01'"* ]]; then
    pass "qualified blocker requires its own effort target"
  else
    fail "missing qualified blocker should report its own effort target: $out"
  fi
  rm -f "$repo/.workflow/tasks"/*.md
}

# --- Scenario: blocker continuation stops at metadata and task body boundaries ---
test_blocked_by_continuation_boundaries() {
  local repo="$TMPDIR/repo1"
  rm -f "$repo/.workflow/tasks"/*.md
  cat > "$repo/.workflow/tasks/01-root.md" <<'EOF'
# 01: Root Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF
  local suffix field
  local -a suffixes=($'\n  99' $'\n- 99' $'- [ ] 99\n  99' $'* [x] 99\n  99' \
      $'## Check\n  99' $'```\n99\n```\n  99')
  for field in 'Task type' 'Base commit' 'Covers' 'Status' 'Delivers' \
      'Files' 'Read first' 'Check' 'Question' 'Time box'; do
    case "$field" in
      'Base commit') suffix="<commit-sha>" ;;
      'Task type') suffix="feature" ;;
      'Status') suffix="active" ;;
      *) suffix="99" ;;
    esac
    suffixes+=("**$field:** $suffix" "  - **$field:** $suffix" "  $field: $suffix")
  done
  for suffix in "${suffixes[@]}"; do
    # No Base commit line here: several suffixes add one, and a second copy
    # is a duplicate-field error. Check comes last as a section for the same reason.
    cat > "$repo/.workflow/tasks/02-child.md" <<EOF
# 02: Child Task
**Effort:** core-work
**Blocked by:** 01
$suffix

## Check

\`true\` passes
EOF
    if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
      pass "Blocked by continuation stops before '$suffix'"
    else
      fail "Blocked by continuation should stop before '$suffix'"
    fi
  done

  for suffix in '  01' '- 01' '* 01'; do
    cat > "$repo/.workflow/tasks/02-child.md" <<EOF
# 02: Child Task
**Effort:** core-work
**Base commit:** <commit-sha>
**Blocked by:**
$suffix
**Check:** 99
EOF
    if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
      pass "numeric blocker continuation accepts '$suffix'"
    else
      fail "numeric blocker continuation should accept '$suffix'"
    fi
  done
  rm -f "$repo/.workflow/tasks"/*.md
}

# --- Scenario 5: nonempty vs empty decision entries ---
test_decision_entries_validation() {
  local repo="$TMPDIR/repo1"

  # Reset task to valid
  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF
  rm -rf "$repo/.workflow/done"

  # Empty decision entry (missing fields)
  cat >> "$repo/.workflow/decisions.md" <<'EOF'
## 2026-02-01 - Empty Entry
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "empty decision entry should be rejected"
  else
    pass "empty decision entry rejected"
  fi

  # Entry with empty field
  cat > "$repo/.workflow/decisions.md" <<'EOF'
# Decisions
## Entries
## 2026-02-01 - Empty Field
- **Decided:**
- **Instead of:** foo
- **Because:** bar
- **Decided by:** agent
- **Revisit when:** never
EOF
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "decision entry with empty field should be rejected"
  else
    pass "decision entry with empty field rejected"
  fi
}

# --- Scenario 6: fenced examples and subheadings accepted ---
test_decision_fenced_and_subheadings() {
  local repo="$TMPDIR/repo1"

  cat > "$repo/.workflow/decisions.md" <<'EOF'
# Decisions

## Why the runner-up is required
Explanation here.

## Format
```markdown
## 2026-01-31 - Fake Example
- **Decided:** fake
```

## Entries

## 2026-02-01 - Complex Valid Decision
### Background Context
Notes on context.
- **Decided:**
  we choose approach A
```markdown
fake block inside entry
```
### Alternatives Considered
- **Instead of:** approach B
- **Because:** approach A is cleaner
- **Decided by:** user
- **Revisit when:** never
EOF

  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "fenced examples and subheadings in decisions accepted"
  else
    fail "fenced examples and subheadings in decisions should be accepted"
  fi
}

# --- Scenario 7: rulebook update preserves edits and updates unedited ---
test_rulebook_update_behavior() {
  local test_kit="$TMPDIR/mock-kit"
  cp -r "$KIT" "$test_kit"

  local repo="$TMPDIR/repo2"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  echo "root" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial"

  (cd "$repo" && "$test_kit/bin/workflow" init >/dev/null 2>&1)

  # Edit CONVENTIONS.md locally
  echo "LOCAL USER EDIT" >> "$repo/.workflow/CONVENTIONS.md"
  # STYLE.md remains unedited

  # Upstream updates both files
  echo "UPSTREAM STYLE UPDATE" >> "$test_kit/STYLE.md"
  echo "UPSTREAM CONVENTIONS UPDATE" >> "$test_kit/CONVENTIONS.md"

  (cd "$repo" && "$test_kit/bin/workflow" update >/dev/null 2>&1)

  local conv_content style_content
  conv_content="$(cat "$repo/.workflow/CONVENTIONS.md")"
  style_content="$(cat "$repo/.workflow/STYLE.md")"

  if [[ "$conv_content" == *"LOCAL USER EDIT"* ]] && [[ "$conv_content" != *"UPSTREAM CONVENTIONS UPDATE"* ]]; then
    pass "locally edited rulebook preserved across update"
  else
    fail "locally edited rulebook was overwritten or missing user edit"
  fi

  if [[ "$style_content" == *"UPSTREAM STYLE UPDATE"* ]]; then
    pass "unedited rulebook refreshed to upstream copy"
  else
    fail "unedited rulebook was not refreshed"
  fi
}

# --- Scenario 8: doctor is strictly read-only (no writes) ---
test_doctor_no_writes() {
  local repo="$TMPDIR/repo1"

  local before_files before_status
  before_files="$(find "$repo" -type f | sort)"
  before_status="$(git -C "$repo" status --porcelain)"

  (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1 || true)

  local after_files after_status
  after_files="$(find "$repo" -type f | sort)"
  after_status="$(git -C "$repo" status --porcelain)"

  if [ "$before_files" = "$after_files" ] && [ "$before_status" = "$after_status" ]; then
    pass "doctor performs no filesystem writes or modifications"
  else
    fail "doctor modified or created files"
  fi
}

# --- Scenario 11: duplicate task number in same effort rejected ---
test_duplicate_task_number_same_effort() {
  local repo="$TMPDIR/repo-dup-task"
  setup_repo "$repo"

  cat > "$repo/.workflow/tasks/01-a.md" <<'EOF'
# 01: Task A
**Effort:** e
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  cat > "$repo/.workflow/tasks/01-dup.md" <<'EOF'
# 01: Task Dup
**Effort:** e
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "duplicate task number in same effort should be rejected"
  elif [[ "$out" == *"01-a.md"* ]] && [[ "$out" == *"01-dup.md"* ]]; then
    pass "duplicate task number in same effort rejected and reports both files"
  else
    fail "duplicate task number rejected but failed to report both files: $out"
  fi
}

# --- Scenario 12: different efforts with same task number accepted ---
test_different_efforts_same_number_ok() {
  local repo="$TMPDIR/repo-diff-eff"
  setup_repo "$repo"

  cat > "$repo/.workflow/tasks/01-a.md" <<'EOF'
# 01: Task A
**Effort:** e1
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  cat > "$repo/.workflow/tasks/01-b.md" <<'EOF'
# 01: Task B
**Effort:** e2
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "different efforts with same task number accepted"
  else
    fail "different efforts with same task number should be accepted"
  fi
}

# --- Scenario 13: open research notes surface in next and next --brief ---
test_open_research_cli() {
  local repo="$TMPDIR/repo1"
  mkdir -p "$repo/.workflow/research"

  cat > "$repo/.workflow/research/explore-api.md" <<'EOF'
# Research: Explore API options

## Goal
Pick streaming protocol.

## Open questions
- [ ] Benchmark SSE vs WebSocket
- [ ] Check browser support
EOF

  local out_next out_brief out_json
  out_next="$(cd "$repo" && "$WORKFLOW" next --no-color)"
  out_brief="$(cd "$repo" && "$WORKFLOW" next --brief --no-color)"
  out_json="$(cd "$repo" && "$WORKFLOW" next --format json)"
  if [[ "$out_next" == *"Open research questions (continue with flow-grill):"* ]] && \
     [[ "$out_next" == *".workflow/research/explore-api.md — Explore API options (2 open)"* ]] && \
     [[ "$out_brief" == *"Research: .workflow/research/explore-api.md (continue with flow-grill)"* ]] && \
     [[ "$out_json" == *'"open_research":[{"path":".workflow/research/explore-api.md","slug":"explore-api","title":"Explore API options","open":2}]'* ]]; then
    pass "open research notes surface in workflow next, next --brief and next JSON"
  else
    fail "expected open research note in next, next --brief and next JSON, got next=$out_next brief=$out_brief json=$out_json"
  fi
  rm -f "$repo/.workflow/research/explore-api.md"
}

# --- Scenario 14: task filename and heading number mismatch rejected ---
test_task_heading_mismatch() {
  local repo="$TMPDIR/repo-heading-mismatch"
  setup_repo "$repo"

  cat > "$repo/.workflow/tasks/01-foo.md" <<'EOF'
# 03: Foo
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "task heading mismatch should cause doctor to fail"
  elif [[ "$out" == *"heading number 3 does not match filename number 1"* ]]; then
    pass "task heading mismatch reported and doctor fails"
  else
    fail "doctor failed but expected mismatch message, got: $out"
  fi
}

# --- Scenario 15: task filename and heading number match accepted ---
test_task_heading_match_ok() {
  local repo="$TMPDIR/repo-heading-match"
  setup_repo "$repo"

  cat > "$repo/.workflow/tasks/01-bar.md" <<'EOF'
# 01: Bar
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "matching task filename and heading number accepted silently"
  else
    fail "matching task filename and heading number should pass"
  fi
}

# --- Scenario 16: AGENTS.md workflow block edit preserved across update ---
test_agents_block_edit_preserved() {
  local repo="$TMPDIR/repo_agents_block_preserve"
  setup_repo "$repo"

  # Add line inside workflow block
  portable_sed '/<!-- workflow:start -->/a\
- Custom user workflow rule' "$repo/AGENTS.md"

  # Run update without --force
  local update_out
  update_out="$(cd "$repo" && "$WORKFLOW" update 2>&1)"

  local content
  content="$(cat "$repo/AGENTS.md")"

  if [[ "$content" == *"- Custom user workflow rule"* ]]; then
    pass "user edit inside AGENTS.md block preserved across update"
  else
    fail "user edit inside AGENTS.md block was lost on update"
  fi

  if [[ "$update_out" == *"edited"* ]] || [[ "$update_out" == *"skipped"* ]]; then
    pass "warning issued when AGENTS.md block edited"
  else
    fail "expected warning when updating edited AGENTS.md block: $update_out"
  fi
}

# --- Scenario 17: AGENTS.md workflow block edit overwritten with --force ---
test_agents_block_force_overwrites() {
  local repo="$TMPDIR/repo_agents_block_preserve"
  if [ ! -d "$repo" ]; then
    setup_repo "$repo"
    portable_sed '/<!-- workflow:start -->/a\
- Custom user workflow rule' "$repo/AGENTS.md"
  fi

  # Run update with --force
  (cd "$repo" && "$WORKFLOW" update --force >/dev/null 2>&1)

  local content
  content="$(cat "$repo/AGENTS.md")"

  if [[ "$content" != *"- Custom user workflow rule"* ]]; then
    pass "user edit inside AGENTS.md block overwritten with --force"
  else
    fail "user edit inside AGENTS.md block was preserved despite --force"
  fi
}

# --- Scenario: AGENTS.md workflow block is prepended with one blank separator ---
test_agents_block_prepended() {
  local mode repo start end existing separator
  for mode in init update; do
    repo="$TMPDIR/repo_agents_block_prepend_$mode"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
    printf '# Existing project rules\n\nKeep local conventions.\n' > "$repo/AGENTS.md"
    git -C "$repo" add AGENTS.md
    git -C "$repo" commit -q -m initial

    (cd "$repo" && "$WORKFLOW" "$mode" --no-claude >/dev/null 2>&1)

    start="$(grep -nFx '<!-- workflow:start -->' "$repo/AGENTS.md" | cut -d: -f1)"
    end="$(grep -nFx '<!-- workflow:end -->' "$repo/AGENTS.md" | cut -d: -f1)"
    existing="$(grep -nFx '# Existing project rules' "$repo/AGENTS.md" | cut -d: -f1)"
    separator="$(sed -n "$((end + 1))p" "$repo/AGENTS.md")"

    if [ "$start" -eq 1 ] && [ "$existing" -eq $((end + 2)) ] && [ -z "$separator" ] &&
       grep -qFx 'Keep local conventions.' "$repo/AGENTS.md"; then
      pass "$mode prepends the AGENTS.md workflow block with one blank separator"
    else
      fail "$mode should prepend the AGENTS.md workflow block with one blank separator"
    fi
  done
}

# --- Scenario: dependency cycle detection simple (01 <-> 02) ---
test_cycle_detection_simple() {
  local repo="$TMPDIR/repo_cycle_simple"
  setup_repo "$repo"

  cat > "$repo/.workflow/tasks/01-task.md" <<'EOF'
# 01: Task One
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 02
EOF

  cat > "$repo/.workflow/tasks/02-task.md" <<'EOF'
# 02: Task Two
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 01
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"circular dependency: core-work/01 -> core-work/02 -> core-work/01"* ]]; then
    pass "simple dependency cycle detected with cycle message"
  else
    fail "expected simple dependency cycle message (01 -> 02 -> 01), got: $out"
  fi

  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "doctor should exit non-zero on simple dependency cycle"
  else
    pass "doctor exits non-zero on simple dependency cycle"
  fi
}

# --- Scenario: dependency cycle detection three tasks (01 -> 02 -> 03 -> 01) ---
test_cycle_detection_three() {
  local repo="$TMPDIR/repo_cycle_three"
  setup_repo "$repo"

  cat > "$repo/.workflow/tasks/01-task.md" <<'EOF'
# 01: Task One
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 02
EOF

  cat > "$repo/.workflow/tasks/02-task.md" <<'EOF'
# 02: Task Two
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 03
EOF

  cat > "$repo/.workflow/tasks/03-task.md" <<'EOF'
# 03: Task Three
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 01
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"circular dependency: core-work/01 -> core-work/02 -> core-work/03 -> core-work/01"* ]]; then
    pass "three-task dependency cycle reports full chain"
  else
    fail "expected three-task cycle chain (01 -> 02 -> 03 -> 01), got: $out"
  fi

  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "doctor should exit non-zero on three-task dependency cycle"
  else
    pass "doctor exits non-zero on three-task dependency cycle"
  fi
}

# --- Scenario: no false positive in linear dependency chain ---
test_no_false_positive() {
  local repo="$TMPDIR/repo_no_cycle"
  setup_repo "$repo"

  cat > "$repo/.workflow/tasks/01-task.md" <<'EOF'
# 01: Task One
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 02
EOF

  cat > "$repo/.workflow/tasks/02-task.md" <<'EOF'
# 02: Task Two
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** 03
EOF

  cat > "$repo/.workflow/tasks/03-task.md" <<'EOF'
# 03: Task Three
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"circular dependency"* ]]; then
    fail "linear dependencies falsely reported as cycle: $out"
  else
    pass "no false positive on linear dependencies"
  fi

  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "doctor exits 0 when dependency chain has no cycles"
  else
    fail "doctor should exit 0 when dependency chain has no cycles: $out"
  fi
}


# --- Scenario: edited AGENTS.md workflow block retained on uninstall ---
test_uninstall_edited_agents_block_retained() {
  local repo="$TMPDIR/repo_uninstall_edited_agents"
  setup_repo "$repo"

  # Edit inside workflow block
  portable_sed '/<!-- workflow:start -->/a\
- Custom local rule that must stay' "$repo/AGENTS.md"

  local out
  out="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1 || true)"

  if [ ! -f "$repo/AGENTS.md" ]; then
    fail "edited AGENTS.md was unexpectedly removed by uninstall"
    return
  fi

  local content
  content="$(cat "$repo/AGENTS.md")"
  if [[ "$content" == *"- Custom local rule that must stay"* ]]; then
    pass "edited AGENTS.md workflow block retained on uninstall"
  else
    fail "edited content inside AGENTS.md was lost during uninstall"
  fi

  if [ -z "$(find "$repo" -name '*workflow-managed*' 2>/dev/null)" ] &&
     (cd "$repo" && "$WORKFLOW" init >/dev/null 2>&1) &&
     grep -q -- "- Custom local rule that must stay" "$repo/AGENTS.md"; then
    pass "no dotfile clutter left and subsequent init still preserves edited AGENTS.md block"
  else
    fail "edited AGENTS.md block should stay protected without scattered marker dotfiles"
  fi

  if [[ "$out" == *"kept AGENTS.md: workflow block was edited locally"* ]]; then
    pass "warning issued when keeping edited AGENTS.md block on uninstall"
  else
    fail "expected warning for keeping edited AGENTS.md block, got: $out"
  fi
}

# --- Scenario: unmodified AGENTS.md block removed preserving outside text ---
test_uninstall_unmodified_agents_block_preserves_outside_text() {
  local repo="$TMPDIR/repo_uninstall_outside_text"
  setup_repo "$repo"

  local original
  original="$(cat "$repo/AGENTS.md")"
  cat > "$repo/AGENTS.md" <<EOF
# Team Guidelines
Header text owned by user.

$original

## Postscript
Footer text owned by user.
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1 || true)"

  if [ ! -f "$repo/AGENTS.md" ]; then
    fail "AGENTS.md with outside text was deleted by uninstall"
    return
  fi

  local content
  content="$(cat "$repo/AGENTS.md")"
  if [[ "$content" == *"Header text owned by user."* ]] && [[ "$content" == *"Footer text owned by user."* ]]; then
    pass "outside user text preserved in AGENTS.md on uninstall"
  else
    fail "outside text in AGENTS.md was lost on uninstall"
  fi

  if [[ "$content" != *"<!-- workflow:start -->"* ]] && [[ "$content" != *"<!-- workflow:end -->"* ]]; then
    pass "unmodified workflow block removed from AGENTS.md"
  else
    fail "workflow block was not removed from AGENTS.md"
  fi

  if [ ! -f "$repo/.workflow/.workflow-version" ] &&
     [ -z "$(find "$repo" -name '*workflow-managed*' 2>/dev/null)" ]; then
    pass "manifest and ownership metadata removed when uninstalled"
  else
    fail "manifest and ownership metadata should be removed after uninstall"
  fi
}

# --- Scenario: malformed, unpaired, and duplicate markers cause no data loss on uninstall ---
test_uninstall_malformed_agents_markers_no_data_loss() {
  local repo="$TMPDIR/repo_uninstall_malformed"
  setup_repo "$repo"

  # Case 1: Unpaired marker (start without end)
  cat > "$repo/AGENTS.md" <<'EOF'
# Important user notes
<!-- workflow:start -->
Content without closing marker.
EOF
  local out
  out="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1 || true)"
  local content
  content="$(cat "$repo/AGENTS.md")"
  if [[ "$content" == *"Content without closing marker."* ]] && [[ "$out" == *"ambiguous or malformed"* ]]; then
    pass "unpaired start marker preserved without data loss on uninstall"
  else
    fail "unpaired start marker caused data loss or missing warning on uninstall: $out"
  fi

  # Case 2: Duplicate markers
  cat > "$repo/AGENTS.md" <<'EOF'
<!-- workflow:start -->
block 1
<!-- workflow:end -->
<!-- workflow:start -->
block 2
<!-- workflow:end -->
EOF
  out="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1 || true)"
  content="$(cat "$repo/AGENTS.md")"
  if [[ "$content" == *"block 1"* ]] && [[ "$content" == *"block 2"* ]] && [[ "$out" == *"ambiguous or malformed"* ]]; then
    pass "duplicate markers preserved without data loss on uninstall"
  else
    fail "duplicate markers caused data loss or missing warning on uninstall: $out"
  fi

  # Case 3: Malformed partial-line marker
  cat > "$repo/AGENTS.md" <<'EOF'
Prefix <!-- workflow:start -->
Inside text
<!-- workflow:end -->
EOF
  out="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1 || true)"
  content="$(cat "$repo/AGENTS.md")"
  if [[ "$content" == *"Inside text"* ]] && [[ "$out" == *"ambiguous or malformed"* ]]; then
    pass "malformed partial-line marker preserved without data loss on uninstall"
  else
    fail "malformed marker caused data loss or missing warning on uninstall: $out"
  fi
}

# --- Scenario: markerless legacy AGENTS block unmodified removable and edited preserved ---
test_uninstall_markerless_legacy_agents_block() {
  local repo="$TMPDIR/repo_uninstall_legacy_unmodified"
  setup_repo "$repo"

  # Subtest A: unmodified block without marker file is removed
  rm -f "$repo/.workflow/.workflow-version" "$repo/.workflow/.agents-block.workflow-managed"
  (cd "$repo" && "$WORKFLOW" uninstall >/dev/null 2>&1)
  if [ -f "$repo/AGENTS.md" ]; then
    fail "markerless legacy unmodified AGENTS.md should have been removed"
  else
    pass "markerless legacy unmodified AGENTS block successfully removed and file deleted"
  fi

  # Subtest B: edited block without marker file is preserved
  repo="$TMPDIR/repo_uninstall_legacy_edited"
  setup_repo "$repo"
  rm -f "$repo/.workflow/.workflow-version" "$repo/.workflow/.agents-block.workflow-managed"
portable_sed '/<!-- workflow:start -->/a\
- Legacy edit that must be kept' "$repo/AGENTS.md"

  local out
  out="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1 || true)"
  if [ -f "$repo/AGENTS.md" ] && grep -q "Legacy edit that must be kept" "$repo/AGENTS.md"; then
    pass "markerless legacy edited AGENTS block preserved on uninstall"
  else
    fail "markerless legacy edited AGENTS block was unexpectedly removed"
  fi
  if [[ "$out" == *"kept AGENTS.md: workflow block was edited locally"* ]]; then
    pass "warning issued when preserving markerless legacy edited AGENTS block"
  else
    fail "expected warning for keeping edited markerless AGENTS block, got: $out"
  fi
}

# --- Scenario: preexisting empty AGENTS.md preserved across uninstall ---
test_uninstall_preexisting_empty_agents_preserved() {
  local repo="$TMPDIR/repo_uninstall_empty_agents"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  echo "root" > "$repo/README.md"
  touch "$repo/AGENTS.md"
  git -C "$repo" add README.md AGENTS.md
  git -C "$repo" commit -q -m "initial with empty AGENTS"

  (cd "$repo" && "$WORKFLOW" uninstall >/dev/null 2>&1)

  if [ -f "$repo/AGENTS.md" ]; then
    pass "preexisting empty AGENTS.md preserved across uninstall"
  else
    fail "preexisting empty AGENTS.md should not be deleted by uninstall"
  fi
}

# --- Scenario: non-git directory init -> update -> uninstall preserves user documents ---
test_nongit_lifecycle_preserves_user_docs() {
  local repo="$TMPDIR/repo_nongit_lifecycle"
  mkdir -p "$repo"
  echo "User Project Readme" > "$repo/README.md"

  # 1. init in non-git directory (the hook is skipped silently there)
  local out_init
  if out_init="$(cd "$repo" && "$WORKFLOW" init 2>&1)"; then
    pass "workflow init succeeds in non-git directory"
  else
    fail "workflow init in non-git directory failed: $out_init"
    return
  fi

  if [ -d "$repo/.workflow" ] && [ -d "$repo/.agents/skills" ] && [ -d "$repo/.workflow/research" ]; then
    pass "workflow init created expected structure in non-git directory"
  else
    fail "workflow init missing structure in non-git directory"
    return
  fi

  # User customizes standards and creates custom spec and glossary additions
  echo "Custom user standards that must be preserved" > "$repo/.workflow/standards.md"
  echo "# Custom Spec Document" > "$repo/.workflow/specs/custom-spec.md"
  cat > "$repo/AGENTS.md" <<'EOF'
# Project Guidelines
Custom user instructions that must survive.

<!-- workflow:start -->
<!-- workflow:end -->

Custom user footer.
EOF

  # 2. update in non-git directory
  local out_update
  if out_update="$(cd "$repo" && "$WORKFLOW" update 2>&1)"; then
    pass "workflow update succeeds in non-git directory"
  else
    fail "workflow update in non-git directory failed: $out_update"
    return
  fi

  # Verify user files preserved across update
  if grep -q "Custom user standards that must be preserved" "$repo/.workflow/standards.md" && \
     [ -f "$repo/.workflow/specs/custom-spec.md" ] && \
     grep -q "Custom user instructions that must survive" "$repo/AGENTS.md"; then
    pass "user documents preserved across update in non-git directory"
  else
    fail "user documents lost or overwritten during update in non-git directory"
    return
  fi

  # 3. uninstall in non-git directory
  local out_uninstall
  if out_uninstall="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1)"; then
    pass "workflow uninstall succeeds in non-git directory"
  else
    fail "workflow uninstall in non-git directory failed: $out_uninstall"
    return
  fi

  # Verify user documents are preserved on uninstall
  local docs_ok=1
  if [ ! -f "$repo/README.md" ] || ! grep -q "User Project Readme" "$repo/README.md"; then
    docs_ok=0
  fi
  if [ ! -f "$repo/.workflow/standards.md" ] || ! grep -q "Custom user standards that must be preserved" "$repo/.workflow/standards.md"; then
    docs_ok=0
  fi
  if [ ! -f "$repo/.workflow/specs/custom-spec.md" ] || ! grep -q "# Custom Spec Document" "$repo/.workflow/specs/custom-spec.md"; then
    docs_ok=0
  fi
  if [ ! -f "$repo/AGENTS.md" ] || ! grep -q "Custom user instructions that must survive" "$repo/AGENTS.md"; then
    docs_ok=0
  fi

  if [ "$docs_ok" -eq 1 ]; then
    pass "user documents preserved after uninstall in non-git directory"
  else
    fail "user documents deleted or corrupted on uninstall in non-git directory"
  fi

  # Toolkit managed skills, framework guides, and manifest must be removed
  if [ -d "$repo/.agents/skills" ] || [ -f "$repo/.workflow/.workflow-version" ] || \
     [ -f "$repo/.workflow/merge-strategy.md" ] || [ -f "$repo/.workflow/spike-tasks.md" ]; then
    fail "toolkit managed artifacts were not cleanly removed on uninstall in non-git directory"
  else
    pass "toolkit managed artifacts cleanly removed on uninstall in non-git directory"
  fi
}

# --- Scenario: external symlink boundaries rejected across init/update/uninstall ---
test_symlink_boundaries_rejected() {
  local outside="$TMPDIR/outside_sentinel_dir"
  mkdir -p "$outside"
  local sentinel="$outside/sentinel.txt"
  echo "ORIGINAL_SENTINEL_CONTENT_12345" > "$sentinel"

  check_sentinel() {
    local label="$1"
    if [ -f "$sentinel" ] && [ "$(cat "$sentinel")" = "ORIGINAL_SENTINEL_CONTENT_12345" ]; then
      return 0
    else
      fail "external sentinel was modified or deleted during $label"
      return 1
    fi
  }

  # Subtest A: .workflow is an external symlink pointing outside
  local repo_wf="$TMPDIR/repo_symlink_wf"
  mkdir -p "$repo_wf"
  echo "root" > "$repo_wf/README.md"
  ln -s "$outside" "$repo_wf/.workflow"

  # init rejected, sentinel intact, no .agents created
  local status_init=0
  (cd "$repo_wf" && "$WORKFLOW" init >/dev/null 2>&1) || status_init=$?
  if [ "$status_init" -ne 0 ] && check_sentinel "init on symlink .workflow" && [ ! -e "$repo_wf/.agents" ]; then
    pass "symlink .workflow rejected on init without writing project content"
  else
    fail "init on symlink .workflow should exit non-zero and not write project content"
  fi

  local status_up=0
  (cd "$repo_wf" && "$WORKFLOW" update >/dev/null 2>&1) || status_up=$?
  if [ "$status_up" -ne 0 ] && check_sentinel "update on symlink .workflow"; then
    pass "symlink .workflow rejected on update"
  else
    fail "update on symlink .workflow should exit non-zero"
  fi

  local status_un=0
  (cd "$repo_wf" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_un=$?
  if [ "$status_un" -ne 0 ] && check_sentinel "uninstall on symlink .workflow"; then
    pass "symlink .workflow rejected on uninstall"
  else
    fail "uninstall on symlink .workflow should exit non-zero"
  fi

  # Subtest B: .agents is an external symlink pointing outside
  local repo_ag="$TMPDIR/repo_symlink_ag"
  mkdir -p "$repo_ag"
  echo "root" > "$repo_ag/README.md"
  ln -s "$outside" "$repo_ag/.agents"

  status_init=0
  (cd "$repo_ag" && "$WORKFLOW" init >/dev/null 2>&1) || status_init=$?
  if [ "$status_init" -ne 0 ] && check_sentinel "init on symlink .agents" && [ ! -e "$repo_ag/.workflow" ]; then
    pass "symlink .agents rejected on init without writing project content"
  else
    fail "init on symlink .agents should exit non-zero and not write project content"
  fi

  status_up=0
  (cd "$repo_ag" && "$WORKFLOW" update >/dev/null 2>&1) || status_up=$?
  if [ "$status_up" -ne 0 ] && check_sentinel "update on symlink .agents"; then
    pass "symlink .agents rejected on update"
  else
    fail "update on symlink .agents should exit non-zero"
  fi

  status_un=0
  (cd "$repo_ag" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_un=$?
  if [ "$status_un" -ne 0 ] && check_sentinel "uninstall on symlink .agents"; then
    pass "symlink .agents rejected on uninstall"
  else
    fail "uninstall on symlink .agents should exit non-zero"
  fi

  # Subtest C: Nested skill directory is a symlink pointing outside
  local repo_nested="$TMPDIR/repo_symlink_nested_skill"
  setup_repo "$repo_nested"
  local skill_outside="$TMPDIR/outside_skill_target"
  mkdir -p "$skill_outside"
  echo "SKILL_SENTINEL_VAL" > "$skill_outside/sentinel.txt"
  rm -rf "$repo_nested/.agents/skills/flow-spec"
  ln -s "$skill_outside" "$repo_nested/.agents/skills/flow-spec"

  status_init=0
  (cd "$repo_nested" && "$WORKFLOW" init >/dev/null 2>&1) || status_init=$?
  status_up=0
  (cd "$repo_nested" && "$WORKFLOW" update >/dev/null 2>&1) || status_up=$?
  status_un=0
  (cd "$repo_nested" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_un=$?

  if [ "$status_init" -ne 0 ] && [ "$status_up" -ne 0 ] && [ "$status_un" -ne 0 ] && \
     [ -f "$skill_outside/sentinel.txt" ] && [ "$(cat "$skill_outside/sentinel.txt")" = "SKILL_SENTINEL_VAL" ]; then
    pass "nested skill dir symlink rejected on init/update/uninstall with outside target intact"
  else
    fail "nested skill dir symlink should reject init/update/uninstall and protect outside target"
  fi

  # Subtest D: Managed file is a symlink pointing outside
  local repo_mf="$TMPDIR/repo_symlink_managed_file"
  setup_repo "$repo_mf"
  local mf_outside="$TMPDIR/outside_mf_target.md"
  echo "MF_SENTINEL_CONTENT" > "$mf_outside"
  rm -f "$repo_mf/.workflow/CONVENTIONS.md"
  ln -s "$mf_outside" "$repo_mf/.workflow/CONVENTIONS.md"

  status_init=0
  (cd "$repo_mf" && "$WORKFLOW" init >/dev/null 2>&1) || status_init=$?
  status_up=0
  (cd "$repo_mf" && "$WORKFLOW" update >/dev/null 2>&1) || status_up=$?
  status_un=0
  (cd "$repo_mf" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_un=$?

  if [ "$status_init" -ne 0 ] && [ "$status_up" -ne 0 ] && [ "$status_un" -ne 0 ] && \
     [ -f "$mf_outside" ] && [ "$(cat "$mf_outside")" = "MF_SENTINEL_CONTENT" ]; then
    pass "managed file symlink rejected on init/update/uninstall with outside target intact"
  else
    fail "managed file symlink should reject init/update/uninstall and protect outside target"
  fi

  # Subtest E: Managed marker is a symlink pointing outside
  local repo_mk="$TMPDIR/repo_symlink_marker"
  setup_repo "$repo_mk"
  local mk_outside="$TMPDIR/outside_marker_target"
  echo "MARKER_SENTINEL_CONTENT" > "$mk_outside"
  rm -f "$repo_mk/.workflow/.CONVENTIONS.workflow-managed"
  ln -s "$mk_outside" "$repo_mk/.workflow/.CONVENTIONS.workflow-managed"

  status_init=0
  (cd "$repo_mk" && "$WORKFLOW" init >/dev/null 2>&1) || status_init=$?
  status_up=0
  (cd "$repo_mk" && "$WORKFLOW" update >/dev/null 2>&1) || status_up=$?
  status_un=0
  (cd "$repo_mk" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_un=$?

  local repo_vf="$TMPDIR/repo_symlink_manifest"
  setup_repo "$repo_vf"
  rm -f "$repo_vf/.workflow/.workflow-version"
  ln -s "$mk_outside" "$repo_vf/.workflow/.workflow-version"
  local status_vf_up=0 status_vf_un=0
  (cd "$repo_vf" && "$WORKFLOW" update >/dev/null 2>&1) || status_vf_up=$?
  (cd "$repo_vf" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_vf_un=$?

  if [ "$status_init" -ne 0 ] && [ "$status_up" -ne 0 ] && [ "$status_un" -ne 0 ] && \
     [ "$status_vf_up" -ne 0 ] && [ "$status_vf_un" -ne 0 ] && \
     [ -f "$mk_outside" ] && [ "$(cat "$mk_outside")" = "MARKER_SENTINEL_CONTENT" ]; then
    pass "managed marker and manifest symlinks rejected on init/update/uninstall with outside target intact"
  else
    fail "managed marker or manifest symlink should reject init/update/uninstall and protect outside target"
  fi

  # Subtest F: AGENTS.md is a symlink pointing outside
  local repo_ag_md="$TMPDIR/repo_symlink_agents_md"
  mkdir -p "$repo_ag_md"
  echo "root" > "$repo_ag_md/README.md"
  local agents_outside="$TMPDIR/outside_agents_target.md"
  echo "AGENTS_SENTINEL_CONTENT" > "$agents_outside"
  ln -s "$agents_outside" "$repo_ag_md/AGENTS.md"

  status_init=0
  (cd "$repo_ag_md" && "$WORKFLOW" init >/dev/null 2>&1) || status_init=$?
  status_up=0
  (cd "$repo_ag_md" && "$WORKFLOW" update >/dev/null 2>&1) || status_up=$?
  status_un=0
  (cd "$repo_ag_md" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_un=$?

  if [ "$status_init" -ne 0 ] && [ "$status_up" -ne 0 ] && [ "$status_un" -ne 0 ] && \
     [ -f "$agents_outside" ] && [ "$(cat "$agents_outside")" = "AGENTS_SENTINEL_CONTENT" ]; then
    pass "AGENTS.md symlink rejected on init/update/uninstall with outside target intact"
  else
    fail "AGENTS.md symlink should reject init/update/uninstall and protect outside target"
  fi

  # Subtest G: AGENTS.md is dangling symlink
  local repo_dangling_ag="$TMPDIR/repo_dangling_agents"
  mkdir -p "$repo_dangling_ag"
  ln -s "$TMPDIR/nonexistent_outside_agents_target.md" "$repo_dangling_ag/AGENTS.md"

  status_init=0
  (cd "$repo_dangling_ag" && "$WORKFLOW" init >/dev/null 2>&1) || status_init=$?
  status_up=0
  (cd "$repo_dangling_ag" && "$WORKFLOW" update >/dev/null 2>&1) || status_up=$?
  status_un=0
  (cd "$repo_dangling_ag" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_un=$?

  if [ "$status_init" -ne 0 ] && [ "$status_up" -ne 0 ] && [ "$status_un" -ne 0 ] && \
     [ -L "$repo_dangling_ag/AGENTS.md" ] && [ ! -e "$repo_dangling_ag/AGENTS.md" ]; then
    pass "dangling AGENTS.md symlink rejected on init/update/uninstall"
  else
    fail "dangling AGENTS.md symlink should reject init/update/uninstall"
  fi

  # Subtest H: Dangling managed target symlink
  local repo_dangling_wf="$TMPDIR/repo_dangling_wf"
  mkdir -p "$repo_dangling_wf"
  ln -s "$TMPDIR/nonexistent_outside_wf_dir" "$repo_dangling_wf/.workflow"

  status_init=0
  (cd "$repo_dangling_wf" && "$WORKFLOW" init >/dev/null 2>&1) || status_init=$?
  status_up=0
  (cd "$repo_dangling_wf" && "$WORKFLOW" update >/dev/null 2>&1) || status_up=$?
  status_un=0
  (cd "$repo_dangling_wf" && "$WORKFLOW" uninstall >/dev/null 2>&1) || status_un=$?

  if [ "$status_init" -ne 0 ] && [ "$status_up" -ne 0 ] && [ "$status_un" -ne 0 ]; then
    pass "dangling .workflow symlink rejected on init/update/uninstall"
  else
    fail "dangling .workflow symlink should reject init/update/uninstall"
  fi
}

# --- Scenario: doctor rejects corrupted AGENTS markers without modifying content ---
test_doctor_agents_markers_validation() {
  local repo="$TMPDIR/repo_doctor_agents_markers"
  setup_repo "$repo"

  check_doctor_rejected_and_unchanged() {
    local label="$1"
    local expected_file="$TMPDIR/expected_agents.md"
    cp "$repo/AGENTS.md" "$expected_file"

    local status=0
    (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1) || status=$?
    if [ "$status" -ne 0 ]; then
      pass "doctor returns non-zero for $label"
    else
      fail "doctor should return non-zero for $label"
    fi

    if cmp -s "$repo/AGENTS.md" "$expected_file"; then
      pass "doctor did not modify AGENTS.md content for $label"
    else
      fail "doctor modified AGENTS.md content for $label"
    fi
    rm -f "$expected_file"
  }

  # 1. Unilateral start marker only (单侧 start)
  cat > "$repo/AGENTS.md" <<'EOF'
# Project Guidelines
<!-- workflow:start -->
Some dangling block content without end
EOF
  check_doctor_rejected_and_unchanged "unilateral start marker"

  # 2. Unilateral end marker only (单侧 end)
  cat > "$repo/AGENTS.md" <<'EOF'
# Project Guidelines
Some content
<!-- workflow:end -->
EOF
  check_doctor_rejected_and_unchanged "unilateral end marker"

  # 3. Duplicate start markers (重复 start)
  cat > "$repo/AGENTS.md" <<'EOF'
<!-- workflow:start -->
<!-- workflow:start -->
Block content
<!-- workflow:end -->
EOF
  check_doctor_rejected_and_unchanged "duplicate start markers"

  # 4. Duplicate end markers (重复 end)
  cat > "$repo/AGENTS.md" <<'EOF'
<!-- workflow:start -->
Block content
<!-- workflow:end -->
<!-- workflow:end -->
EOF
  check_doctor_rejected_and_unchanged "duplicate end markers"

  # 5. Reversed marker order (顺序逆转)
  cat > "$repo/AGENTS.md" <<'EOF'
# Guidelines
<!-- workflow:end -->
Inverted content
<!-- workflow:start -->
EOF
  check_doctor_rejected_and_unchanged "reversed marker order"

  # 6. Partial-line start marker (partial-line start)
  cat > "$repo/AGENTS.md" <<'EOF'
Prefix text <!-- workflow:start -->
Block content
<!-- workflow:end -->
EOF
  check_doctor_rejected_and_unchanged "partial-line start marker"

  # 7. Partial-line end marker (partial-line end)
  cat > "$repo/AGENTS.md" <<'EOF'
<!-- workflow:start -->
Block content
<!-- workflow:end --> Suffix text
EOF
  check_doctor_rejected_and_unchanged "partial-line end marker"

  # 8. Normal paired markers pass doctor (正常 paired 通过)
  local paired_content
  paired_content="$(cat "$KIT/templates/project/AGENTS.md")"
  printf '%s\n' "$paired_content" > "$repo/AGENTS.md"
  (cd "$repo" && "$WORKFLOW" init --force >/dev/null 2>&1 || true)
  # Ensure standards placeholder filled
  portable_sed 's/<[^>]*>/placeholder/g' "$repo/.workflow/standards.md"

  local status_paired=0
  (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1) || status_paired=$?
  if [ "$status_paired" -eq 0 ]; then
    pass "doctor passes with normal paired AGENTS markers"
  else
    fail "doctor should pass with normal paired AGENTS markers"
  fi

  if [ "$(cat "$repo/AGENTS.md")" = "$paired_content" ]; then
    pass "doctor did not modify normal paired AGENTS.md content"
  else
    fail "doctor modified normal paired AGENTS.md content"
  fi
}


# --- 2.3: the CLI travels with the project in .workflow/bin ---
test_vendored_cli() {
  local repo="$TMPDIR/repo_vendored"
  setup_repo "$repo"
  local cli="$repo/.workflow/bin/workflow"
  if [ -x "$cli" ] && [ -f "$repo/.workflow/bin/workflow-core.py" ] &&
     grep -q ' \.workflow/bin/workflow$' "$repo/.workflow/.workflow-version" &&
     [ -z "$(find "$repo" -name '*workflow-managed*' 2>/dev/null)" ]; then
    pass "init copies the CLI into .workflow/bin"
  else
    fail "init should copy an executable CLI into .workflow/bin"
  fi
  mkdir -p "$repo/.workflow/tasks/core"
  cat > "$repo/.workflow/tasks/core/01-first.md" <<'EOF'
# 01: First
**Effort:** core
**Check:** `true` passes
**Blocked by:** None
EOF
  local out
  out="$(cd "$repo" && "$cli" next --no-color 2>/dev/null)"
  if [[ "$out" == *"core/01 First"* ]]; then pass "committed CLI runs daily commands without the toolkit"; else fail "committed CLI next failed: $out"; fi
  if (cd "$repo" && "$cli" doctor >/dev/null 2>&1); then pass "committed CLI runs doctor"; else fail "committed CLI doctor should pass: $(cd "$repo" && "$cli" doctor 2>&1 | tail -5)"; fi
  out="$(cd "$repo" && "$cli" init 2>&1 || true)"
  if [[ "$out" == *"committed copy"* ]]; then pass "committed CLI refuses init and names the toolkit"; else fail "committed CLI init should refuse: $out"; fi

  printf '# local tweak\n' >> "$repo/.workflow/bin/workflow-core.py"
  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)"
  if [[ "$out" == *"skipped .workflow/bin/workflow-core.py"* ]] && tail -n 1 "$repo/.workflow/bin/workflow-core.py" | grep -q 'local tweak'; then
    pass "update keeps an edited CLI file"
  else
    fail "update should keep an edited CLI file: $out"
  fi
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *".workflow/bin/workflow-core.py edited"* ]]; then pass "doctor reports an edited CLI file"; else fail "doctor should report the edited CLI file: $out"; fi
  (cd "$repo" && "$WORKFLOW" update --force >/dev/null 2>&1)
  if cmp -s "$repo/.workflow/bin/workflow-core.py" "$KIT/bin/workflow-core.py"; then pass "update --force restores the CLI file"; else fail "update --force should restore the CLI file"; fi

  (cd "$repo" && "$WORKFLOW" uninstall >/dev/null 2>&1)
  if [ ! -e "$repo/.workflow/bin" ]; then pass "uninstall removes .workflow/bin"; else fail "uninstall should remove .workflow/bin"; fi
}

# --- 2.3: Claude Code adapter ---
test_claude_adapter() {
  local repo="$TMPDIR/repo_claude_off"
  setup_repo "$repo"
  if [ ! -e "$repo/.claude" ] && [ ! -e "$repo/CLAUDE.md" ]; then pass "no Claude files without CLAUDE.md, .claude/ or --claude"; else fail "Claude files written without being asked"; fi

  repo="$TMPDIR/repo_claude_auto"
  mkdir -p "$repo"
  printf '# Notes for Claude\n\nKeep this line.\n' > "$repo/CLAUDE.md"
  setup_repo "$repo"
  if [ -f "$repo/.claude/skills/flow-start/SKILL.md" ] && grep -q '^tools: Read, Grep, Glob, Bash$' "$repo/.claude/agents/workflow-reviewer.md"; then
    pass "existing CLAUDE.md turns on .claude skills and agents with Claude tool names"
  else
    fail "existing CLAUDE.md should install .claude skills and agents"
  fi
  if grep -qx '@AGENTS.md' "$repo/CLAUDE.md" && grep -q 'Keep this line.' "$repo/CLAUDE.md"; then
    pass "CLAUDE.md gains an AGENTS.md import and keeps its own text"
  else
    fail "CLAUDE.md should import AGENTS.md and keep its text"
  fi
  if grep -qx 'claude: yes' "$repo/.workflow/.workflow-version"; then pass "manifest records the Claude choice"; else fail "manifest should record claude: yes"; fi
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then pass "doctor passes with Claude files"; else fail "doctor should pass with Claude files: $(cd "$repo" && "$WORKFLOW" doctor 2>&1 | grep '!')"; fi
  (cd "$repo" && "$WORKFLOW" uninstall >/dev/null 2>&1)
  if [ ! -e "$repo/.claude" ] && grep -q 'Keep this line.' "$repo/CLAUDE.md" && ! grep -q '@AGENTS.md' "$repo/CLAUDE.md"; then
    pass "uninstall removes Claude files and the import, keeps the user's CLAUDE.md"
  else
    fail "uninstall should remove the Claude files and the import only"
  fi

  repo="$TMPDIR/repo_claude_flag"
  mkdir -p "$repo"; git -C "$repo" init -q
  (cd "$repo" && "$WORKFLOW" init --claude >/dev/null 2>&1)
  if [ -f "$repo/.claude/skills/flow-implement/SKILL.md" ] && [ -f "$repo/CLAUDE.md" ]; then pass "init --claude installs the adapter"; else fail "init --claude should install the adapter"; fi
}

# --- 2.3: pre-commit hook ---
test_pre_commit_hook() {
  local repo="$TMPDIR/repo_hook"
  setup_repo "$repo"
  local cli="$repo/.workflow/bin/workflow"
  if [ ! -e "$repo/.git/hooks/pre-commit" ]; then pass "setup_repo leaves the pre-commit hook out"; else fail "setup_repo should not install a hook"; fi
  (cd "$repo" && "$cli" hook install >/dev/null 2>&1)
  if [ -x "$repo/.git/hooks/pre-commit" ] && grep -q 'workflow:pre-commit' "$repo/.git/hooks/pre-commit"; then pass "hook install writes the pre-commit hook"; else fail "hook install should write the hook"; fi
  mkdir -p "$repo/.workflow/tasks/core"
  cat > "$repo/.workflow/tasks/core/01-ok.md" <<'EOF'
# 01: Fine
**Effort:** core
**Check:** `true` passes
**Blocked by:** None
EOF
  mkdir -p "$repo/.workflow/done/core"
  printf '# 02: Old\n\n**Effort:** core\n\n## Progress\n\nCheck after: ran on the final code\nReview: pass (base abc1234)\n' \
    > "$repo/.workflow/done/core/02-old.md"
  local status=0
  (cd "$repo" && "$cli" validate --no-color >/dev/null 2>&1) || status=$?
  if [ "$status" -eq 1 ]; then pass "hook warning fixture returns validate exit 1"; else fail "hook warning fixture should return validate exit 1, got $status"; fi
  git -C "$repo" add -A
  if git -C "$repo" commit -q -m ok >/dev/null 2>&1; then pass "hook lets a commit with only warnings through"; else fail "hook should not block on warnings"; fi
  cat > "$repo/.workflow/tasks/core/02-bad.md" <<'EOF'
# 02: Broken
**Effort:** core
**Check:** `true` passes
**Blocked by:** 99
EOF
  git -C "$repo" add -A
  if git -C "$repo" commit -q -m bad >/dev/null 2>&1; then fail "hook should block a commit with validate errors"; else pass "hook blocks a commit with validate errors"; fi
  git -C "$repo" rm --cached -q "$repo/.workflow/tasks/core/02-bad.md"
  # Partially staged metadata: valid staged content passes commit even if worktree has unstaged errors
  cat > "$repo/.workflow/tasks/core/03-staged.md" <<'EOF'
# 03: Valid
**Effort:** core
**Check:** `true` passes
**Blocked by:** None
EOF
  git -C "$repo" add "$repo/.workflow/tasks/core/03-staged.md"
  cat > "$repo/.workflow/tasks/core/03-staged.md" <<'EOF'
# 03: Valid
**Effort:** core
**Blocked by:** None
EOF
  if git -C "$repo" commit -q -m "staged valid passes" >/dev/null 2>&1; then
    pass "hook validates staged index and allows commit when worktree has unstaged error"
  else
    fail "hook should validate staged index and allow commit when staged is valid"
  fi

  # Conversely: invalid staged content blocks commit even if worktree was fixed
  git -C "$repo" add "$repo/.workflow/tasks/core/03-staged.md"
  cat > "$repo/.workflow/tasks/core/03-staged.md" <<'EOF'
# 03: Valid
**Effort:** core
**Check:** `true` passes
**Blocked by:** None
EOF
  if git -C "$repo" commit -q -m "staged invalid blocks" >/dev/null 2>&1; then
    fail "hook should block commit when staged index has validate errors even if worktree is fixed"
  else
    pass "hook blocks commit when staged index has validate errors"
  fi
  git -C "$repo" checkout HEAD -- "$repo/.workflow/tasks/core/03-staged.md" >/dev/null 2>&1 || true
  rm -f "$repo/.workflow/tasks/core/03-staged.md"
  git -C "$repo" rm -qf "$repo/.workflow/tasks/core/03-staged.md" >/dev/null 2>&1 || true
  git -C "$repo" commit --allow-empty -q -m "clean staged fixture" >/dev/null 2>&1 || true
  rm -f "$repo/.workflow/tasks/core/02-bad.md"; git -C "$repo" add -A
  local no_python="$TMPDIR/hook_no_python" tool
  mkdir -p "$no_python"
  for tool in git bash dirname; do ln -s "$(command -v "$tool")" "$no_python/$tool"; done
  status=0
  (cd "$repo" && PATH="$no_python" bash "$cli" validate --no-color >/dev/null 2>&1) || status=$?
  if [ "$status" -ge 2 ]; then pass "validate errors when Python is missing"; else fail "missing Python should return an error exit, got $status"; fi
  if PATH="$no_python" git -C "$repo" commit --allow-empty -q -m missing-python >/dev/null 2>&1; then fail "hook should block when Python is missing"; else pass "hook blocks a real commit when Python is missing"; fi

  mv "$repo/.workflow/bin/workflow-core.py" "$TMPDIR/hook-core.py"
  status=0
  (cd "$repo" && "$cli" validate --no-color >/dev/null 2>&1) || status=$?
  if [ "$status" -ge 2 ]; then pass "validate errors when its core is missing"; else fail "missing core should return an error exit, got $status"; fi
  if git -C "$repo" commit --allow-empty -q -m missing-core >/dev/null 2>&1; then fail "hook should block when the core is missing"; else pass "hook blocks a real commit when the core is missing"; fi
  mv "$TMPDIR/hook-core.py" "$repo/.workflow/bin/workflow-core.py"

  mv "$cli" "$TMPDIR/hook-cli"
  if git -C "$repo" commit --allow-empty -q -m missing-cli >/dev/null 2>&1; then fail "hook should block when the project CLI is missing"; else pass "hook blocks a real commit when the project CLI is missing"; fi
  mv "$TMPDIR/hook-cli" "$cli"
  (cd "$repo" && "$cli" hook uninstall >/dev/null 2>&1)
  if [ ! -e "$repo/.git/hooks/pre-commit" ]; then pass "hook uninstall removes our hook"; else fail "hook uninstall should remove our hook"; fi
  printf '#!/bin/sh\nexit 0\n' > "$repo/.git/hooks/pre-commit"
  if (cd "$repo" && "$cli" hook install >/dev/null 2>&1); then fail "hook install should refuse a foreign hook"; else pass "hook install refuses to replace someone else's hook"; fi
  if grep -q 'exit 0' "$repo/.git/hooks/pre-commit" && ! grep -q 'workflow:pre-commit' "$repo/.git/hooks/pre-commit"; then pass "foreign hook left untouched"; else fail "foreign hook was modified"; fi
  (cd "$repo" && "$cli" hook install --append >/dev/null 2>&1)
  if grep -q 'workflow:pre-commit:start' "$repo/.git/hooks/pre-commit" && grep -q 'exit 0' "$repo/.git/hooks/pre-commit"; then
    pass "hook install --append adds managed block to foreign hook"
  else
    fail "hook install --append should preserve foreign hook and add managed block"
  fi
  (cd "$repo" && "$cli" hook uninstall >/dev/null 2>&1)
  if [ -f "$repo/.git/hooks/pre-commit" ] && grep -q 'exit 0' "$repo/.git/hooks/pre-commit" && ! grep -q 'workflow:pre-commit' "$repo/.git/hooks/pre-commit"; then
    pass "hook uninstall removes only the appended block from foreign hook"
  else
    fail "hook uninstall should remove only the appended block and keep foreign hook"
  fi
  (cd "$repo" && "$cli" hook install --force >/dev/null 2>&1)
  (cd "$repo" && "$WORKFLOW" uninstall >/dev/null 2>&1)
  if git -C "$repo" commit --allow-empty -q -m uninstalled >/dev/null 2>&1; then pass "full uninstall leaves no blocking workflow hook"; else fail "full uninstall should leave commits possible without the CLI"; fi
}

# --- 2.3: tasks/<effort>/ layout is read the same way by every command ---
test_effort_directory_layout() {
  local repo="$TMPDIR/repo_layout"
  setup_repo "$repo"
  mkdir -p "$repo/.workflow/tasks/api" "$repo/.workflow/tasks/web"
  cat > "$repo/.workflow/tasks/api/01-setup.md" <<'EOF'
# 01: API setup
**Effort:** api
**Check:** `true` passes
**Blocked by:** None
EOF
  cat > "$repo/.workflow/tasks/web/01-setup.md" <<'EOF'
# 01: Web setup
**Effort:** web
**Check:** `true` passes
**Blocked by:** api/01
EOF
  local next
  next="$(cd "$repo" && "$WORKFLOW" next --no-color 2>/dev/null)"
  if [[ "$next" == *"api/01 API setup"* ]]; then
    pass "next reads tasks/<effort>/ and names tasks <effort>/<NN>"
  else
    fail "next should read nested tasks: $next"
  fi
  if (cd "$repo" && "$WORKFLOW" validate --no-color >/dev/null 2>&1 || [ $? -eq 1 ]); then pass "same file name in two effort directories is valid"; else fail "two efforts may both have 01-setup.md"; fi
  portable_sed 's/^\*\*Effort:\*\* web$/**Effort:** api/' "$repo/.workflow/tasks/web/01-setup.md"
  local out; out="$(cd "$repo" && "$WORKFLOW" validate --no-color 2>&1 || true)"
  if [[ "$out" == *"task is under web/ but its Effort is 'api'"* ]]; then pass "validate rejects an Effort that disagrees with its directory"; else fail "validate should reject a directory/Effort mismatch: $out"; fi
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"task is under web/"* ]] && ! (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then pass "doctor reports validate's errors and fails"; else fail "doctor should surface validate errors: $out"; fi
}

# --- 2.5: .gitattributes union-merge block ---
test_gitattributes_block() {
  local repo="$TMPDIR/repo_gitattributes" out
  setup_repo "$repo"
  if grep -qx '# workflow:start' "$repo/.gitattributes" && grep -qx '.workflow/decisions.md merge=union' "$repo/.gitattributes" &&
     grep -qx '.workflow/glossary.md merge=union' "$repo/.gitattributes" && grep -qx '# workflow:end' "$repo/.gitattributes"; then
    pass "init writes the .gitattributes union-merge block"
  else
    fail "init should write the .gitattributes block"
  fi
  (cd "$repo" && "$WORKFLOW" update >/dev/null 2>&1)
  if [ "$(grep -c '^# workflow:start$' "$repo/.gitattributes")" = 1 ]; then pass "update keeps one .gitattributes block"; else fail "update duplicated the .gitattributes block"; fi
  (cd "$repo" && "$WORKFLOW" uninstall >/dev/null 2>&1)
  if [ ! -e "$repo/.gitattributes" ]; then pass "uninstall deletes a .gitattributes that held only the block"; else fail "uninstall should delete the emptied .gitattributes"; fi

  repo="$TMPDIR/repo_gitattributes_own"
  mkdir -p "$repo"
  printf '*.png binary\n' > "$repo/.gitattributes"
  setup_repo "$repo"
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *".gitattributes has the workflow union-merge block"* ]] && grep -qx '\*.png binary' "$repo/.gitattributes"; then
    pass "init appends the block to an existing .gitattributes and doctor sees it"
  else
    fail "init should append the block and keep the user's lines: $out"
  fi
  (cd "$repo" && "$WORKFLOW" uninstall >/dev/null 2>&1)
  if [ "$(cat "$repo/.gitattributes")" = '*.png binary' ]; then pass "uninstall removes only the block from .gitattributes"; else fail "uninstall should leave the user's .gitattributes lines: $(cat "$repo/.gitattributes")"; fi

  repo="$TMPDIR/repo_gitattributes_missing"
  setup_repo "$repo"
  rm -f "$repo/.gitattributes"
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *".gitattributes is missing the workflow union-merge block"* ]]; then pass "doctor reports a missing .gitattributes block"; else fail "doctor should report the missing block: $out"; fi
}

# --- 2.7: branches must agree on the workflow version ---
test_doctor_branch_version_drift() {
  local repo="$TMPDIR/repo_drift" out status
  setup_repo "$repo"
  git -C "$repo" branch -M main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "workflow install"

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1)" || true
  if [[ "$out" != *"this tree has workflow"* ]] && [[ "$out" != *"is not committed"* ]]; then
    pass "doctor is quiet about workflow versions on a clean main"
  else
    fail "doctor should not warn on a clean main: $out"
  fi

  local current
  current="$(sed -n 's/^version: //p' "$repo/.workflow/.workflow-version")"
  git -C "$repo" checkout -q -b feature
  portable_sed 's/^version: .*/version: 2.6.0/' "$repo/.workflow/.workflow-version"
  git -C "$repo" commit -qam "stale workflow"
  status=0
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1)" || status=$?
  if [ "$status" -ne 0 ] && [[ "$out" == *"this tree has workflow 2.6.0, main has $current: merge main into this branch, or commit the update on main"* ]]; then
    pass "doctor warns when a branch carries an older workflow than main"
  else
    fail "doctor should report version drift and fail (exit $status): $out"
  fi
}

test_doctor_uncommitted_update() {
  local repo="$TMPDIR/repo_uncommitted" out status
  setup_repo "$repo"
  git -C "$repo" branch -M main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "workflow install"
  portable_sed 's/^version: .*/version: 99.0.0/' "$repo/.workflow/.workflow-version"
  status=0
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1)" || status=$?
  if [ "$status" -ne 0 ] && [[ "$out" == *"the last 'workflow update' is not committed: commit it on main; other branches and worktrees keep the old rules until they merge it"* ]]; then
    pass "doctor reports an uncommitted workflow update"
  else
    fail "doctor should report the uncommitted update and fail (exit $status): $out"
  fi
}

# --- 2.7: update points at the main branch ---
test_update_branch_guidance() {
  local repo="$TMPDIR/repo_update_branch" out status
  setup_repo "$repo"
  git -C "$repo" branch -M main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "workflow install"

  status=0
  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)" || status=$?
  if [ "$status" -eq 0 ] &&
     [[ "$out" == *"Commit these files on the main branch; other branches and worktrees keep the old rules until they merge or rebase onto it."* ]] &&
     [[ "$out" != *"not main: commit the update on main first"* ]]; then
    pass "update asks for a commit on main without warning when already there"
  else
    fail "update should point at main and not warn on main (exit $status): $out"
  fi

  git -C "$repo" checkout -q -b feature
  status=0
  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)" || status=$?
  if [ "$status" -eq 0 ] &&
     [[ "$out" == *"Commit these files on the main branch; other branches and worktrees keep the old rules until they merge or rebase onto it."* ]] &&
     [[ "$out" == *"you are on feature, not main: commit the update on main first"* ]]; then
    pass "update warns when run on a branch other than main"
  else
    fail "update should warn on a non-main branch (exit $status): $out"
  fi
}

# --- 2.5: removed commands and stale managed copies ---
test_removed_commands_and_stale_copies() {
  local repo="$TMPDIR/repo_removed" out status cmd
  setup_repo "$repo"
  for cmd in tasks deps decisions effort debt hotfix-review; do
    status=0; out="$(cd "$repo" && "$WORKFLOW" "$cmd" 2>&1 >/dev/null)" || status=$?
    if [ "$status" -eq 2 ] && [[ "$out" == "workflow $cmd was removed in 2.5: "* ]]; then
      pass "workflow $cmd exits 2 with a removal hint"
    else
      fail "workflow $cmd should exit 2 with a removal hint (exit $status): $out"
    fi
  done
  status=0; out="$(cd "$repo" && "$WORKFLOW" pulse 2>&1 >/dev/null)" || status=$?
  if [ "$status" -eq 2 ] && [[ "$out" == "workflow pulse was removed: "* ]]; then
    pass "workflow pulse exits 2 with a removal hint"
  else
    fail "workflow pulse should exit 2 with a removal hint (exit $status): $out"
  fi

  local bin="$repo/.workflow/bin"
  printf '#!/usr/bin/env bash\necho old\n' > "$bin/workflow-tasks"
  printf '#!/usr/bin/env bash\necho old\n' > "$bin/workflow-deps"
  printf '%s workflow-tasks\n%s workflow-deps\n' "$(cksum < "$bin/workflow-tasks" | cut -d' ' -f1)" \
    "$(cksum < "$bin/workflow-deps" | cut -d' ' -f1)" >> "$bin/.workflow-managed"
  printf '# local tweak\n' >> "$bin/workflow-deps"
  printf 'old thinking notes\n' > "$repo/.workflow/thinking.md"
  cksum < "$repo/.workflow/thinking.md" | cut -d' ' -f1 > "$repo/.workflow/.thinking.workflow-managed"
  printf 'old phase notes\n' > "$repo/.workflow/phase-boundaries.md"
  cksum < "$repo/.workflow/phase-boundaries.md" | cut -d' ' -f1 > "$repo/.workflow/.phase-boundaries.workflow-managed"
  printf 'old merge notes\n' > "$repo/.workflow/merge-strategy.md"
  cksum < "$repo/.workflow/merge-strategy.md" | cut -d' ' -f1 > "$repo/.workflow/.merge-strategy.workflow-managed"
  printf 'old spike notes\n' > "$repo/.workflow/spike-tasks.md"
  cksum < "$repo/.workflow/spike-tasks.md" | cut -d' ' -f1 > "$repo/.workflow/.spike-tasks.workflow-managed"
  mkdir -p "$repo/.agents/skills/flow-map"
  printf 'old map skill\n' > "$repo/.agents/skills/flow-map/SKILL.md"
  cksum < "$repo/.agents/skills/flow-map/SKILL.md" | cut -d' ' -f1 > "$repo/.agents/skills/flow-map/.workflow-managed"
  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)"
  if [ ! -e "$bin/workflow-tasks" ]; then pass "update deletes an unmodified stale .workflow/bin/workflow-tasks"; else fail "update should delete the stale workflow-tasks: $out"; fi
  if [ -f "$bin/workflow-deps" ] && [[ "$out" == *"kept .workflow/bin/workflow-deps"* ]]; then pass "update keeps an edited stale CLI file with a warning"; else fail "update should keep the edited workflow-deps: $out"; fi
  for retired in thinking phase-boundaries merge-strategy spike-tasks; do
    if [ ! -e "$repo/.workflow/${retired}.md" ] && [ ! -e "$repo/.workflow/.${retired}.workflow-managed" ]; then
      pass "update deletes an unmodified .workflow/${retired}.md"
    else
      fail "update should delete the unmodified ${retired}.md: $out"
    fi
  done
  if [ ! -e "$repo/.agents/skills/flow-map" ]; then
    pass "update deletes retired skill flow-map"
  else
    fail "update should delete retired skill flow-map: $out"
  fi
}

test_next_flags_cli() {
  local repo="$TMPDIR/repo_next_flags" out
  setup_repo "$repo"
  out="$(cd "$repo" && ./.workflow/bin/workflow next --brief)"
  if [ -z "$out" ]; then pass "workflow next --brief stays silent when queue is empty"; else fail "next --brief printed on idle queue: $out"; fi
  mkdir -p "$repo/.workflow/tasks/alpha" "$repo/.workflow/tasks/beta"
  for n in 01 02 03 04 05 06; do
    cat > "$repo/.workflow/tasks/alpha/${n}-slice.md" <<EOF
# ${n}: Slice ${n}
**Effort:** alpha
**Blocked by:** None
**Files:** src/shared.ts
**Check:** echo ok
EOF
  done
  cat > "$repo/.workflow/tasks/beta/01-other.md" <<'EOF'
# 01: Other
**Effort:** beta
**Blocked by:** None
**Check:** echo ok
EOF
  out="$(cd "$repo" && ./.workflow/bin/workflow next --effort alpha --all --no-color)"
  if [[ "$out" == *"Ready tasks (6):"* ]] && [[ "$out" == *"6) alpha/06"* ]] && [[ "$out" != *"beta/01"* ]] && [[ "$out" == *"Shared files across ready tasks"* ]]; then
    pass "workflow next --effort --all scopes tasks, lifts 5-cap, and reports shared files"
  else
    fail "unexpected workflow next --effort --all output: $out"
  fi
  out="$(cd "$repo" && ./.workflow/bin/workflow next --effort alpha --brief --no-color)"
  if [[ "$out" == *"Ready (6):"* ]] && [[ "$out" == *"Overlaps: src/shared.ts"* ]] && [[ "$out" != *"Pulse:"* ]]; then
    pass "workflow next --effort --brief reports ready tasks and overlaps without directives"
  else
    fail "unexpected workflow next --brief output: $out"
  fi
}

# --- Standards placeholder check avoids false positives on generics/HTML ---
test_standards_placeholder_precision() {
  local repo="$TMPDIR/repo_standards_generics" out status=0
  setup_repo "$repo"
  cat > "$repo/.workflow/standards.md" <<'EOF'
# Standards
## Project
CLI service returning Result<void> and Promise<string | null> over <div> output.
## Landing
Landing: direct
EOF
  out="$(cd "$repo" && ./.workflow/bin/workflow doctor 2>&1)" || status=$?
  if [ "$status" -eq 0 ] && [[ "$out" != *"unfilled placeholders"* ]]; then
    pass "doctor accepts generic types and HTML tags in filled standards.md"
  else
    fail "doctor false-positived on filled standards.md (exit $status): $out"
  fi
  printf '\nLanding: <TODO: direct | local-merge | pr>\n' >> "$repo/.workflow/standards.md"
  status=0
  out="$(cd "$repo" && ./.workflow/bin/workflow doctor 2>&1)" || status=$?
  if [ "$status" -ne 0 ] && [[ "$out" == *"standards.md still contains unfilled placeholders"* ]]; then
    pass "doctor catches <TODO: ...> placeholders in standards.md"
  else
    fail "doctor missed <TODO: ...> placeholder in standards.md (exit $status): $out"
  fi
}

# --- Consolidated manifest in .workflow-version & legacy .workflow-managed migration ---
test_single_manifest_and_legacy_marker_migration() {
  local repo="$TMPDIR/repo_manifest_migration" out status=0
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  echo "root" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial"
  (cd "$repo" && "$WORKFLOW" init --claude >/dev/null 2>&1)
  portable_sed 's/<[^>]*>/placeholder/g' "$repo/.workflow/standards.md"

  if [ -z "$(find "$repo" -name '*workflow-managed*' 2>/dev/null)" ] &&
     grep -qx 'managed:' "$repo/.workflow/.workflow-version" &&
     grep -q ' AGENTS\.md#workflow-block$' "$repo/.workflow/.workflow-version" &&
     grep -q ' CLAUDE\.md#workflow-block$' "$repo/.workflow/.workflow-version"; then
    pass "init --claude records all checksums in .workflow-version with zero .workflow-managed dotfiles"
  else
    fail "init --claude should write single manifest without .workflow-managed dotfiles"
  fi

  # Simulate a pre-consolidation repo with legacy .workflow-managed files and no managed: section
  awk '/^managed:$/ { exit } { print }' "$repo/.workflow/.workflow-version" > "$repo/.workflow/.workflow-version.tmp"
  mv "$repo/.workflow/.workflow-version.tmp" "$repo/.workflow/.workflow-version"
  local s_dir
  for s_dir in "$repo/.agents/skills"/*/ "$repo/.claude/skills"/*/; do
    cksum < "${s_dir}SKILL.md" | cut -d' ' -f1 > "${s_dir}.workflow-managed"
  done
  local a_file a_base
  for a_file in "$repo/.agents/agents"/*.md "$repo/.claude/agents"/*.md; do
    a_base="$(basename "$a_file" .md)"
    cksum < "$a_file" | cut -d' ' -f1 > "$(dirname "$a_file")/.${a_base}.workflow-managed"
  done
  cksum < "$repo/.workflow/CONVENTIONS.md" | cut -d' ' -f1 > "$repo/.workflow/.CONVENTIONS.workflow-managed"
  cksum < "$repo/.workflow/STYLE.md" | cut -d' ' -f1 > "$repo/.workflow/.STYLE.workflow-managed"
  cksum < "$KIT/templates/project/AGENTS.md" | cut -d' ' -f1 > "$repo/.workflow/.agents-block.workflow-managed"
  cksum < "$KIT/templates/project/CLAUDE.md" | cut -d' ' -f1 > "$repo/.workflow/.claude-block.workflow-managed"
  printf '%s workflow\n%s workflow-core.py\n' \
    "$(cksum < "$repo/.workflow/bin/workflow" | cut -d' ' -f1)" \
    "$(cksum < "$repo/.workflow/bin/workflow-core.py" | cut -d' ' -f1)" > "$repo/.workflow/bin/.workflow-managed"

  # Edit one skill locally before migrating
  printf '\n<!-- local skill customization -->\n' >> "$repo/.agents/skills/flow-grill/SKILL.md"

  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)"
  if [ -z "$(find "$repo" -name '*workflow-managed*' 2>/dev/null)" ] &&
     grep -qx 'managed:' "$repo/.workflow/.workflow-version" &&
     grep -q 'local skill customization' "$repo/.agents/skills/flow-grill/SKILL.md" &&
     [[ "$out" == *"skipped skill flow-grill"* ]]; then
    pass "update migrates and removes all legacy .workflow-managed dotfiles while preserving local edits"
  else
    fail "update failed to migrate legacy .workflow-managed files cleanly: $out"
  fi

  status=0
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1)" || status=$?
  if [ "$status" -ne 0 ] && [[ "$out" == *"skill flow-grill edited"* ]]; then
    pass "doctor still detects pre-migration local skill edit from consolidated manifest"
  else
    fail "doctor should detect preserved local skill edit after migration (exit $status): $out"
  fi
}

test_bash_temp_files_cleanup() {
  local repo="$TMPDIR/repo_tmp_cleanup"
  setup_repo "$repo"
  local tmp_before tmp_after
  tmp_before="$(find "$TMPDIR" -name 'tmp.*' 2>/dev/null | wc -l)"
  (cd "$repo" && "$WORKFLOW" update >/dev/null 2>&1)
  (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1 || true)
  tmp_after="$(find "$TMPDIR" -name 'tmp.*' 2>/dev/null | wc -l)"
  if [ "$tmp_after" -le "$tmp_before" ]; then
    pass "workflow traps clean up temp files on exit and signals"
  else
    fail "workflow left temporary files behind: before=$tmp_before after=$tmp_after"
  fi
}

test_task_lifecycle_cli() {
  local repo="$TMPDIR/repo_task_lifecycle"
  setup_repo "$repo"
  local cli="$repo/.workflow/bin/workflow"

  # Initial commit so git HEAD is valid
  git -C "$repo" commit --allow-empty -q -m "initial commit"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"

  mkdir -p "$repo/.workflow/specs" "$repo/.workflow/tasks/core"
  cat > "$repo/.workflow/specs/core.md" <<'EOF'
# Spec: core

**Status:** proposed
**Priority:** normal

## What this is for
Core spec goal.

## How we will know it is done
- **W1.** Spec passes.
EOF

  cat > "$repo/.workflow/tasks/core/01-init.md" <<'EOF'
# 01: Init core

**Effort:** core
**Blocked by:** None
**Check:** echo ok

<!-- preserved comment -->
## Context
Preserved task body text.
EOF

  # 1. Project CLI starts task
  local out status=0
  out="$(cd "$repo" && "$cli" task start core/01 2>&1)" || status=$?
  if [ "$status" -eq 0 ] && [[ "$out" == *"Started task core/01"* ]]; then
    pass "cli task start succeeds and outputs confirmation"
  else
    fail "cli task start failed (exit $status): $out"
  fi

  if grep -qF "**Base commit:** $head_sha" "$repo/.workflow/tasks/core/01-init.md" && \
     grep -qF "**Status:** active" "$repo/.workflow/tasks/core/01-init.md" && \
     grep -q "Preserved task body text." "$repo/.workflow/tasks/core/01-init.md"; then
    pass "cli task start records Base commit, sets Status active, and preserves task body"
  else
    fail "cli task start did not correctly update task file: $(cat "$repo/.workflow/tasks/core/01-init.md")"
  fi

  if grep -qF "**Status:** in progress" "$repo/.workflow/specs/core.md"; then
    pass "cli task start advances matching spec to in progress"
  else
    fail "cli task start should advance spec to in progress: $(cat "$repo/.workflow/specs/core.md")"
  fi

  # 2. Global wrapper works as well
  status=0
  out="$(cd "$repo" && "$WORKFLOW" task start core/01 2>&1)" || status=$?
  if [ "$status" -eq 0 ]; then
    pass "global workflow task start succeeds idempotently"
  else
    fail "global workflow task start failed (exit $status): $out"
  fi

  # 3. Task archive refuses unticked checkboxes
  cat >> "$repo/.workflow/tasks/core/01-init.md" <<'EOF'

- [ ] unticked checklist item

## Progress

Check after: verified
EOF

  status=0
  out="$(cd "$repo" && "$cli" task archive core/01 2>&1)" || status=$?
  if [ "$status" -ne 0 ] && [[ "$out" == *"unticked"* ]] && [ -f "$repo/.workflow/tasks/core/01-init.md" ]; then
    pass "cli task archive refuses task with unticked checkboxes and retains source"
  else
    fail "cli task archive should refuse unticked checkbox (exit $status): $out"
  fi

  # 4. Task archive refuses missing Check after proof
  portable_sed 's/- \[ \]/- [x]/' "$repo/.workflow/tasks/core/01-init.md"
  portable_sed '/Check after:/d' "$repo/.workflow/tasks/core/01-init.md"

  status=0
  out="$(cd "$repo" && "$cli" task archive core/01 2>&1)" || status=$?
  if [ "$status" -ne 0 ] && [[ "$out" == *"archived without a Check after or Check waived record"* ]] && [ -f "$repo/.workflow/tasks/core/01-init.md" ]; then
    pass "cli task archive refuses missing Check after proof"
  else
    fail "cli task archive should refuse missing Check after (exit $status): $out"
  fi

  # 5. Task archive refuses to clobber existing destination
  printf '\nCheck after: verified\nReview: pass (base %s)\n' "$head_sha" >> "$repo/.workflow/tasks/core/01-init.md"
  mkdir -p "$repo/.workflow/done/core"
  printf 'EXISTING_ARCHIVE_CONTENT\n' > "$repo/.workflow/done/core/01-init.md"

  status=0
  out="$(cd "$repo" && "$cli" task archive core/01 2>&1)" || status=$?
  if [ "$status" -ne 0 ] && [[ "$out" == *"destination file already exists"* ]] && \
     grep -q 'EXISTING_ARCHIVE_CONTENT' "$repo/.workflow/done/core/01-init.md"; then
    pass "cli task archive refuses to overwrite existing destination"
  else
    fail "cli task archive should not overwrite existing destination (exit $status): $out"
  fi

  # 6. Task archive succeeds after clearing collision
  rm -f "$repo/.workflow/done/core/01-init.md"
  status=0
  out="$(cd "$repo" && "$cli" task archive core/01 2>&1)" || status=$?
  if [ "$status" -eq 0 ] && [[ "$out" == *"Archived task core/01"* ]]; then
    pass "cli task archive succeeds"
  else
    fail "cli task archive failed (exit $status): $out"
  fi

  if [ ! -e "$repo/.workflow/tasks/core/01-init.md" ] && \
     [ -f "$repo/.workflow/done/core/01-init.md" ] && \
     ! grep -q 'Status:' "$repo/.workflow/done/core/01-init.md" && \
     grep -q 'Preserved task body text.' "$repo/.workflow/done/core/01-init.md" && \
     grep -q 'Check after: verified' "$repo/.workflow/done/core/01-init.md" && \
     grep -q "Review: pass (base $head_sha)" "$repo/.workflow/done/core/01-init.md"; then
    pass "cli task archive moved file to done/, removed Status, and preserved body"
  else
    fail "cli task archive file state incorrect: $(cat "$repo/.workflow/done/core/01-init.md" 2>/dev/null || true)"
  fi

  if (cd "$repo" && "$cli" validate --no-color >/dev/null 2>&1); then
    pass "validate passes after task archive"
  else
    fail "validate failed after task archive: $(cd "$repo" && "$cli" validate --no-color 2>&1 || true)"
  fi
}

# --- 2.11: .workflow/.gitignore is generated, topped up, and removed only unedited ---
test_workflow_gitignore() {
  local repo="$TMPDIR/repo_gitignore" out
  setup_repo "$repo"
  local expected
  expected="$(printf '# workflow: local-only state\nworktrees/\nHANDOFF.md')"

  if [ -f "$repo/.workflow/.gitignore" ] && [ "$(cat "$repo/.workflow/.gitignore")" = "$expected" ]; then
    pass "init writes .workflow/.gitignore"
  else
    fail "init should write .workflow/.gitignore: $(cat "$repo/.workflow/.gitignore" 2>/dev/null || true)"
  fi
  if git -C "$repo" check-ignore -q .workflow/worktrees/x; then
    pass "git check-ignore accepts .workflow/worktrees/x after init"
  else
    fail ".workflow/worktrees/x should be git-ignored after init"
  fi
  if ! grep -q ' .workflow/.gitignore$' "$repo/.workflow/.workflow-version"; then
    pass ".workflow/.gitignore is not recorded in the managed manifest"
  else
    fail ".workflow/.gitignore must stay out of the managed: manifest"
  fi

  # update appends the patterns a hand-edited file lost, and keeps the user's lines
  printf '# local notes\nmy-notes/\nworktrees/\n' > "$repo/.workflow/.gitignore"
  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)"
  if grep -qxF 'HANDOFF.md' "$repo/.workflow/.gitignore" &&
     grep -qxF 'my-notes/' "$repo/.workflow/.gitignore" &&
     [[ "$out" == *"added 1 missing pattern(s)"* ]]; then
    pass "update appends the missing .gitignore pattern and keeps user lines"
  else
    fail "update should append HANDOFF.md and keep user lines: $out"
  fi
  if git -C "$repo" check-ignore -q .workflow/worktrees/x; then
    pass "edited .gitignore still ignores worktrees/"
  else
    fail "edited .gitignore should still ignore .workflow/worktrees/x"
  fi

  # uninstall keeps an edited file and says so
  out="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1)"
  if [ -f "$repo/.workflow/.gitignore" ] && grep -qxF 'my-notes/' "$repo/.workflow/.gitignore" &&
     [[ "$out" == *"kept .workflow/.gitignore: edited locally, yours to keep"* ]]; then
    pass "uninstall keeps an edited .workflow/.gitignore"
  else
    fail "uninstall should keep the edited .workflow/.gitignore: $out"
  fi

  # uninstall removes it when it is still exactly what init wrote
  repo="$TMPDIR/repo_gitignore_unmodified"
  setup_repo "$repo"
  (cd "$repo" && "$WORKFLOW" update >/dev/null 2>&1)
  out="$(cd "$repo" && "$WORKFLOW" uninstall 2>&1)"
  if [ ! -e "$repo/.workflow/.gitignore" ] && [[ "$out" == *"removed .workflow/.gitignore"* ]]; then
    pass "uninstall removes an unmodified .workflow/.gitignore"
  else
    fail "uninstall should remove the unmodified .workflow/.gitignore: $out"
  fi

  # a .workflow/.gitignore symlinked outside the project is rejected
  repo="$TMPDIR/repo_gitignore_symlink"
  setup_repo "$repo"
  rm -f "$repo/.workflow/.gitignore"
  ln -s "$TMPDIR/outside_gitignore_target" "$repo/.workflow/.gitignore"
  local sym_status=0
  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)" || sym_status=$?
  if [ "$sym_status" -ne 0 ] && [[ "$out" == *"symlink safety violation"* ]] &&
     [ -L "$repo/.workflow/.gitignore" ]; then
    pass "a .workflow/.gitignore symlink escaping the project is rejected"
  else
    fail "update should reject an escaping .workflow/.gitignore (exit $sym_status): $out"
  fi

  # doctor points at update when the file is gone, and fails
  repo="$TMPDIR/repo_gitignore_doctor"
  setup_repo "$repo"
  rm -f "$repo/.workflow/.gitignore"
  local status=0
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1)" || status=$?
  if [ "$status" -ne 0 ] &&
     [[ "$out" == *".workflow/worktrees/ is not ignored by git; run 'workflow update' to add .workflow/.gitignore"* ]]; then
    pass "doctor warns when .workflow/worktrees/ is not ignored"
  else
    fail "doctor should warn about the missing .gitignore (exit $status): $out"
  fi
}

# --- 2.11: update migrates maps/ into research/ without losing history ---
test_maps_research_migration() {
  local repo="$TMPDIR/repo_maps_migration" out
  setup_repo "$repo"
  mkdir -p "$repo/.workflow/maps" "$repo/.workflow/research"
  printf '# Map: tracked note\n' > "$repo/.workflow/maps/tracked.md"
  printf '# Research: existing note\n' > "$repo/.workflow/research/collide.md"
  printf '# Map: colliding note\n' > "$repo/.workflow/maps/collide.md"
  git -C "$repo" add .workflow/maps .workflow/research
  git -C "$repo" commit -q -m "maps"
  printf '# Map: untracked note\n' > "$repo/.workflow/maps/untracked.md"

  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)"
  if [ -f "$repo/.workflow/research/tracked.md" ] && [ ! -e "$repo/.workflow/maps/tracked.md" ] &&
     git -C "$repo" status --porcelain | grep -q 'R  .workflow/maps/tracked.md -> .workflow/research/tracked.md'; then
    pass "update git-mv's a tracked map so history follows"
  else
    fail "update should git mv the tracked map: $out $(git -C "$repo" status --porcelain)"
  fi
  if [ -f "$repo/.workflow/research/untracked.md" ] && [ ! -e "$repo/.workflow/maps/untracked.md" ]; then
    pass "update moves an untracked map with a plain mv"
  else
    fail "update should move the untracked map: $out"
  fi
  if [ -f "$repo/.workflow/maps/collide.md" ] && grep -qxF '# Research: existing note' "$repo/.workflow/research/collide.md" &&
     [[ "$out" == *"kept .workflow/maps/collide.md: .workflow/research/collide.md already exists"* ]]; then
    pass "update warns and leaves a colliding map without overwriting research"
  else
    fail "update should leave the colliding map and keep research/collide.md: $out"
  fi
  if [[ "$out" == *"moved 2 map(s) from .workflow/maps/ to .workflow/research/"* ]]; then
    pass "update says how many maps moved"
  else
    fail "update should report the moved count: $out"
  fi
  if [ ! -d "$repo/.workflow/maps" ]; then
    fail "maps/ should stay while a colliding entry is unaccounted for"
  else
    pass "maps/ is kept while an entry remains"
  fi

  rm -f "$repo/.workflow/maps/collide.md"
  (cd "$repo" && "$WORKFLOW" update >/dev/null 2>&1)
  if [ ! -d "$repo/.workflow/maps" ]; then
    pass "update removes maps/ once it is empty"
  else
    fail "update should remove the emptied maps/ directory"
  fi
}

# --- 2.11: init installs the pre-commit hook by default ---
test_init_hook_default() {
  local repo="$TMPDIR/repo_init_hook" out
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  echo "root" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial"

  out="$(cd "$repo" && "$WORKFLOW" init --no-claude 2>&1)"
  if [ -x "$repo/.git/hooks/pre-commit" ] && grep -qF 'workflow:pre-commit' "$repo/.git/hooks/pre-commit" &&
     [[ "$out" == *"pre-commit hook installed"* ]]; then
    pass "init installs the pre-commit hook by default"
  else
    fail "init should install the pre-commit hook: $out"
  fi

  repo="$TMPDIR/repo_init_hook_off"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test User"
  echo "root" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial"
  out="$(cd "$repo" && "$WORKFLOW" init --no-claude --no-hook 2>&1)"
  if [ ! -e "$repo/.git/hooks/pre-commit" ] && [[ "$out" == *"pre-commit hook not installed (--no-hook)"* ]]; then
    pass "init --no-hook leaves the hook out"
  else
    fail "init --no-hook should not install the hook: $out"
  fi

  # update accepts --no-hook and never installs one
  if out="$(cd "$repo" && "$WORKFLOW" update --no-claude --no-hook 2>&1)" && [ ! -e "$repo/.git/hooks/pre-commit" ]; then
    pass "update accepts --no-hook and does not install the hook"
  else
    fail "update --no-hook should succeed without installing a hook: $out"
  fi
  (cd "$repo" && "$WORKFLOW" update --no-claude >/dev/null 2>&1)
  if [ ! -e "$repo/.git/hooks/pre-commit" ]; then
    pass "update never installs the hook"
  else
    fail "update must not install the pre-commit hook"
  fi

  # a foreign pre-commit hook is left alone, with a hint
  repo="$TMPDIR/repo_init_hook_foreign"
  mkdir -p "$repo"
  git -C "$repo" init -q
  echo "root" > "$repo/README.md"
  git -C "$repo" add README.md
  printf '#!/bin/sh\nexit 0\n' > "$repo/.git/hooks/pre-commit"
  chmod +x "$repo/.git/hooks/pre-commit"
  if out="$(cd "$repo" && "$WORKFLOW" init --no-claude 2>&1)"; then
    if grep -qF 'exit 0' "$repo/.git/hooks/pre-commit" &&
       ! grep -qF 'workflow:pre-commit' "$repo/.git/hooks/pre-commit" &&
       [[ "$out" == *"workflow hook install --append"* ]]; then
      pass "init leaves a foreign pre-commit hook untouched and names --append"
    else
      fail "init should not touch a foreign hook and should hint at --append: $out"
    fi
  else
    fail "init must not fail because of a foreign hook: $out"
  fi

  # non-git directory: init succeeds and silently skips the hook
  repo="$TMPDIR/repo_init_hook_nongit"
  mkdir -p "$repo"
  echo "root" > "$repo/README.md"
  out="$(cd "$repo" && "$WORKFLOW" init --no-claude 2>&1)" || true
  if [ -d "$repo/.workflow" ] && [ ! -e "$repo/.git" ] && [[ "$out" != *"pre-commit hook"* ]]; then
    pass "init skips the hook silently outside a git repository"
  else
    fail "init outside git should succeed without a hook line: $out"
  fi
}

# --- 2.11: version drift nudge on daily commands ---
test_version_drift_nudge() {
  local repo="$TMPDIR/repo_version_nudge" out err status
  setup_repo "$repo"
  git -C "$repo" branch -M main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "workflow install"
  mkdir -p "$repo/.workflow/tasks/core"
  cat > "$repo/.workflow/tasks/core/01-nudge.md" <<'EOF'
# 01: Nudge
**Effort:** core
**Check:** `true` passes
**Blocked by:** None
EOF
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "one task"
  local kit_version
  kit_version="$("$WORKFLOW" version)"

  # Older project: point at update, on all five daily commands, on stderr only and
  # with the same exit code the project's own (non-nudging) copy returns.
  portable_sed 's/^version: .*/version: 1.0.0/' "$repo/.workflow/.workflow-version"
  local nudge="project workflow is 1.0.0, this CLI is $kit_version: run 'workflow update'"
  local cmd own_status nudge_err="$TMPDIR/nudge.err"
  for cmd in "next --no-color" "validate --no-color" "task start core/01" "doctor" "hook status"; do
    status=0
    out="$(cd "$repo" && "$WORKFLOW" $cmd 2>"$nudge_err")" || status=$?
    err="$(cat "$nudge_err")"; rm -f "$nudge_err"
    own_status=0
    (cd "$repo" && ./.workflow/bin/workflow $cmd >/dev/null 2>&1) || own_status=$?
    if [[ "$err" == *"$nudge"* ]] && [[ "$out" != *"project workflow is"* ]] &&
       [ "$status" -eq "$own_status" ]; then
      pass "workflow $cmd nudges an older project on stderr and keeps the exit code ($status)"
    else
      fail "workflow $cmd should nudge on stderr only (exit $status, own copy $own_status): err=$err"
    fi
  done

  # Newer project: point at upgrading the CLI.
  portable_sed 's/^version: .*/version: 99.0.0/' "$repo/.workflow/.workflow-version"
  status=0
  out="$(cd "$repo" && "$WORKFLOW" next --no-color 2>"$nudge_err")" || status=$?
  err="$(cat "$nudge_err")"; rm -f "$nudge_err"
  if [ "$status" -eq 0 ] &&
     [[ "$err" == *"project workflow is 99.0.0, this CLI is $kit_version: upgrade the CLI (npm install --global @shizuku-yume/workflow)"* ]] &&
     [[ "$out" != *"project workflow is"* ]]; then
    pass "newer project manifest gets the upgrade-CLI nudge"
  else
    fail "newer project should be nudged to upgrade the CLI (exit $status): $err"
  fi

  # The project's own copy never nudges.
  err="$(cd "$repo" && ./.workflow/bin/workflow next --no-color 2>&1 >/dev/null)" || true
  if [[ "$err" != *"project workflow is"* ]]; then
    pass "no nudge when the running script is the project's own copy"
  else
    fail "the project's own copy should not nudge: $err"
  fi

  # Not a workflow project: nothing to compare.
  repo="$TMPDIR/repo_version_nudge_nongit"
  mkdir -p "$repo"
  err="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 >/dev/null)" || true
  if [[ "$err" != *"project workflow is"* ]]; then
    pass "no nudge without .workflow/.workflow-version"
  else
    fail "no manifest should mean no nudge: $err"
  fi
}


# --- 2.11: doctor warns about a newer toolkit on PATH ---
test_doctor_path_toolkit_newer() {
  local repo="$TMPDIR/repo_path_toolkit" out status
  setup_repo "$repo"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "doctor is quiet with no other workflow on PATH"
  else
    fail "doctor should pass with no other workflow on PATH: $(cd "$repo" && "$WORKFLOW" doctor 2>&1 | grep '!')"
  fi

  # A newer standalone workflow earlier on PATH: doctor warns and fails.
  local fake="$TMPDIR/path_toolkit_bin"
  mkdir -p "$fake"
  printf '#!/bin/sh\nprintf "99.0.0\\n"\n' > "$fake/workflow"
  chmod +x "$fake/workflow"
  status=0
  out="$(cd "$repo" && PATH="$fake:$PATH" "$WORKFLOW" doctor 2>&1)" || status=$?
  if [ "$status" -ne 0 ] &&
     [[ "$out" == *"toolkit 99.0.0 on PATH is newer than the installed"*"run 'workflow update'"* ]]; then
    pass "doctor warns about a newer toolkit on PATH and fails"
  else
    fail "doctor should warn about the newer PATH toolkit (exit $status): $out"
  fi

  # An older one is not a problem.
  printf '#!/bin/sh\nprintf "0.0.1\\n"\n' > "$fake/workflow"
  status=0
  out="$(cd "$repo" && PATH="$fake:$PATH" "$WORKFLOW" doctor 2>&1)" || status=$?
  if [ "$status" -eq 0 ] && [[ "$out" != *"on PATH is newer"* ]]; then
    pass "an older toolkit on PATH is not reported"
  else
    fail "an older PATH toolkit should be ignored (exit $status): $out"
  fi
}


test_draft_placeholder_accepted
test_invalid_concrete_sha_rejected
test_invalid_dependencies_rejected
test_explicit_archived_cross_effort
test_blocked_by_strict_grammar
test_blocked_by_multiple_references
test_blocked_by_continuation_boundaries
test_decision_entries_validation
test_decision_fenced_and_subheadings
test_rulebook_update_behavior
test_doctor_no_writes
test_duplicate_task_number_same_effort
test_different_efforts_same_number_ok
test_open_research_cli
test_task_heading_mismatch
test_task_heading_match_ok
test_agents_block_prepended
test_agents_block_edit_preserved
test_agents_block_force_overwrites
test_cycle_detection_simple
test_cycle_detection_three
test_no_false_positive
test_uninstall_edited_agents_block_retained
test_uninstall_unmodified_agents_block_preserves_outside_text
test_uninstall_malformed_agents_markers_no_data_loss
test_uninstall_markerless_legacy_agents_block
test_uninstall_preexisting_empty_agents_preserved
test_nongit_lifecycle_preserves_user_docs
test_symlink_boundaries_rejected
test_doctor_agents_markers_validation
test_vendored_cli
test_claude_adapter
test_pre_commit_hook
test_effort_directory_layout
test_gitattributes_block
test_doctor_branch_version_drift
test_doctor_uncommitted_update
test_update_branch_guidance
test_removed_commands_and_stale_copies
test_next_flags_cli
test_standards_placeholder_precision
test_single_manifest_and_legacy_marker_migration
test_bash_temp_files_cleanup
test_task_lifecycle_cli
test_workflow_gitignore
test_maps_research_migration
test_init_hook_default
test_version_drift_nudge
test_doctor_path_toolkit_newer

printf '\nResults: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
