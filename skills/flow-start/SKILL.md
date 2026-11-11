---
name: flow-start
description: >-
  Load project standards, read the task queue, and recommend or run the next step.
  Use at session start, when resuming, or when unsure what to do next.
---

# Flow: Start

Skip mid-session when context is already loaded and the next step is clear.

## 1. Load context

1. Read `.workflow/standards.md`. If `<TODO: ...>` (or `<...>`) placeholders remain, fill them from repo config (`package.json`, `pyproject.toml`, `Cargo.toml`, CI) and mention the update in one line.
2. If `.workflow/HANDOFF.md` exists, take its state and next step, then delete it.
3. Grep `.workflow/glossary.md` and `.workflow/decisions.md` for terms relevant to the request instead of loading them whole.

## 2. Read state

Run `git status --short` and `.workflow/bin/workflow next --no-color` (`git fetch -q` first under `Landing: pr`). `next` reports paused, blocked, and ready tasks; research notes with open questions; finished-but-unarchived tasks; efforts ready to close; specs without tasks; stale worktrees; and tasks started on other branches. Name the branch if you are not on the main branch. Also note `fix-now` entries in `.workflow/technical-debt.md`.

## 3. Route

- **User only asked what to do next:** name one step and stop. Order: resume `paused` → amend `blocked` (`flow-break`) → archive a finished task (`workflow task archive`) → `flow-close` an effort ready to close → continue an open research note (`flow-grill`) → `flow-break` a spec without tasks → `flow-implement` a ready task. Remove stale worktrees `next` lists (`git worktree remove <path>`).
- **Otherwise:** size the request (CONVENTIONS §3) and act in the same turn.
