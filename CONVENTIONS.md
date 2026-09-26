# Workflow Conventions

Shared ground rules for the `flow-*` skills. Every skill in this repo assumes the
decision protocol in §1 and the document layout in §2. Read this once per session
before invoking any `flow-*` skill; the skills themselves do not repeat it.

This file is not installed as a skill. It lives beside the skills as the single
source of truth, and a project points at it from its `.workflow/standards.md`.

---

## 1. Decision protocol

Every conversation in this workflow has one job: turn the user's time into
decisions, and turn everything else into facts the model looked up itself.

### 1.1 Facts are never the user's job

If a question can be answered from the repository, the issue tracker, the docs,
or a quick search, find it yourself. Dispatch a subagent for slow lookups and
keep working while it runs. Only a decision the user owns may interrupt them.

Ask yourself first: *could I find this out without asking?* If yes, it is not a
question, it is a task.

### 1.2 Triage every question before it reaches the user

Sort each open question into exactly one of three buckets.

**Bucket A - look it up.** The answer exists somewhere. Facts, existing
conventions, prior decisions, what the API actually does.

**Bucket B - decide it yourself, log it.** You can name the clearly better
option, or the question is a detail with no real stakes: naming, formatting,
minor API shape, which helper to reuse, small irreversible-enough choices. Take
the option you would recommend, write it to the session's decision log, and move
on. The user sees it in the log and can overturn any entry at any time.

The test for "clearly better" is honest: if a competent engineer would not push
back, it is Bucket B. If you genuinely see two defensible options with different
consequences, it is Bucket C. When you are unsure which bucket, prefer B and log
it loudly rather than spending the user's attention.

**Bucket C - ask the user.** Only questions where all of these hold: the answer
changes what gets built, the trade-off is real, and you cannot resolve it from
the material in front of you.

Never send a question to the user when:

- it has a good default and a reversible outcome
- one option is better and you can say why in one line
- it is a detail of *how* to implement something already decided
- it could be answered by reading a file that exists

### 1.3 Ask Bucket C in rounds, not one at a time

Never drip questions. One message, all questions in it.

A **round** is every question you can ask right now without inventing an answer
to another open question. Ask the whole round in one message, then stop and wait.

Hard cap: **at most three questions per round.** If more than three are ready,
the extra ones are almost always Bucket B. Decide those, log them, and say so in
one line each. When a fourth genuinely must be asked, split it into a second
round rather than inflating this one.

If an explanation can run for more than one screen, the real question is smaller
than it looks. Ask the one branch point, not the whole tree.

### 1.4 Rank by what blocks progress

Put the question that unblocks the most downstream work first. A question with
no effect on the next step does not belong in this round even if it is on the
frontier; it belongs in the round after the answer that would change it.

### 1.5 Every question carries your recommendation

```
Q1 - <short title>
   <the question, two or three sentences at most>
   Options: <A> | <B> | <C>
   My pick: <one of them>, because <one line>
```

The user can answer "1A, 2B, 3 as you said" in one line. If they answer "you
decide" for anything, that is final: log it and never raise it again.

### 1.6 Close with a confirmation, not a feeling

Before writing any document or touching code, restate every decision from the
round as a short numbered list. The user corrects anything they disagree with.
Silence is not agreement; an unseen correction is not a correction.

### 1.7 Too many open decisions is a size signal

If more than five decisions are still open after a round, the work is too big
for one go. Split it: write a spec for part of it, or escalate to `flow-map`.
Do not push through with a longer list of questions.

### 1.8 Stop when the next step is unblocked

Grilling has no finish line of its own. Stop when no open decision would change
what the next step does. Remaining questions become tasks, spec material, or
open questions recorded in the document, not extra rounds.

---

## 2. Document layout

One root per project: `.workflow/`. Create it lazily; only the parts you use.

```
.workflow/
  standards.md          entry point: how this project is worked on
  glossary.md           what things are called and what the words mean
  specs/<slug>.md       what is being built and why
  tasks/<slug>/         one task: what to build, what to read, how to know it is done
  decisions.md          the log: every choice made, with the runner-up
```

Rules:

- **`standards.md` is the entry point.** A new session reads it first. It names
  the language, the test command, the review axes, and where everything lives.
  Keep it under one screen.
- **The glossary is the vocabulary source.** If a concept gets a name in a spec
  or task, it belongs here. One line per term, plus what not to call it.
- **One spec per effort, updated in place.** When code changes a fact in a spec
  (a path, a default, an interface shape), update the spec in the same change.
  Do not append history to it.
- **When a decision reverses, the spec gets rewritten, not annotated.** Note the
  reversal in `decisions.md` with a link, and fix the spec so it reads as if the
  new decision had always been the one. A spec carrying two contradicting
  answers is worse than no spec.
- **Task folders are deleted when merged.** Their lasting value, if any, moves
  into the spec or the glossary. A finished task folder is archaeology.
- **`decisions.md` is append-only.** One entry per Bucket B and Bucket C
  decision: what was decided, what lost, one line of why. This is what stops the
  same argument from being had again next session.

If a project already has a real issue tracker in use, the tracker wins for
specs and tasks; `.workflow/` keeps `standards.md`, `glossary.md` and
`decisions.md` only. Do not maintain both.

---

## 3. Writing

Everything in this repo is read by a model and by a person who is tired. Both
want the same thing: short sentences that say what is true.

**Say the thing.** No preamble, no restating the request, no conclusion
paragraph that summarizes what was just written. If a section has one fact in
it, that section is a sentence.

**Define a term or drop it.** Jargon is allowed only when it is doing work. The
first use of a term that is not obvious gets one clause of explanation, or an
entry in `glossary.md`. Do not stack three abstractions in a sentence to sound
precise; that hides a missing decision.

**Banned, unless a file in the repo actually has that name:** leverage, synergy,
seam (say "the place where X talks to Y"), deepening, tracer bullet (say "a
slice that works end to end"), blast radius, vertical slice, smart zone, first
class citizen, single source of truth, dogfood, sane, robust, powerful, and any
phrase that would survive being cut without losing information.

**Prefer the concrete noun.** "The order intake module" beats "the domain
boundary responsible for order ingestion". If you cannot name the file, the
thing, or the command, you do not understand it well enough to write it down.

**Length is a symptom.** A document nobody reads is not documentation. If a
spec section runs long, the design is unclear, so fix the design instead of
writing more words about it.

---

## 4. The loop

```
flow-grill      align on what to do, and why        → .workflow/decisions.md
flow-map        plan work too big for one session   → .workflow/specs/ + tasks
flow-spec       write down what is being built      → .workflow/specs/<slug>.md
flow-break      cut it into tasks a session can hold→ .workflow/tasks/<slug>/
flow-verify     check the work against all of it    → report
flow-architect  find the code that resists change   → report
```

Any skill can be skipped. Small work goes `flow-grill` then straight to
implementation. Anything that produces a document is finished by confirming the
document with the user, not by announcing that it was written.
