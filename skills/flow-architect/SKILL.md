---
name: flow-architect
description: >-
  Read a codebase and report where it resists change: duplicated logic, dead
  weight, abstractions nobody uses, modules whose insides leak out. Produces a
  ranked Markdown report of what to cut or reshape, and applies nothing. Use when
  the user says "audit the codebase", "what can we delete", "find the duplication",
  "this is getting hard to change", "clean this up", or as maintenance between
  features.
---

# Flow: Architect

Read `.workflow/CONVENTIONS.md` first (§3 writing), and `.workflow/STYLE.md`:
everything you report has to read like a person wrote it.

Find the code that makes the next change expensive, and say what to do about it.
Report only; change nothing.

Two failures to avoid. Producing a long report nobody acts on. And proposing a
clever redesign where the real answer was deleting three files.

## Look at the code that changes

Maintenance budget should follow change, not size. A sprawling module nobody
touches is not a problem worth fixing today.

If the user named an area, use it. Otherwise read the recent history and find the
files that keep coming up:

```
git log --oneline -60
git log --format= --name-only -60 | sort | uniq -c | sort -rn | head -30
```

Those are the hot spots. Start there. If history is scattered with no pattern,
say so and widen the scan.

Read `.workflow/glossary.md` and the specs for the area first: the project already
has names for things, and some of what looks wrong may be a recorded decision.

## What to hunt

**Duplication.** The same logic written twice, in two files or two places. The
second copy is where the bug will hide. Report the shared shape and where it
should live. Watch for the same *rule* expressed differently, which matters more
than identical lines.

**Dead weight.** Unused exports, flags nobody sets, config for a value that never
changes, an interface with one implementation, a factory for one product, a
wrapper that only delegates, a compatibility path for a caller that no longer
exists. Grep for the callers before reporting one; dead code that is actually
live is a bad report.

**Hand-rolled basics.** Something the language's standard library already ships
(say which function), or the platform already does (`<input type="date">` instead
of a date-picker dependency, a CSS rule instead of JS, a database constraint
instead of application checks). Name the replacement.

**Unneeded dependencies.** A package pulled in for one format call, one parse, one
small utility. Name the standard-library or native replacement.

**Modules that leak.** Data structures passed around in their raw form so every
caller knows the internals; a function whose arguments expose what it does
internally; two modules reaching into each other. Say what the boundary should be
instead.

**Modules that are just plumbing.** A layer that only forwards calls, a module
whose interface is as complicated as its body. For these, ask: if I deleted it,
would the complexity concentrate somewhere better, or just move? "Just move" means
leave it alone.

**Logic that cannot be tested where it sits.** Real behaviour sitting inside
functions that need a database, a network, or a UI to run at all. Say what would
let it be checked.

For each candidate, sentence one is the concrete symptom: the file, the name, what
it does wrong. Not "this module is not cohesive".

## Rank by what it costs to leave alone

Biggest pain first, where pain means: how often this is touched, how many changes
it forces, how hard it is to understand the first time. An ugly file nobody edits
ranks below a tidy file that every feature has to modify.

Use three labels: **Fix now**, **Worth doing**, **Only if it grows**.

## Report format

Markdown, in the conversation or written to a file if it is long. No HTML, no
diagrams for their own sake; a short before/after sketch is fine where structure
is the point.

```markdown
# Architecture review: <area> (<date>)

## Where the time goes
<two or three lines: which files and modules the recent changes keep landing in>

## Findings

### 1. <Concrete symptom> [Fix now]

**Where:** <files>
**What is wrong:** <the specific problem, with the evidence: this rule appears in
three places; this flag is set nowhere; these two modules import each other>
**What to do:** <the change, in plain terms>
**What it buys:** <what gets easier afterwards: fewer places to edit, a test that
can exist, a dependency that goes away>
**Cost:** <what the change itself risks, and how big it is>

### 2. ...

## What I would not touch
<candidates that look bad but are not worth it, one line each with the reason.
This section matters: it stops the next audit re-proposing them.>
```

End with two lines: the count of findings and the one you would do first.

## Rules

- **Count the deletion.** For anything you propose removing, state the change in
  size: `-N lines, -M dependencies`. If a proposal does not shrink the code or
  make a specific change easier, it is a preference, not a finding.
- **Never propose a rewrite.** Proposals must be doable in a few tasks, or be
  broken into ones that are.
- **Respect the recorded decisions.** If a finding contradicts a spec or a logged
  decision, only raise it when the code has since made that decision actively
  painful, and say so explicitly: "this contradicts the decision in <spec>, but
  that decision costs us X every time we touch this".
- **Correctness bugs found along the way** are reported in one line under a
  separate heading and then dropped. This skill is about structure; do not turn it
  into a bug hunt.
- **Stop when the money is on the table.** Five sharp findings beat twenty padded
  ones. If there are only two, report two and say the area is in good shape.

## After the report

Nothing is changed. The user picks what to act on. Each finding they want to pursue
becomes its own effort: `flow-grill` to settle the approach, then `flow-spec` and
`flow-break` if it is bigger than one session. Small findings can just be fixed.

Offer to log the rejected ones in `.workflow/decisions.md`, so the next review
does not re-propose them.
