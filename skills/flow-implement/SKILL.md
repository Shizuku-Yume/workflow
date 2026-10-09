---
name: flow-implement
description: >-
  Build one task end to end: code, proof, docs, review, archive, commit, land. Use
  when user says "implement task 3", "build this", "do next task". Supports quick/standard/thorough.
argument-hint: "<effort>/<NN> [quick|standard|thorough]"
---

# Flow: Implement

Read `.workflow/CONVENTIONS.md` and `.workflow/STYLE.md` first. Then read task file and spec sections it names. A task file that needs the conversation that produced it is broken; fixing it is part of this job.

Per CONVENTIONS §0: check codebase before asking. Implementation discovers facts through reading code and running tests, not asking.

Do this end to end: build, prove, sync docs, review, archive, commit, land. Don't stop between steps to ask whether to continue. Stop only for decision that changes what gets built, asked as one batch (CONVENTIONS §1.3), or when the plan itself is wrong (step 1, "When the plan is wrong").

Task reference is `<effort>/<NN>`. Bare `NN` is fine when only one effort has that number; if several do, ask which.

## Intensity levels

One setting controls how much review runs. Default `standard`. The security pass (CONVENTIONS §7) is not part of this setting: it runs at every level when the change calls for it.

| Level | Review | Use for |
| --- | --- | --- |
| `quick` | no review agents; tests, check and real-path proof only | typo fixes, documentation, obvious single-line bugs, test-only updates |
| `standard` | `flow-verify` (three checks, two agents) | everything else |
| `thorough` | `flow-verify`, then `flow-architect` on touched area | large refactors, architectural changes, code touching many callsites |

## 1. Confirm startable

Read task file. If `Task type: spike`, follow `.workflow/spike-tasks.md` as well: deliverable is an answer, the time box is a scope limit, code may be discarded. If `Task type: bugfix`, CONVENTIONS §8 governs how it is built.

Read `Status`:
- `blocked`: the task is waiting for its plan to be fixed (CONVENTIONS §5). Say so and stop; don't build around it.
- `paused`: this is a resume. Read `## Progress` first, restore the work it names (worktree, branch, stash), keep the recorded Base commit, set `Status: active`, and continue from the next step it gives.

Read task's `Blocked by`. Unqualified `NN` means that task in this task's own effort; `<effort>/<NN>` means that effort. Every referenced task must be archived under `.workflow/done/<effort>/` and have landed (`merge-strategy.md`): in the main branch, or in the blocker branch this task is stacked on. If any blocker is still active, missing, uncommitted, or unlanded with no stacking allowed: say which and stop. Don't work around it, don't quietly do the blocker first.

Read `Landing:` in `.workflow/standards.md` (`merge-strategy.md` gives the default and the modes). Under `local-merge` and `pr`, each task gets a branch `<effort>/<NN>-<slug>`:
- Claim first: `git branch -a --list '*<effort>/<NN>-*'`. A branch that exists and isn't this resume means someone else has the task: say whose and stop.
- Create the branch from the main branch. Stacking on an unlanded blocker (allowed only under `pr`): create it from the blocker's branch and write `**Base branch:** <blocker branch>`.
Under `direct`, say in one line that work goes straight onto the current branch.

Pin or preserve Base commit and track start time:
- If `Base commit` missing or contains `<commit-sha>` placeholder, capture `git rev-parse HEAD` and current timestamp before touching code. Write to task file: `**Base commit:** <sha>`, `**Started:** <ISO 8601 timestamp>` and `**Status:** active`.
- If resuming with concrete SHA recorded, preserve original baseline. Validate it resolves (`git cat-file -e <sha>^{commit}`). If doesn't resolve: stop and report.

`flow-verify` requires this exact Base commit.

First task of its effort? Move the effort definition to `Status: active` and the spec to `**Status:** in progress` if they still say `planning` and `proposed` (CONVENTIONS §6).

If task doesn't name where work goes or how to check it, fill in from spec and code, say so in one line.

Before writing code, look at code task touches and existing tests. Make change the way project already does things. Run test command from `.workflow/standards.md` to confirm baseline is clean; you need the baseline before you can claim anything about after.

Then run the task's `Check` before changing anything, and record the result in the task's `## Progress` as `Check before: <what it printed or why it can't run yet>`. It should fail, or not be runnable because the thing it exercises doesn't exist yet. If it already passes, either the work is already done or the Check doesn't test the behaviour: find out which, and fix the Check (say so) before building. A Check that passes before and after proves nothing. Spikes skip this.

### When the plan is wrong

If the task or spec assumes something the code doesn't do, contradicts itself, or turns out to be several tasks, now or at any later step: don't rewrite the task to match what's easy, and don't build around it.

1. Set `**Status:** blocked` and add a `## Blocked` section: what the task or spec assumed, what is actually true (file, command and output as evidence), and what has to be decided or changed.
2. Leave partial code on the task branch, or in a stash named `<effort>/<NN> blocked`, and say where in the section.
3. Commit the task file on its own, so the block outlives this session.
4. Report it and route per CONVENTIONS §5 (replan). The task resumes after `flow-break` amend has cleared `blocked`.

## 2. Build it

Smallest change that delivers what task says. Files in task are expected starting locations, not closed whitelist: add necessary tests, callers, docs required to deliver behavior safely.

