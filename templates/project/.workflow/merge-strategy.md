# Merge and Branch Strategy

How finished work reaches the main branch, how a task is claimed, and when a
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
once, fast-forward the main branch, delete the task branch. Nothing is pushed, so
it suits one person, with parallel tasks in separate worktrees.

**`pr`** — one branch per task as above, pushed, merged through a pull request.
The task is landed when its PR is merged. Push and open the PR as the last step of
`flow-implement`. Use it whenever several people share a remote: pushed task
branches are how they see each other's claims.

## Work without a task file

Small tasks and hotfixes (CONVENTIONS §4) land by the same mode. Under `direct`,
commit on the current branch. Under `local-merge` and `pr`, branch from the main
branch as `small/<slug>` (a hotfix: `hotfix/<slug>`) and land it like a task
branch. There is nothing to archive. A hotfix still leaves its follow-up `bugfix`
task (CONVENTIONS §4).

## Claiming a task and where its state lives

Under `local-merge` and `pr`, the task branch is the claim, and the started task's
file (`Status`, `## Progress`, `## Blocked`) lives on that branch until it lands.
`.workflow/bin/workflow next` reads task branches, local and remote, and lists those
tasks as paused, needing replanning, in progress or finished-not-landed instead of
ready; under `pr`, `git fetch` first so teammates' branches show. A branch that
exists for a task you are not resuming means someone else has it. To resume a
paused or blocked task, check out its branch. Under `direct` there is one working
tree and the task file's `Status` is the whole story.

## Dependent tasks

A task starts only when every blocker is archived under `.workflow/done/<effort>/`
and has landed on the main branch.

Under `pr` a dependent may stack instead of waiting: branch from the blocker's
branch and record `**Base branch:** <blocker branch>` in the task file. When the
blocker merges, rebase the dependent onto the main branch and drop the
`Base branch` line. Under `local-merge`, landing takes minutes, so wait.

## Base commit

`flow-implement` records `Base commit: <sha>` before the first edit. It is the
comparison point for `flow-verify`, never changes during implementation, and stays
in the task file as history. If the main branch moves ahead, don't rebase until
landing.

After a rebase the Base commit is still an ancestor, but `git diff <Base commit>`
now also contains everything that landed in between. A review rerun after a rebase
compares against `git merge-base <main branch> HEAD` instead.

## Merge style

Rebase and fast-forward (or rebase-merge on the hosting side): linear history, each
task one commit, easy to bisect. Squash-merge is the fallback. Task work gets no
merge commits.

## Rebase and conflicts

1. `git fetch origin` (under `pr`)
2. `git rebase <main branch>` (or `origin/<main branch>`)
3. Resolve conflicts, `git rebase --continue`
4. Rerun the test suite, the task's Check, and the real path once
5. Under `pr`: `git push --force-with-lease`

The whole `flow-verify` doesn't rerun after a rebase: the change itself hasn't
moved. The Check and the real path do, because a rebase can break behaviour
without a textual conflict. If conflict resolution changed the task's own lines,
that resolution is a fix: CONVENTIONS §7 decides whether it goes back to the
reviewer.

## Protection rules

Recommended for the main branch under `pr`: require PR review and status checks
(tests, lint); no force push, no deletion.
