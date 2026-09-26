---
name: flow-verify
description: >-
  Review a change on three axes at once: does it do what was asked, is the code
  any good, and did the work follow this project's process. Use before merging,
  when the user says "review this", "check my work", "did I miss anything",
  "review since main", or when flow-implement calls it after building a task.
---

# Flow: Verify

Read `.workflow/CONVENTIONS.md` first (§2 for where things live).

Three separate reviews of the same change, run as parallel subagents so their
findings do not contaminate each other, then reported side by side.

They are separate on purpose. Code can follow every convention and build the wrong
thing, or build exactly the right thing in a way nobody can maintain, or be
perfectly good work that skipped the evidence this project agreed to produce. A
change that fails one axis has failed; do not average the three into a verdict.

## 1. Pin the comparison point

Whatever the user named: a commit, a branch, a tag. If they named nothing, ask
once. Capture the command now and reuse it everywhere:

```sh
git diff <point>...HEAD      # three dots: compares against the merge base
git log <point>..HEAD --oneline
```

Check the reference resolves and the diff is not empty before spawning anything.
An empty diff or a bad reference should fail here, not inside three subagents.

## 2. Gather what each axis needs

**Axis 1, built as asked** needs the source of truth: the spec, the task file, or
the issue. Look in commit messages, `.workflow/specs/`, `.workflow/tasks/`, or a
path the user gave. If there is none, run this axis as "no spec available" rather
than inventing requirements.

**Axis 2, code quality** needs the project's standards: `.workflow/standards.md`,
plus whatever the repo already has (`AGENTS.md`, `CONTRIBUTING.md`, lint config).

**Axis 3, process** needs `.workflow/standards.md` and `.workflow/decisions.md`:
what this project agreed to do, and what was decided along the way.

## 3. Spawn the review agents

Use the project's review agents, not a general worker. They are read-only, they
have their own briefs, and they will not start editing your files.

| Axis | Agent | Needs |
| --- | --- | --- |
| Built as asked, and code quality | `workflow-reviewer` | the diff command, the commit list, the spec or task text, `.workflow/standards.md` |
| Process followed | `workflow-process` | the diff command, the commit list, `.workflow/` |
| Security, when it applies | `security-reviewer` | the diff command, the commit list |

Give each one the diff command and commit list in its task. They run the diff
themselves.

The security pass is conditional: run it when the diff touches authentication,
authorisation, input that reaches a query, a shell, or a filesystem path, secrets,
cryptography, or a trust boundary in either direction. Say explicitly whether you
ran it, so nobody assumes it happened.

If those agents are not available in this harness, fall back to a general-purpose
subagent, and paste the relevant brief into its task: for the reviewer, the
standards file and the change; for the process check, the five things it must
look at (evidence, stale documents, decisions, leftovers, scope). Say in the
report that you fell back.

## 4. Report

One section per axis, findings as the agent wrote them, lightly cleaned. Then one
line per axis: how many findings, and the worst one *within that axis*. Never a
single overall verdict across axes.

A clean axis is information: say so in its section rather than leaving it blank.

End with the honest one-liner: is this ready, and if not, what is the shortest
path to it being ready.

## 5. Then what

Fix the findings, or hand them to the user. A finding the user rejects gets one
line in `.workflow/decisions.md` so the next review does not raise it again.

Do not re-run the whole review after fixing a finding unless asked. Check the
specific thing that was wrong.

When `flow-implement` called this, go back there for the remaining steps: update
the documents the change made stale, commit, and archive the task.
