---
name: flow-start
description: >-
  Load project context and classify request. Routes trivial questions, small tasks,
  complex work to right path. Use at session start or when resuming work.
---

# Flow: Start

Load the project's context, classify the request, and route it. Runs once per session, or when context was lost.

## 1. Load project context

Read silently:
1. `.workflow/standards.md` — commands, layout, project conventions. If it still holds unfilled `<...>` placeholders, inspect the repository's build, test and lint configs (`package.json`, `pyproject.toml`, `Cargo.toml`, `Makefile`, CI workflows) and top-level layout, fill in `.workflow/standards.md`, and mention what you filled in in the report.
2. Check that `.workflow/glossary.md` and `.workflow/decisions.md` exist, but do not preload them. After classification or once the area to touch is known, grep relevant glossary and decision terms; read the newest decision entries and any linked supersession entries as needed.
3. If `.workflow/HANDOFF.md` exists (from a task-less session switch, CONVENTIONS §6), read its objective, verified artifacts, failed routes, and next action; delete `.workflow/HANDOFF.md` once absorbed into active work or planning files so no stale handoff lingers.

A missing file goes in the report; a project without decisions or glossary is new, not broken. This keeps the session entry point small while preserving the evidence-before-questions rule.

## 2. Check workflow state

- `.workflow/bin/workflow next --no-color` — ready tasks ranked by priority, and above them every started task: paused, needing replanning, in progress, or finished but not landed, with the branch it lives on. Under `Landing: pr`, `git fetch -q` first so teammates' task branches show. Read `.workflow/tasks/*/` files directly when you need more.
- State is read from one tree. When `next` says it is reading a branch behind the main branch, or that an effort integrates on another branch, read that branch (`next` there, or `git show <branch>:<path>`) before saying where the project stands, and name the branch you read.
- A paused task is interrupted work: offer to resume it before starting anything new. Under `local-merge` and `pr` its handoff is in the task file on its branch, so check out that branch first.
- `Status: blocked` is a plan waiting to be fixed (CONVENTIONS §5).
- `grep -rl 'Hotfix:' .workflow/tasks/` — hotfix follow-up tasks still waiting for the proper fix (CONVENTIONS §4).
- `grep -n 'Priority:\*\* fix-now' .workflow/technical-debt.md` — debt marked fix-now.

Hotfix follow-ups and fix-now debt don't pick the next task; they go in the report so they aren't forgotten.

If this session will cross several phases, or context is already heavy, follow `.workflow/phase-boundaries.md` at each boundary.

## 3. Classify and route

Classify by blast radius and reversibility, not file count. Read direct callers before
locking the class; use CONVENTIONS §4 for hotfix and small-task criteria, then
CONVENTIONS §5 for routing. Upgrade work that crosses a public contract, persisted schema,
or architectural boundary.

Trivial questions get direct answers. Hotfixes and small tasks follow CONVENTIONS §4;
do not restate its process here. For complex work, use `next` and existing specs, maps,
and tasks to choose the earliest incomplete step in CONVENTIONS §5. Clear 1–3 task work
needing no durable spec goes straight to `flow-break`.

## 4. Report and proceed

Report context or missing files, relevant paused/blocked work and follow-ups, the
classification, and the next action—concisely, without a fixed line count. Then take that
action in the same turn; do not stall when the next step is clear (CONVENTIONS §1.1).

## When to skip this skill

Skip mid-session with context loaded, when the user names a flow skill directly, or when
resuming with context present. Use on a fresh session, after compaction, when asked
what's next, or when unsure which skill applies.

