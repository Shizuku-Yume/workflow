# Workflow

English | [简体中文](README.md)

Project-local workflow skills and CLI for coding agents and developers.

Injects conventions, skills, document layouts, and a task scheduling CLI directly into the target Git repository, giving coding agents structured engineering capabilities for planning, decomposition, implementation, verification, and retrospectives.

---

## Key Features

- **Project-Local & Zero Extra Setup**: All conventions, skills, templates, and scheduling tools are copied and committed into the repository root (`.workflow/`, `.agents/`, and optionally `.claude/`). Any teammate, CI runner, or cloud agent cloning the repository gets the identical workflow without global environment dependencies or PATH configuration.
- **Evidence Before Questions & Momentum (§0, §1)**: Agents autonomously investigate codebase evidence (patterns, existing behaviors, APIs, constraints) before interrupting the user. Reversible choices take reasonable defaults to maintain momentum; only questions involving user decision ownership (intent, scope, expensive reversals) are batched and asked.
- **DAG Task Queue & Scope Routing (§5)**: Clear 1–3 task work goes straight to `flow-break` without spec or close ceremony, while multi-task or architecturally non-obvious efforts use `flow-spec` and `flow-close`. Ready tasks in `.workflow/tasks/<effort>/` are scheduled topologically by `workflow next` based on priority and dependencies.
- **Observable Verification (§2.1, §8)**: Every task requires an explicit `Check` command. Features and bug fixes must reproduce or fail before changes and pass afterward; unverified deliverables are rejected. A check against a fixture or mock proves only the stand-in: behaviour that depends on a real service is checked against it.
- **Real-Path Acceptance (§6)**: `flow-close` reruns every spec check on the build that will ship and walks the main use as a user would. An effort is done only when the user says yes, recorded as `**Accepted:**` in its retrospective.
- **Proportional Scope & Anti-OverDefense (§10)**: Bounds fixes and implementation without suppressing bug discovery. Real defects reachable through supported use are reported directly; avoids unpaid hashes, unreachable corner-case hardening, rubric or audit loops, unrequested wrappers or flags, and trial-and-error or AI traces in deliverables (`STYLE.md`).
- **Parallel Work with Integration Branches (§9)**: Parallel tasks run in separate worktrees. `flow-implement <effort>` coordinates whole-effort DAG execution in waves, serializing file overlaps and harvesting completed deliverables immediately. An effort that can't land piece by piece names an integration branch in its spec; its tasks land there and the whole effort lands on main at close. Delegating a task to a subagent keeps its proof with the session that archives it.
- **Append-Only Decision Log**: Significant architectural decisions are appended to `.workflow/decisions.md` with five structured fields (`Decided`, `Instead of`, `Because`, `Mine`, `Revisit when`). Git union merge configuration prevents merge conflicts across parallel branches.
- **Independent Two-Brief Reviews (§7)**: Built-in `workflow-reviewer` agent conducts independent reviews covering process adherence and code implementation quality (`security-reviewer` reviews boundary closure on trust boundaries); localized leaf tasks can use a single combined review pass. Findings are batched for fixes and affected checks rerun; in-scope fixes without new files, callers, or sinks skip redundant re-review.

---

## Installation & Setup

### 1. Install CLI Globally

Recommended via npm:

```bash
npm install --global @shizuku-yume/workflow
```

Alternatively, clone this repository and use `bin/workflow`.

### 2. Initialize a Project

Run from the root of any target Git repository:

```bash
workflow init
```

Common options:
- `--claude`: Force-install Claude Code adapter files (`.claude/skills/`, `.claude/agents/`, and `CLAUDE.md` importing `AGENTS.md`). Enabled automatically if `CLAUDE.md` or `.claude/` exists.
- `--no-claude`: Install standard `.agents/` and `AGENTS.md` only.
- `--force`: Overwrite modified managed files.

### 3. Install Pre-Commit Hook (Optional)

Prevent committing malformed tasks or broken dependencies:

```bash
workflow hook install
```

---

## Skills Overview

The toolkit provides 9 standard skills covering distinct development phases (routed per §5):

