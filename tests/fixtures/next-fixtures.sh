#!/usr/bin/env bash
# Fixture builders shared by the workflow-next integration scenarios.
next_project() {
  mkdir -p "$1/.workflow/tasks" "$1/.workflow/efforts"
}
next_effort() {
  local root="$1" slug="$2" priority="$3" goal="$4"
  cat > "$root/.workflow/efforts/$slug.md" <<EOF
# Effort: $slug
Priority: $priority
Status: active

## Goal

$goal

## Scope

Scope must not be included in the goal preview.
EOF
}
next_task() {
  local root="$1" filename="$2" effort="$3" blockers="$4" check="$5"
  local number="${filename%%-*}"
  cat > "$root/.workflow/tasks/$filename" <<EOF
# $number: Task $number
**Effort:** $effort
**Blocked by:** $blockers
**Check:** $check
EOF
}
next_priority_fixture() {
  local root="$1"
  next_project "$root"
  next_effort "$root" urgent urgent 'Restore service.'
  next_effort "$root" high high 'Ship high priority work.'
  next_effort "$root" normal normal 'Deliver normal work.'
  next_effort "$root" low low 'Polish optional behavior.'
  next_task "$root" 99-urgent.md urgent None 'Check service health.'
  next_task "$root" 10-high.md high None 'Check task ten.'
  next_task "$root" 02-high.md high 'None, can start now' 'Check task two.'
  next_task "$root" 01-normal.md normal None 'Check task one.'
  next_task "$root" 20-normal.md normal None 'Check task twenty.'
  next_task "$root" 03-low.md low None 'Check low task.'
  next_task "$root" 04-blocked.md urgent 99 'Not ready.'
}
