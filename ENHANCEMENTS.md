# Workflow Enhancements v2.2

This document summarizes the improvements made to the workflow system.

## New CLI Commands

All commands can be run from anywhere in the project. Use `--help` for detailed usage.

### `workflow tasks`
List and filter active tasks.

```bash
workflow tasks              # list all
workflow tasks --blocked    # only blocked tasks
workflow tasks --ready      # only unblocked tasks
workflow tasks --effort api-v2
workflow tasks --status     # summary counts
```

### `workflow deps`
Visualize task dependencies as graphs.

```bash
workflow deps                      # mermaid flowchart
workflow deps --format dot         # Graphviz DOT
workflow deps --format text        # simple text
workflow deps --effort api-v2      # filter by effort
workflow deps --all                # include completed tasks
```

### `workflow decisions`
Search and validate decision log.

```bash
workflow decisions                 # list all (newest first)
workflow decisions recent 5        # last 5 decisions
workflow decisions search cache    # keyword search
workflow decisions validate        # check format
```

### `workflow effort`
Manage effort lifecycle.

```bash
workflow effort list               # all efforts with status
workflow effort status api-v2      # detailed effort info
workflow effort create new-effort  # create definition
workflow effort complete api-v2    # mark complete
```

### `workflow debt`
Track technical debt from architect reviews.

```bash
workflow debt list                 # all debt items
workflow debt list --priority fix-now
workflow debt add                  # interactive add
workflow debt resolve ID           # mark resolved
workflow debt init                 # create tracking file
```

### `workflow hotfix-review`
Track unresolved hotfixes.

```bash
workflow hotfix-review             # unresolved only
workflow hotfix-review --all       # include resolved
```

## New Documents

### `.workflow/technical-debt.md`
Track architecture findings from `flow-architect`. Items categorized by priority:
- **Fix now** — blocking current work
- **Worth doing** — helpful but not urgent
- **Only if it grows** — defer until area expands

### `.workflow/merge-strategy.md`
Branch and merge guidelines:
- When to rebase vs merge
- How Base commit works during long tasks
- Conflict resolution process
- Branch protection recommendations

### `.workflow/spike-tasks.md`
Exploratory task guidelines:
- When to use spike tasks
- Time-boxing rules
- What to do with spike code
- Recording findings

### `.workflow/efforts/<slug>.md`
Effort definitions tracking:
- Goal and scope
- Success criteria
- Dependencies
- Status and progress

## Enhanced Features

### Task Format Extensions
Tasks now support:
- `Task type: spike` for exploratory work
- `Status: active | paused | blocked` for interruption tracking
- `Started: <timestamp>` automatically recorded
- `Finished: <timestamp>` added on archive

### Effort Lifecycle
- Explicit effort definitions with goals and success criteria
- Progress tracking (active/done task counts)
- `workflow effort complete` points to `done/<effort>/retrospective.md`
- Cross-effort dependency tracking

### Decision Log Enhancements
- Searchable by keyword
- Format validation
- Recent decisions quick view
- Hotfix tracking with "Revisit when" field

### Technical Debt Tracking
- Formal process for `flow-architect` findings
- Priority-based categorization
- Resolution tracking
- Prevents re-discovery

### Dependency Visualization
- See task relationships graphically
- Identify bottlenecks
- Understand blocking chains
- Export for documentation

## Updated Skills

### `flow-architect`
Logs unaddressed findings with flag-based `workflow debt add`; rejected findings go to `workflow debt accept`.

### `flow-break`
- Task template matches `workflow validate`: numbers-only `Blocked by`, `Task type` field
- Creates the effort definition when missing and runs `workflow validate` before hand-off

### `flow-implement`
- One intensity setting (`quick | standard | thorough`); the separate `--verify` flag is gone
- Records `Base commit`, `Started` and `Status: active` when starting
- Archive-and-commit step: `Finished` timestamp, `git mv` to `done/<effort>/`, `workflow validate`, one commit
- Security pass for changes crossing a trust boundary
- Spike tasks: time box is a scope limit; findings recorded, throwaway code kept out of main

### `flow-start`
Reads state through `workflow next` and `workflow tasks`; offers to resume `Status: paused` tasks; recognizes spikes.

## Workflow Installation

New files are installed automatically with `workflow init` or `workflow update`:
- `merge-strategy.md`
- `spike-tasks.md`
- `technical-debt.md`
- `efforts/` directory

Existing projects should run:
```bash
workflow update
```

## Migration Notes

### For Existing Projects

1. **Run update:**
   ```bash
   cd your-project
   workflow update
   ```

2. **Optional: Create effort definitions**
   For active efforts, run:
   ```bash
   workflow effort create <slug>
   ```
   Then edit `.workflow/efforts/<slug>.md` with goals and scope.

3. **Optional: Initialize debt tracking**
   ```bash
   workflow debt init
   ```

4. **Review hotfixes**
   Check for unresolved temporary fixes:
   ```bash
   workflow hotfix-review
   ```

### Backward Compatibility

All changes are backward compatible:
- Old task files work without modification
- New fields are optional
- Existing workflows continue unchanged
- Commands degrade gracefully if files missing

## CLI Implementation Notes

The CLI tools are Bash scripts in `bin/`:
- `workflow-tasks` — task listing and filtering
- `workflow-deps` — dependency visualization
- `workflow-decisions` — decision log search
- `workflow-effort` — effort management and progress display
- `workflow-debt` — technical debt tracking
- `workflow-hotfix-review` — hotfix tracking
- `workflow-validate` — workflow structure validation
- `workflow-next` — ready-task suggestions

Main `workflow` script dispatches to these via `dispatch_subcommand()`.

Integration status:
- All eight commands support `--help`, examples, TTY-aware output, and `--no-color`.
- Commands locate the Git root, falling back to the current directory outside Git.
- Structured commands support JSON where documented; `workflow effort` intentionally remains a human-readable display command.
- `completions/workflow.bash` and `completions/_workflow` provide Bash and Zsh completion.
- `tests/cli-tests.sh` runs command suites, non-Git fallback checks, a 120-task performance smoke test, and `tests/skills-lint.sh`, which resolves CONVENTIONS references, checks skill step numbering and empty sections, and round-trips the task, spike and decision examples through `workflow validate`.
- Task numbers are unique per effort, so `01` may exist in two efforts; commands identify a task as `<effort>/<NN>` and resolve bare `NN` blockers within the task's own effort. Strict `Blocked by` grammar is `None` or a comma-list of `NN`/`<effort>/NN`. Missing effort definitions are warnings, not errors.
- `workflow effort` uses Bash 4+ features; completed efforts are hidden unless `--archived`, and velocity-based ETA is not reported.

The delivered CLI implementation, integration, and documentation requirements are complete. Optional velocity ETA, macOS certification, animated demos, and man pages remain outside this release's scope; no coverage percentage is claimed without coverage instrumentation.

## Future Enhancements

Consider for future versions:
1. Web dashboard for effort/task visualization
2. Integration with issue trackers (GitHub, Jira)
3. Task time tracking
4. Decision log indexing with tags
5. Git hooks for task validation

## Version History

- **2.2.0** — CLI tools, effort lifecycle, technical debt tracking
- **2.1.0** — Phase boundaries, thinking framework
- **2.0.0** — Initial release with 8 flow skills