| Skill | When to Use | Description |
| :--- | :--- | :--- |
| `flow-start` | Session start / context lost / resuming work | Loads project standards, classifies request (clarification, small task, or complex work). |
| `flow-grill` | Requirements vague / design options open | Clarifies scope, categorizes decisions, batches user questions, and logs decisions. |
| `flow-map` | Foggy projects / multi-session exploration | Charts dependencies and open questions across sessions when requirements are unclear. |
| `flow-spec` | Settled design / multi-task effort needing a spec | Records consensus into a structured effort specification (`.workflow/specs/<effort>.md`); clear 1–3 task work skips this step. |
| `flow-break` | Splitting spec or clear scope into tasks | Decomposes a spec or clear 1–3 task scope into task files with dependencies (`Blocked by`) and observable checks (`Check`). |
| `flow-implement` | Building a single task or orchestrating an effort | End-to-end task execution (audit, implementation, verification, review, archive); accepts `<effort>` to coordinate DAG waves across parallel worktrees. |
| `flow-verify` | Reviewing completed work before merging | Invokes `workflow-reviewer` for process and quality review; localized leaf tasks can use a single combined review pass. |
| `flow-close` | All tasks of an effort with a spec landed | Verifies against spec, demonstrates behavior, logs retrospective, and marks spec done (efforts without a spec finish on last task land). |
| `flow-architect` | High code friction / auditing technical debt | Detects duplication, dead code, leaky modules, and tracks technical debt. |

---

## CLI Reference

Run `workflow <command>` via the global CLI or call `.workflow/bin/workflow <command>` committed inside the project.

### Daily Commands

- `workflow next [--effort SLUG] [--all] [--format text|json]`
  Inspects task dependency graphs and displays up to 5 ready tasks by priority (or all ready tasks with `--all`, optionally scoped with `--effort`), along with paused and blocked tasks, detecting shared file path overlaps across ready tasks (`file_overlaps`). Off the main branch it names the branch it read and how far main is ahead; it lists tasks landed on main but still open in this tree, shows an effort integrating on another branch as one line, and names tasks that several branches claim.
- `workflow pulse [--effort SLUG] [--quiet-idle] [--format text|json]`
  Compact queue snapshot and anti-drift execution reminder for long autonomous runs, displaying active, ready, and blocked task state (supports `--effort`, and stays silent when idle under `--quiet-idle`).
- `workflow validate [--strict] [--format text|json]`
  Statically validates schemas, field grammar, dependency references, and decision logs across `tasks/`, `done/`, and `specs/`. A task being archived must have every checklist item ticked and a `Check after:` record; a spec can't be marked done while one of its tasks is open or before the user's acceptance is recorded.
- `workflow doctor`
  Diagnoses repository health, validating managed files, symlink safety, AGENTS markers, glossary integrity, and task dependency cycles. It warns when this branch runs a different workflow version than main, or when the last update is not committed.
- `workflow hook install|uninstall|status [--force|--append]`
  Manages the Git pre-commit hook that runs validation before commits (`--append` adds a managed block to an existing hook).
- `workflow version`
  Prints current toolkit version.

### Setup & Maintenance

- `workflow init [--force] [--claude|--no-claude]`
  Installs workflow skills, rules, and the committed CLI into the current repository.
- `workflow update [--force] [--claude|--no-claude]`
  Re-copies skills, rules, and CLI updates while preserving custom user files and edits. Commit the result on the main branch: other branches and worktrees keep the old rules until they merge it.
- `workflow uninstall`
  Cleanly removes workflow-managed files while retaining user code and data.

---

## Project Structure

Layout created after `workflow init` (see §2):

```
AGENTS.md                          # Primary agent rules entry point (workflow markers)
.agents/
  skills/<name>/SKILL.md           # Implementation steps for the 9 workflow skills
  agents/workflow-reviewer.md      # Reviewer agent briefs (process & quality)
  agents/security-reviewer.md      # Security brief (trust-boundary closure)
.workflow/
  bin/workflow                     # Committed CLI executable (Bash)
  bin/workflow-core.py             # Committed validator and queue engine (Python 3 stdlib)
  CONVENTIONS.md                   # Complete workflow conventions rulebook
  STYLE.md                         # Writing and communication style guidelines
  standards.md                     # Project-specific configuration (build, test, landing)
  glossary.md                      # Domain glossary (Git union merge)
  decisions.md                     # Append-only architectural decisions (Git union merge)
  technical-debt.md                # Architectural findings backlog
  merge-strategy.md                # Git branch and landing strategies
  phase-boundaries.md              # Context boundaries and phase management
  spike-tasks.md                   # Guidelines for exploratory spike tasks
  specs/<effort>.md                # Effort specifications
  tasks/<effort>/<NN>-<slug>.md    # Individual task files
  maps/<slug>.md                   # Multi-session fog maps
  done/<effort>/                   # Archived tasks and retrospectives
```

---

## Requirements

- **OS**: POSIX-compliant system (Linux / macOS).
- **Shell**: Bash 3.2+ (standard on macOS).
- **Python**: Python 3.8+ (standard library only, for `validate` and `next`).
- **Git**: Version control and path resolution.
- **Node.js** (Optional): Node.js 14+ (only required if installing via npm global package).

---

## License

MIT
