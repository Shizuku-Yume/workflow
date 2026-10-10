# Workflow

English | [简体中文](README.md)

Project-local workflow skills and CLI for coding agents and developers.

Injects conventions, skills, document layouts, and a task scheduling CLI directly into the target Git repository, giving coding agents structured engineering capabilities for planning, decomposition, implementation, verification, and retrospectives.

---

## Key Features

- **Project-Local & Zero Extra Setup**: All conventions, skills, templates, and scheduling tools are copied and committed into the repository root (`.workflow/`, `.agents/`, and optionally `.claude/`). Any teammate, CI runner, or cloud agent cloning the repository gets the identical workflow without global environment dependencies or PATH configuration.
- **Evidence Before Questions (§0, §1)**: Agents must autonomously investigate codebase evidence (patterns, existing behaviors, APIs, constraints) before interrupting the user. Only questions involving user decision ownership (intent, preferences, scope, irreversible trade-offs) are batched and asked.
- **DAG Task Queue & Dependency Tracking**: Complex efforts are broken down via `flow-break` into bite-sized, single-session task files (`.workflow/tasks/<effort>/`), scheduled topologically by `workflow next` based on priority and dependencies.
- **Observable Verification (§2.1, §8)**: Every task requires an explicit `Check` command. Features and bug fixes must reproduce or fail before changes and pass afterward; unverified deliverables are rejected.
- **Append-Only Decision Log**: Significant architectural decisions are appended to `.workflow/decisions.md` with five structured fields (`Decided`, `Instead of`, `Because`, `Mine`, `Revisit when`). Git union merge configuration prevents merge conflicts across parallel branches.
- **Independent Two-Brief Reviews (§7)**: Built-in `workflow-reviewer` agent conducts independent reviews covering both process adherence and code implementation quality.

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
| `flow-spec` | Settled design / ready for documentation | Records consensus into a structured effort specification (`.workflow/specs/<effort>.md`). |
| `flow-break` | Splitting spec into actionable tasks | Decomposes spec into tasks with dependencies (`Blocked by`) and observable checks (`Check`). |
| `flow-implement` | Building a single task (Feature / Bugfix / Refactor / Spike) | End-to-end task execution: dirty file audit, implementation, verification, review, and archive. |
| `flow-verify` | Reviewing completed work before merging | Invokes `workflow-reviewer` for quality inspection and process compliance verification. |
| `flow-close` | All tasks of an effort landed | Verifies against spec, demonstrates behavior, logs retrospective, and marks spec done. |
| `flow-architect` | High code friction / auditing technical debt | Detects duplication, dead code, leaky modules, and tracks technical debt. |

---

## CLI Reference

Run `workflow <command>` via the global CLI or call `.workflow/bin/workflow <command>` committed inside the project.

### Daily Commands

- `workflow next [--format text|json]`
  Inspects task dependency graphs and displays up to 5 ready tasks by priority, along with paused and blocked tasks.
- `workflow validate [--strict] [--format text|json]`
  Statically validates schemas, field grammar, dependency references, and decision logs across `tasks/`, `done/`, and `specs/`.
- `workflow doctor`
  Diagnoses repository health, validating managed files, symlink safety, AGENTS markers, glossary integrity, and task dependency cycles.
- `workflow hook install|uninstall|status [--force]`
  Manages the Git pre-commit hook that runs validation before commits.
- `workflow version`
  Prints current toolkit version.

### Setup & Maintenance

- `workflow init [--force] [--claude|--no-claude]`
  Installs workflow skills, rules, and the committed CLI into the current repository.
- `workflow update [--force] [--claude|--no-claude]`
  Re-copies skills, rules, and CLI updates while preserving custom user files and edits.
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
