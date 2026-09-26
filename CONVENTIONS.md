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

Cap: **six questions per round**, and eight only when every one of them genuinely
blocks the next step. Six is not a target to reach; two good questions beat six
padded ones. If more than six are ready, the extra ones are almost always Bucket
B. Decide those, log them, and mention each in one line. When a seventh genuinely
must be asked, do not inflate the round: split it into two rounds, or drop the
weakest question and log your own answer to it.

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

## 2. Where things live

Everything is inside the project, tracked by git. Nothing lives in a global
directory, so a teammate who clones the repository gets the same workflow.

```
AGENTS.md                        the short list of rules; holds the workflow block
.agents/skills/<name>/SKILL.md   the steps, one directory each
.omp/agents/<name>.md            the review agents (other harnesses read their own dir)
.workflow/
  CONVENTIONS.md                 this file: the full rulebook
  STYLE.md                       how everything you write should read
  standards.md                   this project: commands, layout, rules
  glossary.md                    what things are called
  decisions.md                   every choice made, with the runner-up
  specs/<slug>.md                what is being built and why
  tasks/<NN>-<slug>.md           one task: what to build, how to know it is done
  maps/<slug>.md                 the plan for work whose route is not visible yet
  done/<slug>.md                 finished and archived
```

`AGENTS.md` is read at the start of every session, so it stays short: rules the
agent must not miss, and a pointer to this file for everything else. This file is
read on demand. Depth belongs here; brevity belongs there.

Rules:

- **`standards.md` is this project's entry point.** A new session reads it first.
  It names the commands, the layout, the conventions, and what the project has
  ruled out. Keep it under one screen.
- **The glossary is the vocabulary source.** If a concept gets a name in a spec or
  a task, it belongs here. One line per term, plus what not to call it.
- **One spec per effort, updated in place.** When code changes a fact a spec
  states (a path, a default, an interface shape), update the spec in the same
  change. Do not append history to it.
- **When a decision reverses, the spec gets rewritten, not annotated.** Note the
  reversal in `decisions.md` with a link, and fix the spec so it reads as if the
  new decision had always been the one. A spec carrying two contradicting answers
  is worse than no spec, because it gets believed.
- **Finished tasks move to `done/`.** Their lasting value, if any, moves into the
  spec or the glossary first. A task file nobody will read again is archaeology.
- **`decisions.md` is append-only.** One entry per Bucket B and Bucket C
  decision: what was decided, what lost, one line of why. This is what stops the
  same argument being had again next session.

If a project already has a real issue tracker in use, the tracker wins for
specs and tasks; `.workflow/` keeps `standards.md`, `glossary.md` and
`decisions.md` only. Do not maintain both.

---

## 3. Writing

**`.workflow/STYLE.md` is the rulebook for everything you write**, in any
language: chat replies, documents, commit messages, code comments, and text a
user sees on screen. Read it and follow it. It covers sounding like a person
rather than a translation, not mixing languages inside one document, keeping
developer vocabulary out of user-facing text, and how long an answer should be.

Three rules from it matter most inside workflow documents:

**Say the thing.** No preamble, no restating the request, no closing paragraph
that summarizes what was just written. If a section holds one fact, that section
is a sentence.

**Define a term or drop it.** A term that is not obvious gets one clause of
explanation, or an entry in `glossary.md`. Stacking three abstractions in one
sentence does not make it precise; it hides the decision that was never made.

**Name the concrete thing.** "The order intake module" beats "the domain
boundary responsible for order ingestion". If you cannot name the file, the
thing, or the command, you do not understand it well enough to write it down.

---

## 4. The loop

```
flow-grill      align on what to do, and why        → .workflow/decisions.md
flow-map        plan work too big for one session   → .workflow/maps/
flow-spec       write down what is being built      → .workflow/specs/<slug>.md
flow-break      cut it into tasks a session can hold→ .workflow/tasks/
flow-implement  build one task, then review it      → code, then .workflow/done/
flow-verify     review any change on three axes     → report
flow-architect  find the code that resists change   → report
```

Any skill can be skipped. Small work goes `flow-grill` then straight to
implementation. Anything that produces a document is finished by confirming the
document with the user, not by announcing that it was written.
