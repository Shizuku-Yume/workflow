---
name: flow-verify
description: >-
  Review change across three checks using two agent roles: built as asked, code
  quality, process followed. Use before merging or when user says "review this".
---

# Flow: Verify

Read `.workflow/CONVENTIONS.md` §2 and §7 first.

Three checks across two agent roles: `workflow-reviewer` covers what-was-asked and
code-quality; `workflow-process` covers process adherence.

This is the review behind `flow-implement`'s `standard` level. `quick` skips it;
`thorough` runs it and then `flow-architect`. `flow-close` runs it in effort mode
(below) over a whole effort.

## 1. Pin comparison point

When called from `flow-implement`: comparison point is task's exact Base commit recorded before implementation. Falling back to `main` strictly forbidden.

Standalone review invoked by user: use whatever user named (commit, branch, tag). If nothing named, default to `main` (or `origin/HEAD` if no `main`), say you assumed it, let them correct.

After a rebase: if the task branch was rebased since its Base commit was pinned (landing, `merge-strategy.md`), `git diff <Base commit>` now includes everything others landed in between. Compare against `git merge-base <main branch> HEAD` instead, or against the stacked `Base branch`, and say so. The Base commit stays in the task file as history.

Capture diff commands now, reuse everywhere:
```sh
git diff <point>                          # working tree vs comparison point
git diff <point>...HEAD                   # committed changes since point
git diff HEAD                             # uncommitted vs HEAD
git ls-files --others --exclude-standard  # untracked
git log <point>..HEAD --oneline           # commit history
```

Check comparison reference resolves to valid commit and combined change set (committed, staged, unstaged, untracked) is non-empty before spawning. When called from `flow-implement`, committed changes since baseline optional (work typically staged/unstaged before task commit). Final evaluated diff must be non-empty. Empty change set or bad baseline fails here, not inside review agents.

## 2. Gather what each axis needs

**Axis 1, built as asked** needs source of truth: spec, task file, or issue. From `flow-implement` the task file path is passed in; hand it to both agents. Look in commit messages, `.workflow/specs/`, `.workflow/tasks/`, or path user gave. If none, run axis as "no spec available" rather than inventing requirements.

**Axis 2, code quality** needs project standards: `.workflow/standards.md`, plus repo files (`AGENTS.md`, `CONTRIBUTING.md`, lint config).

**Axis 3, process** needs `.workflow/standards.md` and `.workflow/decisions.md`: what project agreed to do, what was decided along way.

## 3. Spawn review agents

Two agent roles performing three checks: `workflow-reviewer` covers built-as-asked and code-quality; `workflow-process` covers process.

| Check / Axis | Agent Role | Needs |
| --- | --- | --- |
| 1. Built as asked | `workflow-reviewer` | diff commands, untracked files, commit list, spec or task text |
| 2. Code quality | `workflow-reviewer` | diff commands, untracked files, commit list, `.workflow/standards.md`, repo conventions |
| 3. Process followed | `workflow-process` | diff commands, untracked files, commit list, `.workflow/` |

Two subagent invocations enough. Give each agent diff commands, untracked file list, commit list, and the task file and spec paths in its task. They run commands themselves. Each marks every finding `blocking` or `nonblocking` (CONVENTIONS §7); those labels are theirs, not yours to change.

If agents not available (harness-specific agent directory, project may not have set up for yours), fall back to general-purpose subagent and paste relevant brief into task. Briefs in `.agents/agents/workflow-reviewer.md` and `.agents/agents/workflow-process.md`. Say in report you fell back.

## 4. Report

Report each axis with explicit status:
- `pass`: no finding the reviewer marked `blocking`
- `blocked`: one or more findings the reviewer marked `blocking` (correctness bug, missing deliverable, broken invariant, unrecorded substantial decision, security issue)
- `not-run`: axis couldn't be evaluated (missing baseline or prerequisite)

One section per axis, findings as agent wrote them, lightly cleaned. Then one line per axis with status, how many findings, worst one *within that axis*. Never single overall verdict averaged across axes.

Clean axis is information: mark `pass` and state that rather than leaving blank.

End with honest one-liner: is this ready, if not what's shortest path. If any axis `blocked` or `not-run`, change **not ready**. Evaluated diff must be non-empty.

Final evaluated diff must match change being released. If review fixes alter scope, update task or rerun affected axis rather than silently committing different change.

## 5. Then what

Fix findings or hand to user, per CONVENTIONS §7: only the user waives a blocking finding (decision entry, `Mine: no`); a nonblocking one you disagree with gets a `Mine: yes` entry so the next review doesn't raise it again.

Don't re-run whole review after fixing unless asked. A fix that stays in the lines the finding named: check the specific thing that was wrong. A fix bigger than that: send only the fix delta back to the same agent role (CONVENTIONS §7 says how to isolate it).

When `flow-implement` called this, return to `flow-implement` for final steps: archive task to `.workflow/done/<effort>/` and commit code, docs, archive move together. When `flow-close` called this, return to it.

## Effort mode

`flow-close` runs this review over a finished effort. What changes:

- **Comparison point:** the `Base commit` of the effort's earliest-started archived task. Other efforts may have landed since then, so also pass the effort's own commit list, `git log --format='%h %s' <point>..HEAD -- .workflow/done/<effort>/`, and tell the agents to judge those commits, not everything in the range.
- **Axis 1** is judged against the spec ("What it does", "What it must not do", the W-numbered checks), not against any one task. A behavior the spec promises that no task delivered is the finding this mode exists for.
- **Axis 2** looks at how the tasks fit together: the same helper written twice by two tasks, names that drifted between them, an interface one task changed and another still uses the old way.
- **Axis 3** checks that spec and glossary match the finished code, and that decisions tagged with the effort are honoured or superseded.

The working tree is clean here, so the diff is committed history only; a non-empty commit list is the precondition instead of a non-empty working-tree diff.
