---
name: flow-implement
description: >-
  Build one task end to end or orchestrate a whole effort's DAG wave by wave. Use
  when user says "implement task 3", "implement <effort>", "do next task". Levels: standard (default) or thorough.
argument-hint: "<effort>/<NN> | <effort> [thorough]"
---

# Flow: Implement

Read the task file and the named spec sections. Read CONVENTIONS §2 (task files and
state), §6 (lifecycle and handoff), §7 (review), §8 (bug fixing), §9 (delegation),
and §10 (scope and proportionality). Read `merge-strategy.md` for branch and landing
rules, and `.workflow/STYLE.md` for the commit message and report. A task that depends
on the conversation that produced it is broken; repair that as part of the work.

Find facts in the code and work end to end. Stop only for a decision that changes what
gets built, or when the plan is wrong. Batch decision questions; do not ask for facts
the repository can provide. Bare `NN` is fine when only one effort has that number.

`standard` (default) runs `flow-verify`; `thorough` also runs `flow-architect` on the
touched area when the change is a large refactor or has many callers.

## 1. Start

For `spike`, also follow `.workflow/spike-tasks.md`; for `bugfix`, follow CONVENTIONS
§8. Apply CONVENTIONS §2 and `merge-strategy.md` for task state, dirty files, claims,
branches, base commit, dependencies, and landing. Do not restate those mechanics here.

For a new task, make the start record in `## Progress` before touching code: Base
commit (`git rev-parse HEAD`), Started (ISO 8601), Status active, and pre-existing
dirty paths (or `none`). On resume, preserve the recorded Base commit and restore the
state named by the task's handoff. A blocked task stays blocked; report it and stop.

Confirm blockers are archived and landed (or stacked as allowed by the merge strategy).
Reopen a `proposed` or `done` effort as `in progress` when required. Read the task,
spec, standards, relevant code and tests. If the task omits where to work or how to
check it, infer that from the repository and record the choice.

Run the project's clean-baseline command only when it settles a live uncertainty. Run
the task's Check before implementation and record `Check before:` plus its output or
why it cannot run. A feature or bugfix should fail; a refactor should pass; a spike
skips this gate. If a feature or bugfix passes, determine whether the task is already
done or the Check misses the behavior, then correct the Check or plan.

## 2. Build

Make the smallest change that delivers the task, including necessary callers, tests and
docs. Apply the minimalism ladder from CONVENTIONS §10 before custom code: need it,
existing project solution, standard library, native platform feature, installed
dependency, then the smallest clear implementation. Keep anti-overdefense in force:
do not add theoretical edge-case hardening, speculative flags or compatibility layers,
guards guarding guards, or checks that do not settle a supported-use risk. Report real
reachable defects; keep fixes proportional to the task.

Add only requested configurability, error handling and abstractions. For bugs, use the
§8 reproduce/pin/root-cause/sibling-check order. Keep the Check strict and make it
exist while writing the code. Run targeted checks as they settle live uncertainties;
do not rerun unchanged passing checks. Delete a fixed technical-debt entry in the same
commit.

## 3. Prove

Run the task's Check after the change and record `Check after:`. Exercise the real path
once and record what happened (UI, command, or real service); a stand-in proves only
the stand-in and does not discharge real-path proof. If the Check cannot pass, record
the blocker and keep it strict. Before every targeted check, state the uncertainty it
settles and what failure would change; skip unchanged reruns.

## 4. Sync documents and decisions

Before review, update facts in the spec, glossary or standards that no longer match,
and record durable lessons there. Log only decisions meeting CONVENTIONS §1.2 in the
format of `.workflow/decisions.md`, tagged `**Effort:** <effort>`; identify choices made
on the user's behalf with `Mine: yes` in the report.

## 5. Review

Run the §7 security pass when its trust-boundary trigger applies; otherwise record that
none applies. Run `flow-verify` with the task's exact Base commit and task-file path;
in `thorough`, then run `flow-architect` on the touched area. Record in `## Progress`
the reviewed base SHA, briefs run, brief statuses/findings, and every blocking outcome.

Handle findings under §7: fix one round together and rerun affected checks only. A
delta review is needed only for a blocking fix or a fix that expands the boundary.
Append unaddressed architect findings to `.workflow/technical-debt.md` under `## Entries`
using the required concrete symptom, Where, Added, Priority, Problem, Impact, Solution
and Cost fields. If a fix changes the deliverable, update the task and rerun its
affected brief.

## 6. Archive, commit and land

Apply CONVENTIONS §2 and `merge-strategy.md`: finish or justify every checklist item,
add Finished, remove Status, archive the task, validate it, stage only task paths,
commit code/tests/docs/decisions/archive together, and land it according to `Landing:`.
Do not stage `Dirty at start` paths. A final task in an effort with a spec proceeds to
`flow-close`; a spec-less effort ends here. Spikes record findings and keep throwaway
code off the landing branch.

## 7. Report

Use concise STYLE-compliant output. If unfinished, say so first, state what remains,
and leave the task unarchived and paused. For a regular task report concisely:
what works; Check before/after and real-path proof; review findings and disposition;
what was left out and when it matters; decisions made on the user's behalf (`Mine:
yes`) by heading, or `none`. For a spike report the question, finding, record location,
code kept or discarded, and decisions, or `none`.

## When the plan is wrong

The task or spec is wrong when an assumption contradicts observed code, it contradicts
itself, or it is several tasks. Follow CONVENTIONS §5: mark the task blocked with
assumed versus observed facts and the decision needed, preserve partial work on the
task branch or named stash, commit the task-file state as required, and route the
replan. Do not work around a broken plan.

## Pausing and resuming

When stopping before completion, follow CONVENTIONS §6: reconcile disk state, record
completed proof, failed routes and counterexamples, open findings, branch/worktree,
uncommitted-work location, and the exact next action in `## Progress`; set Status
paused and commit/push the task state as the merge strategy requires.

## Scope

Build the task as written. Report unrelated problems as candidate tasks. Decisions in
`.workflow/decisions.md` remain settled.

## Effort mode (`<effort>`)

When given `<effort>` without `/<NN>`, act as a lightweight coordinator (CONVENTIONS §9):
1. Run `.workflow/bin/workflow next --effort <effort> --all --format json`. Resolve any `paused` or `blocked` tasks before starting new ones.
2. Dispatch non-overlapping `ready_tasks` concurrently in separate worktrees (`../<repo>-<effort>-<NN>`); serialize tasks sharing paths in `file_overlaps` (or assign one shared-interface owner).
3. Harvest each finished subagent as soon as it returns — do not wait for the whole wave: verify `Check`, real path, and §7 review, archive and land on the landing branch, remove its worktree, and rerun `next --effort <effort> --all --format json` to dispatch newly unlocked tasks.
4. If a blocker stalls for two rounds without progress, take over the specific gap or run `flow-break` amend while keeping independent tasks moving. For multi-hour autonomous runs, schedule `.workflow/bin/workflow pulse --effort <effort> --quiet-idle` (e.g. `/loop 30m` where supported).
5. When no open tasks remain and all work has landed, run `flow-close <effort>` if `.workflow/specs/<effort>.md` exists; otherwise report completion.
