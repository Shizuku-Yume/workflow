---
name: flow-spec
description: >-
  Turn a settled conversation into a spec document: what is being built, why,
  how the pieces connect, what was ruled out, and how anyone will know it works.
  No interview; it writes down what the conversation already decided. Use after a
  design discussion, when handing work to another session, or when the user says
  "write the spec", "write this up", "document the decision", "turn this into a
  spec".
---

# Flow: Spec

Read `CONVENTIONS.md` next to this skill first (§2 document layout, §3 writing).

Input: a conversation, a design discussion, or an existing half-formed document.
Output: `.workflow/specs/<slug>.md`.

Do **not** interview the user. Everything needed was decided in the conversation.
If something genuinely was not, write it under "Open questions" and keep going;
do not stop to ask.

## The two mistakes

**Writing implementation.** A spec that names every function is stale the week it
lands. Name the modules, the boundaries, the contracts, the shapes. Not the lines.

**Writing nothing but conclusions.** A spec that says what was decided without
the option it beat is a press release. The next session reads it, disagrees with
the reasoning it cannot see, and reopens the decision. The rejected option is
half the value of the document.

## Before writing

1. **Find the decisions already made.** The conversation, `.workflow/decisions.md`,
   and the user's message are the source. Do not invent decisions to fill a section.
2. **Look at the code.** Read the modules this will touch. A spec written without
   reading the code reads like one.
3. **Use the project's words.** Take names from `.workflow/glossary.md`. If you
   need a new term, add it to the glossary as you write.

## The document

```markdown
# <Title>

**Status:** proposed | in progress | done

## What this is for

The problem, from the user's perspective, in plain language. What is broken,
missing, or newly wanted, and what happens if nobody does this. This section must
stand on its own: delete everything below it and it still describes a real
problem.

## What it does

The behaviour after the change, from the user's perspective. Not the
implementation; what someone notices is different. Concrete enough to demo.

## How it is built

The decisions that shape the code. Modules added or changed, the boundaries
between them, the data shapes, the interfaces, the failure behaviour. Prose and
short lists; a snippet only when a snippet is clearer than a paragraph (a state
machine, a schema, a type). Say what each piece is responsible for and what it is
not.

## What it must not do

Out of scope, explicitly, with the reason. Things a reasonable reader might
assume are included. This section prevents scope creep better than any amount of
saying what is in scope.

## What was considered and rejected

One entry per real alternative, and each entry leads with the case *for* it:

- **<The option>.** Its strongest argument, stated fairly. Then the constraint
  that killed it.

Only real options considered. Do not invent alternatives to look thorough, and
do not write "do nothing" unless doing nothing was actually on the table.

## How we will know it works

- The checks that prove the behaviour: what command, what result.
- What is tested at which level, and why that level.
- The observable signal when it breaks.
- The edges worth a test: empty input, big input, concurrent use, failure of each
  external dependency, permission denied.

If anything here is "we will see", say so plainly instead of dressing it up.

## Open questions

Decisions that are genuinely unresolved, each with what would settle it and who
can settle it. Empty is the good outcome. A long list here means the spec is not
ready to build from.

## Notes

Anything a reader would otherwise have to ask you. Links to the conversation, the
task folders, related specs.
```

## Rules

- **Numbers not adjectives.** "Handles large imports" is nothing. "10k rows
  under 2s on the current box" is a spec. If nobody knows the number, say that.
- **One spec per effort, updated in place.** When the code changes a fact in the
  spec, fix the fact in the same change. Never append a "2026-04-02 update"
  section; rewrite the sentence so the document reads as current.
- **A reversed decision rewrites the spec**, and gets one line in
  `.workflow/decisions.md`. Nobody should be able to read two contradicting
  answers in one document.
- **Write specs for people who will read it in six months**, having forgotten
  everything. Not for the person who just had the conversation.
- **No file paths that will move.** Name the module, not `src/foo/bar.ts`. If a
  path matters, say where it sits and why.
- **Skip sections that have nothing to say.** Delete the heading. An empty
  section is noise; a missing section is information.

## Finish

Write the file, then report in three or four lines: the path, what the spec
decides, and the open questions if any. Confirm with the user before treating it
as settled. Then the next step is `flow-break` if the work is bigger than one
session, or straight to building if it is not.
