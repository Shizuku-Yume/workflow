# Merge and Branch Strategy

How finished work reaches the main branch, how a task is claimed, and when a
dependent task may start. `.workflow/standards.md` picks the landing mode with
`Landing:`; where the two disagree, standards.md wins.

The main branch is `main`, or `master` if that is what exists, unless
standards.md names another. The landing branch is where a task lands: the main
branch, or the effort's integration branch when its spec names one (below).

## Landing modes

**`direct`** — commit straight onto the current branch. No task branches. Suits
one person working in one tree; there is no parallel work to protect.

**`local-merge`** (default) — one branch per task, `<effort>/<NN>-<slug>`, cut from
the landing branch. After committing, compare `Base commit` with the current landing
branch `HEAD`. Only if the branch moved ahead, rebase and rerun the test suite, Check,
and real path once. Fast-forward on the landing branch (in its other worktree if needed),
remove any separate task worktree, then delete the task branch. Nothing is pushed.

**`pr`** — one pushed branch per task, merged by pull request. It lands when merged;
open the PR as `flow-implement`'s last step. Use when people share a remote so task
claims are visible.

Landing needs a clean tree. If the landing tree has unclaimed changes, stop and ask
whose they are; moving work elsewhere leaves the landing branch stale.

## Integration branch

For an effort whose tasks can't land on the main branch one at a time without
leaving it broken or half-switched (a migration, an engine swap, a cutover that
works only once every caller has moved), or when the main branch must stay
releasable while many parallel tasks land. Under `local-merge` and `pr` only.

- `flow-break` names it in the spec header (`**Integration branch:**
  <effort>/integration`), commits the plan on the main branch, then cuts the branch
  from that commit. Later plan changes for the effort are committed on it.
- Task branches are cut from it and land on it as they would on the main branch.
  A task archived on the integration branch has landed; its dependents start.
- When the main branch moves, merge it into the integration branch (never rebase a
  branch others build on) and rerun the tests; always do it before `flow-close`.
- `flow-close` runs on the integration branch. Once the user accepts, it lands on the
  main branch: fast-forward if the main branch has not moved since the last merge,
  else a merge commit. Never replace the main branch's tree with the branch's: the
  task history is how the effort is audited. Then delete it and the landed task
  branches. Under `pr`, one PR lands it.
- `next` on the main branch shows the effort as one line naming the integration
  branch; on that branch, or on a task branch of the effort, it lists the tasks.

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

One task, one branch. A retry continues on the task's branch; starting over goes
through `flow-break` amend, which renames the old branch to `attempt/<effort>-<NN>`.
`next` names tasks that several branches claim.

Under `pr`, fetch before claiming. Commit the task's start record and push its branch
before building so teammates can see the claim; do not replace an existing claim.

## Worktrees

Only under `local-merge` and `pr`, and only when two tasks run at the same time:
one working tree holds one branch, so parallel tasks need one worktree each.

```sh
git worktree add ../<repo>-<effort>-<NN> -b <effort>/<NN>-<slug> <landing branch>
```

Name it after the task so a stray directory is traceable, and keep it beside the
repository, never in a temporary directory: it holds uncommitted work. `.workflow/`
is a relative path, so the new tree gets the task directory and the CLI with it;
nothing else needs copying. Land the task, then `git worktree remove <path>` before
deleting its branch. `git worktree prune` clears the records of trees deleted by
hand. Run `git worktree list` when you are unsure which tree is where.

Git refuses a branch that another worktree has checked out. That is the claim
(above) enforced by git rather than by convention: a second session cannot start a
task someone else holds. Under `direct` there is one tree and none of this applies.

## Dependent tasks

A dependent starts when its blockers are archived and landed. Under `pr`, it may instead
stack on a blocker's unmerged PR branch; record `**Base branch:** <blocker branch>`.
After that PR merges, rebase onto the landing branch and remove `Base branch`. This lets
task 01 proceed on a planning PR branch for doc-only plans. Under `local-merge`, wait.

## Base commit

`flow-implement` records `Base commit: <sha>` before editing; it remains history and is
the `flow-verify` comparison point. If the landing branch moves ahead, don't rebase until
landing. After rebase, update the review comparison point to
`git merge-base <landing branch> HEAD` (CONVENTIONS §7).

## Merge style

Rebase and fast-forward (or rebase-merge on the hosting side): linear history,
easy to bisect. Squash-merge is the fallback. Task work gets no merge commits; an
integration branch takes the main branch by merge and lands by fast-forward or one
merge commit.

## Rebase and conflicts

1. Under `pr`, fetch origin; rebase onto the landing branch (or its origin ref).
2. Resolve conflicts and continue. If the landing branch actually moved ahead since
   `Base commit`, rerun the test suite, Check, and real path once. Otherwise skip these
   redundant reruns: `Base commit` is already the landing branch `HEAD`.
3. Under `pr`, push with `--force-with-lease`.

The rebase alone does not require full `flow-verify`. Update the comparison point to
`git merge-base <landing branch> HEAD` (CONVENTIONS §7). If conflict resolution changed
task lines, treat it as a fix and apply §7 review rules.

## Protection rules

Recommended for the main branch under `pr`: require PR review and status checks
(tests, lint); no force push, no deletion.
