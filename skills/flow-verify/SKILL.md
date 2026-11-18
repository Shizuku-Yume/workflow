---
name: flow-verify
description: >-
  Review a change in a fresh subagent for requirement completion, evidence, and
  code quality. Use before landing or when the user says "review this".
---

# Flow: Verify

Review in a fresh subagent, never in the context that wrote the change (CONVENTIONS §5).

## 1. Pin the base

Use the task's `Base commit`, or `git merge-base <landing branch> HEAD` after a rebase; without a task, `main` / `origin/HEAD`. Confirm there is something to review: `git diff <base>`, `git status --short`, `git log <base>..HEAD --oneline`.

## 2. Spawn reviewers

- Selection order (never use a generic coding/task agent when a dedicated review specialist exists):
  1. Spawn one fresh `workflow-reviewer` if registered.
  2. Otherwise use the host's dedicated code-review agent or review model role with `.agents/agents/workflow-reviewer.md` as its checklist.
  3. Otherwise spawn a fresh read-only subagent or isolated worker session that authored none of the code, using `.agents/agents/workflow-reviewer.md` as its brief.
- Pass the base SHA, the task or spec path, `.workflow/standards.md`, and any untracked files. When UI changed, instruct reviewers to open and inspect the visual/screenshot receipts in the Evidence directory. For a large cross-module diff, split requirements & proof and code quality into two parallel reviewers.
- When the change touches a trust boundary, also spawn `security-reviewer` (or a fresh reviewer with `.agents/agents/security-reviewer.md`) on the changed boundary files and their direct callers and callees.

## 3. Act on findings

Record `Review: pass (base <sha>)` (or `Review: pass (base <sha>, reviewer <id>)`) or `Review: blocked (base <sha>)` in `## Progress`; use that exact shape, since the CLI parses it. Bare `pass` without detail and self-review are rejected by `task archive` and `validate`. Any `blocking` finding means not ready.
- Fix the whole round's findings together, then rerun the affected checks once.
- Rerun the reviewer only if a `blocking` finding was fixed or the fixes added files, callers, or trust boundaries.
- **Round cap & escalation:** cap review-fix cycles at 2 rounds (initial review + one re-review). If blocking findings remain after round 2, stop: do not keep looping, guessing, or self-approving. In unattended runs, set `Status: blocked` with the findings and stop (CONVENTIONS §4, §5). Otherwise present the findings, evidence, and failed attempts; do not land until the user waives the finding (recorded as `Review: waived — <finding>; user, <YYYY-MM-DD>` in the task, CONVENTIONS §5), gives direction, or marks the task `paused` / `blocked` to replan.
- **Degraded mode:** if a reviewer subagent cannot be spawned or fails to run, never review in the authoring context: record `Review: skipped — <reason>`, tell the user, and continue. `flow-close` reviews it.

## 4. Effort close mode

When called from `flow-close`, run `workflow-reviewer` on requirements & proof plus cross-task integration, from the first task's base commit, and review every task recorded as `Review: skipped`. Reuse recorded reviews for tasks unchanged since. Run `security-reviewer` if the effort as a whole touched a trust boundary.
