---
name: flow-architect
description: >-
  Find code that makes the next change expensive: duplication, dead weight, leaky
  modules, hand-rolled basics. Use when the user says "audit the codebase" or "find duplication".
---

# Flow: Architect

Read `.workflow/STYLE.md`; write like a person. Per CONVENTIONS §0, check the codebase before asking. Read `.workflow/glossary.md` and the area's specs before judging apparent inconsistencies.

Find code that makes the next change expensive and say what to do. Report only; change nothing. Prefer deleting three files to a clever redesign.

## 1. Find where change lands

Maintenance cost follows change, not size. Start with the area the user named. Otherwise inspect recent history:

```sh
git log --oneline -60
git log --format= --name-only -60 | sort | uniq -c | sort -rn | head -30
```

Start with hot spots. If history is scattered, say so and widen the scan. A large, quiet module may be less costly than a small file every feature must change.

## 2. Hunt for costly structure

Open each candidate with a concrete symptom: file, name, and what it does wrong. “Module not cohesive” is not a symptom.

- **Duplication:** repeated logic or the same rule implemented differently. Show the shared shape and where it should live; differing copies often hide bugs.
- **Dead weight:** unused exports, unset flags, unchanging config, one-implementation interfaces, single-product factories, delegating wrappers, or obsolete compatibility paths. Check callers before calling code dead.
- **Hand-rolled basics:** use a standard-library function or native platform feature where it already fits (for example, date input, CSS, or a database constraint). Name the replacement.
- **Unneeded dependencies:** packages used for one format, parse, or small utility. Name the standard-library or platform replacement.
- **Leaky modules:** callers forced to understand raw internals, arguments exposing implementation, or modules reaching into each other. Name a simpler boundary.
- **Plumbing:** layers that only forward calls or interfaces as complicated as their implementation. Remove only if complexity shrinks rather than moves.
- **Hard-to-test logic:** real behavior that cannot run without a database, network, or UI. Say what small seam would make it checkable.

## 3. Rank by cost

Rank by change frequency, changes forced, and effort to understand. An ugly file nobody edits ranks below a tidy file every feature must modify. Use **Fix now**, **Worth doing**, or **Only if it grows**. Five sharp findings beat twenty padded ones; report fewer when that is all the evidence supports.

## 4. Report

Write Markdown in the conversation or a file if long. Skip HTML and decorative diagrams; a short before/after sketch is fine when structure is the point.

```markdown
# Architecture review: <area> (<date>)

## Where time goes
<two or three lines: where recent changes keep landing>

## Findings
<findings in priority order; repeat the entry below as needed>

### 1. <Concrete symptom> [Fix now]
**Where:** <files>
**What is wrong:** <specific problem with evidence>
**What to do:** <plain-language change>
**What it buys:** <what gets easier>
**Cost:** <size, risk, and trade-off>

### 2. ...
<repeat the finding fields above>

## What I would not touch
<candidates that look bad but are not worth changing, with reason>
```

End with the finding count and first action. For every removal, put the size
change in **Cost** as `-N lines, -M dependencies` (include zero counts). A proposal
that neither shrinks code nor makes a specific change easier is a preference, not a finding.

## 5. Keep proposals bounded

Never propose a rewrite. Each proposal fits in a few tasks or breaks into tasks that do. Respect recorded decisions; challenge one only when the code has made it actively painful, and name the recurring cost. Correctness bugs found along the way get one line under a separate heading, then stop: this is structure review, not a bug hunt.

Prefer deletion over new machinery (CONVENTIONS §10). Before custom code, ask
whether it needs to exist, already exists in the codebase, is in the standard
library, or is provided natively by the platform. Then check installed dependencies
before proposing the smallest clear implementation. Do not add speculative wrappers,
single-use abstractions, guards for unsupported scenarios, or hashes/checksums
whose cost buys no concrete benefit. Keep real defects reachable through supported
use in scope; don't manufacture risk.
Record why an unaddressed finding remains debt, and why a declined finding is a
decision; do not leave either outcome implicit.

## 6. Follow findings through

Nothing changes in this skill; the user chooses what to act on. Each accepted finding becomes its own effort (`flow-grill`, then `flow-spec` and `flow-break`) unless it qualifies as a small task under CONVENTIONS §4, in which case it can be fixed directly.

Append each unaddressed finding to `## Entries` in `.workflow/technical-debt.md`, using that file's format. Use the concrete symptom as the heading and map labels to priority: Fix now → `fix-now`, Worth doing → `worth-doing`, Only if it grows → `only-if-grows`.

If the user declines a finding, remove its debt entry if present and append a decision to `.workflow/decisions.md` using its required fields (`Decided: not fixing <symptom>; Instead of: fixing it; Because; Mine: no; Revisit when`). This prevents future reviews from re-proposing it.
