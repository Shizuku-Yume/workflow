# Workflow

English | [简体中文](README.md)

Lightweight, repo-local workflow skills and CLI for coding agents and developers. Running `workflow init` writes conventions, skills, templates, and a task-queue CLI directly into your Git repository so planning, task breakdown, implementation, and review stay consistent without heavy project-management overhead.

---

## Design Principles

- **Committed to the Repo**: Rules, skills, and the CLI live inside the repository (`.workflow/`, `.agents/`, and optional `.claude/`). Collaborators and CI clone and run without global configuration.
- **Check Code Before Asking**: Search code, configs, and git history before asking questions. Pick sensible defaults for reversible details; bring only user-owned direction or costly architectural trade-offs to the user.
- **Real-Path Verification**: Every task carries a runnable `Check` command. Reproduce bugs before fixing them, and verify changes through the real CLI or application entry point rather than mocks alone.
- **Lean Implementation**: Reuse existing code and standard libraries before adding new code. Fix real reachable bugs without speculative defenses, passthrough wrappers, or unrequested compatibility flags.
- **Fresh-Context Review**: A fresh `workflow-reviewer` subagent inspects requirement completion and code quality together, triggering `security-reviewer` at trust boundaries like auth or external input.
- **Parallel Worktrees & Logged Decisions**: `workflow next` schedules ready tasks and flags shared-file overlaps. Parallel tasks run in isolated Git worktrees (`.workflow/worktrees/<effort>-<NN>`). Difficult-to-reverse technical decisions append to `.workflow/decisions.md` (Git union merge prevents conflicts), while project terms live in `glossary.md`.

---

## How It Works in Practice

Pick the shortest path for the size and clarity of the change:

1. **Small change or bugfix**: edit code directly → run tests and the real entry point → commit. No task files, no review ceremonies.
2. **1–3 clear tasks**: `flow-break` writes task cards → `flow-implement` builds and archives them. No spec, no `flow-close`.
3. **Multi-task feature or contract/schema change**: `flow-spec` → `flow-break` → `flow-implement` → `flow-close`.

**When scope or design is unsettled** (regardless of size), run `flow-grill` first to clarify trade-offs, then take the matching path above. Record unknowns that require multi-session exploration in `maps/<slug>.md`, which `workflow next` lists until resolved.

---

## The 9 Workflow Skills

Most days only require 2–4 skills. The toolkit divides skills into **daily core skills** and **on-demand supporting skills**:

### Daily Core Skills

| Skill | When to Use | What It Does |
| :--- | :--- | :--- |
| `flow-start` | Session start / resuming / unsure what's next | Loads project standards, inspects queue state, and recommends or resumes the next step. |
| `flow-grill` | Unclear requirements / open scope | Clarifies requirements and trade-offs against code facts. Moves directly to `flow-spec` or `flow-break` once settled, or saves a `maps/<slug>.md` note for multi-session exploration. |
| `flow-spec` | Unsettled architecture / complex multi-task effort | Writes a concise technical spec (`specs/<effort>.md`); skipped for 1–3 clear tasks. |
| `flow-break` | Splitting scope into tasks | Breaks specs or clear goals into task files with `Blocked by` dependencies and runnable `Check` commands. |
| `flow-implement` | Building a task or an effort queue | Builds, verifies, reviews, and archives tasks; coordinates parallel waves across worktrees in `.workflow/worktrees/` when given `<effort>`. |
| `flow-verify` | Pre-merge code review | Runs a fresh `workflow-reviewer` subagent for requirements and code quality, plus security review at trust boundaries. |

### On-Demand Supporting Skills

| Skill | When to Use | What It Does |
| :--- | :--- | :--- |
| `flow-close` | Wrapping up a spec effort | Runs all spec checks and the main flow on the delivery build, records acceptance upon user sign-off, and marks the spec done. |
| `flow-retro` | Rough session / workflow friction | Reviews session friction and proposes concrete automated checks, layout notes, or rule reductions (requires user approval). |
| `flow-architect` | High change friction / technical debt | Audits high-friction modules for duplication, dead code, and leaky abstractions, tracking actionable cleanup tasks. |

---

## Installation & Setup

### 1. Install the CLI

Via npm:

```bash
npm install --global @shizuku-yume/workflow
```

Or clone this repository and run `bin/workflow` directly.

### 2. Initialize a Project

From the root of your Git repository:

```bash
workflow init
```

Options:
- `--claude`: Also install Claude Code adapter files (`.claude/` and `CLAUDE.md`; auto-enabled when already present).
- `--no-claude`: Install `.agents/` and `AGENTS.md` only.
- `--force`: Overwrite locally edited managed files.

### 3. Optional Pre-Commit Hook

Validate task files and decision formatting before each commit:

```bash
workflow hook install
```

---

## CLI Reference

Use `workflow <command>` globally, or `.workflow/bin/workflow <command>` inside any initialized repository.

### Daily Commands

- `workflow next [--effort SLUG] [--all] [--brief] [--format text|json]`
  Lists ready tasks by priority, shows active/paused/blocked tasks, and warns on shared files; `--brief` prints a compact snapshot and stays silent when idle.
- `workflow task start <task>`
  Activates a task, records current HEAD as `Base commit`, sets `Status: active`, and advances matching spec to `in progress` if needed.
- `workflow task archive <task>`
  Verifies completed checkboxes and required task proof (`Check after:` or spike `## Findings`), removes `Status`, moves to `.workflow/done/<effort>/`, and validates repository state.
- `workflow validate [--strict] [--format text|json]`
  Validates task files, archived tasks, specs, and `decisions.md`.
- `workflow doctor`
  Checks installed workflow files, branch version sync, and `validate`.
- `workflow hook install|uninstall|status [--force|--append]`
  Manages the Git pre-commit validation hook.
- `workflow version`
  Prints the toolkit version.

### Setup & Maintenance

- `workflow init [--force] [--claude|--no-claude]` — Install workflow files and CLI into the current repo.
- `workflow update [--force] [--claude|--no-claude]` — Refresh unmodified skills, rules, and CLI while preserving local edits.
- `workflow uninstall` — Remove unmodified managed files while keeping project standards, specs, tasks, and decisions.

---

## Project Layout

Created by `workflow init`:

```
AGENTS.md                        # Entry rules for agents (marked block)
.agents/
  skills/<name>/SKILL.md         # 9 workflow skill definitions
  agents/workflow-reviewer.md    # Requirements and code quality reviewer
  agents/security-reviewer.md    # Trust-boundary security reviewer
.workflow/
  bin/workflow                   # Repo-local CLI (Bash)
  bin/workflow-core.py           # Validator and queue engine (Python 3 stdlib)
  CONVENTIONS.md                 # Shared workflow conventions
  STYLE.md                       # Writing and reporting rules
  standards.md                   # Project commands, layout, and Landing mode
  glossary.md                    # Domain terms (Git union merge)
  decisions.md                   # Consequential decisions log (Git union merge)
  technical-debt.md              # Tracked technical debt
  specs/<effort>.md              # Technical specifications
  tasks/<effort>/<NN>-<slug>.md  # Open task cards
  maps/<slug>.md                 # Multi-session exploration notes from flow-grill
  done/<effort>/                 # Archived tasks and closeout notes
```

---

## Requirements

- **OS**: Linux / macOS (POSIX)
- **Shell**: Bash 3.2+ (stock macOS Bash compatible)
- **Python**: Python 3.8+ (standard library only, for `validate` and `next`)
- **Git**: Version control and branch inspection
- **Node.js** (Optional): Node.js 14+ (only for global npm installation)

---

## License

MIT
