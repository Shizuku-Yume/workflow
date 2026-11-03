---
name: flow-implement
description: >-
  Build one task end to end, or run an effort's task queue wave by wave. Use for
  "implement task 3", "implement <effort>", or "do the next task".
argument-hint: "<effort>/<NN> | <effort>"
---

# Flow: Implement

Read the task file and the spec sections it cites. A bare `NN` works when unambiguous.

## 1. Start

- Stop if a `Blocked by` task has not landed. Run `git status --short` and leave pre-existing dirty files alone.
- Set `Base commit` (`git rev-parse HEAD`) and `Status: active`. Under `local-merge` or `pr`, cut the task branch or worktree first (CONVENTIONS §7). Set the spec to `in progress` if it was `proposed` or `done`.
- Record `Check before:` in `## Progress` when the task type calls for it (CONVENTIONS §2.1).

## 2. Build

Make the smallest clear change across code, callers, tests, and docs (CONVENTIONS §8). For bugs, follow CONVENTIONS §6.

## 3. Verify

- Run `Check` and record `Check after:` in `## Progress`, plus one real user, CLI, or service run.
- If the change affects them, update relevant lines in `specs/`, `glossary.md`, `standards.md`, or `technical-debt.md`. Log costly-to-reverse choices in `.workflow/decisions.md`.

## 4. Review

Run `flow-verify` against `Base commit`. Put deferred cleanup in `.workflow/technical-debt.md`.

## 5. Archive and land

- Tick `- [x]` items, remove `Status`, move the task file to `.workflow/done/<effort>/`, and run `.workflow/bin/workflow validate`. Then land per CONVENTIONS §7. If it was the last task of a spec effort, run `flow-close <effort>`.
- Report what changed, the `Check` and real-path results, and the review outcome. Include breaking or migration notes and logged decisions only when applicable.
- **Broken assumption:** set `Status: blocked`, add `## Blocked`, and replan (CONVENTIONS §3). **Stopping mid-task:** hand off per CONVENTIONS §4 and set `Status: paused`.

## 6. Effort queue mode

When the argument is `<effort>`:
1. Run `.workflow/bin/workflow next --effort <effort> --all --format json`. Handle `paused` and `blocked` tasks first.
2. Run ready tasks in parallel, one worktree and subagent each (CONVENTIONS §7). Each subagent builds and passes `Check` in its own worktree. Tasks listed together in `file_overlaps` run one after another.
3. As each subagent finishes, confirm `Check` and the real path, run `flow-verify`, and land in the main session; remove the worktree and rerun `next`. On long runs, `workflow next --effort <effort> --brief` prints a compact queue check (silent when idle).
4. When every task has landed, run `flow-close <effort>` if the effort has a spec.
