---
name: flow-spec
description: >-
  Turn settled conversation into a spec document. No interview. Use after design
  discussion or when user says "write the spec", "document the decision".
---

# Flow: Spec

Read `.workflow/CONVENTIONS.md` §2 (where things live) and `.workflow/STYLE.md` first.

Input: conversation, design discussion. Output: `.workflow/specs/<slug>.md`.

**Do not interview the user.** Everything needed was decided in conversation. If something genuinely wasn't, write it under "Open questions" and keep going.

## Two mistakes to avoid

**Writing implementation** — spec that names every function is stale in a week. Name modules, boundaries, contracts, shapes. Not lines.

**Writing only conclusions** — spec without the rejected option is a press release. Next session reads it, disagrees with invisible reasoning, reopens decision.

## Before writing

1. **Find decisions already made** — conversation, `.workflow/decisions.md`, user's message are source. Don't invent decisions to fill sections.
2. **Look at the code** — read modules this will touch. Per CONVENTIONS §0: evidence before questions. Check codebase for facts before asking user.

## The document

```markdown
# <Title>

**Status:** proposed | in progress | done

## What this is for
Problem from user's perspective. What's broken, missing, or wanted, and what
happens if nobody does this. Must stand alone.

## What it does
Behavior after the change, from user's perspective. Not implementation; what
someone notices is different. Concrete enough to demo.

## How it is built
Decisions that shape code. Modules added/changed, boundaries, data shapes,
interfaces, failure behavior. Prose and short lists; snippet only when clearer
(state machine, schema, type). Say what each piece is responsible for and what
it's not.

## What it must not do
Out of scope, explicitly, with reason. Things a reasonable reader might assume
are included. Prevents scope creep.

## What was considered and rejected
One entry per real alternative:
- **<The option>.** Its strongest argument, stated fairly. Then constraint that
  killed it.

Only real options considered. Don't invent alternatives to look thorough.

## How we will know it works
Checks that prove behavior, each with an ID. Tasks list the IDs they make pass
in `Covers`; `flow-close` runs all of them against the finished effort.
- **W1.** <what command, what result>
- **W2.** ...

Also:
- What's tested at which level, and why that level.
- Observable signal when it breaks.
- Edges worth testing: empty input, big input, concurrent use, failure of each
  external dependency, permission denied.

If anything is "we will see", say so plainly.

## Open questions
Unresolved decisions, each with what would settle it and who can settle it.
Empty is good. Long list means spec not ready to build from.

## Notes
Anything a reader would otherwise ask. Links to conversation, task files,
related specs.
```

## Rules

- **Numbers not adjectives** — "Handles large imports" is nothing. "10k rows under 2s" is spec. If nobody knows number, say that.
- **Updated in place, never annotated** — reversed decision rewrites spec (CONVENTIONS §2). No contradicting answers in one document. Once tasks exist, a spec change goes through `flow-break` amend so they follow it (CONVENTIONS §5).
- **Check IDs are stable** — never renumber a check tasks already cite. A dropped check keeps its ID out of use; a new one takes the next free number.
- **Write for someone reading in six months** — not for person who just had conversation.
- **No file paths that will move** — name module, not `src/foo/bar.ts`.
- **Delete sections with nothing to say** — empty section is noise. Deletions pass convergence gate: if you have nothing for "What was considered and rejected" because no alternatives existed, delete the heading. Missing section conveys "this didn't apply", empty section suggests forgotten content.

## Convergence gate

Before presenting, verify:

**Completeness:**
- "What this is for" stands alone as problem statement
- "What it does" describes observable user-facing behavior
- "How it is built" names modules, boundaries, data shapes
- "What it must not do" lists reasonable out-of-scope items (or section deleted if scope obvious)
- "How we will know it works" specifies runnable checks, each with an ID
- Sections with no content are deleted, not left empty
- No duplicate facts across sections
- No contradictions (resolve per latest decision)
- All terms match `.workflow/glossary.md` or newly added
- Decisions the spec relies on cite their entry as `decisions.md: <date> - <title>`

**Resolvability:**
- "Open questions" either empty or each names who/what settles it
- No placeholder text like "TBD", "to be decided"
- No unresolved alternatives disguised as notes

**Evidence:**
- Code inspection mentioned (which modules read)
- Rejected alternatives have real reasons, not invented ones
- Numbers replace adjectives where they matter

If any check fails, fix before presenting.

## Finish

After passing convergence gate, write file and report:
1. Path
2. What spec decides (one line)
3. Open questions if any, or "ready to build"

**Require explicit user confirmation** before proceeding. Present summary and stop. Only after user confirms does spec become settled.

If spec changes materially after confirmation, re-run convergence gate and get fresh confirmation.

Next step: `flow-break`, also when the work fits one session. Building needs a task file: it carries the Base commit `flow-verify` compares against, the Check, and the archive. A one-task breakdown skips flow-break's review round, so it costs little.

The spec is written with `**Status:** proposed`; `flow-implement` and `flow-close` move it on (CONVENTIONS §6).
