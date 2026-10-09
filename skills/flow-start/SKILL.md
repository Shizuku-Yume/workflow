---
name: flow-start
description: >-
  Load project context and classify request. Routes trivial questions, small tasks,
  complex work to right path. Use at session start or when resuming work.
---

# Flow: Start

Initialize workflow session and route request to appropriate step. Runs once per session, or when context lost and needs reloading.

## 1. Load project context

Read these files silently:
1. `.workflow/standards.md` — commands, layout, project conventions
2. `.workflow/glossary.md` — vocabulary and avoided terms
3. `.workflow/decisions.md` — choices made with option they beat. It is append-only and grows without bound: read the recent entries (`.workflow/bin/workflow decisions recent 10 --no-color`) plus whatever matches the area you expect to touch (`.workflow/bin/workflow decisions search <term>`, `.workflow/bin/workflow decisions --effort <slug>`), not the whole file, unless it is short.

If any missing, note for report but continue. Project without decisions or glossary is new, not broken.

Check workflow state:
```bash
.workflow/bin/workflow next --no-color     # ready tasks, ranked by effort priority
.workflow/bin/workflow tasks --no-color    # every active task, with blockers and Status
```

If `.workflow/bin/workflow` is missing (a project installed before 2.3 that hasn't run `workflow update`), list `.workflow/tasks/**/*.md` and read their `Effort`, `Blocked by` and `Status` fields yourself. A task with `Status: paused` is interrupted work: offer to resume it before starting anything new. A task with `Task type: spike` delivers an answer, not code.

If this session will cross several phases, or the context is already heavy, `.workflow/phase-boundaries.md` decides at each boundary whether to continue, clear, compact, switch sessions, or hand a piece to a subagent.

## 2. Classify request

Sort the user's message into exactly one class from CONVENTIONS §4: trivial, hotfix, small, or complex. The criteria live there and only there; read them rather than working from memory. Every hotfix criterion must hold, or it isn't one. When uncertain between small and complex, it's complex.

## 3. Route

### Trivial → answer directly
Respond to question or clarify workflow. Don't invoke another skill.

### Hotfix → immediate fix with mandatory follow-up
State what you understood as the outage/critical bug. Fix immediately without
grilling or spec. Verify where the failure was observed; if you can't reach
production, say so and hand that check to the user.

Before the session ends, write the hotfix decision entry CONVENTIONS §4 specifies
(`Decided` starts with `Hotfix:`). If you cannot honestly write it, it wasn't a
hotfix: stop and reclassify.

### Small task → fast path
Small tasks skip grilling and spec writing. Route depends on whether needs decisions:

- **No decisions needed** (clear requirement, obvious implementation): go straight to building. Mention what you understood and proceed.
- **One or two decisions** (implementation choice, edge case handling): ask in one message with your recommendation per CONVENTIONS §1.3, wait for answer, then build. Log decision to `decisions.md` if has real trade-offs.
- **Three or more decisions**: not actually small. Reclassify as complex and route to `flow-grill`.

Small tasks still require:
- Reading code that will be touched
- Running tests before and after
- One-line proof that it works (run thing, not just tests)
- Commit message stating what changed

Small tasks skip:
- `flow-grill` (unless reclassified)
- `flow-spec` and `flow-break`
- `flow-verify` (but still run tests and prove it works)

### Complex work → full workflow

Route to earliest incomplete step:

| Situation | Route to |
| --- | --- |
| Unclear requirements, design questions, or "grill me" | `flow-grill` |
| Too big or foggy; questions depend on other questions | `flow-map` |
| Decisions settled, just needs writing down | `flow-spec` |
| Spec exists, needs task breakdown | `flow-break` |
| Task file ready to build | `flow-implement` |
| Finished work needs review | `flow-verify` |
| Code is expensive to change | `flow-architect` |

Use `.workflow/bin/workflow next` output and existing artifacts (`.workflow/specs/`, `.workflow/maps/`, `.workflow/tasks/`) to determine starting point. Name tasks as `<effort>/<NN>`.

## 4. Report and proceed

State in three lines:
1. What context was loaded (or missing)
2. Classification (trivial/small/complex) and why
3. Next action

Then proceed directly to that action in same turn. Don't stop after reporting unless classification ambiguous and genuinely needs user's input.

## When to skip this skill

Skip `flow-start` when:
- Already mid-session with loaded context
- User directly invokes specific flow skill by name
- Resuming interrupted flow where context still present

Use it when:
- Starting fresh session
- Context was compacted or lost
- User asks "where should I start" or "what's next"
- You're uncertain which skill applies

## Rules

- **Never ask whether to classify.** Make classification based on message content and project state.
- **Never stop after reporting classification.** Route and proceed in same turn unless genuine decision blocks progress.
- **Reclassify freely.** If "small" task reveals more decisions during building, stop and upgrade to `flow-grill`.
- **Fast path is for obvious.** When in doubt between small and complex, choose complex. Under-planning more expensive than over-planning for genuinely unclear work.
