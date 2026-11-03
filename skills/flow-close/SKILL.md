---
name: flow-close
description: >-
  Close an effort after its last task has landed: check the assembled whole
  against the spec, demo it, revisit its decisions, write the retrospective,
  mark the spec done. Use when flow-implement finishes an effort's last task or
  the user says "close the effort", "wrap up <effort>".
argument-hint: "<effort>"
---

# Flow: Close

Read `.workflow/CONVENTIONS.md` §2, §4, §6, and §7, plus `.workflow/STYLE.md` first.

Tasks were checked separately. This close checks the assembled effort against its spec, demonstrates the real shipped path, and records acceptance and learning.

## 1. Confirm closable

- Find `.workflow/specs/<effort>.md`. If absent, stop: a no-spec effort (lone bugfix, spike, `maintenance`) ends when its last task lands; no close or retrospective.
- No task remains under `.workflow/tasks/<effort>/`; otherwise name it and stop, or drop it through `flow-break` amend. Every archived task must have landed on the landing branch (`merge-strategy.md`). Use its up-to-date head; on an integration branch merge main into it first and rerun tests.
- If `.workflow/done/<effort>/retrospective.md` exists, this is a reopen: close only tasks added since the last close, appending at step 7. Compare from the earliest-started added task's `Base commit`; otherwise use the earliest-started archived task.
- List commits once and reuse them: `git log --format='%h %s' <point>..HEAD -- .workflow/done/<effort>/`. On reopen, include newly archived tasks, not earlier closes.
## 2. Run the spec checks and demo

Run every check in “How we will know it works,” by ID, on the landing head and the actual shipping build/path (packaged app, deployed service, installed CLI), not a stand-in. Record pass, fail, or not runnable with reason; a stand-in run is not a pass. Checks absent from task `Covers` are still expected. Any failure blocks.

Then use the feature once through the real entry point and dependencies, following “What it does” to completion. Note what happened for the user report.

## 3. Review the whole

Run `flow-verify` in effort mode with step 1's comparison point and commit list. It reuses task review records in `## Progress` and checks assembly, without replaying unchanged task briefs. A spec-requested evidence or documentation pass is a separate invocation over the assembled whole, never a rerun of an unchanged brief.

Handle findings per CONVENTIONS §7. Make and recheck a fix here only if it passes as a small task (§4); commit it with the close. Otherwise add a task through `flow-break` amend and wait to close. Report open hotfix follow-ups (`grep -rl 'Hotfix:' .workflow/tasks/`) touching this effort; they remain open until their task lands.
## 4. Revisit decisions

List decisions with `grep -n 'Effort:\*\* <effort>' .workflow/decisions.md` and those cited by the spec. Check each `Revisit when`; report triggers. Reversal requires a new entry made with the user (§2), not unilateral change.

## 5. Show the user

Send one message: each spec check by ID and result, demo observations, review status per brief, and triggered decisions. Ask whether the effort is accepted. Only the user's explicit yes accepts; silence or passing checks do not. Until then keep the spec `in progress` and report waiting for acceptance. If something is missing, add tasks through `flow-break` amend and wait.

## 6. What changes

Review findings repeated across multiple tasks are patterns. Convert a genuine mechanical pattern to an automated check, or a judgement pattern to one concise `.workflow/standards.md` line. Do not create one-off bureaucracy; if no pattern recurred, record none.

## 7. Write the retrospective

Write `.workflow/done/<effort>/retrospective.md`, using task/spec history (`git log --stat --follow -- <path>`) for plan versus actual and archived task `## Progress` for findings. Record patterns and their resulting check/standard, or why none recurred; include remaining debt and open hotfixes.

On reopen append `## Reopened <date>` with the same headings and its own `**Accepted:**` line; keep the original shipment readable. `validate` requires one more `Accepted:` line than `## Reopened` headings.

```markdown
# Retrospective: <effort>

## Goal
<one or two sentences from the spec>

**Accepted:** <date> by <who said yes>

## What shipped
<user-visible result; spec check results by ID>

## Decisions that shaped it
<entry headings, one line each on why they mattered>

## Plan versus actual
- Tasks at break: N. Added later: N. Split: N. Dropped: N, and why.
- Spec changes after confirmation: N, sections and why.
- Blocked tasks and what the plan got wrong.

## Review findings
<blocking findings by kind: correctness, missing deliverable, standards, process>

## What changes
<recurring patterns and resulting check/standard, or none>

## Debt left behind
<technical-debt.md entries by heading; open hotfix follow-ups>
```

## 8. Mark done and commit

1. Set the spec to `**Status:** done`.
2. Run `.workflow/bin/workflow validate`; errors block.
3. Commit retrospective, spec status, checks/standards, decision entries, and step 3 fixes together. Land per `Landing:` (`merge-strategy.md`). On an integration branch, land the close commit by fast-forward or one merge commit, never replace main's tree; then delete the landed task branches.

## 9. Report

Report concisely: done or exactly what remains; spec check totals and failures/unrun checks; review findings and response; triggered decisions; checks/standards added or "none".
