---
name: flow-break
description: >-
  Cut spec into tasks a single session can finish, with dependencies. Use when
  user says "break this down", "split into tasks", or before parallel work.
---

# Flow: Break

Read `.workflow/CONVENTIONS.md` §2 first. Input: spec or settled conversation. Output: task files in `.workflow/tasks/<effort>/`, archived to `.workflow/done/<effort>/` when finished.

Run even when the work fits one session: building goes through a task file, because that is where the Base commit, the Check and the archive live. A one-task breakdown is quick (step 3 skips its round).

Also runs in amend mode when a task is `Status: blocked` or the spec changed under tasks already written ("Amending an effort", below).

## Why tasks exist

Long sessions degrade: attention is sharpest early. Each task sized to fit one fresh session with room to spare.

Second reason: order. Tasks declare blockers, so independent ones can run in parallel (separate worktrees/branches/directories only; shared working tree is serial).

## Good task shape

- **Delivers working behavior** end to end: narrow path that runs, is visible, checkable. Not "add database layer" which delivers nothing usable.
- **Fresh session can finish it** without reading whole codebase. Task says which files matter.
- **Checkable** by something other than person who wrote it.
- **Independent** of tasks declared after it. Everything needed is already in repo or in blocking task.

**Bugfix tasks** — `Task type: bugfix`. Built per CONVENTIONS §8: the `Check` is the failing test that reproduces the bug, and `Delivers` says what works again. If nobody knows the cause yet, draft an investigation spike first and block the fix on it.

**Exception: spike tasks** — time-boxed technical exploration where deliverable is
an answer, not code. Mark with `Task type: spike` and follow
`.workflow/spike-tasks.md`. The time box is a scope limit stated as what to stop
after (one prototype, one benchmark run), not wall-clock hours an agent can't
measure. Produces written findings, code may be throwaway. Completing a spike
means answering the question, whether answer is "yes", "no", or "yes but needs X".
Use for: "Can library Y do Z?", "Is approach A feasible?", "How does existing
module B work?".

## Sizing

Too big if can't describe what it delivers in one sentence without "and", or needs more than ~dozen files read to start. Too small if can't check on its own. When unsure, cut smaller: two small tasks in sequence beat one that stalls halfway with nothing working.

## Process

### 1. Read spec and code

Identify where work touches. Look for tidying that makes real change easier: rename confusing thing, extract shared piece, move function in wrong file. Tidying goes first as own task. Make change easy, then make easy change.

Recorded debt is the first place to look: `.workflow/bin/workflow debt list --by-file --no-color`. An active item whose `Where` overlaps the files this work touches is a candidate tidy-first task, when fixing it makes this change easier. Otherwise leave it; name it in the hand-off so it isn't silently built around. A debt item a task fixes is resolved in that task's commit (`.workflow/bin/workflow debt resolve <id>`).

### 2. Draft tasks

For each:
- **Effort** — lowercase slug `[a-z0-9]+(-[a-z0-9]+)*`, determines archive dir `.workflow/done/<effort>/`
- **Task type** — `feature`, `bugfix`, `refactor`, `spike` (optional, defaults to `feature`)
- **Base commit** — `<commit-sha>` placeholder when drafting. `flow-implement` captures real SHA when starting.
- **Delivers** — behavior person can observe once done (for spike: "Answer to: <question>")
- **Blocked by** — required: `None`, or comma-list of `NN` (same effort) or `<effort>/NN` (cross-effort). Numbers only; titles break `.workflow/bin/workflow validate`.
- **Covers** — the IDs of the spec checks ("How we will know it works") this task makes pass, e.g. `W1, W3`. Omit when there is no spec or the task covers none (a tidy-first task).
- **Files** — expected starting locations. Not closed whitelist; necessary tests/callers/docs may be added during implementation.
- **Read first** — specific spec sections, glossary entries, files needed to start. Short list; long list means task too big.
- **Check** — command to run and result that means it works (for spike: how answer will be validated)
- **Done when** — acceptance points as checklist (for spike: question answered with evidence)
Behavior and checks, not code. No snippets except when snippet carries decision prose can't (schema, state machine, type). Never paste file path if file likely to move; name module instead.

Don't create task for work nobody asked for.

**Coverage gate.** Every spec check ID appears in some task's `Covers`, or is named in the hand-off as checked only when the effort closes (`flow-close`), because it needs all the pieces at once. A check nobody covers and nobody named is a hole in the plan.

