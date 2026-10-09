---
name: flow-break
description: >-
  Cut spec into tasks a single session can finish, with dependencies. Use when
  user says "break this down", "split into tasks", or before parallel work.
---

# Flow: Break

Read `.workflow/CONVENTIONS.md` §2 first. Input: spec or settled conversation. Output: task files in `.workflow/tasks/`, archived to `.workflow/done/<effort>/` when finished.

## Why tasks exist

Long sessions degrade: attention is sharpest early. Each task sized to fit one fresh session with room to spare.

Second reason: order. Tasks declare blockers, so independent ones can run in parallel (separate worktrees/branches/directories only; shared working tree is serial).

## Good task shape

- **Delivers working behavior** end to end: narrow path that runs, is visible, checkable. Not "add database layer" which delivers nothing usable.
- **Fresh session can finish it** without reading whole codebase. Task says which files matter.
- **Checkable** by something other than person who wrote it.
- **Independent** of tasks declared after it. Everything needed is already in repo or in blocking task.

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

### 2. Draft tasks

For each:
- **Effort** — lowercase slug `[a-z0-9]+(-[a-z0-9]+)*`, determines archive dir `.workflow/done/<effort>/`
- **Task type** — `feature`, `bugfix`, `refactor`, `spike` (optional, defaults to `feature`)
- **Base commit** — `<commit-sha>` placeholder when drafting. `flow-implement` captures real SHA when starting.
- **Delivers** — behavior person can observe once done (for spike: "Answer to: <question>")
- **Blocked by** — required: `None`, or comma-list of `NN` (same effort) or `<effort>/NN` (cross-effort). Numbers only; titles break `workflow validate`.
- **Files** — expected starting locations. Not closed whitelist; necessary tests/callers/docs may be added during implementation.
- **Read first** — specific spec sections, glossary entries, files needed to start. Short list; long list means task too big.
- **Check** — command to run and result that means it works (for spike: how answer will be validated)
- **Done when** — acceptance points as checklist (for spike: question answered with evidence)
Behavior and checks, not code. No snippets except when snippet carries decision prose can't (schema, state machine, type). Never paste file path if file likely to move; name module instead.

Don't create task for work nobody asked for.

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

### 4. Write files

`.workflow/tasks/<NN>-<slug>.md`. Number within the effort, `01`, `02` in dependency order (blockers first). Another effort may reuse the same numbers, so refer to tasks elsewhere as `<effort>/<NN>`, and pick slugs that don't collide with another effort's file in the shared `tasks/` directory.

```markdown
# <NN>: <Title>

**Effort:** <effort>
**Task type:** feature
**Base commit:** <commit-sha>

**Delivers:** <observable behavior>

**Blocked by:** None | <NN>, <effort>/<NN>
**Files:** <where work happens>

**Read first:** <spec sections, glossary terms, files>

**Check:** `<command>` → <result that means it works>

- [ ] <acceptance point>
- [ ] <acceptance point>
```

If `.workflow/efforts/<effort>.md` doesn't exist, run `workflow effort create <effort>` and fill in goal, scope, success criteria and priority from the spec.

Then run `workflow validate`. Fix every error in the task files before handing off.

### 5. Hand off

Report list with:
- What can start now
- What runs in parallel (truly independent vs needs coordination)
- Recommended merge order if conflicts likely

Each task built in fresh session by reading its own file plus spec sections it
names; nobody should need conversation that produced it. If task would need that
conversation, it's missing something; fix task file now.

Build with `flow-implement`, one per session. Independent tasks run in parallel only in separate worktrees/directories; branch in same working tree is not isolation. Task can't start until all blockers are finished: their files sit under `.workflow/done/<effort>/` in committed HEAD or in the branch the dependent task uses. An uncommitted done file doesn't count. `workflow next` applies the same rule, so an archived blocker stops blocking without editing the dependent task's `Blocked by`.

When task finishes, `flow-implement` archives to `.workflow/done/<effort>/` and commits code, docs, and archive move together.

Genuinely exploratory task is decision task: settles question, produces answer written back into spec, not code. Mark it so nobody tries to build it.
