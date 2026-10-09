---
name: flow-grill
description: >-
  Align on what to build before building it. Batch questions, decide small things,
  log choices. Use when requirements are vague or design unclear.
---

# Flow: Grill

Read `.workflow/CONVENTIONS.md` §1 (decision protocol) and `.workflow/STYLE.md` first.

Goal: agree on what to build and why. Small choices made and logged. Next step unblocked.

Not a requirements form. Not a reason to ask about things you can look up. Four questions and six logged decisions beats twelve questions.

## 1. Evidence check (mandatory)

CONVENTIONS §0: before asking anything, check if the codebase answers it.

For each potential question:
- Is the answer in code, tests, configs?
- Does existing pattern or convention answer this?
- Can I trace execution to find out?

If yes: investigate via `grep`, `find`, subagents, or read files. Report findings briefly (one line each) before questions.

## 2. Write the design tree down, privately

List decisions this work depends on: what it's for, what it must not do, where it plugs into existing code, what shape data takes, how it gets tested, what happens when it fails, what user sees. Mark each:

- already settled by user's message or existing docs
- fact you can look up (do it now, step 1)
- real open decision

Only the last group can become questions.

When a decision feels forced by convention rather than constraint, decompose it with `.workflow/thinking.md`: restate problem, list fundamental truths, challenge assumptions, build up from truths, validate. Present the decomposition when it shows a requirement can be met much more simply. Use for expensive decisions (infrastructure, architecture shifts, breaking changes, new dependencies), not every implementation choice.

## 3. Triage every open decision

Bucket each per CONVENTIONS §1.2:

- **Look it up** → do it now. Don't ask.
- **Decide and log** → take your recommendation. Write it to `.workflow/decisions.md` if substantial (CONVENTIONS §1.2), mention it in one line at end of round.
- **Ask** → changes what gets built, trade-off is real, can't resolve from what's in front of you.

Be aggressive about the middle bucket. Default for a detail is "decide it and say so", not "ask".

**Draft decision entries as you evaluate options.** Write competing alternatives with their strongest cases while fresh. This prevents strawman "Instead of" entries written later when memory has faded.

## 4. Ask the round

Ask every question you can ask right now without guessing another answer, in one message, ranked by what unblocks most downstream work. Format and cap per CONVENTIONS §1.3. Six is a ceiling, not a target: two good questions beat six padded ones. Extras beyond six are almost always things you should decide yourself: decide, log, list one line each under the questions.

Then stop. Don't keep asking while waiting, don't start building, don't write the spec.

## 5. Repeat only for questions answers opened

Answer often makes new questions askable and kills others. Recompute the tree, ask another round only if a genuinely blocking question remains.

**Two to four rounds is normal.** If entering a fifth round, work is likely too big: stop, suggest `flow-map` or smaller slice. Judgment, not hard limit; genuine convergence in round 5 is fine, perpetual grilling means unclear scope.

## 6. Name things as you go

When you land on a name for a concept/module/state, write to `.workflow/glossary.md` immediately: the term, what it means, what not to call it.

If a term is two things wearing one name, split it now.

## 7. Confirm and stop

Restate every decision as numbered list (CONVENTIONS §1.4). State next step in one line. Finish.

If user says "enough": write decisions log, list what's still open (one line each), hand back.

## Decision log

Append to `.workflow/decisions.md` per CONVENTIONS §2 and the format in that file. Five fields required; tag the entry `**Effort:** <slug>` when it belongs to one effort. Run `workflow decisions validate` after appending.

Use draft entries written during step 3. If "Instead of" reads like a strawman, that alternative was never serious; find the real runner-up or acknowledge the choice needs no entry.

## When to use something else

CONVENTIONS §5 has routing. Work too big to see route through → `flow-map`. User already knows what they want → `flow-spec`.
