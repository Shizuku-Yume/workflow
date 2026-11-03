---
name: flow-spec
description: >-
  Turn settled conversation into a spec document. No interview. Use after design
  discussion or when user says "write the spec", "document the decision".
---

# Flow: Spec

Read CONVENTIONS §0, §2, §3, §5 and §6, plus `.workflow/STYLE.md`. Clear 1–3 task work
with no durable spec skips this step and goes straight to `flow-break`.

Write `.workflow/specs/<effort>.md` from the settled conversation and existing decisions;
do not re-interview. Keep genuinely unresolved items under Open questions and continue.
The spec is a clean launch document, not a defense transcript (STYLE.md).

## Before writing

Collect settled choices from the conversation and `.workflow/decisions.md`; read the code
and relevant glossary terms. Cite relied-on decisions as `decisions.md: <date> - <title>`.

## Spec template

```markdown
# <Title>

**Status:** proposed
**Priority:** normal

## What this is for
Standalone user problem and what happens if it remains unsolved.

## What it does
Observable user-facing behavior, concrete enough to demonstrate.

## How it is built
Modules, boundaries, data shapes, interfaces, and failure behavior; explain
responsibilities without prescribing function-by-function implementation.

## What it must not do
Plausible assumptions that are out of scope, with reasons.

## What was considered and rejected
- **<Option>.** Strongest case, then the constraint that ruled it out.

## How we will know it works
- **W1.** <runnable check and observable passing result>
- **W2.** <runnable check and observable passing result>

## Open questions
Unresolved choices and who or what settles them; omit when empty.

## Notes
Useful links or context; omit when empty.
```

## Rules

- Make the problem standalone and behavior observable. Keep the spec about outcomes and
  boundaries, not implementation trivia; use numbers where they materially clarify scope.
- Define stable, runnable `W`-ID checks with observable pass signals. At least one must
  exercise the main user path end to end through the real entry point and real dependencies;
  name any remaining stand-in. Tasks cite covered IDs; `flow-close` checks the whole effort.
- Include only real rejected alternatives and unresolved questions. No `TBD` or other
  placeholders; delete empty sections and avoid duplicate or contradictory facts.
- Update the spec in place when facts or decisions change. Once tasks exist, amend through
  `flow-break` (CONVENTIONS §5); keep terminology aligned with the glossary.
- `Priority` is optional (default `normal`); `Status` starts `proposed` and advances per
  CONVENTIONS §6.

## Finish

If `flow-break` follows now, go straight to it; its review covers the spec and tasks.
Otherwise report the path, decisions, and open questions or readiness; get approval and
commit the spec and related planning records per CONVENTIONS §2. Material changes after
approval need fresh approval.
