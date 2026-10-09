---
name: flow-implement
description: >-
  Build one task end to end: code, proof, docs, review, archive, commit. Use when
  user says "implement task 3", "build this", "do next task". Supports quick/standard/thorough.
argument-hint: "<effort>/<NN> [quick|standard|thorough]"
---

# Flow: Implement

Read `.workflow/CONVENTIONS.md` and `.workflow/STYLE.md` first. Then read task file and spec sections it names. A task file that needs the conversation that produced it is broken; fixing it is part of this job.

Per CONVENTIONS §0: check codebase before asking. Implementation discovers facts through reading code and running tests, not asking.

Do this end to end: build, prove, sync docs, review, archive, commit. Don't stop between steps to ask whether to continue. Stop only for decision that changes what gets built, asked as one batch (CONVENTIONS §1.3).

Task reference is `<effort>/<NN>`. Bare `NN` is fine when only one effort has that number; if several do, ask which.

## Intensity levels

One setting controls how much review runs. Default `standard`.

| Level | Review | Use for |
| --- | --- | --- |
| `quick` | none; tests, check and real-path proof only | typo fixes, documentation, obvious single-line bugs, test-only updates |
| `standard` | `flow-verify` (three checks, two agents) | everything else |
| `thorough` | `flow-verify`, then `flow-architect` on touched area | large refactors, architectural changes, code touching many callsites |

## 1. Confirm startable

Read task file. If `Task type: spike`, follow `.workflow/spike-tasks.md` as well: deliverable is an answer, the time box is a scope limit, code may be discarded.

Read task's `Blocked by`. Unqualified `NN` means that task in this task's own effort; `<effort>/<NN>` means that effort. If it declares blockers (not `None`), every referenced task must be archived under `.workflow/done/<effort>/` in committed HEAD or merged into current branch. If any blocker still active, missing, uncommitted, or unresolved: say which and stop. Don't work around it, don't quietly do the blocker first.

Check the branch model before the first edit: `.workflow/standards.md` wins, then `.workflow/merge-strategy.md`. If they prescribe a branch per task, create or switch to `<effort>/<NN>-<slug>` now. If the project commits straight to its main branch, say so in one line and continue.

Pin or preserve Base commit and track start time:
- If `Base commit` missing or contains `<commit-sha>` placeholder, capture `git rev-parse HEAD` and current timestamp before touching code. Write to task file: `**Base commit:** <sha>` and `**Started:** <ISO 8601 timestamp>`. Set `**Status:** active` if the field exists.
- If resuming with concrete SHA recorded, preserve original baseline. Validate it resolves (`git cat-file -e <sha>^{commit}`). If doesn't resolve: stop and report.

`flow-verify` requires this exact Base commit.

If task doesn't name where work goes or how to check it, fill in from spec and code, say so in one line.

If task is wrong (assumes something code doesn't do, spec contradicts it), stop and report. Don't rewrite task to match what's easy.

Before writing code, look at code task touches and existing tests. Make change the way project already does things. Run test command from `.workflow/standards.md` to confirm baseline is clean; you need the baseline before you can claim anything about after.

## 2. Build it

Smallest change that delivers what task says. Files in task are expected starting locations, not closed whitelist: add necessary tests, callers, docs required to deliver behavior safely.

Don't add configurability, error handling, abstractions task didn't ask for. If you believe one genuinely needed, do simple thing and say what you skipped in final report.

Run typecheck and touched tests as you go, not once at end.

**Write check while writing code.** Whatever task's `Check` line says, make it exist. Change with no way to tell if it works isn't finished change.

## 3. Prove it

Run task's check command and look at output. Not test suite in general: thing that would fail if this specific behavior broke.

Then exercise real path once, by hand or script, and note what happened. Test that passes proves what test asserts; running thing proves thing works. On UI change, open it. On CLI change, run command. Report what you saw, including anything that looked wrong.

If check can't pass, say what blocks it rather than loosening it.

## 4. Sync documents and record decisions

Before review:

- **Update stale documents** — fact in spec, glossary, or `.workflow/standards.md` that no longer matches code gets fixed now, in this change. That's why those files are trustworthy.
- **Record decisions made** — choice that affects scope, interfaces, compatibility, risk, future maintenance, or carries substantive alternative trade-offs goes into `.workflow/decisions.md` as complete five-field entry, tagged `**Effort:** <effort>` so `.workflow/bin/workflow decisions --effort` finds it. Routine implementation details (naming, formatting, helper reuse) don't need entry.

## 5. Review it

**`quick`:** skip review. Still required: full test suite, task's check, real-path proof, failures fixed.

**`standard`:** run `flow-verify` against work, passing task's exact Base commit from step 1. Falling back to `main` is forbidden.

Add a security pass (a security-review agent if the harness has one, otherwise a general subagent briefed for it) when the change touches authentication, authorisation, input reaching a query or shell, secrets, file paths, or anything crossing a trust boundary. Otherwise skip it and say you skipped it.

**`thorough`:** `standard`, then `flow-architect` on the touched area. It reports cuts and reshapes but changes nothing; unaddressed findings go to `.workflow/bin/workflow debt add`.

Address review findings:
- **Blocking** (correctness bugs, missing deliverables, broken invariants, violated standards) must be fixed and specifically rechecked, or explicitly accepted by user with recorded decision.
- **Nonblocking** (minor follow-ups, stylistic preferences) can be recorded or deferred.
- Finding you disagree with gets a decision entry explaining why, not silence.

Don't re-run whole review after fixing; check specific thing that was wrong.

## 6. Archive and commit

1. **Capture what the task taught.** Anything worth keeping goes into spec, glossary, or decisions first. Archived task file is not a substitute for updating the spec.
2. **Close the task file.** Tick finished `- [ ]` items. Add `**Finished:** <ISO 8601 timestamp>`. Remove `**Status:**` if present.
3. **Move it:** `git mv .workflow/tasks/<effort>/<NN>-<slug>.md .workflow/done/<effort>/` (create directory if needed). A task still in the flat layout moves from `.workflow/tasks/<NN>-<slug>.md`.
4. **Close the effort if this was its last task.** When no other task of `<effort>` remains under `.workflow/tasks/`, write `.workflow/done/<effort>/retrospective.md`: goal, what shipped, decisions that shaped it, debt left behind. `.workflow/bin/workflow effort complete <effort>` points readers there.
5. **Validate:** `.workflow/bin/workflow validate`. Errors block the commit; warnings about archived files don't.
6. **Commit once:** code, tests, docs, decision entries, and archive move in one commit. Message per STYLE.md: what changed and why. No "wip", no unrelated edits riding along.

Spike tasks: findings go into the task file's `## Findings` section and into spec, decision, or glossary. Throwaway code doesn't reach main: drop it before committing, or keep it on a `spike/<effort>-<NN>` branch and name the branch in Findings. Then archive and commit the task file and recorded findings as above.

Don't push or open a PR unless `.workflow/standards.md` or user says to.

## 7. Report

**For regular tasks**, four lines:
- What now works, from user's point of view
- What you ran to prove it, what it said
- What reviews found, what you did about it
- What you deliberately left out, when it would matter

If task not finished, say that first, say exactly what remains, and don't archive it.

**For spike tasks**, four lines:
- What question was answered
- What was learned (the finding)
- Where it's recorded (spec/decision/glossary)
- Whether spike code kept or discarded

## What this is not

Not license to reinterpret task. Not reason to fix unrelated things noticed on way (report them; open separate task). Not place to re-litigate decision already in `.workflow/decisions.md`.