Don't add configurability, error handling, abstractions task didn't ask for. If you believe one genuinely needed, do simple thing and say what you skipped in final report.

Run typecheck and touched tests as you go, not once at end.

**Write check while writing code.** Whatever task's `Check` line says, make it exist. Change with no way to tell if it works isn't finished change.

For a bugfix, the order is CONVENTIONS §8: reproduce, failing check, root cause written into `## Progress`, fix, look sideways at sibling callers.

## 3. Prove it

Run task's check command and look at output. Not test suite in general: thing that would fail if this specific behavior broke. It passing now, after failing in step 1, is the evidence; record `Check after:` next to `Check before:`.

Then exercise real path once, by hand or script, and note what happened. Test that passes proves what test asserts; running thing proves thing works. On UI change, open it. On CLI change, run command. Report what you saw, including anything that looked wrong.

If check can't pass, say what blocks it rather than loosening it.

## 4. Sync documents and record decisions

Before review, so the review sees them:

- **Update stale documents** — fact in spec, glossary, or `.workflow/standards.md` that no longer matches code gets fixed now, in this change. That's why those files are trustworthy.
- **Capture what the task taught** — anything worth keeping goes into spec, glossary, or decisions now. The archived task file is not a substitute for updating the spec.
- **Record decisions made** — choice that affects scope, interfaces, compatibility, risk, future maintenance, or carries substantive alternative trade-offs goes into `.workflow/decisions.md` as complete five-field entry, tagged `**Effort:** <effort>` so `.workflow/bin/workflow decisions --effort` finds it. Routine implementation details (naming, formatting, helper reuse) don't need entry. Keep a list of the ones you made yourself (`Mine: yes`); the report names them.

## 5. Review it

**Security pass**, at every level: CONVENTIONS §7 says when it runs. When it doesn't apply, say so in one line.

**`quick`:** no review agents. Still required: full test suite, task's check, real-path proof, failures fixed.

**`standard`:** run `flow-verify` against work, passing task's exact Base commit from step 1 and the task file path. Falling back to `main` is forbidden.

**`thorough`:** `standard`, then `flow-architect` on the touched area. It reports cuts and reshapes but changes nothing; unaddressed findings go to `.workflow/bin/workflow debt add`.

Handle findings per CONVENTIONS §7: the reviewer's `blocking` and `nonblocking` labels stand; a blocking finding is fixed or waived by the user (`Mine: no`), never by you; a fix bigger than the finding goes back to the reviewer as a delta. Record each blocking finding and its outcome in `## Progress`.

If fixes change what the task delivers, update the task file and rerun the affected axis rather than committing a different change than was reviewed.

## 6. Archive, commit, land

1. **Close the task file.** Tick finished `- [ ]` items. Add `**Finished:** <ISO 8601 timestamp>`. Remove `**Status:**`. Keep `## Progress`: it is the task's record.
2. **Move it:** `git mv .workflow/tasks/<effort>/<NN>-<slug>.md .workflow/done/<effort>/` (create directory if needed). A task still in the flat layout moves from `.workflow/tasks/<NN>-<slug>.md`.
3. **Validate:** `.workflow/bin/workflow validate`. Errors block the commit; warnings about archived files don't.
4. **Commit once:** code, tests, docs, decision entries, and archive move in one commit. Message per STYLE.md: what changed and why. No "wip", no unrelated edits riding along.
5. **Land it** per `Landing:` (`merge-strategy.md`). `direct`: done. `local-merge`: rebase onto the main branch, rerun the tests, the task's Check and the real path once, fast-forward the main branch, delete the task branch. `pr`: push the branch and open a PR; dependents wait for its merge or stack on it. Push or open a PR only under `pr` or when the user asks.
6. **Last task of the effort?** When no other task of `<effort>` remains under `.workflow/tasks/` and all of them have landed, the effort goes to `flow-close`: in this session if the window is still light, otherwise in a fresh one (`.workflow/phase-boundaries.md`). Don't write the retrospective here.

Spike tasks: findings go into the task file's `## Findings` section and into spec, decision, or glossary. Throwaway code doesn't reach main: drop it before committing, or keep it on a `spike/<effort>-<NN>` branch and name the branch in Findings. Then archive, commit and land the task file and recorded findings as above.

## 7. Report

**For regular tasks**, five lines:
- What now works, from user's point of view
- What you ran to prove it, what it said before and after
- What reviews found, what you did about it
- What you deliberately left out, when it would matter
- Decisions you made on the user's behalf (`Mine: yes`), by heading, or "none": the user is entitled to overturn them, and can't without seeing them

If task not finished, say that first, say exactly what remains, and don't archive it.

**For spike tasks**, five lines:
- What question was answered
- What was learned (the finding)
- Where it's recorded (spec/decision/glossary)
- Whether spike code kept or discarded
- Decisions you made on the user's behalf, or "none"

## Pausing and resuming

When the session has to stop before the task is done (window full, user stops, waiting on something outside the plan), write the handoff CONVENTIONS §6 describes into `## Progress` and set `**Status:** paused`. Test it: could a session that never saw this conversation continue from the task file alone? If not, the handoff is missing something.

A plan that turned out wrong is not a pause; that is `blocked` (step 1).

## What this is not

Not license to reinterpret task. Not reason to fix unrelated things noticed on way (report them; open separate task). Not place to re-litigate decision already in `.workflow/decisions.md`.
