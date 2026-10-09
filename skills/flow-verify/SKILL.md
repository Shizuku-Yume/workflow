---
name: flow-verify
description: >-
  Review change across three checks using two agent roles: built as asked, code
  quality, process followed. Use before merging or when user says "review this".
---

# Flow: Verify

Read `.workflow/CONVENTIONS.md` §2 and §7 first.

Three checks across two agent roles: `workflow-reviewer` covers built-as-asked and
code quality; `workflow-process` covers process. This is the review behind every
`flow-implement` level (`thorough` adds `flow-architect` after it). `flow-close`
runs it in effort mode (below).

## 1. Pin comparison point

From `flow-implement`: the task's exact Base commit, recorded before implementation.
Never fall back to `main`.

Standalone: whatever the user named (commit, branch, tag). If nothing, use `main`
(or `origin/HEAD` if there is no `main`), say you assumed it, let them correct it.

After a rebase (landing, `merge-strategy.md`), `git diff <Base commit>` also
contains everything others landed in between. Compare against
`git merge-base <main branch> HEAD`, or the stacked `Base branch`, and say so. The
Base commit stays in the task file as history.

Capture the diff commands once and reuse them:
```sh
git diff <point>                          # working tree vs comparison point
git diff <point>...HEAD                   # committed changes since point
git diff HEAD                             # uncommitted vs HEAD
git ls-files --others --exclude-standard  # untracked
git log <point>..HEAD --oneline           # commit history
```

Confirm the point resolves to a commit and the combined change set (committed,
staged, unstaged, untracked) is non-empty before spawning agents. From
`flow-implement` the work is usually still uncommitted; that is fine. A bad point or
an empty change set fails here, not inside the agents.

## 2. Gather what each axis needs

**Axis 1, built as asked:** the source of truth. From `flow-implement` the task file
path is passed in; hand it to both agents. Otherwise look in commit messages,
`.workflow/specs/`, `.workflow/tasks/`, or the path the user gave. With none, run
the axis as "no spec available" rather than inventing requirements.

**Axis 2, code quality:** `.workflow/standards.md` plus repo conventions
(`AGENTS.md`, `CONTRIBUTING.md`, lint config).

**Axis 3, process:** `.workflow/standards.md` and `.workflow/decisions.md`.

## 3. Spawn review agents

| Check / Axis | Agent role | Needs |
| --- | --- | --- |
| 1. Built as asked | `workflow-reviewer` | diff commands, untracked files, commit list, spec or task text |
| 2. Code quality | `workflow-reviewer` | diff commands, untracked files, commit list, `.workflow/standards.md`, repo conventions |
| 3. Process followed | `workflow-process` | diff commands, untracked files, commit list, `.workflow/` |

Two invocations. Give each agent the diff commands, untracked file list, commit
list, and the task file and spec paths; they run the commands themselves. Their
`blocking` / `nonblocking` labels stand (CONVENTIONS §7).

If the named agents aren't available in this harness, use a general-purpose
subagent with the brief pasted in (`.agents/agents/workflow-reviewer.md`,
`.agents/agents/workflow-process.md`), and say in the report that you fell back.

## 4. Report

Each axis gets a status:
- `pass`: no finding the reviewer marked `blocking`
- `blocked`: one or more `blocking` findings
- `not-run`: the axis couldn't be evaluated (missing baseline or prerequisite)

One section per axis with the findings as the agent wrote them, lightly cleaned.
Then one line per axis: status, number of findings, worst one in that axis. No
overall verdict averaged across axes. A clean axis is reported as `pass`, not left
blank.

End with one line: ready or not, and if not, the shortest path. Any `blocked` or
`not-run` axis means **not ready**.

## 5. Then what

Fix the findings or hand them to the user, per CONVENTIONS §7 (waivers, rechecks
sized to the fix, findings kept). The reviewed diff must match the change being
released: if fixes alter scope, update the task and rerun the affected axis.

Called from `flow-implement` or `flow-close`: return to it for its remaining steps.

## Effort mode

`flow-close` runs this review over a finished effort. What changes:

- **Comparison point:** the `Base commit` of the effort's earliest-started archived
  task. Other efforts may have landed since, so also pass the effort's own commit
  list, `git log --format='%h %s' <point>..HEAD -- .workflow/done/<effort>/`, and
  tell the agents to judge those commits, not everything in the range.
- **Axis 1** is judged against the spec ("What it does", "What it must not do", the
  W-numbered checks), not one task. A behaviour the spec promises that no task
  delivered is the finding this mode exists for.
- **Axis 2** looks at how the tasks fit together: a helper written twice, names that
  drifted, an interface one task changed and another still uses the old way.
- **Axis 3** checks that spec and glossary match the finished code, and that
  decisions tagged with the effort are honoured or superseded.

The working tree is clean, so the diff is committed history only; a non-empty
commit list is the precondition instead of a non-empty working-tree diff.
