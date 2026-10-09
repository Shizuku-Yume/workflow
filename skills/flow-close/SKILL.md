---
name: flow-close
description: >-
  Close an effort after its last task has landed: check the assembled whole
  against the spec, demo it, revisit its decisions, write the retrospective,
  settle statuses. Use when flow-implement finishes an effort's last task or the
  user says "close the effort", "wrap up <effort>".
argument-hint: "<effort>"
---

# Flow: Close

Read `.workflow/CONVENTIONS.md` §6 (lifecycle) and §7 (review), and `.workflow/STYLE.md` first.

Every task was checked on its own, against its own baseline. Nobody has yet checked that the pieces add up to what the spec promised; tasks that each pass can still fail together. This skill does that check, and an effort is not complete until it has.

## 1. Confirm closable

- No task of `<effort>` is left under `.workflow/tasks/<effort>/` (or directly under `.workflow/tasks/` with `Effort: <effort>`). If one is, name it and stop: it is unfinished, or it should be dropped through `flow-break` amend.
- Every archived task has landed on the main branch (`merge-strategy.md`); under `Landing: pr` its PR is merged. Work from an up-to-date main branch.
- Find the spec: the effort definition, the tasks' `Read first` lines, `.workflow/specs/`. An effort without one (a lone bugfix, a spike) closes against its tasks' `Delivers` and `Check`; say so in one line.
- Find the comparison point: the `Base commit` of the effort's earliest-started archived task. List the effort's commits once and reuse the list: every task commit moves a file into `done/<effort>/`, so `git log --format='%h %s' <point>..HEAD -- .workflow/done/<effort>/` finds them.

## 2. Run the spec's checks

Run every check in the spec's "How we will know it works", by ID, against the assembled code. These are the spec's checks, which describe the whole, not the task Checks again. Record each as pass, fail, or not runnable with the reason.

A check no task lists in `Covers` is expected here: some checks only make sense once everything is in. A failing check is a blocking finding.

Then use the feature once the way the spec's "What it does" describes, as a user would, and note what you saw. Step 5 shows this to the user.

## 3. Review the whole

Run `flow-verify` in effort mode (its "Effort mode" section) with the comparison point and commit list from step 1. Axis 1 is judged against the spec, not against any one task; axis 2 looks at how the tasks fit together; axis 3 checks the effort's documents and decisions.

Handle findings per CONVENTIONS §7. A fix that would pass as a small task (CONVENTIONS §4) is made here, rechecked, and committed with the close. Anything bigger becomes a task in this effort through `flow-break` amend, and closing waits for it.

## 4. Revisit decisions

List the effort's decisions (`.workflow/bin/workflow decisions --effort <effort> --no-color`) plus any entry the spec cites. For each, read `Revisit when` and ask whether what this effort built or learned has triggered it. A triggered entry goes into the report with what triggered it. Reversing it is a new entry with `Supersedes` (CONVENTIONS §2), made with the user, not here on your own.

Hotfix entries this effort's tasks resolved should already be marked: `.workflow/bin/workflow hotfix-review --no-color` lists what is still open.

## 5. Show the user

One message: each spec check by ID with its result, what you did for the demo and what it showed, review status per axis, triggered decisions. Ask whether the effort is accepted.

This is the only stop in this skill. Accepted: carry on. Something missing: it becomes tasks through `flow-break` amend, and closing waits.

## 6. Write the retrospective

`.workflow/done/<effort>/retrospective.md`. The git history of `.workflow/tasks/<effort>/`, `.workflow/done/<effort>/` and the spec answers the plan-versus-actual questions (`git log --stat --follow -- <path>`); the `## Progress` sections of archived tasks hold the review findings.

```markdown
# Retrospective: <effort>

## Goal
<one or two sentences, from the effort definition>

## What shipped
<what a user can now do; spec check results by ID>

## Decisions that shaped it
<entry headings, one line each on why it mattered>

## Plan versus actual
- Tasks at break: N. Added later: N. Split: N. Dropped: N, and why.
- Spec changes after confirmation: N, which sections, why.
- Tasks that went `blocked`: which, and what the plan had wrong.

## Review findings
<blocking findings by kind: correctness, missing deliverable, standards, process.
A kind that came up in more than one task is a pattern.>

## What changes
<each rule this effort shows the project needs, and where it went in
.workflow/standards.md; or why it didn't go in>

## Debt left behind
<debt IDs and hotfix entries still open>
```

A pattern in the review findings is the most useful line here. Turn it into a rule in `.workflow/standards.md` ("How code is written here" or "What we do not do") in this same change, so the next effort's implementer avoids it and its reviewer checks for it. A retrospective that changes nothing is a diary.

## 7. Settle statuses and commit

1. Spec: `**Status:** done`.
2. Effort: `.workflow/bin/workflow effort complete <effort>`.
3. `.workflow/bin/workflow validate`. Errors block.
4. One commit: retrospective, statuses, `standards.md` changes, decision entries, any fixes from step 3. Land it per `Landing:` (`merge-strategy.md`).

## 8. Report

Five lines:
- Whether the effort is complete, or exactly what is left
- Spec checks: how many passed, and which failed or couldn't run
- What the effort review found and what was done about it
- Decisions whose `Revisit when` has triggered
- Rules added to `standards.md`, or "none"
