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

- Stop if a `Blocked by` task has not landed. Commit or stash unrelated work before `task start` (it warns on a dirty tree). Under `local-merge` or `pr`, cut the task branch or worktree first, under the `Worktrees:` root (CONVENTIONS §7).
- Run `.workflow/bin/workflow task start <effort>/<NN>` to record `Base commit`, set `Status: active`, and update the matching spec to `in progress` if it was `proposed` or `done`.
- Claim any `Resources` the task lists, per `standards.md`. Record `Check before:` in `## Progress` when the task type calls for it (CONVENTIONS §2.1).

## 2. Build

Make the smallest clear change across code, callers, tests, and docs (CONVENTIONS §8). For bugs, follow CONVENTIONS §6.

## 3. Verify

- Run `Check` and record `Check after:` as the Check's own result in `## Progress`, receipts under the Evidence directory (never a temp path), plus one real user, CLI, or service run. If the user waives it, record `Check waived: <reason; who; date>`. Two failed attempts at the same `Check`: stop and replan (CONVENTIONS §3).
- If the change affects them, update relevant lines in `specs/`, `glossary.md`, `standards.md`, or `technical-debt.md`. Log costly-to-reverse choices in `.workflow/decisions.md`.

## 4. Review

Run `flow-verify` against `Base commit`; it records the `Review:` line in `## Progress`. Put deferred cleanup in `.workflow/technical-debt.md`. If blocking findings remain after 2 review-fix rounds, stop and escalate to the user (CONVENTIONS §5).

## 5. Archive and land

- Tick `- [x]` items, record proof (spike: `## Findings`; else `Check after:` or `Check waived:`) and `flow-verify`'s `Review:` line, then run `.workflow/bin/workflow task archive <effort>/<NN>`. It checks the proof lines, strips `Status`, moves the file to `.workflow/done/<effort>/`, and prints when the effort is ready to close. Then land per CONVENTIONS §7. Keep `## Progress` as current state: one line per superseded attempt, long logs to the Evidence directory (CONVENTIONS §2.1).
- Report what changed, the `Check` and real-path results, and the review outcome. Include breaking or migration notes and logged decisions only when applicable.
- **Broken assumption:** set `Status: blocked`, add `## Blocked`, and replan (CONVENTIONS §3). **Stopping mid-task:** hand off per CONVENTIONS §4 and set `Status: paused`.

## 6. Effort queue mode

When the argument is `<effort>`:
1. Run `.workflow/bin/workflow next --effort <effort> --all --format json`. Handle `paused` and `blocked` tasks first.
2. Run ready tasks in parallel, one worktree under the `Worktrees:` root (`standards.md`, default `.workflow/worktrees/`) and one subagent each (CONVENTIONS §7). Each subagent builds and passes `Check` in its own worktree. Tasks listed together in `file_overlaps` or `resource_overlaps` run one after another.
3. As each subagent finishes, confirm `Check` and the real path, run `flow-verify`, and land in the main session; remove the worktree (`git worktree remove <path>`) and rerun `next`. On long runs, `workflow next --effort <effort> --brief` prints a compact queue check (silent when idle).
4. When every task has landed, run `flow-close <effort>` if the effort has a spec; otherwise the final report lists the tasks with `Check waived` or `Review: skipped` / `Review: waived`.
