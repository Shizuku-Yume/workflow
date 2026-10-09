# Merge and Branch Strategy

How a finished task reaches the main branch, how a task is claimed, and when a
dependent task may start. `.workflow/standards.md` picks the landing mode with
`Landing:`; where the two disagree, standards.md wins.

The main branch is `main`, or `master` if that is what exists, unless
standards.md names another.

## Landing modes

**`direct`** — commit straight onto the current branch. No task branches. Suits
one person working in one tree; there is no parallel work to protect.

**`local-merge`** (default when `Landing:` is unset) — one branch per task,
`<effort>/<NN>-<slug>`, created from the main branch. After the task's commit:
rebase onto the main branch, rerun the tests, the task's Check and the real path
once, fast-forward the main branch, delete the task branch. Nothing is pushed.

**`pr`** — one branch per task as above, pushed, merged through a pull request.
The task is landed when its PR is merged. Push and open the PR as the last step of
`flow-implement`.

Hotfixes use `hotfix/<description>` under `local-merge` and `pr`, land the same
way, and leave a follow-up `bugfix` task (CONVENTIONS §4).

## Claiming a task

Under `local-merge` and `pr`, the task branch is the claim. Before starting,
`git branch -a --list '*<effort>/<NN>-*'`: if a branch exists and this session
isn't resuming it, someone else has the task. `Status: active` in the task file
is not a claim; other worktrees can't see it until it lands.

Under `direct` there is one working tree, so there is nothing to claim.

## Dependent tasks

A task starts only when every blocker is archived under `.workflow/done/<effort>/`
and has landed on the main branch.

Under `pr` a dependent may stack instead of waiting: branch from the blocker's
branch and record `**Base branch:** <blocker branch>` in the task file. When the
blocker merges, rebase the dependent onto the main branch and drop the
`Base branch` line. Under `local-merge`, landing takes minutes, so wait.

## Task Base Commit

1. `flow-implement` records `Base commit: <sha>` before the first edit.
2. It is the comparison point for `flow-verify`.
3. It never changes during implementation, and stays in the task file as history.

**During implementation:** if the main branch moves ahead, don't rebase until
landing. `flow-verify` compares against your Base commit, not the current main
branch.

**After a rebase** the Base commit is still an ancestor, but `git diff <Base
commit>` now also contains everything that landed in between. A review rerun after
a rebase compares against `git merge-base <main branch> HEAD` instead.

## Merge Strategy

**Preferred:** rebase and fast-forward (or rebase-merge on the hosting side).
Linear history, each task one commit, easy to bisect.

**Alternative:** squash and merge. One commit per task, intermediate commits lost.

**Never:** merge commits for task work.

## Conflict Resolution

When rebasing onto the main branch:
1. `git fetch origin` (under `pr`)
2. `git rebase <main branch>` (or `origin/<main branch>`)
3. Resolve conflicts, `git rebase --continue`
4. Rerun the test suite, the task's Check, and the real path once
5. Under `pr`: `git push --force-with-lease`

Don't rerun the whole `flow-verify` after a rebase: the change itself hasn't
moved. Do rerun the Check and the real path. A rebase can break behaviour without
a single textual conflict, when something the change relies on moved underneath
it. If conflict resolution changed the task's own lines, that resolution is a fix:
CONVENTIONS §7 decides whether it goes back to the reviewer.

## Protection Rules

Recommended for the main branch under `pr`:
- Require PR review
- Require status checks (tests, lint)
- No force push
- No deletion
