---
name: flow-grill
description: >-
  Align on what to build before building it. Batch questions, decide small things,
  log choices. Use when requirements are vague or design unclear.
---

# Flow: Grill

Resolve only decisions still open after checking the repo. Read `.workflow/CONVENTIONS.md`
§0 and §1.1–§1.3, plus `.workflow/STYLE.md`, first.

## 1. Find facts and map choices

Check code, tests, configs, docs, and prior decisions before asking. For a port, migration,
rewrite, or replacement, map each user-visible flow and old concept to its new counterpart;
read the new system's own model and identify behavioral differences for a decision.

List privately what the work is for, must not do, where it fits, data shape, failure
behavior, and observable outcome. Separate settled decisions, findable facts (look them
up), and genuine open choices.

For expensive choices—architecture shifts, infrastructure, breaking changes, or new
dependencies—start from the problem and hard constraints. Test each proposed piece by
asking what breaks if removed; choose the cheapest experiment that resolves uncertainty.

## 2. Triage and ask

Apply CONVENTIONS §1.1 and §1.2: resolve facts; for Bucket B, choose the reasonable,
reversible option and state its trade-off in one line instead of offering a menu. Log only
decisions that meet the convention's criteria. Ask only Bucket C questions: genuine
user-owned trade-offs about what gets built or expensive-to-reverse choices.
Batch independent questions in one ranked message (up to CONVENTIONS §1.3's limit). Include
a recommendation and one-line reason. Stop grilling immediately when the next step is
unblocked; proceed to `flow-spec` or `flow-break` as appropriate. If the work remains too
foggy to plan, use `flow-map`.

## 3. Record and continue

Add only shared project terms to `.workflow/glossary.md`. Append qualifying choices to
`.workflow/decisions.md` using its format; cite the entry as `decisions.md: <date> - <title>`.
Commit planning records if the session ends here, per CONVENTIONS §2. When proceeding to
`flow-spec` or `flow-break`, carry decisions forward without reopening settled choices.
