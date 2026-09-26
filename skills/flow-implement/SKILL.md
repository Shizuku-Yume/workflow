---
name: flow-implement
description: >-
  Build one task from the task folder, then review it and commit it, without
  being asked for each step. Runs the tests it was told to run, checks its own
  work with the review agents, and archives the task when it passes. Use when the
  user says "implement task 3", "build this ticket", "do the next task", "work on
  01", or after flow-break has produced a task list.
---

# Flow: Implement

Read `.workflow/CONVENTIONS.md` and `.workflow/STYLE.md` first. Then read the task
file you were given, and the spec sections it names. Nothing else in the
conversation matters; a task file that needs this conversation is broken, and
fixing it is part of this job.

You do this end to end: build, prove, review, commit, archive. Do not stop
between the steps to ask whether to continue. Stop only for a decision that
changes what gets built, and ask it as one batched question (CONVENTIONS §1.3).

## 1. Confirm the task is startable

Read the task's `Blocked by`. If a blocker is not done, say which one and stop.
Do not work around it, and do not quietly do the blocker first.

If the task file does not name where the work goes or how to check it, that is a
gap: fill it in from the spec and the code, and say so in one line.

If the task turns out to be wrong - it assumes something the code does not do, or
the spec contradicts it - stop and report that. Do not rewrite the task to match
what is easy to build.

### Before you write code

Look at the code the task touches and the tests that already exist. Make the
change in the way this project already does things; a second convention invented
for one task is a cost the next person pays.

Confirm the starting point is clean: run the test command from
`.workflow/standards.md`. If it fails before you start, that failure is not yours,
and you need to know the baseline before you can claim anything about after.

## 2. Build it

Smallest change that delivers what the task says. Every file the task names, and
no file it does not.

Do not add configurability, error handling, or abstractions the task did not ask
for. If you believe one is genuinely needed, do the simple thing and say what you
skipped in the final report; the user can ask for it.

Run the typecheck and the tests you touched as you go, not once at the end.

**Write the check while you write the code.** Whatever the task's `Check` line
says, make it exist. A change with no way to tell whether it works is not a
finished change, and "it compiles" is not a way to tell.

## 3. Prove it

Run the task's check command and look at the output. Not the test suite in
general: the thing that would fail if this specific behaviour broke.

Then exercise the real path once, by hand or by script, and note what happened.
A test that passes proves what the test asserts; running the thing proves the
thing works. On a UI change, open it. On a CLI change, run the command. Report
what you saw, including anything that looked wrong.

If the check cannot pass, say what blocks it rather than loosening it.

## 4. Review it

Run `flow-verify` against the work you just did. Two review agents in parallel,
each cheaper and less biased than reviewing your own diff:

- **`workflow-reviewer`** for correctness and code quality.
- **`workflow-process`** for evidence, documents, decisions, leftovers, scope.

Plus a security pass with `security-reviewer` when the change touches
authentication, authorisation, input that reaches a query or a shell, secrets,
file paths, or anything crossing a trust boundary. Skip it otherwise and say you
skipped it.

Fix what the reviews find. A finding you disagree with gets one line in
`.workflow/decisions.md` explaining why, not silence.

Do not re-run the whole review after fixing a finding; check the specific thing
that was wrong.

## 5. Close it out

- **Update the documents the change made stale.** If a fact in the spec, the
  glossary or `standards.md` no longer matches the code, fix it now, in this
  change. That is the whole reason those files are trustworthy.
- **Record the decisions you made.** Anything you chose without asking goes into
  `.workflow/decisions.md` with what it beat.
- **Commit.** One commit for the task, message saying what changed and why. No
  "wip", no "fixes", no unrelated edits riding along.
- **Archive the task.** Move the task file to `.workflow/done/`. If it taught
  something worth keeping, put that in the spec or the glossary first; do not
  archive a task file as a substitute for updating the spec.

## 6. Report

Four lines, no more:

- What now works, from the user's point of view.
- What you ran to prove it, and what it said.
- What the reviews found and what you did about it.
- What you deliberately left out, and when it would matter.

If the task is not finished, say that first, and say exactly what remains.

## What this is not

Not a licence to reinterpret the task. Not a reason to fix unrelated things you
noticed on the way (report them; open a separate task). Not a place to re-litigate
a decision that is already in `.workflow/decisions.md`.
