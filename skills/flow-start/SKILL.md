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
3. `.workflow/decisions.md` — choices made with option they beat. It is append-only and grows without bound: read the recent entries (`workflow decisions recent 10 --no-color`) plus whatever matches the area you expect to touch (`workflow decisions search <term>`, `workflow decisions --effort <slug>`), not the whole file, unless it is short.

If any missing, note for report but continue. Project without decisions or glossary is new, not broken.

Check workflow state:
```bash
workflow next --no-color     # ready tasks, ranked by effort priority
workflow tasks --no-color    # every active task, with blockers and Status
```

If the `workflow` command isn't on PATH, list `.workflow/tasks/*.md` and read their `Effort`, `Blocked by` and `Status` fields yourself. A task with `Status: paused` is interrupted work: offer to resume it before starting anything new. A task with `Task type: spike` delivers an answer, not code.

If this session will cross several phases, or the context is already heavy, `.workflow/phase-boundaries.md` decides at each boundary whether to continue, clear, compact, switch sessions, or hand a piece to a subagent.

## 2. Classify request

Sort user's message into exactly one category:

**Trivial** — question with factual answer, clarification about workflow itself, or greeting. No code changes, no decisions.

**Hotfix** — production outage or critical bug. Must meet ALL criteria:
- System is degraded or down affecting users now
- Fix is localized and well-understood
- Risk of delay exceeds risk of skipping process

If any criterion fails (not affecting users, fix unclear, can wait hours), classify as small or complex instead.

**Small task** — well-scoped work fitting these bounds:
- Single behavior change or bug fix
- Impact radius: affects <3 modules' behavior (not file count)
- Requirements clear from message
- No architectural decisions
- Rollback cost: can revert in <5 minutes if wrong
When uncertain between small and complex, treat as complex.

## 3. Route

### Trivial → answer directly
Respond to question or clarify workflow. Don't invoke another skill.

### Hotfix → immediate fix with mandatory follow-up
State what you understood as the outage/critical bug. Fix immediately without
grilling or spec. Verify where the failure was observed; if you can't reach
production, say so and hand that check to the user.

**Mandatory before the session ends:** write decision entry to `.workflow/decisions.md`:
- **Decided:** `Hotfix:` followed by the temporary fix applied
- **Instead of:** proper solution (or "unclear, needs investigation")
- **Because:** why immediate fix was necessary and why shortcuts were justified
- **Mine:** yes
- **Revisit when:** timeline for proper fix or follow-up investigation

`workflow hotfix-review` lists entries whose `Decided` says hotfix, temporary or
workaround. When the proper fix lands, run
`workflow hotfix-review --mark-resolved <id>` in the same commit.

If you cannot honestly write this entry (fix wasn't localized, risk wasn't that
high, could have waited), it wasn't a hotfix. Stop and reclassify.

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

Use `workflow next` output and existing artifacts (`.workflow/specs/`, `.workflow/maps/`, `.workflow/tasks/`) to determine starting point. Name tasks as `<effort>/<NN>`.

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
