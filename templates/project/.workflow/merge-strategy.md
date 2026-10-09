# Merge and Branch Strategy

Default branch and merge policy for the workflow. If this project works
differently (direct commits to main, merge commits, no PRs), say so in
`.workflow/standards.md`; standards.md wins over this file.

## Branch Model

**Main branch:** `main` (or `master`)
- Always deployable
- Protected: requires review
- Direct commits forbidden

**Feature branches:** `<effort>/<NN>-<slug>`
- One branch per task
- Created from current main
- Deleted after merge

**Hotfix branches:** `hotfix/<description>`
- Created from main
- Merged directly to main
- Follow-up proper solution as separate task

## Task Base Commit

When starting a task:
1. `flow-implement` records `Base commit: <sha>` before first edit
2. This SHA is the comparison point for `flow-verify`
3. Base commit never changes during implementation

**During implementation:**
- If main moves ahead: don't rebase until ready to merge
- Continue working on your base
- `flow-verify` compares against your Base commit, not current main

**Before merge:**
- Rebase onto current main
- Base commit stays unchanged (it's historical record)
- Resolve conflicts
- Re-run tests (not full review)
- Merge

**Why this works:**
- Review sees exactly what you changed from your starting point
- No confusion about "what changed while I worked"
- Conflicts handled at merge time, not during review

## Merge Strategy

**Preferred:** Rebase and merge
- Linear history
- Each task = one or few commits
- Easy to bisect

**Alternative:** Squash and merge
- Single commit per task
- Clean history
- Loses intermediate commits

**Never:** Merge commits for feature work
- Makes history hard to follow
- Reserve for hotfixes only

## Conflict Resolution

When rebasing onto main:
1. `git fetch origin`
2. `git rebase origin/main`
3. Resolve conflicts
4. `git rebase --continue`
5. Re-run test suite
6. Force push: `git push --force-with-lease`

**Don't re-run flow-verify after rebase** — your changes haven't changed, only their position in history.

## Protection Rules

Recommended branch protection for main:
- Require PR review
- Require status checks (tests, lint)
- No force push
- No deletion
