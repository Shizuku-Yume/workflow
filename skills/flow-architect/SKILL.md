---
name: flow-architect
description: >-
  Find code that makes next change expensive: duplication, dead weight, leaky
  modules, hand-rolled basics. Use when user says "audit codebase", "find duplication".
---

# Flow: Architect

Read `.workflow/CONVENTIONS.md` §3 and `.workflow/STYLE.md`: everything you report must read like person wrote it.

Per CONVENTIONS §0: check codebase before asking. This skill is read-only investigation.

Find code that makes next change expensive, say what to do. Report only; change nothing.

Two failures to avoid: long report nobody acts on, and clever redesign where real answer was deleting three files.

## Look at code that changes

Maintenance budget follows change, not size. Sprawling module nobody touches isn't problem worth fixing today.

If user named area, use it. Otherwise read recent history, find files that keep coming up:

```sh
git log --oneline -60
git log --format= --name-only -60 | sort | uniq -c | sort -rn | head -30
```

Those are hot spots. Start there. If history scattered with no pattern, say so and widen scan.

Read `.workflow/glossary.md` and specs for area first: project already has names for things, some of what looks wrong may be recorded decision.

## What to hunt

**Duplication** — same logic written twice. Second copy is where bug will hide. Report shared shape and where it should live. Watch for same *rule* expressed differently, matters more than identical lines.

**Dead weight** — unused exports, flags nobody sets, config for value that never changes, interface with one implementation, factory for one product, wrapper that only delegates, compatibility path for caller no longer exists. Grep for callers before reporting; dead code that's actually live is bad report.

**Hand-rolled basics** — something language's standard library ships (say which function), or platform already does (`<input type="date">` instead of date-picker dependency, CSS rule instead of JS, database constraint instead of application checks). Name replacement.

**Unneeded dependencies** — package pulled in for one format call, one parse, one small utility. Name standard-library or native replacement.

**Modules that leak** — data structures passed around in raw form so every caller knows internals; function whose arguments expose what it does internally; two modules reaching into each other. Say what boundary should be instead.

**Modules that are just plumbing** — layer that only forwards calls, module whose interface is as complicated as its body. Ask: if I deleted it, would complexity concentrate somewhere better, or just move? "Just move" means leave alone.

**Logic that can't be tested where it sits** — real behavior inside functions needing database, network, or UI to run at all. Say what would let it be checked.

For each candidate, sentence one is concrete symptom: file, name, what it does wrong. Not "module not cohesive".

## Rank by what it costs to leave alone

Biggest pain first, where pain = how often touched, how many changes it forces, how hard to understand first time. Ugly file nobody edits ranks below tidy file every feature must modify.

Three labels: **Fix now**, **Worth doing**, **Only if it grows**.

## Report format

Markdown, in conversation or written to file if long. No HTML, no diagrams for own sake; short before/after sketch fine where structure is point.

```markdown
# Architecture review: <area> (<date>)

## Where time goes
<two or three lines: which files/modules recent changes keep landing in>

## Findings

### 1. <Concrete symptom> [Fix now]

**Where:** <files>
**What is wrong:** <specific problem with evidence: rule in three places; flag set nowhere; two modules import each other>
**What to do:** <the change, plain terms>
**What it buys:** <what gets easier: fewer places to edit, test that can exist, dependency that goes away>
**Cost:** <what change itself risks, how big it is>

### 2. ...

## What I would not touch
<candidates that look bad but not worth it, one line each with reason. This
matters: stops next audit re-proposing them.>
```

End with two lines: count of findings and one you'd do first.

## Rules

- **Count deletion** — for anything you propose removing, state change in size: `-N lines, -M dependencies`. Proposal that doesn't shrink code or make specific change easier is preference, not finding.
- **Never propose rewrite** — proposals must be doable in few tasks, or broken into ones that are.
- **Respect recorded decisions** — finding contradicting spec or logged decision gets raised only when code has since made that decision actively painful, say so explicitly: "contradicts decision in <spec>, but costs us X every time we touch this".
- **Correctness bugs found along way** go in one line under separate heading then dropped. This skill about structure; don't turn into bug hunt.
- **Stop when money on table** — five sharp findings beat twenty padded ones. If only two, report two and say area in good shape.

## After report

Nothing changed. User picks what to act on. Each finding they want becomes own effort: `flow-grill` to settle approach, then `flow-spec` and `flow-break`. Findings that pass as small tasks (CONVENTIONS §4) can just be fixed.

**Track unaddressed findings** in `.workflow/technical-debt.md`, one per finding, with flags so no prompt opens:

```sh
.workflow/bin/workflow debt add --title '<concrete symptom>' --location '<files>' \
  --priority fix-now|worth-doing|only-if-grows \
  --problem '<what is wrong>' --impact '<what it buys>' \
  --solution '<what to do>' --cost '<cost>'
```

Labels map to priorities: Fix now → `fix-now`, Worth doing → `worth-doing`, Only if it grows → `only-if-grows`. This stops future reviews re-discovering the same issues and keeps the reason something wasn't fixed.

Findings the user rejects: `.workflow/bin/workflow debt accept <id> --reason '<why>'`, so next review doesn't re-propose them.
