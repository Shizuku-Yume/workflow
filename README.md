# workflow

Task-driven workflow for coding agents: decide what to build, write it down, break it into tasks, build, review.

Installs into a project, not globally. Everything is committed with the project.

## Install

```sh
git clone https://github.com/Shizuku-Yume/workflow.git ~/tools/workflow
cd your-project
~/tools/workflow/bin/workflow init            # add --claude for Claude Code
```

Fill in `.workflow/standards.md` (or let `flow-start` fill it from the repository on first use). Commit what `init` lists.

The CLI is copied into the project as `.workflow/bin/` and committed with it, so teammates, CI and cloud agents need no toolkit checkout. `init`, `update` and `uninstall` copy from the toolkit, so run those from the checkout; everything else works from either copy.

Requirements: Bash 3.2 or newer (stock macOS is fine), git, python3, and the usual awk/sed (BSD or GNU).

**Claude Code** reads `.claude/skills/` and `CLAUDE.md`, not `.agents/` and `AGENTS.md`. `--claude` also installs the skills and review agents there and adds a `CLAUDE.md` block that imports `AGENTS.md`. It turns on by itself when the project already has `CLAUDE.md` or `.claude/`; `--no-claude` turns it off. Codex reads `.agents/skills/` and `AGENTS.md` directly.

| Command | Does |
| --- | --- |
| `workflow init [--claude]` | install into the current project |
| `workflow update` | re-copy skills, rules and CLI after toolkit changes; removes files the toolkit no longer ships |
| `workflow uninstall` | remove installed files, keep your documents |
| `workflow doctor` | report what's installed and missing; runs `validate` |
| `workflow hook install` | run `validate` before each commit; blocks on errors, warnings pass |
| `workflow validate` | check task files and the decision log (exit 0 valid, 1 warnings, 2 errors) |
| `workflow next` | ready tasks ranked by spec priority; started tasks (paused, blocked, in progress, finished on a branch) listed above them, never as ready |

`validate` and `next` take `--format json` and `--no-color`. Their report goes to stdout (pure JSON with `--format json`); usage errors and side warnings go to stderr. Everything else in `.workflow/` is plain Markdown that agents read and grep directly.

## What it installs

```
AGENTS.md                     workflow block pointing to the rules
.agents/skills/flow-*/        nine workflow steps
.agents/agents/workflow-*.md  review agents
CLAUDE.md, .claude/           with --claude: import of AGENTS.md, skills, agents
.gitattributes                union merge for decisions.md and glossary.md
.workflow/
  bin/                        the CLI, committed with the project
  CONVENTIONS.md              the rulebook
  STYLE.md                    writing guide
  phase-boundaries.md         when to continue, clear, compact or delegate
  merge-strategy.md           landing modes, task claims, rebase
  spike-tasks.md              exploratory work
  standards.md                project-specific rules (yours)
  glossary.md                 vocabulary (yours)
  decisions.md                decision log (yours)
  technical-debt.md           architecture findings (yours)
  specs/<effort>.md           what to build, with Status and Priority
  tasks/<effort>/<NN>-<slug>.md
  maps/  done/<effort>/
```

Skills and agents are copied, not linked. Managed files carry markers; `update` skips files you edited, with a warning (`--force` overrides).

## The skills

| Skill | Does | Output |
| --- | --- | --- |
| `flow-start` | Load context, classify the request, route | routing decision |
| `flow-grill` | Align on what to build, questions in batches | `decisions.md`, `glossary.md` |
| `flow-spec` | Write the design down | `specs/<effort>.md` |
| `flow-break` | Cut into session-sized tasks, one review of spec and tasks, commit the plan | `tasks/<effort>/<NN>-<slug>.md` |
| `flow-implement` | Build, prove, review, archive, commit, land | code, docs, `done/<effort>/` |
| `flow-verify` | Three checks across two review agents, per task or per effort | report |
| `flow-close` | Check a finished effort against its spec, demo, retrospective | `done/<effort>/retrospective.md` |
| `flow-architect` | Find expensive-to-change code | report, `technical-debt.md` |
| `flow-map` | Plan foggy work one question at a time | `maps/<slug>.md` |

Where each rule lives, and which wins when two disagree, is in `CONVENTIONS.md`: the user's current instruction, then `standards.md` and the repository's own conventions, then CONVENTIONS, then STYLE.

- **Small tasks** skip grill, spec, break and verify but still run the tests and prove the change works (CONVENTIONS §4). They land on a `small/<slug>` branch or directly, as `Landing:` says.
- **When the plan is wrong**, the task is marked `Status: blocked`, the spec is fixed, and `flow-break` amends the remaining tasks (CONVENTIONS §5).
- **Review levels:** `flow-implement <effort>/<NN>` runs `flow-verify`; add `thorough` to also run `flow-architect` on the touched area. A change crossing a trust boundary gets a security pass on every path (CONVENTIONS §7).
- **Landing:** `Landing:` in `standards.md` says how finished work reaches the main branch: `direct`, `local-merge` (default, one person) or `pr` (several people sharing a remote). Under the branch modes a started task's state lives on its branch, and `next` reads task branches, so claims, pauses and blocks show from the main branch (`merge-strategy.md`).
- **Efforts** are the slug that groups tasks. An effort with a spec ends with `flow-close`; one without (a lone bugfix, `maintenance`) is done when its last task lands.
- **Task references** are `<effort>/<NN>`: numbers are unique within an effort, not across efforts.

## Troubleshooting

**`.workflow` is missing.** Commands find the project root with `git rev-parse --show-toplevel`, or use the current directory outside git.

**Malformed files.** `validate` names the file, line and fix. `Blocked by` takes `None` or a comma-list of `NN` (same effort) and `<effort>/NN`; titles after the numbers are errors. Problems inside `done/` archives are warnings, so old history never blocks a commit. CRLF line endings are read like LF. Repair the Markdown and rerun `validate`.

**Running the tests.** `bash tests/cli-tests.sh` from the checkout runs the installer regression suite, the Python tests for `validate` and `next`, and `tests/skills_lint.py`, which checks that CONVENTIONS references resolve, skill steps are numbered without gaps, the examples in skills pass `validate`, and no document mentions removed commands. CI runs it on Ubuntu and macOS, plus a smoke test with stock macOS `/bin/bash` 3.2.

## Where this came from

- [mattpocock/skills](https://github.com/mattpocock/skills): grill to spec to tasks, batched questions, wide refactors as expand–contract, mechanical review findings turned into checks
- [mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis): specs and vocabulary in the repo, commits that leave other people's changes alone
- [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail): the ladder and counted deletions
- [czm15053/write-notes-like-deepseek](https://github.com/czm15053/write-notes-like-deepseek): the rejected option, consequences with costs, checkable verification

What changed: questions triaged so most never reach the user; one owner per status; plans fixed in the plan, not in code; architecture review in plain Markdown; three checks across two review agents; written for any harness, not one vendor.
