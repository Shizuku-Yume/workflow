---
name: flow-map
description: >-
  Plan work too big to see all the way through, as a map of open questions
  answered one per session. Use when a project is large or foggy, or the user says "I don't know how to approach this".
---

# Flow: Map

Read `.workflow/CONVENTIONS.md` §1 (decision protocol) and §2 (file structure), and
`.workflow/STYLE.md`. Per CONVENTIONS §0, check the codebase before asking; many
questions that feel like decisions are facts waiting to be found.

Use this skill when the route isn't visible: the plan can't be written yet because
it depends on things nobody has worked out. Signs: the work spans sessions and its
shape depends on missing answers, grilling keeps stopping on questions that hang on
other open questions, or the user can name the goal but not the first step. If you
can already list the tasks, use `flow-spec` and `flow-break`; a map for clear work
is ceremony.

The output is a map of the questions that gate the work. Answer one per session and
let the answers accumulate until the way is clear. Expect fog, and clear it with
answers, not guesses.

## Map or spec

A **map** holds questions whose answers are decisions. A **spec** holds decisions
already made: what will be built. A map graduates into one or more specs rather than
replacing them, and it is finished when nothing is left in it.

## Charting the map

### 1. Name the destination

Say in one or two sentences what the end looks like: a shipped feature, a locked
decision, a finished migration, a written document. The destination sets the scope,
so a wrong one makes every question wrong. If it is unclear, settle it with
`flow-grill`; it is the one question you can't defer.

### 2. Fan out and find questions

Grill the user **wide rather than deep**: across the whole space, looking for the
questions that gate everything else rather than for answers. If no fog appears, the
route is visible: say so and use `flow-spec` and `flow-break`.

### 3. Write the map

Write `.workflow/maps/<slug>.md`:

```markdown
# Map: <destination in a few words>

**Destination:** <what reaching the end looks like>
**Started:** <date>   **Status:** charting | working | clear

## Route so far
<!-- One line per answered question, newest last. Detail lives in the question's
section below; this is the index. -->

## Open questions
<!-- Answerable now: everything they depend on is settled. Group them by what
they block. -->

## Not yet clear
<!-- Coming, but not sharp enough to phrase yet: they hang on answers we don't
have. Write loosely. This is fog. -->

## Ruled out
<!-- Beyond the destination: named, out of this effort, with a reason. These
never graduate. -->
```

Give each open question its own section below the header blocks:

```markdown
## Q<N>: <question, as a question>

**Blocks:** <what can't start until this is answered>
**Kind:** research | decide | build-a-bad-version | do-something-first
**Depends on:** <Q numbers, or none>
**Answer:** <filled in when answered>
```

The map is an index, not a store. Each answer's detail lives in its question's
section, and Route so far only points at it. A map that states its answers twice
will drift.

Commit the new map (and any decision entries) when the charting session ends, per
CONVENTIONS §2.

### 4. Four kinds

Each kind says how to answer the question.

- **research**: a fact someone can find in docs, a third-party API or a library.
  Answer it with a subagent, in parallel, without the user.
- **decide**: a real choice between options. Answer it with `flow-grill`.
- **build-a-bad-version**: how something should look or behave, which talking can't
  settle. Make the cheapest rough thing to react to (a stub, a sketch, a throwaway
  page), then keep it or throw it away.
- **do-something-first**: nothing to decide, but discussion waits until something
  exists: an API account to judge behaviour, moved data to see its shape, access.
  Do the work; the answer records what was done and the facts that came out.

Fill in `Depends on` after all the questions exist, so the numbers are real. A
question whose dependencies are all answered is **open**; the rest are blocked or
still fog.

## Where lines go

**Question or fog?** The test is sharpness, not answerability. Anything you can
state precisely now is a question, even if it is blocked; anything you can't is fog.
Keep fog coarse: one patch may later become three questions, or none.

**Fog or ruled out?** Fog is toward the destination: in scope but unclear. Ruled-out
work lies beyond it. Scope decides "Ruled out"; sharpness decides "Not yet clear".
Ruled-out work never graduates. If the destination changes, it returns as a new
effort, not a resumed one.

## Working the map

Answer one question per session, so each answer gets a clean context.

1. Read the map header and Route so far, not every question section.
2. Pick the first open question, or the one the user named.
3. Answer it the way its kind says, reading any related question sections you need.
4. In the question's section, record the decision, the option it beat and what it
   was based on. For a real decision, add one complete entry to
   `.workflow/decisions.md`. The first answer moves the map from `Status: charting`
   to `Status: working` (CONVENTIONS §6).
5. Add the answer to Route so far, answer any question it just unblocked, and
   promote fog that is now sharp enough to phrase. Remove promoted fog from "Not yet
   clear" so it lives in one place.
6. Move anything the answer shows beyond the destination to "Ruled out" with a
   reason, instead of resolving it on the route.
7. Commit the map and any decision entries at the end of the session, per
   CONVENTIONS §2.

## Finishing

When no open questions remain and no fog can be promoted, the route is clear. Write
the specs it implies (`flow-spec`), cut them into tasks (`flow-break`), and mark the
map `Status: clear` with a closing line saying what it produced.

Keep the map. It records why the plan looks the way it does, which is exactly what
someone will ask in three months.
