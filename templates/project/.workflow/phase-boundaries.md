# Phase Boundaries

A phase is a stage of work: grilling, spec, breakdown, task, or review. At its boundary,
choose how context carries forward. You usually cannot clear or compact your own window;
first commit planning docs and write any unfinished task handoff — or `.workflow/HANDOFF.md`
when no task file is active (CONVENTIONS §6) — then recommend the next step in one line.

## Options

- **Continue:** stay in this session.
- **Clear:** empty the window; files carry the work.
- **Compact:** compress context into a fresh window.
- **Switch session:** change directory, harness, or person; committed files hand off.
- **Subagent:** delegate a tightly scoped piece and take back its report.

Use the first applicable rule:

1. Keep `flow-grill` → `flow-spec` → `flow-break` in one window; each builds on the
   preceding discussion.
2. Start a task or `flow-close` in a fresh session: their inputs are committed files.
3. Clear or compact at a phase boundary only on real degradation signals, not a fixed
   schedule. Mid-phase, finish or delegate first. On resume/compaction, verify workspace
   state and reread `next` and the active task. Reuse valid check evidence for unchanged
   inputs; do not rerun settled suites.
4. Delegate independent, tightly scoped lookups or task builds (CONVENTIONS §9). On
   multi-hour autonomous runs, schedule `.workflow/bin/workflow pulse --quiet-idle` (such
   as `/loop 30m`) to counter context drift.
5. Otherwise continue: it costs nothing and loses nothing.
