---
name: flow-grill
description: >-
  Align on what to build before building it. Batch questions, decide small things,
  log choices. Use when requirements are vague or design unclear.
---

# Flow: Grill

Read `.workflow/CONVENTIONS.md` §1 (decision protocol) and `.workflow/STYLE.md` first.

Goal: agree on what to build and why, with small choices made and logged, so the next step is unblocked. Four questions and six logged decisions beat twelve questions.

## 1. Evidence check

CONVENTIONS §0: before asking anything, check whether the code, tests, configs or an existing pattern answer it. Investigate with `grep`, `find`, file reads or subagents, and report findings in one line each before the questions.

## 2. Write the design tree down, privately

List the decisions this work depends on: what it's for, what it must not do, where it plugs into existing code, what shape data takes, how it gets tested, what happens when it fails, what the user sees. Mark each as settled (by the user's message or existing docs), a fact to look up (do it now, step 1), or a real open decision. Only the last group can become questions.

For expensive choices (infrastructure, architecture shifts, breaking changes, new dependencies), decompose before deciding:
- Restate the problem without naming a solution.
- List the hard constraints.
- For each proposed piece, ask what breaks if it's removed.
- Build up only what a constraint demands.
- Name the cheapest experiment that would prove it.

Present the decomposition when it shows a requirement can be met much more simply.

## 3. Triage every open decision

Bucket each per CONVENTIONS §1:

- **Look it up** → do it now.
- **Decide and log** → take your recommendation, log it if substantial, mention it in one line at the end of the round.
- **Ask** → it changes what gets built, the trade-off is real, and you can't resolve it from what's in front of you.

Default for a detail is "decide it and say so". Draft decision entries while you evaluate options, with each alternative's strongest case written while it's fresh.

## 4. Ask the round

Ask every question you can ask now without guessing another answer, in one message, ranked by what unblocks most, formatted and capped per CONVENTIONS §1. Extras beyond the cap are things to decide yourself: decide, log, list one line each under the questions.

Then stop and wait for the answers.

## 5. Repeat only for questions the answers opened

Recompute the tree; ask another round only if a blocking question remains. Two to four rounds is normal. Entering a fifth usually means the work is too big: suggest `flow-map` or a smaller slice.

## 6. Name things as you go

When you land on a name for a concept, module or state, write it to `.workflow/glossary.md` immediately: the term, what it means, what not to call it. A term that names two things gets split now.

## 7. Confirm and stop

Restate every decision as a numbered list (CONVENTIONS §1) and state the next step in one line.

If the user says "enough": write the decision log, list what's still open (one line each), hand back.

If the session ends here (no `flow-spec` follows now), commit the decision and glossary entries per CONVENTIONS §2.

## Decision log

Append to `.workflow/decisions.md` in the format that file shows: five fields, plus `**Effort:** <slug>` when the entry belongs to one effort. Run `.workflow/bin/workflow validate` after appending.

Start from the drafts written in step 3. If "Instead of" reads like a strawman, that alternative was never serious: find the real runner-up, or the choice needs no entry.

## When to use something else

Routing is in CONVENTIONS §5. Work too big to see the route through → `flow-map`. User already knows what they want → `flow-spec`.
