# Workflow Conventions

Shared reference for the `flow-*` skills. Read only the section the current step needs. `.workflow/standards.md` overrides this file.

## 1. Ask or decide

Search code, tests, configs, docs, and git history before asking. Never invent product requirements.
- **Reversible details:** pick a sensible default and move on.
- **User-owned choices** (goals, scope, risk, costly trade-offs): ask in batches of up to 5, most impactful first, each with options and `My pick: <option>, because <reason>`.
- **Logging:** add a choice to `decisions.md` only when it is costly to reverse and a real alternative was rejected.

## 2. File layout

```
AGENTS.md                        workflow block points here
.agents/skills/<name>/SKILL.md   skill steps
.agents/agents/<name>.md         review agents
.workflow/
  bin/workflow                   project CLI
  bin/workflow-core.py           validate and next (Python 3 stdlib)
  CONVENTIONS.md                 this file
  STYLE.md                       writing and reporting rules
  standards.md                   project commands, layout, and Landing mode
  glossary.md                    project terms
  decisions.md                   append-only decision log
  technical-debt.md              tracked code debt
  specs/<effort>.md              spec for multi-task efforts
  tasks/<effort>/<NN>-<slug>.md  open task files
  research/<slug>.md             durable research notes cited by specs and tasks
  done/<effort>/                 archived tasks and closeout.md
  worktrees/<effort>-<NN>/       parallel task worktrees (root configurable, §7)
  .gitignore                     local-only state: worktrees/, HANDOFF.md
```

- Run `.workflow/bin/workflow <command>` from the repo root. Keep `standards.md` under one screen.
- An `<effort>` groups `tasks/<effort>/`, `done/<effort>/`, and an optional `specs/<effort>.md`. A spec has `**Status:** proposed | in progress | done`, `**Priority:** critical | high | normal | low`, and optionally `**Integration branch:**` (§7). Edit specs in place when facts change.
- `decisions.md` is append-only; its header defines the entry format. Its optional `**Effort:**` names the effort a decision belongs to. `decisions.md` and `glossary.md` use git union merge, so concurrent additions may interleave; cite by date and title. `Revisit when` is consumed by `flow-grill` (a request that meets a recorded condition reopens that decision as a question) and `flow-architect`.
- **Evidence:** `standards.md` names one directory (`Evidence: <path>`) for check logs, screenshots, and receipts. It may be in the repo, gitignored, or outside it; `Check after` cites paths there (§2.1), never `/tmp` or another temporary directory.
- `workflow init` installs the pre-commit `validate` hook (`--no-hook` opts out; a fresh clone runs `workflow hook install`) and writes `.workflow/.gitignore`. When a global `workflow` and the project's copy differ in version, the CLI says so on stderr: run `workflow update`.
- Run `git status --short` before editing. Never touch or stage files that were already dirty without asking; stage with `git add -- <paths>`.

### 2.1 Task files

