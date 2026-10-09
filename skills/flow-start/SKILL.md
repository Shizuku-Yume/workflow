---
name: flow-start
description: >-
  Load project context and classify request. Routes trivial questions, small tasks,
  complex work to right path. Use at session start or when resuming work.
---

# Flow: Start

Load the project's context, classify the request, and route it. Runs once per session, or when context was lost.

## 1. Load project context

Read silently:
1. `.workflow/standards.md` — commands, layout, project conventions
2. `.workflow/glossary.md` — vocabulary and avoided terms
3. `.workflow/decisions.md` — append-only, so read the newest entries at the end, plus `grep -n -i '<term>' .workflow/decisions.md` for the area you expect to touch, or `grep -n 'Effort:\*\* <slug>' .workflow/decisions.md` for one effort. An entry carrying `Superseded by` is history: follow the pointer.

A missing file goes in the report; a project without decisions or glossary is new, not broken.

**Brownfield.** If `standards.md` still contains `<...>` placeholders, fill what the repository answers: commands from package manifests, Makefile, CI and lint config; layout from the tree; `Landing:` from how the repo uses branches. Leave the rest marked. Show the user the filled file in one message, ask them to correct it, then continue with the request.

## 2. Check workflow state

- `.workflow/bin/workflow next --no-color` — ready tasks ranked by priority, plus paused and blocked ones. Read `.workflow/tasks/*/` files directly when you need more.
- `Status: paused` is interrupted work: offer to resume it (its `## Progress` says where it stopped) before starting anything new.
- `Status: blocked` is a plan waiting to be fixed (CONVENTIONS §5).
- Open `Task type: bugfix` tasks whose `Read first` names a hotfix entry are hotfixes still waiting for the proper fix.
- `grep -n 'Priority:\*\* fix-now' .workflow/technical-debt.md` — debt marked fix-now.

Hotfix follow-ups and fix-now debt don't pick the next task; they go in the report so they aren't forgotten.

If this session will cross several phases, or context is already heavy, follow `.workflow/phase-boundaries.md` at each boundary.

## 3. Classify request

Sort the message into exactly one class from CONVENTIONS §4 (trivial, hotfix, small, complex). Read the criteria there. Every hotfix criterion must hold; between small and complex, choose complex.

The class is provisional: before calling something small, read the callers of what it changes. The CONVENTIONS §4 tripwires upgrade it while building.

## 4. Route

### Trivial → answer directly
Answer or clarify. No other skill.

### Hotfix → fix now, follow-up before the session ends
State the outage you understood and fix it, with no grilling or spec. Verify where the failure was observed; if you can't reach production, say so and hand that check to the user. Before the session ends, write the hotfix decision entry and draft the follow-up bugfix task, both as CONVENTIONS §4 specifies. If you can't write the entry honestly, it wasn't a hotfix: reclassify.

### Small task → fast path
Run `git status --porcelain` first: paths already modified or untracked belong to someone else (CONVENTIONS §2). Then:

- **No decisions needed:** say what you understood and build.
- **One or two decisions:** ask in one message with your recommendation (CONVENTIONS §1), wait, then build. Log a decision with real trade-offs.
- **Three or more:** it's complex; route to `flow-grill`.

The fast path keeps what CONVENTIONS §4 requires of small tasks (read the code and its callers, tests before and after, proof by running it, CONVENTIONS §8 for a bug, the CONVENTIONS §7 security pass). Land it per `.workflow/merge-strategy.md`.

### Complex → full workflow
Route to the earliest incomplete step with the table in CONVENTIONS §5, using `next` output and existing `.workflow/specs/`, `.workflow/maps/`, `.workflow/tasks/`. Name tasks `<effort>/<NN>`.

## 5. Report and proceed

Three lines:
1. Context loaded (or missing), plus paused or blocked tasks, open hotfix follow-ups and fix-now debt when there are any
2. Classification and why
3. Next action

Then do that action in the same turn. Stop only when the classification genuinely needs the user's input.

## When to skip this skill

Skip it mid-session with context loaded, when the user names a flow skill directly, or when resuming with context still present. Use it on a fresh session, after compaction, when the user asks "what's next", or when unsure which skill applies.
