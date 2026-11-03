---
name: flow-map
description: >-
  Plan work too big to see all the way through, as a map of open questions across
  sessions. Use when a project is large or foggy, or the user says "I don't know how
  to approach this".
---

# Flow: Map

Use when the route depends on unanswered questions across sessions. Read CONVENTIONS
§0, §1, §2, §6 and STYLE.md. Check the repository before asking. If tasks are already
clear, skip the map: use `flow-spec` and `flow-break`; clear 1–3 task work without a
durable spec goes directly to `flow-break`.

## Map or spec

A map holds decisions still to make; a spec holds settled decisions. Work the map until
its route is clear, then graduate to one or more specs and tasks.

## Charting the map
Chart the destination and the questions that gate reaching it.
Maps move through `charting` → `working` → `clear` (CONVENTIONS §6).

### 1. Name the destination

State in one or two sentences what reaching the end means. If the destination itself is
unclear, use `flow-grill` first.

### 2. Find gating questions

Explore broadly for questions that block the route, not detailed answers. Write
`.workflow/maps/<slug>.md`:

```markdown
# Map: <destination in a few words>

**Destination:** <what reaching the end looks like>
**Started:** <date>   **Status:** charting | working | clear

## Route so far
<!-- One line per answer, newest last. -->

## Open questions
<!-- Answerable now, grouped by what they block. -->

## Not yet clear
<!-- In scope but hanging on unanswered dependencies. -->

## Ruled out
<!-- Beyond the destination, with a reason. -->
```

Give each question a section below the header:

```markdown
## Q<N>: <question, as a question>

**Blocks:** <what can't start until this is answered>
**Kind:** research | decide | build-a-bad-version | do-something-first
**Depends on:** <Q numbers, or none>
**Answer:** <filled in when answered>
```

The four kinds determine the next move:
- **research:** find the fact in docs, code, or an API, using a subagent when useful.
- **decide:** resolve the user-owned choice with `flow-grill`.
- **build-a-bad-version:** make the cheapest rough artifact that lets people react.
- **do-something-first:** create the prerequisite (access, account, moved data), then record what happened.

Put anything precise enough to state into Open questions, even if blocked. Keep fog coarse
in Not yet clear. Ruled-out work is outside the destination and never graduates. Add
dependencies after all questions exist, then commit the map and decision entries per CONVENTIONS §2.

## Working the map
Work open questions in dependency order, updating the map as facts settle.

### 1. Select a question

Read the header and route, choose the first open question or the one the user named, and
read its related sections.

### 2. Answer and update

Answer according to its kind. Record the basis and add a decision only when CONVENTIONS
§1.2 requires it. The first answer changes `charting` to `working` (CONVENTIONS §6). Add the result to
Route so far, promote newly sharp fog, and move out-of-destination work to Ruled out.

### 3. Commit and repeat

Commit the map and planning entries at session end. Answer independent questions together;
otherwise continue in dependency order until no open question or promotable fog remains.

## Finish

When the route is clear, set `Status: clear`, add a closing line describing its output,
write the resulting spec with `flow-spec`, and cut tasks with `flow-break`. Keep the map as
the record of why the route took its shape.
