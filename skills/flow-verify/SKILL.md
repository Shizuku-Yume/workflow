---
name: flow-verify
description: >-
  Review a change on three axes at once: does it do what was asked, is the code
  any good, and did the work follow this project's process. Use before merging,
  when the user says "review this", "check my work", "did I miss anything",
  "review since main", or as the last step of building any task.
---

# Flow: Verify

Read `CONVENTIONS.md` next to this skill first (§2 for where the spec, tasks and
standards live).

Three separate reviews of the same change. They are separate on purpose: code can
follow every convention and build the wrong thing, or build exactly the right
thing in a way nobody can maintain, or be perfectly good work that skipped the
steps this project agreed on.

Run the three axes as parallel subagents so their findings do not contaminate each
other, then report them side by side. Do not merge or rerank across axes; do not
pick one overall winner. A change that passes two axes and fails the third has
failed.

## 1. Pin the comparison point

Whatever the user named: a commit, a branch, a tag. If they named nothing, ask
once. Capture the command now and reuse it:

```
git diff <point>...HEAD      # three dots: compares against the merge base
git log <point>..HEAD --oneline
```

Check the reference resolves and the diff is not empty before spawning anything.
An empty diff or a bad reference should fail here, not inside three subagents.

## 2. Gather what each axis needs

**Did it do what was asked** needs the source of truth: the spec, the task file,
or the issue. Look for it in commit messages, `.workflow/specs/`, `.workflow/tasks/`,
or an explicit path the user gave. If there is none, say so and run this axis as
"no spec available" rather than inventing requirements.

**Is the code any good** needs this project's standards: `.workflow/standards.md`,
`AGENTS.md`, `CONTRIBUTING.md`, lint config, and the smell baseline below. On top
of whatever the project documents, these apply, because most projects document
nothing:

- **A name that does not say what the thing is.** A function, variable or type
  whose name hides its purpose. Rename it; if no honest name exists, the design is
  unclear.
- **The same logic in more than one place** within the change. Extract the shared
  shape and call it from both.
- **A method reaching into another object's data** more than its own. Move it onto
  the data it wants.
- **The same few fields travelling together** everywhere. Bundle them into one
  type.
- **A primitive standing in for a concept** that deserves its own type.
- **The same switch over the same type** repeated in the change. Replace with one
  shared map, or polymorphism.
- **One logical change forcing scattered edits** across many files. Gather what
  changes together into one module.
- **One file edited for several unrelated reasons.** Split it.
- **Abstraction or hooks for needs nothing asked for.** Delete until a real need
  appears.
- **Long `a.b().c().d()` navigation** the caller should not depend on. Hide the
  walk behind one method.
- **A class or function that only delegates.** Cut it.
- **A subclass ignoring most of what it inherits.** Use composition.

Two rules bind this list. The project wins: a documented project standard
overrides a baseline item. And each item is a judgement call, not a rule
violation; skip anything a linter or type checker already enforces.

**Did it follow the process** needs `.workflow/standards.md` and
`.workflow/decisions.md`: what this project agreed to do, and what was decided
along the way.

## 3. Spawn three subagents

**Axis 1, built as asked.** Given the diff command, the commit list, and the spec
or task text. Report: requirements that are missing or half-done; behaviour in the
diff nobody asked for; requirements that look done but are wrong. Quote the spec
line for each finding. Under 400 words.

**Axis 2, code quality.** Given the diff command, the commit list, the project's
standards files, and the smell baseline pasted in full (the subagent cannot see
this file). Report per file where relevant: violations of documented standards,
citing the standard; and any baseline smell, named, with the code quoted. Separate
hard violations from judgement calls. Skip what tooling enforces. Under 400 words.

**Axis 3, process.** Given the diff command, the commit list, `.workflow/standards.md`
and `.workflow/decisions.md`. Report:

- **Evidence.** Does the change carry proof it works: a test that would fail if
  the behaviour broke, or a recorded check with its output? "It compiles" is not
  evidence. Name what is missing.
- **Documents.** If the change altered a fact a spec or the glossary states, was
  that updated in the same change? Was a reversed decision recorded?
- **Decisions.** Does the code contain choices that contradict a logged decision,
  or that should have been logged and were not?
- **Leftovers.** Debug prints, commented-out code, dead flags, a `TODO` that
  encodes a decision instead of making it, files that no longer belong.
- **Scope.** Does the diff do work beyond the task, or stop short of it?

Under 400 words.

## 4. Report

Three sections, one per axis, findings as written by each subagent, lightly
cleaned. Then one line per axis: the count and the worst item *within that axis*.
Never a single overall verdict across axes.

End with the honest one-liner: is this ready to merge, and if not, what is the
shortest path to it being ready. If an axis found nothing, say that in its section
instead of leaving it blank; a clean axis is information.

## 5. Then what

Fix the findings, or hand them to the user. A finding the user rejects gets one
line in `.workflow/decisions.md` so the next review does not raise it again.

Do not re-run the whole review after fixing a finding unless the user asks. The
fix either addresses it or it does not; check that specific thing.
