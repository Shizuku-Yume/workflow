---
name: flow-map
description: >-
  Plan work too big to see whole way through, as map of open questions answered
  one per session. Use when project large/foggy or user says "I don't know how to approach this".
---

# Flow: Map

Read `.workflow/CONVENTIONS.md` §1 (decision protocol) and §2 (where things live), and `.workflow/STYLE.md`.

Per CONVENTIONS §0: check codebase before asking. Many questions that feel like decisions are facts waiting to be discovered.

For work where route not visible. Not "plan is long", but "can't write plan yet, depends on things not worked out".

Output: map listing questions gating work, each answered in own session, answers accumulating until way is clear. Fog expected. Don't try to clear by guessing.

Use when work spans more than one session and shape depends on answers nobody has, when grilling keeps stopping on questions depending on other unanswered questions, or user can describe goal but not first step. Don't use when route already visible — if you can list tasks, that's `flow-spec` plus `flow-break`. Map for clear work is ceremony.

## Map or spec

**Map** holds questions whose answers are decisions. **Spec** holds decisions already made, describing what will be built. Map graduates into one or more specs; doesn't replace them, finished when nothing left in it.

## Charting map

### 1. Name destination

What does end of this effort look like? Shipped feature, decision locked, migration done, document written. One or two sentences. Everything depends on this: decides what's in scope. Wrong destination makes every question wrong. If destination unclear, settle with `flow-grill` — it's one question you can't defer.

### 2. Fan out and find questions

Grill user, but **wide rather than deep**: across whole space, not down one thread. Looking for questions gating everything else, not answers. If produces no fog, stop: route visible, use `flow-spec` and `flow-break`, say so.

### 3. Write map

`.workflow/maps/<slug>.md`:

```markdown
# Map: <destination in few words>

**Destination:** <what reaching end looks like>
**Started:** <date>   **Status:** charting | working | clear

## Route so far
<!-- one line per answered question, newest last. Detail lives in question's
section below; this is index. -->

## Open questions
<!-- questions that can be answered now: everything they depend on is settled.
Grouped by what they block. -->

## Not yet clear
<!-- questions coming but can't phrase sharply yet: hang on answers we don't
have. Write loosely. This is fog. -->

## Ruled out
<!-- things beyond destination: named, out of this effort, with reason. Never
graduate. -->
```

Each open question gets own section below header blocks:

```markdown
## Q<N>: <question, as question>

**Blocks:** <what can't start until this answered>
**Kind:** research | decide | build-a-bad-version | do-something-first
**Depends on:** <Q numbers, or none>
**Answer:** <filled in when answered>
```

Map is index, not store. Each answered question's detail lives in own section; Route-so-far list just points at it. Map restating own answers twice will drift.

### 4. Four kinds

Not decoration; each says how to answer it.

- **research** — answer is fact someone can find: read docs, check third-party API, look at what library does. Answer with subagent, in parallel, without user.
- **decide** — real choice between options. Answer with `flow-grill`.
- **build-a-bad-version** — question is "how should this look or behave", talking can't answer. Make cheapest rough thing that can be reacted to: stub, sketch, throwaway page. Keep or throw away after.
- **do-something-first** — nothing to decide, but discussion blocked until it exists: sign up for API so behavior can be judged, move data so shape can be seen, get access. Does work. Answer records what was done and facts that came out.

Write each question's `Depends on` after all exist, so numbers are real. Question whose dependencies all answered is **open**; everything else blocked or still fog.

## Where lines go

**Question or fog?** Test is whether you can phrase sharply now, not whether you can answer now. Question when you can state precisely, even if blocked. Fog when can't yet phrase sharply — don't chop fog into question-sized pieces; it's coarser, one patch may turn into three questions later, or none.

**Fog or ruled out?** Fog gathers toward destination, in scope but unclear. Ruled out beyond destination. Scope puts something in "Ruled out", sharpness in "Not yet clear". Work in "Ruled out" never graduates; if destination changes, comes back as new effort, not resumed one.

## Working map

One question per session. Not two: point of map is each answer gets clean context.

1. Read map header and Route so far. Not every question section.
2. Pick next open question: first one whose dependencies all answered. If user named one, use theirs.
3. Answer it, in way its kind says. Read any related question sections needed.
4. Write answer into question's section: decision, option it beat, what it was based on. If real decision, add one complete decision entry to `.workflow/decisions.md`. The first answered question moves the map from `Status: charting` to `Status: working` (CONVENTIONS §6).
5. Update map: add answer to Route so far, answer any question it just unblocked, promote whatever fog now sharp enough to phrase. Remove promoted fog from "Not yet clear" so lives in exactly one place.
6. If answer shows something beyond destination, move to "Ruled out" with reason, rather than resolving on route.

## Finishing

When no open questions remain and no fog can be promoted, route is clear. Write specs map now implies (`flow-spec`), cut into tasks (`flow-break`), mark map `Status: clear` with closing line saying what it produced.

Keep map. It's record of why plan looks way it does, exactly what someone will ask in three months.
