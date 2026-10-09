# Changelog

What changed in each version and what an existing project has to do about it.
Usage lives in the README and in `--help`.

## 2.5.0

Lighter: fewer files, fewer commands, fewer stops, no Bash 4. Plus the gaps a
review against Trellis and mattpocock/skills turned up.

### Upgrade

From the toolkit checkout, in each project:

```sh
~/tools/workflow/bin/workflow update
git add .workflow .agents AGENTS.md .gitattributes && git commit    # plus .claude CLAUDE.md with the Claude adapter
```

- **Runtime:** Bash 3.2 or newer (stock macOS now works without Homebrew), git
  and python3. `validate` and `next`, and therefore the pre-commit hook, run on
  python3.
- **Efforts:** effort definitions are gone. For each `.workflow/efforts/<slug>.md`,
  copy its `Priority:` into the header of `.workflow/specs/<slug>.md` (rename the
  spec to the effort's slug if it differs), then `git rm -r .workflow/efforts`.
  Goal, scope and success criteria already live in the spec.
- **Hotfixes:** each open hotfix entry should have a `Task type: bugfix` follow-up
  task whose `Read first` names it; draft the missing ones. Entries already marked
  `resolved` stay as history.
- **technical-debt.md** is yours, so `update` leaves it alone. When convenient,
  move to the flat format in the new template: drop the status sections and IDs,
  delete resolved items, and turn accepted ones into decision entries.
- **standards.md** is yours too. The template no longer has "Where things go"
  or the tracker sentence; delete them from yours if you like.
- `update` deletes the old CLI files in `.workflow/bin/` and `.workflow/thinking.md`
  when you haven't edited them.

### Changes

- **Six commands removed:** `tasks`, `deps`, `decisions`, `effort`, `debt` and
  `hotfix-review`, with the shell completions. Agents read the Markdown directly:
  the end of `decisions.md` plus `grep`, `technical-debt.md`, and `next` for tasks.
  The CLI is `init`, `update`, `uninstall`, `doctor`, `hook`, `validate`, `next`.
  `validate --fix` is gone because CRLF files now parse like LF and are no longer
  reported; `next --interactive` is gone too. Removed commands and options say so
  and exit 2.
- **`validate` prints its report on stdout,** like other linters, so it pipes into
  `grep` or `less`; `--format json` keeps stdout pure JSON. Usage errors and side
  warnings stay on stderr. Scripts that read the 2.4 report from stderr need to
  switch.
- **No Bash 4.** `bin/workflow` runs on Bash 3.2; `validate` and `next` moved to
  `bin/workflow-core.py` (stdlib only). The CLI went from eleven Bash files (about
  4,700 lines) to two files (about 2,700 lines).
- **Effort merged into spec.** The spec (`specs/<effort>.md`) carries `Status` and
  `Priority` and is an effort's only state machine. Two parallel lifecycles moved
  by the same skills at the same moments became one.
- **`flow-close` only for efforts with a spec.** A lone bugfix or `maintenance`
  task no longer triggers a demo and a retrospective.
- **Plans get committed.** Planning skills commit what they wrote before any task
  branch is cut. Before, task files could ride into the first task's commit, and
  archiving an untracked task file with `git mv` failed.
- **Other people's changes stay out of your commits.** A task records the paths
  already dirty when it started and stages its own paths by name; `git add -A` is
  gone from the review rules.
- **Refactor tasks** have a Check that passes before and after, instead of being
  told to fail first.
- **Small tasks have a landing rule:** `small/<slug>` under `local-merge` and `pr`.
- **Precedence is written down:** the user's instruction, then `standards.md` and
  the repository's own conventions (commit style from `git log`), then
  CONVENTIONS, then STYLE. STYLE no longer bans `chore:` in repos that use it.
- **Hotfixes are tracked by their follow-up task,** not by a command and a field
  rewrite. `decisions.md` is now strictly append-only apart from `Superseded by`.
- **Technical debt is a flat list.** An entry is deleted by the task that fixes
  it, or by a decline recorded as a decision.
- **One plan review.** When spec and breakdown happen in one session, the user
  approves both at once instead of twice.
- **Union merge** for `decisions.md` and `glossary.md` (`.gitattributes`), so
  branches that each add an entry don't conflict.
- **Brownfield start:** `flow-start` fills `standards.md` placeholders from the
  repository and asks once.
- **Retrospectives prefer checks to rules:** a mechanical pattern becomes a lint
  rule, test or CI step; only a judgement call becomes a line in `standards.md`.
- **Wide refactors** are planned expand → migrate in batches → contract.
- **A failed fix is reverted,** not built on: back to the root cause.
- **Smaller always-loaded text:** the AGENTS.md block is a short set of pointers
  and invariants; `flow-implement` reads only the CONVENTIONS sections it uses;
  `quick` is gone (trivial work is a small task); `thinking.md` was folded into
  `flow-grill`; `phase-boundaries.md` and `STYLE.md` were cut down to rules.

## 2.4.0

### Upgrade

From the toolkit checkout, in each project:

```sh
~/tools/workflow/bin/workflow update
git add .workflow .agents AGENTS.md && git commit    # plus .claude CLAUDE.md with the Claude adapter
```

`standards.md` is yours, so `update` doesn't touch it. Add a `Landing:` line
(see the new "Branches and landing" section in the template). Without one,
tasks land as `local-merge`: a branch per task, fast-forwarded into the main
branch locally. Projects that commit straight to the main branch should write
`Landing: direct`.

### Changes

- **A wrong plan gets fixed in the plan.** `flow-implement` used to stop with
  "report it" and nothing after. Now the task gets `Status: blocked` and a
  `## Blocked` section, the spec is fixed (through `flow-grill` when a decision
  is open), and `flow-break` has an amend mode that goes through every remaining
  task of the effort. `workflow next` no longer offers a `Status: blocked` task;
  it reports it under its own blocker.
- **`flow-close`, the ninth skill.** Tasks were each checked against their own
  baseline, and nothing checked that they added up to the spec. `flow-close`
  runs the spec's checks against the finished effort, reviews it with
  `flow-verify` in its new effort mode, demos it to the user, revisits the
  effort's `Revisit when` conditions, writes the retrospective, and settles
  statuses. Spec checks get IDs (`W1`, `W2`); tasks list the ones they make pass
  in `Covers`, and `flow-break` checks every ID is covered or left to the close.
- **Every status has an owner.** Spec, effort, map and task statuses are in one
  table (CONVENTIONS §6) that says which skill moves each one. Before, nothing
  moved a spec out of `proposed` or an effort out of `planning`, and nothing
  wrote `paused` or `blocked`.
- **Paused tasks carry a handoff.** `## Progress` in the task file says what is
  done, the next step, open review findings, and where uncommitted work is, so a
  fresh session can resume without the old conversation.
- **Building always goes through a task file.** `flow-spec` no longer suggests
  skipping `flow-break` for one-session work, which left `flow-implement` and
  `flow-verify` without a task or Base commit. A one-task breakdown skips the
  review round.
- **Bugs have a procedure** (CONVENTIONS §8): reproduce, failing check, root
  cause written down, fix, check sibling callers. Unknown causes get an
  investigation spike first. A hotfix now also leaves a `bugfix` task for the
  proper fix.
- **Checks must fail first.** `flow-implement` runs the task's Check before
  building and records `Check before` and `Check after` in `## Progress`.
- **Review rules in one place** (CONVENTIONS §7). Reviewers mark findings
  `blocking` or `nonblocking`; only the user waives a blocking one. Fixes larger
  than the finding go back to the reviewer as a delta. The security pass runs on
  every path, small tasks and hotfixes included, instead of only at `standard`.
  "Capture what the task taught" moved before the review so the process reviewer
  sees those document edits.
- **Landing modes.** The default branch model (branch per task) combined with
  "don't push unless told to" left finished tasks on branches nobody merged, so
  their dependents never became ready. `Landing: direct | local-merge | pr`
  decides, `flow-implement` lands as its last step, a task branch is the claim
  on a task, `pr` allows stacking with `Base branch`, and reviews after a rebase
  compare against the merge base.
- **One task at a time,** instead of one task per session, which
  `phase-boundaries.md` contradicted. What matters is not interleaving tasks.
- **Small-task tripwires.** Classification is provisional; changing a public
  interface or persisted data, adding a dependency, reaching a third module, or a
  third decision upgrades the task on the spot.
- **What gets written down gets read.** Reversed decisions get a
  `Superseded by` pointer; `flow-start` surfaces unresolved hotfixes and fix-now
  debt; `flow-break` looks for debt in the area it touches; the retrospective
  records plan versus actual and turns repeated review findings into
  `standards.md` rules; `flow-implement` reports the decisions it made on the
  user's behalf.
- **One routing table.** `flow-start` had its own copy of CONVENTIONS §5 and the
  two had started to differ.

## 2.3.0

### Upgrade

From the toolkit checkout, in each project:

```sh
~/tools/workflow/bin/workflow update          # --claude to add the Claude Code adapter
git add .workflow/bin && git commit
```

Optional: move tasks into their effort directory, one `git mv` per task, e.g.
`git mv .workflow/tasks/03-cache.md .workflow/tasks/api-v2/03-cache.md`. Tasks
left directly under `tasks/` keep working.

### Changes

- **The CLI is committed with the project.** `init` and `update` copy `bin/`
  into `.workflow/bin/`, and the skills call `.workflow/bin/workflow`. Before
  this, the skills called `workflow` from PATH, which only existed on the
  machine that ran `init`. An edited CLI file is kept on `update` unless
  `--force`, like an edited skill.
- **Claude Code adapter.** `--claude` installs the skills into
  `.claude/skills/`, the review agents into `.claude/agents/` (with Claude Code's
  capitalised tool names), and a `CLAUDE.md` block that imports `AGENTS.md`. On
  by default when the project already has `CLAUDE.md` or `.claude/`.
- **Tasks live in `tasks/<effort>/`.** Numbers were already per effort, but all
  efforts shared one directory, so `01-setup.md` in two efforts collided.
  `validate` now errors when a task's directory and `Effort` disagree, and
  `effort rename` moves the directory.
- **Every command finds tasks the same way.** `tasks` and `next` read only the
  top level of `tasks/` while `deps`, `effort` and `validate` read
  subdirectories, so a nested task was counted by one and invisible to another.
  All of them use `wf_task_files` in `workflow-lib.bash` now.
- **`doctor` runs `validate`** instead of a second, 250-line copy of the task
  and decision checks that disagreed with it (doctor rejected tasks without
  `Base commit`, which CONVENTIONS calls optional, and rejected lowercase
  `none`, which every other command accepts). Validate errors count as doctor
  problems; validate warnings are shown but don't fail it. `validate` took over
  the one check only doctor had: heading number vs filename number. Doctor's
  draft/started count now goes by a real `Base commit` or `Started`, not by the
  absence of the `<commit-sha>` placeholder.
- **Tasks are named `<effort>/<NN>` everywhere,** with at least two digits.
  `deps` printed `demo/1`, `next` printed `[1] [demo]`, `tasks` printed
  `1 [demo]`. This also changes the `dependency` strings in
  `next --format json` (`core/7` is now `core/07`); task `number` fields stay
  numeric. `tasks` no longer prints `Status: N/A` for tasks that were never
  interrupted.
- **`workflow hook install`** writes a pre-commit hook that runs `validate` and
  blocks on errors only. It won't overwrite a hook it didn't write.
- **`effort create` works for an effort that tasks already name.** It refused
  with "already exists" as soon as any task named the effort, which is the
  order flow-break uses and the fix `validate` suggests.
- **Rules have one home.** The small-task and hotfix criteria were written out
  in the README, CONVENTIONS §4 and flow-start, and the README copy had already
  lost the rollback criterion. They live in CONVENTIONS §4 now, together with
  the hotfix decision entry fields; the others point there.
- **Fixes found by running on macOS for the first time.** `workflow update` always
  failed there with "could not prepare the AGENTS.md workflow block": BSD awk
  rejects a multi-line `-v` value, so the block now goes through the
  environment. `workflow debt add` and `debt list --format json` failed with an
  awk syntax error from an unparenthesised `?:` inside `printf`.
- CI on Ubuntu and macOS (macOS with the system awk, so BSD awk is covered).
  `ENHANCEMENTS.md` became this file.

## 2.2.0

Published in one commit together with 2.1.0.

- Eight CLI commands: `tasks`, `deps`, `decisions`, `effort`, `debt`,
  `hotfix-review`, `validate`, `next`, with JSON output where it makes sense,
  Bash and Zsh completion, and a test suite.
- Effort definitions (`efforts/<slug>.md`), technical-debt tracking, merge
  strategy and spike-task guides.
- `flow-start`, the eighth skill.

## 2.1.0

- `thinking.md` (first-principles decomposition) and `phase-boundaries.md`
  (continue, clear, compact, switch session, or delegate).

## 2.0.0

- Project-local install: skills and rules are copied into the project and
  committed with it.
- `STYLE.md`, `flow-implement`, and the two review agents.
- Seven skills.

## Before 2.0

- The first six skills: grill, spec, break, verify, architect, map.
