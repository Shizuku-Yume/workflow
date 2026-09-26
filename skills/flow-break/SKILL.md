---
name: flow-break
description: >-
  Cut a spec into tasks where each one is a complete piece of working behavior
  that a single session can build and finish, with the dependencies between them
  written down. Use after a spec exists and the work is bigger than one sitting;
  when the user says "break this down", "split this into tasks", "what order do
  we do this in", or before handing work to run in parallel.
---

# Flow: Break

Read `.workflow/CONVENTIONS.md` first (§2 where things live).

Input: a spec, a plan, or the current conversation. Output: one file per task in
`.workflow/tasks/`.

## Why tasks exist

A long session degrades: the model's attention is sharpest early and gets worse
as context fills, so a job described in one huge document gets built worse than
the same job described in five small ones. Each task is sized to fit in one fresh
session with room to spare.

The second reason is order. Tasks declare what blocks them, so independent ones
can run in parallel and the user can see what is actually startable now.

## The shape of a good task

- **It delivers working behaviour**, end to end: a narrow path that runs, is
  visible, and can be checked. Not "add the database layer", which delivers
  nothing anyone can use.
- **A fresh session can finish it** without reading the whole codebase first.
  The task says which files matter.
- **It is checkable** by something other than the person who wrote it.
- **It is independent** of tasks declared after it. Everything it needs is either
  already in the repo or in a task that blocks it.

Prefer the narrow complete path over the broad incomplete one. A task that adds
one field through the whole stack, storage to display, is usually better than a
task that adds five fields to storage only.

**The exception: mechanics that touch everything at once.** Renaming a shared
symbol, changing a column type, moving a file used in a hundred places. This
cannot land green in one task. Sequence it as three steps instead: add the new
thing beside the old, move the callers over in batches, then delete the old
thing. Each batch is its own task and each lands with the build passing.

## Sizing

A task is too big if you cannot describe what it delivers in one sentence
without "and". Too big if it needs more than roughly a dozen files read to start.
Too small if it cannot be checked on its own.

When unsure, cut smaller. Two small tasks in sequence beat one that stalls
half-way with nothing working.

## Process

### 1. Read the spec and the code

Identify the places the work touches. Look for tidying that makes the real change
easier: renaming the confusing thing, extracting the shared piece, moving the
function that is in the wrong file. That tidying goes first, as its own task.
Making the change easy, then making the easy change.

### 2. Draft the tasks

For each one, write:

- **Delivers** - the behaviour a person can observe once it is done.
- **Blocked by** - which other tasks must finish first, or none.
- **Files** - where the work happens, so the next session does not go hunting.
- **Read first** - the specific spec sections, glossary entries, or files needed
  to start. Keep this list short; a long list means the task is too big.
- **Check** - the command to run and the result that means it works.
- **Done when** - the acceptance points, as a checklist.

### 3. Quiz the user

Present the whole breakdown as a numbered list: title, what it delivers, what
blocks it. Ask three things only:

- Is this the right size?
- Are the dependencies right - does each task depend only on what truly gates it?
- Should any be joined or split?

Iterate until they approve. This is one round, not a negotiation per task.

### 4. Write the folders

`.workflow/tasks/<NN>-<slug>.md`, numbered `01`, `02` in dependency order so
blockers come first:

```markdown
# <NN>: <Title>

**Delivers:** <the observable behaviour>

**Blocked by:** <NN titles> | None, can start now

**Files:** <where the work happens>

**Read first:** <spec sections, glossary terms, files>

**Check:** `<command>` → <the result that means it works>

- [ ] <acceptance point>
- [ ] <acceptance point>
```

Rules for what goes in: behaviour and checks, not code. No snippets except when a
snippet carries a decision prose cannot (a schema, a state machine, a type).
Never paste a file path into a task if the file is likely to move before the task
runs; name the module instead.

Do not create a task for work nobody asked for. If a task exists only because the
plan looks tidier with it, drop it.

### 5. Hand off

Report the list with what can start now and what runs in parallel. Each task is
built in a fresh session by reading its own file plus the spec sections it names;
nobody should need the conversation that produced it. If a task would need that
conversation, it is missing something; fix the task file now.

Build them with `flow-implement`, one task per session. Independent tasks can run
in parallel sessions; a task whose `Blocked by` is not done cannot start.

A task that is genuinely exploratory rather than buildable is a decision task: its
job is to settle a question, and it produces an answer written back into the spec,
not code. Mark it as one so nobody tries to build it.
