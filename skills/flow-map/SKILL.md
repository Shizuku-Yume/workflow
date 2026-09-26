---
name: flow-map
description: >-
  Plan work that is too big to see the whole way through: chart it as a map of
  open questions, answer them one at a time, and let the route to the destination
  become clear. Use when a project is large or foggy, when the user says "I do not
  know how to approach this", "this is too big", "help me plan this out", "where
  do we even start", or when grilling keeps producing questions that cannot be
  answered yet.
---

# Flow: Map

Read `.workflow/CONVENTIONS.md` first (§1 decision protocol, §2 where things
live), and `.workflow/STYLE.md`.

For work where the route is not visible. Not "the plan is long", but "we cannot
write the plan yet, because it depends on things we have not worked out".

The output is a map: one document listing the questions that gate the work, each
answered in its own session, with the answers accumulating until the way is clear.
Fog is expected. Do not try to clear it by guessing.

## When this applies

Use it when:

- The work spans more than one session and its shape depends on answers nobody has.
- Grilling keeps stopping because questions depend on other unanswered questions.
- The user can describe the goal but not the first step.

Do not use it when the route is already visible. If you can list the tasks, that
is `flow-spec` plus `flow-break`, not this. A map for clear work is ceremony.

## Map or spec

A **map** holds questions whose answers are decisions. It is done when nothing is
left to decide and everything is ready to build.

A **spec** holds decisions already made, describing what will be built. A map
graduates into one or more specs; it does not replace them.

A map is finished when it has nothing left in it. That is the goal: the map should
end up empty of open work because it all moved into specs and task lists.

## Charting the map

### 1. Name the destination

What does the end of this effort look like? A shipped feature, a decision locked,
a migration done, a document written. One or two sentences. Everything else
depends on this: it decides what is in scope, and a wrong destination makes every
ticket on the map wrong.

If the destination is unclear, settle it first with `flow-grill`. It is the one
question you cannot defer.

### 2. Fan out and find the questions

Grill the user, but **wide rather than deep**: across the whole space, not down
one thread. You are looking for the questions that gate everything else, not the
answers to them.

If this produces no fog, stop. The route is visible; use `flow-spec` and
`flow-break` instead, and say so.

### 3. Write the map

`.workflow/maps/<slug>.md`:

```markdown
# Map: <destination in a few words>

**Destination:** <what reaching the end looks like>

**Started:** <date>   **Status:** charting | working | clear

## Route so far

<!-- one line per answered question, newest last. The detail lives in the
question's own section below; this is the index. -->

## Open questions

<!-- the questions that can be answered now: everything they depend on is settled.
Grouped by what they block. -->

## Not yet clear

<!-- questions you can tell are coming but cannot phrase sharply yet: they hang on
answers we do not have. Write them loosely. This is the fog. -->

## Ruled out

<!-- things beyond the destination: named, out of this effort, with the reason.
They never graduate. -->
```

The map is an index, not a store. Each answered question's detail lives in its own
section; the Route-so-far list just points at it. A map that restates its own
answers twice will drift.

### 4. Write the open questions as concrete questions

Each one gets its own section below the header blocks:

```markdown
## Q<N>: <the question, as a question>

**Blocks:** <what cannot start until this is answered>

**Kind:** research | decide | build-a-bad-version | do-something-first

**Depends on:** <Q numbers, or none>

**Answer:** <filled in when answered>
```

Four kinds, and they are not decoration:

- **research** - the answer is a fact someone can find: read the docs, check the
  third-party API, look at what the library actually does. Answer it with a
  subagent, in parallel, without the user.
- **decide** - a real choice between options. Answer it with `flow-grill`.
- **build-a-bad-version** - the question is "how should this look or behave",
  and talking cannot answer it. Make the cheapest rough thing that can be reacted
  to: a stub, a sketch, a throwaway page. Keep it, or throw it away after.
- **do-something-first** - nothing to decide, but the discussion is blocked until
  it exists: sign up for the API so its behaviour can be judged, move the data so
  its shape can be seen, get the access. This is the one kind that does work. Its
  answer records what was done and the facts that came out of it.

### 5. Wire the dependencies

Write each question's `Depends on` after all of them exist, so the numbers are
real. A question whose dependencies are all answered is **open**. Everything else
is blocked or still fog.

## Where the lines go

**Question or fog?** The test is whether you can phrase it sharply now, not
whether you can answer it now.

- **A question** when you can state it precisely, even if it is blocked.
- **Fog** when you cannot yet phrase it that sharply. Do not chop fog into
  question-sized pieces; it is coarser than a question, and one patch may turn
  into three questions later, or none.

**Fog or ruled out?** Fog gathers toward the destination and is in scope but
unclear. Ruled out is beyond the destination. Scope puts something in "Ruled out";
sharpness puts it in "Not yet clear". Work in "Ruled out" never graduates; if the
destination changes, it comes back as a new effort, not a resumed one.

## Working the map

One question per session. Not two: the point of the map is that each answer gets
a clean context.

1. Read the map header and Route so far. Not every question section.
2. Pick the next open question: the first one whose dependencies are all answered.
   If the user named one, use theirs.
3. Answer it, in the way its kind says. Read any related question sections you need.
4. Write the answer into that question's section: the decision, the option it beat,
   and what it was based on. If it was a real decision, add one line to
   `.workflow/decisions.md`.
5. Update the map: add the answer to Route so far, answer any question it just
   unblocked, and promote whatever fog is now sharp enough to phrase. Remove
   promoted fog from "Not yet clear" so it lives in exactly one place.
6. If the answer shows something is beyond the destination, move it to "Ruled out"
   with the reason, rather than resolving it on the route.

## Finishing

When no open questions remain and no fog can be promoted, the route is clear. Write
the specs the map now implies (`flow-spec`), cut them into tasks (`flow-break`), and
mark the map `Status: clear` with a closing line saying what it produced.

Keep the map. It is the record of why the plan looks the way it does, which is
exactly what someone will ask in three months.
