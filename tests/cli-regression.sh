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
  (cd "$dir" && "$WORKFLOW" init >/dev/null 2>&1)
  # Fill template placeholders in standards.md so standards.md passes doctor
  sed -i 's/<[^>]*>/placeholder/g' "$dir/.workflow/standards.md"
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
  cat > "$repo/.workflow/done/archived-effort/01-done.md" <<'EOF'
# 01: Done Task
**Effort:** archived-effort
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
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
  for field in 'Task type' 'Base commit' 'Started' 'Finished' 'Status' 'Delivers' \
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
- **Mine:** yes
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
- **Mine:** no
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

# --- Scenario 13: stalled flow-map documents warn, active maps pass ---
test_map_staleness() {
  local repo="$TMPDIR/repo1"
  mkdir -p "$repo/.workflow/maps"

  # Active map with open questions: no warning
  cat > "$repo/.workflow/maps/active.md" <<'EOF'
# Map: Active Map
**Destination:** Ship feature
**Started:** 2026-10-01   **Status:** working

## Route so far

## Open questions
## Q1: How to structure the model?
**Blocks:** Implementation
**Kind:** decide
**Depends on:** none
**Answer:**

## Not yet clear
- More details later

## Ruled out
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map active.md:"* ]]; then
    fail "active map with open questions should not trigger staleness warning: $out"
  else
    pass "active map with open questions produces no warning"
  fi

  # Stale map: Status: working, "## Open questions" empty, "## Not yet clear" with item -> doctor warns
  cat > "$repo/.workflow/maps/stale.md" <<'EOF'
# Map: Stale Map
**Destination:** Ship feature
**Started:** 2026-10-01   **Status:** working

## Route so far

## Open questions

## Not yet clear
- Unpromoted fog item

## Ruled out
EOF

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map stale.md: Status working but no open questions and fog remains"* ]]; then
    pass "stale map warning issued when open questions empty and fog remains"
  else
    fail "expected warning for stale map, got: $out"
  fi
  rm -f "$repo/.workflow/maps/stale.md" "$repo/.workflow/maps/active.md"
}

test_draft_statistics() {
  local repo="$TMPDIR/repo_draft_stats"
  setup_repo "$repo"

  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"

  cat > "$repo/.workflow/tasks/01-draft.md" <<'EOF'
# 01: Draft Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** <commit-sha>
**Blocked by:** None, can start now
EOF

  cat > "$repo/.workflow/tasks/02-started.md" <<EOF
# 02: Started Task
**Effort:** core-work
**Check:** `true` passes
**Base commit:** $head_sha
**Blocked by:** None, can start now
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1) && [[ "$out" == *"Tasks: 2 active (1 draft, 1 started)"* ]]; then
    pass "draft statistics reported in doctor output"
  else
    fail "expected 'Tasks: 2 active (1 draft, 1 started)' with exit 0, got: $out"
  fi
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
  sed -i '/<!-- workflow:start -->/a - Custom user workflow rule' "$repo/AGENTS.md"

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
    sed -i '/<!-- workflow:start -->/a - Custom user workflow rule' "$repo/AGENTS.md"
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

# --- Scenario: glossary format validation ---
test_glossary_malformed() {
  local repo="$TMPDIR/repo_glossary"
  [ -d "$repo" ] || setup_repo "$repo"

  cat > "$repo/.workflow/glossary.md" <<'EOF'
# Glossary

This is an unexpected paragraph line instead of a list of terms.
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "glossary with paragraph instead of list should cause doctor to fail"
  elif [[ "$out" == *"glossary.md: unexpected line format"* ]]; then
    pass "glossary malformed paragraph reported and doctor fails"
  else
    fail "doctor failed but expected unexpected line format warning, got: $out"
  fi
  cat > "$repo/.workflow/glossary.md" <<'EOF'
# Glossary

- malformed list item without colon or dash
EOF

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "glossary with malformed list item should cause doctor to fail"
  elif [[ "$out" == *"glossary.md: malformed line"* ]]; then
    pass "glossary malformed list line reported and doctor fails"
  else
    fail "doctor failed but expected malformed line warning, got: $out"
  fi
}


