---
name: flow-grill
description: >-
  Interview the user to pin down what to build before building it. Asks in
  batches instead of one at a time, decides the small things itself and logs
  them, and stops as soon as the next step is unblocked. Use at the start of any
  non-trivial feature, refactor, or design change; whenever the user says "grill
  me", "align on this", "let's nail the design", "I want to think this through";
  or when a plan is vague in a way that would change what gets built.
---

# Flow: Grill

Read `CONVENTIONS.md` next to this skill first (§1 decision protocol, §2 document
layout). It is the contract this skill implements.

Goal: by the end, you and the user agree on what to build and why, the small
choices are made and written down, and the next step is unblocked. Nothing more.

## What this is not

Not a requirements form. Not a checklist to run to the end. Not a reason to ask
about things you can decide or look up. A grilling that asks twelve questions has
usually failed; four questions and six logged decisions is a good session.

## Process

### 1. Read before you ask

Build a picture from the repository, the existing `.workflow/` docs, and the
user's message. Dispatch subagents for anything slow. Do not open with questions
that this step would have answered; the user's first experience of this skill
must not be a question they could have answered themselves.

### 2. Write the design tree down, privately

List the decisions this work depends on: what it is for, what it must not do,
where it plugs into existing code, what shape the data takes, how it gets
tested, what happens when it fails, what the user sees. Then mark each one:

- settled already by the user's message or the existing docs
- a fact you can look up
- a real open decision

Only the last group can become questions.

### 3. Triage every open decision

For each one, choose a bucket (CONVENTIONS §1.2):

- **Look it up** → do it now, do not ask.
- **Decide and log** → take your recommendation. Write it to
  `.workflow/decisions.md` immediately, with the option that lost and one line of
  why. Mention it to the user in one line at the end of the round.
- **Ask** → it changes what gets built, the trade-off is real, you cannot resolve
  it. At most three per round.

Be aggressive about the middle bucket. The default for a detail is "decide it
and say so", not "ask".

### 4. Ask the round

Ask every question you can ask right now without guessing another answer. Rank
by which unblocks the most downstream work. Format per CONVENTIONS §1.5:

```
Q1 - <short title>
   <question, two or three sentences>
   Options: <A> | <B> | <C>
   My pick: <A>, because <one line>
```

Then stop. Do not keep asking while waiting, do not start building, do not write
the spec.

### 5. Repeat only for questions the answers opened up

An answer often makes new questions askable and kills others. Recompute and ask
a second round if a genuinely blocking question remains. Two or three rounds is
normal. If a fourth round is coming, the work is too big: stop and say so, and
suggest `flow-map` (a plan built from decision tickets) or a smaller first slice.

### 6. Name things as you go

When you and the user land on a name for a concept, a module, or a state, write
it to `.workflow/glossary.md` before moving on: the term, one line of what it
means, and what not to call it. Do this at the moment of decision, not later.
A decision made and a word agreed are the same act; if the vocabulary drifts,
every document written after it drifts too.

If a term turns out to be two things wearing one name, say so and split it now.

### 7. Confirm, then stop

Restate every decision in one numbered list: what was decided, and for the
logged ones, that they were yours. The user corrects what they disagree with.
Then state the next step in one line and finish.

If the user says "enough" at any point, stop immediately: write the decisions
log, list what is still open in one line each, and hand back.

## Writing the decision log

Append to `.workflow/decisions.md`, newest last:

```markdown
## <date> - <one line: what was decided>

- **Decided:** <the choice>
- **Instead of:** <the runner-up, and why it lost>
- **Because:** <the constraint that forced it, not a feeling>
- **Mine:** yes | no (<who made the call>)
- **Revisit when:** <the observation that would invalidate this>
```

`Rather than` is the field that earns its keep: a decision recorded without the
option it beat is a decision someone will reopen next session.

## When to reach for something else

- The work is too big for one session and you cannot see the route yet → `flow-map`.
- The user already knows exactly what they want and just needs it written down → `flow-spec`.
- The user wants the codebase looked at rather than an idea → `flow-architect`.
