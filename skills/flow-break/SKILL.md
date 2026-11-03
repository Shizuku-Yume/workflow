---
name: flow-break
description: >-
  Cut spec into tasks a single session can finish, with dependencies. Use when
  user says "break this down", "split into tasks", or before parallel work.
---

# Flow: Break

Read CONVENTIONS §2, §2.1, §5 and §6. Break either a settled spec or settled
conversation into `.workflow/tasks/<effort>/`. If scope is clear, 1–3 tasks, and needs no
durable spec, skip `flow-spec` and come here directly. Use amend mode for a blocked task
or a changed spec.

## Shape and sizing

Each task should deliver observable working behavior, fit a fresh session, be independently
checkable, and avoid depending on later tasks. Integrate early: task 01 is the thinnest
end-to-end slice on the real entry point. For wide refactors, expand, migrate in batches,
then contract. A gate task checks assembled behavior; it does not take over a blocker's
Check (CONVENTIONS §9).

Use `feature` (default), `bugfix`, `refactor`, or `spike` per CONVENTIONS §2.1; bugs follow
§8. Spike answers are scoped experiments. Keep a task small enough to deliver in one
sentence and check on its own.

## Process
Turn the settled scope into ordered, independently checkable tasks.

### 1. Read the scope

Read the spec or settled conversation, relevant code, and applicable technical-debt
entries. Make a tidy-first task only when it helps the requested change; otherwise note
overlapping debt in the handoff.

### 2. Draft tasks

For each task define its effort and type, observable `Delivers`, true `Blocked by` gates,
expected `Files`, concise `Read first`, `Check`, and acceptance checklist. Add `Covers` for
spec check IDs only. Checks state a command and passing signal, using the real path when
required; spikes state how their answer is validated. Include behavior and decisions, not
implementation snippets unless prose cannot express the contract.

**Coverage gate (spec efforts):** every spec check ID must appear in task `Covers` or be
explicitly reserved for `flow-close` because it needs the assembled effort. Resolve every
other gap before presenting.

### 3. Review once

Present the task list with deliverables, blockers, and real parallelism/coordination; state
where work lands. For an unconfirmed spec, summarize it briefly and settle spec and task
approval together. Skip the spec summary and `Covers` when there is no spec. For an
already-confirmed one-task effort, state its delivery and Check and proceed. Propose an
integration branch only when the main branch cannot remain sound or releasable; follow
`merge-strategy.md`.

### 4. Write and hand off

Write numbered files in dependency order; never reuse numbers already used by the effort.
Use this task template:

```markdown
# <NN>: <Title>

**Effort:** <effort>
**Task type:** feature
**Base commit:** <commit-sha>

**Delivers:** <observable behavior>

**Blocked by:** None | <NN>, <effort>/<NN>
**Files:** <where work happens>

**Read first:** <spec sections, glossary terms, files>
**Covers:** <check IDs>

**Check:** `<command>` → <result that means it works>

- [ ] <acceptance point>
```

Validate and correct task files. Commit planning docs and tasks together before task
branches. Under `Landing: pr`, task 01 may stack on the planning PR branch (CONVENTIONS
§2); otherwise start from the appropriate landing branch. Report ready tasks, parallel
work, close-only checks, and relevant debt. Each task must be buildable from its own file
and named spec sections. Build with `flow-implement`; separate worktrees for parallel work.

## Amending an effort

Fix a blocked assumption in the plan, not with a code workaround. Read the blocked task's
`## Blocked` and `## Progress`, plus the spec or decision that changed. Review every
remaining task for accurate delivery, files, reading, checks, coverage, and blockers.

Rewrite stale tasks; remove tasks no longer needed and repair their dependents. Never
renumber; new tasks use the next number after all active and archived tasks. If the spec
was `done`, reopen it to `in progress` (§6). Edit the blocked task on its branch and remove
`## Blocked`: if delivery is unchanged, pause it with progress intact; if changed, reset
its Base commit and Started/Status, preserve reusable-work notes, and release its old task
branch for a fresh claim. Rerun the coverage gate, present one concise change round, then
validate and commit plan updates together on the landing branch.