`workflow validate` checks these fields. The template is in `flow-break`.
- **Path and heading:** `tasks/<effort>/<NN>-<slug>.md` with `# <NN>: <Title>` (at least 2 digits); cite as `<effort>/<NN>`.
- **Required:** `Effort` (slug `[a-z0-9]+(-[a-z0-9]+)*`), `Blocked by` (`None`, or a comma list of `NN` / `<effort>/NN`), `Check` (command and expected result, or a `## Check` section).
- **Optional:** `Delivers`, `Files`, `Read first`, `- [ ]` items, `Task type` (`feature` by default, `bugfix`, `refactor`, `spike`), `Covers` (spec `W` IDs), `Base commit`, `Base branch` (an unlanded blocker's branch to build on), `Status` (`active | paused | blocked`), `Resources` (comma list of `Shared resources:` names, §7).
- **Proof lines** in `## Progress`:
  - `Check before: <result>` — the state before the change.
  - `Check after: <result>` — the result of running `Check` on the final code. It is the Check's own result, cites receipts in the Evidence directory (`standards.md`), and never a temporary path. A placeholder (`n/a`, `not run`, `todo`, `skipped`) is no result at all, and a narrower observation (build passes, boot log) does not satisfy a Check that asked for more.
  - `Check waived: <reason; who; date>` — the user waived the Check; replaces `Check after`.
  - `Review: <outcome> <detail>` — the `flow-verify` outcome; the last `Review:` line wins. The first word is the outcome, case-insensitive: `pass`, `blocked`, `skipped`, or `waived`, and `skipped`/`waived` need a reason after it. Canonical: `pass (base <sha>)`, `blocked (base <sha>)`, `skipped — <reason>`, `waived — <finding>; user, <YYYY-MM-DD>` (§5).
- **Proof by task type**, recorded as those lines:
  - `bugfix`: fails before, passes after.
  - `refactor`: passes before and after.
  - `feature`: passes after, plus one run through the real entry point.
  - `spike`: runs a bounded experiment to answer an open question; keeps throwaway code off main, and archives on `## Findings` instead of `Check after:`.
- **Progress is state, not a log:** keep proof lines, root cause, and handoff state; collapse superseded attempts to one line each; long logs go to the Evidence directory. A spec states the contract; dated remediation journals belong in tasks or research notes.
- Tests using mocks verify only isolated logic. Check behavior that depends on external services or real runtimes against those real environments, and note what remains mocked.
- **Archive:** tick the `- [x]` items, drop `Status`, move the file to `done/<effort>/`, and run `workflow validate`. The file needs a non-placeholder `Base commit`, a `Check after` or `Check waived` with a real result, and a `Review:` line; spikes need `## Findings`. A complete checklist left under `tasks/` is unarchived: `workflow next` lists it until `workflow task archive` moves it.

## 3. Sizing and routing

Size by blast radius and ease of revert, after reading the direct callers:
- **Question:** answer directly.
- **Small change or bugfix:** edit, run tests and a real-path check, then commit (§6 for bugs, `security-reviewer` at trust boundaries). No task file and no `flow-verify`. Log in `decisions.md` only if a temporary shortcut was taken; open a `bugfix` task if the root cause remains.
- **1–3 clear tasks:** `flow-break` → `flow-implement`. No spec and no `flow-close`.
- **Multi-task or contract/schema/boundary change:** `flow-spec` → `flow-break` → `flow-implement` → `flow-close`.
- **Unclear scope or open trade-offs (any size):** run `flow-grill` first, then follow the matching path above.

| Situation | Skill |
|-----------|-------|
| Start, resume, or lost context | `flow-start` |
| Unclear requirements or open trade-offs | `flow-grill` |
| Multi-task design settled; needs a spec | `flow-spec` |
| Clear scope or settled spec; needs task files | `flow-break` |
| Ready task or queue to build | `flow-implement` |
| Review changes before landing | `flow-verify` |
| Last task of a spec effort landed | `flow-close` |
| A session hit avoidable friction | `flow-retro` |
| High change friction or code debt audit | `flow-architect` |

**Unknowns.** `flow-grill` settles what the code and the user can answer in chat. An unknown that needs an experiment becomes a `spike` task. One that spans sessions becomes a research note at `.workflow/research/<slug>.md`: durable notes (audits, prior art, experiment results) that specs and tasks cite in `Read first`. Unresolved items are `- [ ]` under `## Open questions`; `workflow next` lists notes that still have some. Tick or remove settled questions; delete a note only when nothing cites it.

**Reference acceptance.** When the work ports or must match a reference (upstream version, design mock, previous behaviour), at least one spec `W` check compares against the reference itself, not an item list derived from it.

**Replan.** When a plan assumption fails, or the same `Check` fails twice for any task type, set `Status: blocked`, add `## Blocked` (assumed vs. observed, decision needed), update the spec or `decisions.md`, and run `flow-break` amend. Fix the plan instead of coding around it.

## 4. State and handoff

Plan in one session when practical; implement from committed files. Resume `paused` tasks before starting new ones. A new task under a `done` spec returns it to `in progress`.

`workflow next` reports current state: started and ready tasks, efforts ready to close, checklists complete but unarchived, specs without tasks, open research questions, shared-resource overlaps, and stale worktrees. `--brief` condenses each to one line.

**Handoff.** Before pausing or leaving an unfinished task, set `Status: paused`, record verified work, failed attempts, the branch or worktree, and the next step under `## Progress`, then commit. If working without a task file, record the same state in `.workflow/HANDOFF.md` instead (gitignored, left uncommitted; `flow-start` loads and removes it on resume).

## 5. Review

Never review a change in the context that wrote it. `flow-verify` runs the reviewers (`.agents/agents/`):
- `workflow-reviewer` checks requirements and code quality. One fresh subagent per change; split into two only for large cross-module diffs.
- `security-reviewer` runs only when the change touches auth, secrets, untrusted external input, network exposure, or permissions.
- Findings are `blocking` or `nonblocking`. Only the user can waive a `blocking` finding; record it as `Review: waived — <finding>; user, <YYYY-MM-DD>` in the task, not in `decisions.md`.
- **Record:** the outcome is the last `Review:` line in `## Progress` — `pass (base <sha>)`, `blocked`, `skipped — <reason>`, or `waived — <finding>; user, <date>`. Closeout also lists tasks with `Check waived` or `Review: skipped|waived`.
- **Degraded mode:** never review inside the authoring context. If a reviewer subagent cannot be spawned or fails to run, record `Review: skipped — <reason>` and tell the user. `flow-close` reviews every task marked `skipped` before the effort can close; a spec-less effort's final report lists them.
- **Review-fix cap:** cap review-fix cycles at 2 rounds. If blocking findings remain after two rounds, stop: do not continue looping. Escalate to the user with the findings and evidence. The user decides whether to waive the finding (recorded as `Review: waived …` in the task), provide direction, or mark the task blocked/paused for replanning.

## 6. Fixing bugs

1. **Reproduce** with the exact command or input. If it won't reproduce, report that and stop.
2. **Pin** it with a failing check or test.
3. **State the root cause** in one or two lines (`## Progress` or the commit message).
4. **Fix the cause** and any sibling callers with the same flaw.
5. **Verify** the check passes and the real path works. When the same `Check` fails twice, stop guessing and replan (§3).

## 7. Branches and parallel work

`Landing:` in `standards.md` selects one mode:
- `direct`: commit on the current branch.
- `local-merge`: cut `<effort>/<NN>-<slug>` (or `small/<slug>`, `hotfix/<slug>`) from the landing branch, merge locally after verification, then delete the branch and its worktree.
- `pr`: push the task branch and land through a pull request; `git fetch` first.

Rules for every mode:
- Commit planning docs on the landing branch before cutting task branches.
- Before landing, check whether the landing branch moved (`git merge-base <landing branch> HEAD`). If it did, rebase and rerun the checks.
- **Integration branch:** when tasks cannot land on main one at a time, the spec sets `**Integration branch:** <effort>/integration`. Tasks branch from and merge into it; `flow-close` lands it on main.
- **Worktrees:** one worktree per task (`git worktree add <worktrees>/<effort>-<NN> -b <effort>/<NN>-<slug> <landing branch>`). `<worktrees>` is `Worktrees:` in `standards.md`, default `.workflow/worktrees/`, ignored via `.workflow/.gitignore`. Then `git worktree remove <worktrees>/<effort>-<NN>` after landing. `workflow next` names stale worktrees whose branch is already merged; remove them.
- **Shared resources:** a thing only one task can use at a time (device, fixed port, GUI app, license seat) is named under `Shared resources:` in `standards.md` with how to claim and release it. Tasks that need it list it in `Resources:`; tasks sharing one run one after another, and `workflow next` reports overlaps among ready tasks.
- Never share a worktree. Subagents run `Check` before returning; the main session confirms `Check`, the real-path run, and `flow-verify` before landing.

## 8. Keep implementations lean

Report every real bug reachable in supported use; keep the fix minimal.
- **Reuse first:** check repo code → stdlib → platform → installed dependencies before writing new code.
- **Threat model:** assume a trusted local user unless `standards.md` or an exposed interface accepts untrusted input. Skip guards for impossible local states.
- **No dead weight:** no speculative caching, guards for impossible states, single-use interfaces, passthrough wrappers, or unrequested flags and compatibility layers.
- **Checks:** skip rerunning checks when inputs haven't changed; never skip the task `Check` or the real-path run before landing.
