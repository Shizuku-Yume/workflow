---
name: flow-verify
description: >-
  Review change with two briefs of the workflow-reviewer agent: built as asked
  (with evidence and process), and code quality. Use before merging or when user
  says "review this".
---

# Flow: Verify

Read `.workflow/CONVENTIONS.md` §2 and §7 first.

Run two independent `workflow-reviewer` invocations by default so neither sees the
other's conclusions (or one combined A+B invocation for a localized leaf task with no
trust boundary, no contract/spec change, and ≤3 files / mechanical batch, CONVENTIONS §7):

1. **Built as asked, and process** — requirements, evidence, documents,
   decisions, leftovers, and scope.
2. **Quality** — correctness, callers, maintainability, and security.

This backs every `flow-implement` level (`thorough` adds `flow-architect`).
`flow-close` uses effort mode below.

## 1. Pin comparison point

For `flow-implement`, use the task's exact Base commit recorded before work;
never silently substitute `main`. Standalone, use the user's commit, branch, or
tag; if none is named, use `main` (or `origin/HEAD` without `main`) and state it.

After a rebase or landing (`merge-strategy.md`), use
`git merge-base <landing branch> HEAD` (or the stacked Base branch), avoiding
intervening landed work. Keep the original Base commit in task history.

Capture and reuse:

```sh
git diff <point>; git diff <point>...HEAD; git diff HEAD
git ls-files --others --exclude-standard; git log <point>..HEAD --oneline
```

Confirm the point resolves to a commit and committed, staged, unstaged, and
untracked changes are non-empty before spawning agents. A bad point or empty
change set is a prerequisite failure, not an agent finding.

## 2. Gather brief inputs

Brief A receives the `flow-implement` task file; otherwise use commit messages,
`.workflow/specs/`, `.workflow/tasks/`, or the user's path. With none, say “no
spec available” and do not invent requirements; also read relevant `.workflow/`
documents, decisions, and debt. Brief B receives `.workflow/standards.md` and
repository conventions (`AGENTS.md`, `CONTRIBUTING.md`, lint configuration).

## 3. Spawn independent reviewers

Give each agent the commands, untracked-file list, commit list, task/spec paths,
and named brief (two parallel invocations by default, or one combined A+B pass when the
CONVENTIONS §7 leaf fast-path applies); agents run commands themselves. Ask each to state the comparison point,
paths, and any trust boundaries reviewed; record the base SHA, briefs run, and blocking
outcomes in `## Progress` per CONVENTIONS §7. Do not review unchanged tasks or code.

| Brief | Role | Inputs |
| --- | --- | --- |
| A. Built as asked, and process | `workflow-reviewer` | diff, commits, task/spec, `.workflow/` |
| B. Quality | `workflow-reviewer` | diff, commits, standards, conventions |

If unavailable, use a general-purpose subagent with the brief in
`.agents/agents/workflow-reviewer.md`, and say so in the report.

## 4. Report statuses and findings

Each brief has one status: `pass` (no `blocking` finding), `blocked` (one or
more blocking findings), or `not-run` (prerequisite/baseline prevented review).
Give each a section of lightly cleaned findings, then one line with status,
count, and worst finding. Do not average briefs. End `ready` or `not ready` and
the shortest path; any `blocked` or `not-run` means not ready.

## 5. Recheck fixes

Apply or hand off findings per CONVENTIONS §7. Fix all findings from both briefs together,
then rerun affected checks once. Rerun a reviewer brief only for a `blocking` fix or a fix
that adds files, callers, sinks, or deliverable changes (CONVENTIONS §7). Keep
findings/waivers; if
scope changes, update the task and rerun the affected brief. Return to the caller
for remaining steps.

## 6. Effort mode

`flow-close` reviews a finished effort. Run Brief A over the effort (Brief B is optional
when requested); reuse task review records in `## Progress` and skip tasks whose code has
not changed since review. Focus on uncovered commits,
post-review changes, and assembly checks.

Assembly always checks every spec ID (pass/fail/not-runnable), “What it does,”
and “What it must not do”; the integration diff from the true effort base
(earliest Base or merge-base with main); cross-task interfaces/callers;
generated/config/schema/API compatibility; and aggregate trust boundaries,
including the §7 security pass when non-empty. Use `flow-close`'s point and
listed commits, not later landed work. Judge Brief A against the whole spec,
glossary, and W-checks, and ensure effort decisions are honored or superseded.
With a clean tree, a non-empty listed commit set is the precondition.