test_glossary_duplicate() {
  local repo="$TMPDIR/repo_glossary"
  [ -d "$repo" ] || setup_repo "$repo"

  cat > "$repo/.workflow/glossary.md" <<'EOF'
# Glossary

- **foo**: first definition of foo
- **foo**: second definition of foo
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "glossary with duplicate terms should cause doctor to fail"
  elif [[ "$out" == *"glossary.md: duplicate term: foo"* ]]; then
    pass "glossary duplicate term reported and doctor fails"
  else
    fail "doctor failed but expected duplicate term warning, got: $out"
  fi
}

test_glossary_valid() {
  local repo="$TMPDIR/repo_glossary"
  [ -d "$repo" ] || setup_repo "$repo"

  cat > "$repo/.workflow/glossary.md" <<'EOF'
# Glossary

- **foo**: first definition of foo
- **bar** - second definition of bar
- plain_term: third definition plain colon
- plain_dash - fourth definition plain dash
  - **indented**: fifth definition with leading spaces
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "valid glossary format accepted by doctor"
  else
    fail "valid glossary format should pass doctor, got: $out"
  fi
}

# --- Scenario: glossary with official wrapped definitions and repeated Avoid entries ---
test_glossary_official_wrapped_avoid_repeats() {
  local repo="$TMPDIR/repo_glossary_wrapped"
  setup_repo "$repo"

  cat > "$repo/.workflow/glossary.md" <<'EOF'
# Glossary

## Format

```markdown
- **Term**: what it means, in one sentence, ideally naming where it shows up in the
  code.
- _Avoid_: the words that mean the same thing but should not be used.
```

## Terms

- **Order**: what it means, in one sentence, ideally naming where it shows up in the
  codebase and domain logic.
- _Avoid_: Purchase
- _Avoid_: Checkout
  when used to mean the persistent entity.
- **Account**: user identity record with **important** context.
- _Avoid_: do not use **Profile**
- **Profile**: valid separate term defined here.
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "glossary official wrapped and repeated Avoid entries accepted by doctor"
  else
    fail "glossary official wrapped and repeated Avoid entries should pass doctor, got: $out"
  fi
}

# --- Scenario: headings after Terms are not parsed as glossary entries ---
test_glossary_terms_section_boundary() {
  local repo="$TMPDIR/repo_glossary_sections"
  setup_repo "$repo"

  cat > "$repo/.workflow/glossary.md" <<'EOF'
# Glossary

## Terms

- **Order**: a persistent order.
- _Avoid_: Purchase

## Notes

Notes can contain ordinary prose and unrelated lists.
- an unstructured note
- _Avoid_: this is not attached to Order
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    pass "glossary ignores sections following Terms"
  else
    fail "glossary Notes section should not be validated as terms, got: $out"
  fi
}

# --- Scenario: glossary orphan Avoid entry rejected ---
test_glossary_orphan_avoid_rejected() {
  local repo="$TMPDIR/repo_glossary_orphan"
  setup_repo "$repo"

  cat > "$repo/.workflow/glossary.md" <<'EOF'
# Glossary

## Terms

- _Avoid_: OrphanTerm
- **RealTerm**: valid definition of real term
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "orphan Avoid entry should cause doctor to fail"
  elif [[ "$out" == *"orphan Avoid"* ]]; then
    pass "orphan Avoid entry rejected with warning"
  else
    fail "doctor failed but expected orphan Avoid warning, got: $out"
  fi
}

# --- Scenario: glossary duplicate real terms still rejected with Avoid entries ---
test_glossary_duplicate_real_terms_with_avoid() {
  local repo="$TMPDIR/repo_glossary_dup_real"
  setup_repo "$repo"

  cat > "$repo/.workflow/glossary.md" <<'EOF'
# Glossary

## Terms

- **Order**: first definition of order
- _Avoid_: Purchase
- **Order**: second definition of order
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if (cd "$repo" && "$WORKFLOW" doctor >/dev/null 2>&1); then
    fail "duplicate real terms with Avoid entries should cause doctor to fail"
  elif [[ "$out" == *"glossary.md: duplicate term: Order"* ]]; then
    pass "duplicate real term rejected even when Avoid entries present"
  else
    fail "doctor failed but expected duplicate term warning, got: $out"
  fi
}

