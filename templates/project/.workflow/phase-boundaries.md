# Phase Boundaries

A **phase** is a chunk of work inside a session: the grilling, the spec writing,
the implementation, the review. At the **boundary** between phases you have
several options for managing context and continuity.

This guide helps choose between continuing, clearing, compacting, switching
sessions, or delegating to subagents.

---

## The options

**Continue** — stay in the current session, keep all context.  
**Clear context** — empty the window when nothing here matters to the next phase.  
**Compact** — compress this context and seed a fresh session with it.  
**Switch session** — start a fresh session in a new directory or harness.  
**Subagent** — delegate a tightly-scoped task to its own window, get a report back.

---

## Decision tree

Work through these questions in order. Stop at the first match.

### 1. Does the next phase need anything from this one?

**No** → **Clear context**.

Examples:
- After archiving and landing a task, starting the next unrelated task
- After `flow-architect` report is read, starting new feature work
- After finishing research that produced a document

The document or committed code is the handoff. Context is disposable.

**Yes** → Continue to question 2.

### 2. Does the next phase happen in a different directory or harness?

**Yes** → **Switch session**.

Examples:
- Prototyping in a separate directory
- Handing work to a colleague
- Moving from planning session to implementation in different tool

Create a handoff document if the receiving session needs setup context beyond the
committed files.

**No** → Continue to question 3.

### 3. Is the next work tightly scoped and independent?

**Yes** → **Subagent**.

Examples:
- Research a library or API during planning
- Check impact of a proposed change
- Investigate a bug while implementing a feature

Spawn the subagent and continue working. Retrieve results when ready.

**No** → Continue to question 4.

### 4. Is the context window getting full, or is reasoning degrading?

The **smart zone** is the part of the window in which the model reasons sharply.
Beyond it, reasoning degrades: missed details, repeated questions, weaker
decisions. Where it ends depends on the model and harness, so don't trust a fixed
token number. Use two signals:

- **Fill level**, if the harness shows it: past roughly half of the window with
  more phases still to run.
- **Observable degradation**: repeating a question already answered, missing a
  decision recorded earlier, re-reading files already read.

**Yes** to either → **Compact** at the nearest phase boundary.

Examples:
- After `flow-grill` but before `flow-spec`, if grilling ran long
- After `flow-spec` but before `flow-break`, if spec is complex
- After several task implementations, before starting the next

Compact captures decisions, specs, task states, and glossary, then starts fresh.

**No** → Continue to question 5.

### 5. Default: Continue

Stay in the current session. Costs nothing, loses nothing.

Most phase transitions are Continue: grilling → spec → break → implement for
a feature that fits in one context window.

---

## When NOT to compact

**Don't compact prematurely.** Compaction loses some nuance and context. Compact
on a signal from question 4, not on habit.

Bad compaction triggers:
- After every phase (too frequent, loses continuity)
- "Just to be safe" with no fill-level or degradation signal
- When the next phase is small (implementing one task after grilling)

Good compaction triggers:
- Grilling + spec + break filled much of the window and multiple tasks remain
- Long back-and-forth left fragmented context, decision thread is hard to follow
- Context degradation is observable (repeated questions, missed prior decisions)

---

## Phase boundary checklist

Before crossing a phase boundary:

**Completed phase:**
- [ ] Deliverable written (spec, tasks, code, report)
- [ ] Decisions logged to `.workflow/decisions.md`
- [ ] Glossary updated if new terms were agreed
- [ ] Documents that changed are committed (if applicable)

**Leaving a task unfinished** (clearing, compacting or switching mid-task):
- [ ] `## Progress` in the task file holds the handoff CONVENTIONS §6 describes
- [ ] `Status: paused` set
- [ ] Uncommitted work is where `## Progress` says it is

**Next phase:**
- [ ] Input is clear (what file to read, what task to build)
- [ ] No unresolved blockers
- [ ] Decision made: continue / clear / compact / switch / subagent

## Examples

**Small feature, one session:**
```
flow-grill → Continue
flow-spec → Continue
flow-break (produces 2 tasks) → Continue
flow-implement task 1 → Continue
flow-implement task 2 → Done
```
Continue throughout. The window never got full, and all phases benefit from shared understanding. Task 2 starts after task 1 is archived and landed: one task at a time, in sequence, not interleaved.

**Large feature, long planning:**
```
flow-grill (many rounds) → Continue
flow-spec → Continue
flow-break (produces 8 tasks) → Clear: planning now lives in spec and task files
```
Grill, spec and break stay together (rule 1 below). After that, each task starts fresh from its task file (rule 2); nothing from the planning conversation is needed.

**Parallel research:**
```
flow-grill (round 2, 15k)
  → Need: "Does library X support feature Y?"
  → Subagent: research library X
  → Continue: keep grilling while subagent works
```
Subagent for research. Main session continues, retrieves results when needed.

---

## Context hygiene rules

1. **Keep phases 1-3 unbroken** (`flow-grill` → `flow-spec` → `flow-break`) so grilling, spec, task breakdown build on same thinking.

2. **One task at a time.** A task starts after the previous one is archived, paused or blocked, never interleaved with it. The next task may start in the same session while question 4 says the window is fine; otherwise clear first. Each task only needs its task file and the spec, so clearing costs nothing.

3. **Compact at phase boundaries, never mid-phase.** If context pressure builds during phase, finish phase first or delegate remaining work to subagent.

4. **Observable degradation beats theoretical limits.** If model repeating questions or missing recent decisions, compact even if token count seems fine.

5. **When in doubt, Continue.** Premature compaction more expensive than late compaction for most workflows.

---

## Integration with workflow

**`flow-start`** performs implicit context loading, so fresh session after clearing or compacting picks up project state from documents.

**`flow-grill` and `flow-spec`** should stay in same context when possible (spec benefits from grilling discussion).

**`flow-implement`** can start fresh per task, using task file and spec as input rather than relying on conversation history. A task left unfinished at a boundary is paused with its handoff written, so the next session doesn't need this one.

**`flow-close`** reads only committed files (spec, archived tasks, decisions), so it can run fresh after the last task lands.

**Subagents** appropriate during any phase for independent lookups: during `flow-grill` for research, during `flow-implement` for impact analysis, during `flow-architect` for deep investigation.
