# workflow

Task-driven workflow for coding agents: decide what to build, write it down, break into tasks, build, review.

Installs into a project, not globally. Everything committed with the project.

## Install

```sh
git clone https://github.com/Shizuku-Yume/workflow.git ~/tools/workflow
~/tools/workflow/bin/workflow init
```

Fill in `AGENTS.md` and `.workflow/standards.md`. Commit.

| Command | Does |
| --- | --- |
| `workflow init` | install into current project |
| `workflow update` | re-copy skills and rules after toolkit changes |
| `workflow doctor` | report what's installed and missing |
| `workflow uninstall` | remove installed files, keep your documents |
| `workflow tasks` | list and filter active tasks |
| `workflow deps` | visualize task dependencies (mermaid/dot/text) |
| `workflow decisions` | search and manage decision log; filter by text, field, date, or `--effort` tag |
| `workflow effort` | manage effort lifecycle and progress |
| `workflow debt` | track technical debt from architect reviews |
| `workflow hotfix-review` | list unresolved hotfixes needing proper solutions |
| `workflow validate` | validate workflow files and dependency references |
| `workflow next` | suggest ready tasks by effort priority |

## What it installs

```
AGENTS.md                     workflow block with pointer to rules
.agents/skills/flow-*/        eight workflow steps
.agents/agents/workflow-*.md  review agents
.workflow/
  CONVENTIONS.md              the rulebook
  STYLE.md                    writing guide
  thinking.md                 first principles framework
  phase-boundaries.md         context management
  merge-strategy.md           branch and rebase guidelines
  spike-tasks.md              exploratory work guidelines
  technical-debt.md           architecture debt tracking
  standards.md                project-specific rules
  glossary.md                 vocabulary
  decisions.md                decisions log
  efforts/<slug>.md           effort definitions
  specs/  tasks/  maps/  done/<effort>/
```

Skills and agents are copied, not linked. `workflow update` pulls newer versions. Managed files carry markers; edited files are skipped with warning (`--force` overrides).

## The skills

| Skill | Does | Output |
| --- | --- | --- |
| `flow-start` | Load context, classify request, route | routing decision |
| `flow-grill` | Align on what to build, batch questions | `decisions.md`, `glossary.md` |
| `flow-spec` | Write the design down | `specs/<slug>.md` |
| `flow-break` | Cut into session-sized tasks | `tasks/<NN>-<slug>.md` |
| `flow-implement` | Build, prove, review, archive, commit | code, docs, `done/<effort>/` |
| `flow-verify` | Three-axis review (what/quality/process) | report |
| `flow-architect` | Find expensive-to-change code | report |
| `flow-map` | Plan foggy work one question at a time | `maps/<slug>.md` |

**Small task fast path:** single behavior change, affects <3 modules' behavior, clear requirements, no architectural decision → skip grill/spec/break/verify, still run tests and prove it works. Impact radius counts, not file count (CONVENTIONS §4).

**Intensity levels** (`flow-implement <effort>/<NN> [level]`): `quick` (skip review), `standard` (default), `thorough` (add architect check).

**Task references:** task numbers are unique within an effort, not across efforts. Refer to a task as `<effort>/<NN>`; `workflow next` prints start hints in that form.

## Troubleshooting and known limitations

### Commands report that `.workflow` is missing

CLI commands locate the project root with `git rev-parse --show-toplevel`; when no Git repository is present they fall back to the current working directory. Inside Git, run from the project directory or any descendant. Outside Git, run from the directory containing `.workflow/`. Commands that only inspect data report an empty result where appropriate; lifecycle commands such as `workflow debt init` can create their required files.

### Output formats and scripting

Use `--format json` with commands that expose structured output (`tasks`, `decisions`, `debt`, `hotfix-review`, `next`, and `validate`). `workflow deps` offers `mermaid`, `dot`, and `text` graph formats. `workflow effort` intentionally provides human-readable lifecycle/progress displays only; it has no JSON format flag. Use `--no-color` in scripts and CI. `--help` shows command-specific options and examples.

### Validation and malformed files

`workflow validate` uses validator-specific exit statuses: 0 means valid, 1 means warnings, and 2 means validation errors or invalid usage. Other command failures use 1 for runtime/file errors and 2 for invalid options. Diagnostics are written to stderr; JSON data remains on stdout.

The tools parse Markdown metadata conservatively. `Blocked by` takes `None` or a comma-list of `NN` (same effort) and `<effort>/NN` (cross-effort); anything else, including titles after the numbers, is malformed, and each reference must identify an existing task. Duplicate numbers are errors only within one effort. A missing effort definition (`.workflow/efforts/<slug>.md`) is a warning: definitions are optional, and `workflow next` ranks tasks without one at normal priority. Repair the source Markdown and rerun `workflow validate`. Problems inside `done/<effort>/` archives are reported as warnings rather than errors, so an old archive never blocks a new commit.

### No colors or terminal output

Color is enabled only for interactive terminal output. Pass `--no-color` to force plain text. Piping output, redirecting it, or using JSON automatically keeps data suitable for automation.

### Performance

The commands scan task and decision Markdown files on demand rather than maintaining an index. This keeps project state transparent but means very large projects may take longer; use focused filters (`--effort`, date filters, or a format suitable for your consumer) when available.

### Shell completion

For Bash, source the completion script from this checkout:

```bash
source /path/to/workflow/completions/workflow.bash
```

For Zsh, add the completion directory to `fpath` before `compinit`:

```zsh
fpath=(/path/to/workflow/completions $fpath)
autoload -Uz compinit && compinit
```

Completions cover the wrapper and standalone commands, flags, subcommands, formats, and existing effort slugs.

### Running the CLI tests

Run `tests/cli-tests.sh` from the checkout. It invokes all eight command suites, wrapper regressions, shared integration contracts, a cross-command parser-consistency check, completion checks, timed 120-task/120-decision tests, and `tests/skills-lint.sh`, which checks that CONVENTIONS references in skills and templates resolve, skill steps are numbered without gaps or empty sections, and the task and decision examples in the skills pass `workflow validate`. Bash 4+, Git, and Python 3 are required; native Zsh completion tests run when Zsh is available. Set `WORKFLOW_PERF_MAX_SECONDS` to override the default 30-second per-command performance ceiling on slower machines.

### Runtime limitations

The commands use Bash 4.3 or newer (not a POSIX `sh`) with awk, Git, and the usual coreutils; no Python runtime is needed. Task and effort metadata is read by one shared parser, `bin/workflow-lib.bash`, so every command accepts the same field spellings and continuation rules. Effort progress is based on task counts, not velocity estimates. Linux is exercised by the test suite; macOS behavior, especially date and text-editing utilities, is not certified by these checks.


## Where this came from

- [mattpocock/skills](https://github.com/mattpocock/skills) — grill to spec to tasks, batched questions
- [mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis) — specs and vocabulary in repo
- [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) — ladder and counted deletions
- [czm15053/write-notes-like-deepseek](https://github.com/czm15053/write-notes-like-deepseek) — rejected option, consequences with costs, checkable verification

What changed: questions triaged so most never reach user; architecture review in plain Markdown; three checks across two review agents; written for any harness, not one vendor.