### 3. Quiz user

Present whole breakdown as numbered list: title, what it delivers, what blocks it.

For parallel work, identify coordination needs:
- **Truly independent** — no shared interfaces, can merge in any order
- **Interface dependency** — not blocked by, but both touch same API/module boundary (note in task: "Coordinate with NN on <interface>")
- **Merge sequence preferred** — merging N before M reduces conflicts, though M not blocked (note in task: "Easier after NN")

Ask three things:
- Right size?
- Dependencies right — each task depends only on what truly gates it?
- Should any be joined or split?

Iterate until approved. One round, not negotiation per task.

A breakdown of one task skips this round: say what the task delivers and how it will be checked, and go on.

### 4. Write files

`.workflow/tasks/<effort>/<NN>-<slug>.md`. Number within the effort, `01`, `02` in dependency order (blockers first). Another effort may reuse the same numbers and slugs in its own directory, so refer to tasks elsewhere as `<effort>/<NN>`.

```markdown
# <NN>: <Title>

**Effort:** <effort>
**Task type:** feature
**Base commit:** <commit-sha>

**Delivers:** <observable behavior>

**Blocked by:** None | <NN>, <effort>/<NN>
**Files:** <where work happens>

**Read first:** <spec sections, glossary terms, files>
**Covers:** <check IDs>

**Check:** `<command>` → <result that means it works>

- [ ] <acceptance point>
- [ ] <acceptance point>
```

If `.workflow/efforts/<effort>.md` doesn't exist, run `.workflow/bin/workflow effort create <effort>` and fill in goal, scope, success criteria and priority from the spec. It starts as `Status: planning`; `flow-implement` moves it on (CONVENTIONS §6).

Then run `.workflow/bin/workflow validate`. Fix every error in the task files before handing off.

### 5. Hand off

Report list with:
- What can start now
- What runs in parallel (truly independent vs needs coordination)
- Recommended merge order if conflicts likely
- Spec checks left to `flow-close`, and debt items in the way that weren't made tasks

Each task must be buildable from a fresh session that reads only its own file
plus the spec sections it names; nobody should need conversation that produced it. If task would need that
conversation, it's missing something; fix task file now.

Build with `flow-implement`, one task at a time per working tree. Independent tasks run in parallel only in separate worktrees/directories; branch in same working tree is not isolation. A task whose branch `<effort>/<NN>-<slug>` already exists is claimed by whoever made it. Task can't start until all blockers are finished: archived under `.workflow/done/<effort>/` and landed (`merge-strategy.md`), or, under `Landing: pr`, stacked on the blocker's branch and recorded as `Base branch`. `.workflow/bin/workflow next` treats an archived blocker as finished, so it stops blocking without editing the dependent task's `Blocked by`.

When task finishes, `flow-implement` archives to `.workflow/done/<effort>/`, commits code, docs, and archive move together, and lands it. When the effort's last task has landed, `flow-close` checks the whole against the spec.

Genuinely exploratory task is decision task: settles question, produces answer written back into spec, not code. Mark it so nobody tries to build it.

## Amending an effort

Runs when a task of the effort is `Status: blocked`, or when the spec changed under tasks already written. The plan is fixed in the plan, here, not worked around in code.

1. Read what changed: the blocked task's `## Blocked` section, and the spec change or decision entry that answered it (`git diff` on the spec).
2. Go through every remaining task of the effort under `.workflow/tasks/<effort>/`, the blocked one first. For each: does `Delivers` still describe what the spec now wants? Do `Read first`, `Files`, `Check` and `Covers` still point at the right things? Is `Blocked by` still the real gate?
3. Rewrite what is stale. A task with no reason left to exist is deleted: name it and why in the decision entry for the change, and fix every `Blocked by` that pointed at it. New tasks take numbers after the highest one the effort has used, archived ones included; never renumber, other files refer to the numbers.
4. On the blocked task, remove `## Blocked`. If what it delivers is unchanged, set `Status: paused` and make sure `## Progress` says where the earlier work is, so `flow-implement` resumes it on the same Base commit. If what it delivers changed, reset `Base commit` to the `<commit-sha>` placeholder, drop `Started` and `Status`, and name any work worth reusing in `## Progress`; `flow-implement` then starts it on a clean baseline.
5. Rerun the coverage gate.
6. Present the changes as one round, as in step 3: what was rewritten, added, dropped, and why. Then `.workflow/bin/workflow validate` and commit the task and spec changes together.