# --- Scenario: edited AGENTS.md workflow block retained on uninstall ---
test_uninstall_edited_agents_block_retained() {
  local repo="$TMPDIR/repo_uninstall_edited_agents"
  setup_repo "$repo"

  # Edit inside workflow block
  sed -i '/<!-- workflow:start -->/a - Custom local rule that must stay' "$repo/AGENTS.md"

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

  if [ -f "$repo/.workflow/.agents-block.workflow-managed" ]; then
    pass "ownership marker retained when edited AGENTS.md block preserved"
  else
    fail "ownership marker should be retained for edited AGENTS.md block"
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

  if [ ! -f "$repo/.workflow/.agents-block.workflow-managed" ]; then
    pass "agents block marker removed when block successfully uninstalled"
  else
    fail "agents block marker should be removed after block uninstalled"
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
  rm -f "$repo/.workflow/.agents-block.workflow-managed"
  (cd "$repo" && "$WORKFLOW" uninstall >/dev/null 2>&1)
  if [ -f "$repo/AGENTS.md" ]; then
    fail "markerless legacy unmodified AGENTS.md should have been removed"
  else
    pass "markerless legacy unmodified AGENTS block successfully removed and file deleted"
  fi

  # Subtest B: edited block without marker file is preserved
  repo="$TMPDIR/repo_uninstall_legacy_edited"
  setup_repo "$repo"
  rm -f "$repo/.workflow/.agents-block.workflow-managed"
  sed -i '/<!-- workflow:start -->/a - Legacy edit that must be kept' "$repo/AGENTS.md"

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

  # 1. init in non-git directory
  local out_init
  if out_init="$(cd "$repo" && "$WORKFLOW" init 2>&1)"; then
    pass "workflow init succeeds in non-git directory"
  else
    fail "workflow init in non-git directory failed: $out_init"
    return
  fi

  if [ -d "$repo/.workflow" ] && [ -d "$repo/.agents/skills" ]; then
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

  # Toolkit managed skills / manifest must be removed
  if [ -d "$repo/.agents/skills" ] || [ -f "$repo/.workflow/.workflow-version" ]; then
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

  if [ "$status_init" -ne 0 ] && [ "$status_up" -ne 0 ] && [ "$status_un" -ne 0 ] && \
     [ -f "$mk_outside" ] && [ "$(cat "$mk_outside")" = "MARKER_SENTINEL_CONTENT" ]; then
    pass "managed marker symlink rejected on init/update/uninstall with outside target intact"
  else
    fail "managed marker symlink should reject init/update/uninstall and protect outside target"
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
  sed -i 's/<[^>]*>/placeholder/g' "$repo/.workflow/standards.md"

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

# --- Scenario: map staleness edge cases (empty fog, multiline comments, code fences, answered Qs, end Qs, clear/charting) ---
test_map_staleness_edge_cases() {
  local repo="$TMPDIR/repo_map_edge_cases"
  setup_repo "$repo"
  mkdir -p "$repo/.workflow/maps"

  # 1. Empty fog does not warn:
  # 1a. Completely empty fog section
  cat > "$repo/.workflow/maps/map_empty_fog.md" <<'EOF'
# Map: Empty Fog
**Destination:** Finish phase
**Started:** 2026-10-01   **Status:** working

## Route so far

## Open questions

## Not yet clear

## Ruled out
EOF

  local out
  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map_empty_fog.md"* ]]; then
    fail "map with empty fog should not trigger staleness warning: $out"
  else
    pass "map with empty fog produces no staleness warning"
  fi
  rm -f "$repo/.workflow/maps/map_empty_fog.md"

  # 1b. Official multiline HTML comment under ## Not yet clear
  cat > "$repo/.workflow/maps/map_comment_fog.md" <<'EOF'
# Map: Comment Fog
**Destination:** Finish phase
**Started:** 2026-10-01   **Status:** working

## Route so far

## Open questions

## Not yet clear
<!--
Things you know you don't know, or hunches not ready to be questions.
Promote to Open Questions as they sharpen.
-->

## Ruled out
EOF

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map_comment_fog.md"* ]]; then
    fail "map with only multiline HTML comment in fog should not trigger staleness warning: $out"
  else
    pass "map with official multiline comment in fog produces no staleness warning"
  fi
  rm -f "$repo/.workflow/maps/map_comment_fog.md"

  # 1c. Fenced code block example under ## Not yet clear
  cat > "$repo/.workflow/maps/map_fenced_fog.md" <<'EOF'
# Map: Fenced Fog
**Destination:** Finish phase
**Started:** 2026-10-01   **Status:** working

## Route so far

## Open questions

## Not yet clear
```markdown
- Fenced example item that is not a real fog entry
```

## Ruled out
EOF

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map_fenced_fog.md"* ]]; then
    fail "map with fenced example in fog should not trigger staleness warning: $out"
  else
    pass "map with fenced example in fog produces no staleness warning"
  fi
  rm -f "$repo/.workflow/maps/map_fenced_fog.md"

  # 2. Empty open + real fog + answered historical Q warns
  cat > "$repo/.workflow/maps/map_answered_q.md" <<'EOF'
# Map: Answered History
**Destination:** Finish phase
**Started:** 2026-10-01   **Status:** working

## Route so far

## Open questions

## Not yet clear
- Genuine fog item requiring clarity

## Ruled out

## Q1: Which database?
**Blocks:** Storage
**Kind:** decide
**Depends on:** none
**Answer:** SQLite
EOF

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map map_answered_q.md: Status working but no open questions and fog remains"* ]]; then
    pass "empty open + real fog + answered historical Q triggers staleness warning"
  else
    fail "expected staleness warning for map with answered historical Q, got: $out"
  fi
  rm -f "$repo/.workflow/maps/map_answered_q.md"

  # 3. Official end-of-document Q unanswered does NOT warn
  cat > "$repo/.workflow/maps/map_unanswered_end_q.md" <<'EOF'
# Map: Unanswered End Q
**Destination:** Finish phase
**Started:** 2026-10-01   **Status:** working

## Route so far

## Open questions

## Not yet clear
- Genuine fog item requiring clarity

## Ruled out

## Q1: Which database?
**Blocks:** Storage
**Kind:** decide
**Depends on:** none
**Answer:**
EOF

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map_unanswered_end_q.md"* ]]; then
    fail "unanswered Q at end of map should count as open question and not warn: $out"
  else
    pass "unanswered Q at end of document produces no staleness warning"
  fi
  rm -f "$repo/.workflow/maps/map_unanswered_end_q.md"

  # 4. Multiline Answer historical Q still triggers warning
  cat > "$repo/.workflow/maps/map_multiline_answer.md" <<'EOF'
# Map: Multiline Answer
**Destination:** Finish phase
**Started:** 2026-10-01   **Status:** working

## Route so far

## Open questions

## Not yet clear
- Lingering uncertainty item

## Ruled out

## Q1: Which architecture pattern?
**Blocks:** Design
**Kind:** decide
**Depends on:** none
**Answer:**
We decided to adopt the pipeline architecture because it cleanly
isolates transformation stages and simplifies regression testing.
EOF

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map map_multiline_answer.md: Status working but no open questions and fog remains"* ]]; then
    pass "multiline answered historical Q still triggers staleness warning when fog remains"
  else
    fail "expected staleness warning for multiline answered historical Q, got: $out"
  fi
  rm -f "$repo/.workflow/maps/map_multiline_answer.md"

  # 5. Clear and charting maps do not trigger warning (even with empty open and fog)
  cat > "$repo/.workflow/maps/map_clear.md" <<'EOF'
# Map: Clear Map
**Destination:** Finished milestone
**Started:** 2026-10-01   **Status:** clear

## Route so far

## Open questions

## Not yet clear
- Leftover notes from earlier exploration

## Ruled out
EOF

  cat > "$repo/.workflow/maps/map_charting.md" <<'EOF'
# Map: Charting Map
**Destination:** Exploration
**Started:** 2026-10-01   **Status:** charting

## Route so far

## Open questions

## Not yet clear
- Initial unknowns being surveyed

## Ruled out
EOF

  out="$(cd "$repo" && "$WORKFLOW" doctor 2>&1 || true)"
  if [[ "$out" == *"map_clear.md"* ]] || [[ "$out" == *"map_charting.md"* ]]; then
    fail "clear and charting maps should not trigger staleness warning: $out"
  else
    pass "clear and charting maps produce no staleness warning"
  fi
  rm -f "$repo/.workflow/maps/map_clear.md" "$repo/.workflow/maps/map_charting.md"
}

# --- 2.3: the CLI travels with the project in .workflow/bin ---
test_vendored_cli() {
  local repo="$TMPDIR/repo_vendored"
  setup_repo "$repo"
  local cli="$repo/.workflow/bin/workflow"
  if [ -x "$cli" ] && [ -f "$repo/.workflow/bin/workflow-core.py" ] && [ -f "$repo/.workflow/bin/.workflow-managed" ]; then
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
  printf '# 02: Old\n\n**Effort:** core\n' > "$repo/.workflow/done/core/02-old.md"
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
  sed -i 's/^\*\*Effort:\*\* web$/**Effort:** api/' "$repo/.workflow/tasks/web/01-setup.md"
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

  local bin="$repo/.workflow/bin"
  printf '#!/usr/bin/env bash\necho old\n' > "$bin/workflow-tasks"
  printf '#!/usr/bin/env bash\necho old\n' > "$bin/workflow-deps"
  printf '%s workflow-tasks\n%s workflow-deps\n' "$(cksum < "$bin/workflow-tasks" | cut -d' ' -f1)" \
    "$(cksum < "$bin/workflow-deps" | cut -d' ' -f1)" >> "$bin/.workflow-managed"
  printf '# local tweak\n' >> "$bin/workflow-deps"
  printf 'old thinking notes\n' > "$repo/.workflow/thinking.md"
  cksum < "$repo/.workflow/thinking.md" | cut -d' ' -f1 > "$repo/.workflow/.thinking.workflow-managed"
  out="$(cd "$repo" && "$WORKFLOW" update 2>&1)"
  if [ ! -e "$bin/workflow-tasks" ]; then pass "update deletes an unmodified stale .workflow/bin/workflow-tasks"; else fail "update should delete the stale workflow-tasks: $out"; fi
  if [ -f "$bin/workflow-deps" ] && [[ "$out" == *"kept .workflow/bin/workflow-deps"* ]]; then pass "update keeps an edited stale CLI file with a warning"; else fail "update should keep the edited workflow-deps: $out"; fi
  if [ -f "$KIT/templates/project/.workflow/thinking.md" ]; then
    pass "thinking.md still shipped; stale removal not applicable"
  elif [ ! -e "$repo/.workflow/thinking.md" ] && [ ! -e "$repo/.workflow/.thinking.workflow-managed" ]; then
    pass "update deletes an unmodified .workflow/thinking.md"
  else
    fail "update should delete the unmodified thinking.md: $out"
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
test_map_staleness
test_draft_statistics
test_task_heading_mismatch
test_task_heading_match_ok
test_agents_block_edit_preserved
test_agents_block_force_overwrites
test_cycle_detection_simple
test_cycle_detection_three
test_no_false_positive
test_glossary_malformed
test_glossary_duplicate
test_glossary_valid
test_glossary_official_wrapped_avoid_repeats
test_glossary_terms_section_boundary
test_glossary_orphan_avoid_rejected
test_glossary_duplicate_real_terms_with_avoid
test_uninstall_edited_agents_block_retained
test_uninstall_unmodified_agents_block_preserves_outside_text
test_uninstall_malformed_agents_markers_no_data_loss
test_uninstall_markerless_legacy_agents_block
test_uninstall_preexisting_empty_agents_preserved
test_nongit_lifecycle_preserves_user_docs
test_symlink_boundaries_rejected
test_doctor_agents_markers_validation
test_map_staleness_edge_cases
test_vendored_cli
test_claude_adapter
test_pre_commit_hook
test_effort_directory_layout
test_gitattributes_block
test_removed_commands_and_stale_copies

printf '\nResults: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
