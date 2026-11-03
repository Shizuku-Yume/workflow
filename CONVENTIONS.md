# Workflow Conventions

Shared rules for `flow-*` skills. Read only the sections named by the active skill.

**Precedence:** user's current instruction → `.workflow/standards.md` and existing repo
conventions (`git log`, linter/formatter config, CONTRIBUTING) → this file → `STYLE.md`.
Asking to go faster cuts repetition (rerunning unchanged checks, re-reviews, replaying
history), never a task's `Check` or real-path verification unless the user names that
check explicitly.

---

## 0. Evidence before questions

Check the codebase before asking. Existing behaviour, patterns, APIs, constraints, and
config are yours to find via search, reads, or subagents. Interrupt the user only for
decisions they own: intent, scope, risk tolerance, acceptance criteria, and genuine
trade-offs.

---

## 1. Decision protocol

### 1.1 Momentum first
Momentum is part of the deliverable. Stalling on menus of options, re-confirming a clear
goal, or blocking main work on a cosmetic detail is itself a wrong choice. Non-blocking
details get noted, not solved first.

### 1.2 Triage before asking
Sort every open question into one bucket:
- **A — Look it up:** facts, conventions, prior decisions (§2), API behaviour. Resolve immediately.
- **B — Decide it (log if qualifying):** one option is clearly better, or choices are reasonable and reversible. Pick one and state the trade-off in one line. Log in `decisions.md` only when **all three** hold: hard to reverse, non-obvious to a future reader, and a real alternative lost. Routine naming and formatting never qualify.
- **C — Ask the user:** options genuinely diverge on what gets built, or reversal is expensive.

### 1.3 Batch and stop when unblocked
Batch independent Bucket C questions (max 6), ranked by what blocks the most work:
```
Q1 - <title>
   <2-3 sentences>
   Options: A | B | C
   My pick: <one>, because <one line>
```
Settled user answers need no recap approval; routine Bucket B picks need no approval. Stop
grilling as soon as the next step is unblocked.

---

## 2. File structure

```
AGENTS.md                        workflow block points here
.agents/skills/<name>/SKILL.md   the steps
.agents/agents/<name>.md         review agents
.workflow/
  bin/workflow                   the CLI, committed with the project
  bin/workflow-core.py           validate and next (python3, stdlib only)
  CONVENTIONS.md                 this file
  STYLE.md                       writing rules
  standards.md                   project-specific: commands, layout, Landing
  glossary.md                    vocabulary
  decisions.md                   choices made, with runner-up
  technical-debt.md              architecture findings to address
  merge-strategy.md              branches, landing, claiming tasks
  phase-boundaries.md            continue, clear, compact or delegate
  spike-tasks.md                 exploratory work guidelines
  specs/<effort>.md              what to build, for an effort that has a spec
  tasks/<effort>/<NN>-<slug>.md  one task each, in its effort's directory
  maps/<slug>.md                 multi-session planning
  done/<effort>/                 archived tasks, plus retrospective.md written by flow-close
```

**Efforts and specs.** An effort slug groups tasks (`tasks/<effort>/`, `done/<effort>/`).
Specs (`specs/<effort>.md`) are for multi-task or architecturally non-obvious efforts;
clear 1–3 task work, lone bugfixes, spikes, and `maintenance` skip `flow-spec` and
`flow-close` and go straight to `flow-break`. Spec header:
```
**Status:** proposed | in progress | done
**Priority:** critical | high | normal | low
**Integration branch:** <effort>/integration
```
`Priority` (optional, default `normal`; `urgent` aliases `critical`) lives only in the
spec header and ranks ready tasks in `next`. `Integration branch` is optional for efforts
that cannot land task-by-task (`merge-strategy.md`). Update specs in place when code
changes their facts.

**Core file rules:**
- Run `.workflow/bin/workflow <command>` from the repo root. Inspect active state via
  `.workflow/bin/workflow next`, recent entries + `grep` on `decisions.md`, and `technical-debt.md`.
- Keep `standards.md` under one screen.
- **Commit planning docs** (decisions, glossary, specs, maps, tasks) onto the landing
  branch before cutting task branches. Under `Landing: pr`, task 01 may stack on the
  planning PR branch (`Base branch:`, `merge-strategy.md`) instead of stalling until merge.
- `decisions.md` is append-only (five required fields defined in that file; cite as
  `decisions.md: <date> - <title>`). Reversals add `**Supersedes:** <old heading>` on the
  new entry and append `**Superseded by:** <new heading>` to the old one. Both
  `decisions.md` and `glossary.md` use git union merge.
- **Dirty files at start:** run `git status --porcelain` before starting work; record
  pre-existing paths as `Dirty at start: <paths|none>` in `## Progress` and never stage
  them (`git add -- <paths>`). Ask if the task needs to edit one.
- **Survivable evidence:** save Check logs/screenshots where `standards.md` specifies,
  never in temporary directories, and cite paths in `## Progress`.

### 2.1 Task files

Enforced by `workflow validate` (`flow-break` drafts, `flow-implement` executes/archives):
- Path `tasks/<effort>/<NN>-<slug>.md`, heading `# <NN>: <Title>` (at least two digits;
  cited as `<effort>/<NN>`).
- Required fields: `Effort` (`[a-z0-9]+(-[a-z0-9]+)*`), `Blocked by` (`None`, or comma
  list of `NN` / `<effort>/NN`), `Check` (command + passing signal, or `## Check`). A
  stand-in (mock/fixture) proves only the stand-in; real-service behaviour checks the real
  service or names the remaining stand-in.
- Expected from `flow-break`: `Delivers`, `Files`, `Read first`, and `- [ ]` checklist.
- `Task type:` (`feature` default | `bugfix` | `refactor` | `spike`): `feature`/`bugfix`
  Check fails before and passes after; `refactor` passes before and after with unchanged
  behaviour; `spike` answers a question (`spike-tasks.md`).
- Optional: `Base commit:`, `Started:`/`Finished:` (ISO 8601), `Status: active | paused | blocked`,
  `Covers:` (`W1, W3`), `Base branch:`.
- Sections: `## Progress`, `## Blocked` (§5), `## Findings` (spikes).
- Archiving: move to `done/<effort>/` in the same commit as code/docs with all checklist
  items ticked (or deleted with reason in `## Progress`) and `Check after:` recorded
  (`## Findings` for spikes). Run `.workflow/bin/workflow validate` after task/decision edits.

---

## 3. Writing

`.workflow/STYLE.md` governs all human-facing output and clean-deliverable rules. Repo
conventions take precedence.

---

## 4. Task sizing

Judge by **blast radius and reversibility**, not file count (editing a core type used by
20 modules is not small; touching 3 leaf files with clear behaviour may be). Read direct
callers before locking classification; upgrade and route through §5 if a change breaks a
public contract, persisted schema, or architectural boundary.

- **Trivial** — question or clarification. Answer directly.
- **Hotfix** — live user-facing degradation/outage AND localized understood fix AND waiting
  is riskier than skipping process. Fix and verify on the failing surface immediately, run
  the §7 security pass, and before ending the session record: (1) `## <date> - Hotfix: <title>`
  in `decisions.md` (`Decided`, `Instead of`, `Because`, `Mine: yes`, `Revisit when`), and
  (2) a follow-up `Task type: bugfix` task citing that entry. If it cannot be written
  honestly, reclassify.
- **Small task** — single clear behaviour change or bugfix, no architectural trade-off,
  revertable in <5 minutes. Skips `flow-grill`, `flow-spec`, `flow-break`, and
  `flow-verify`; still checks dirty files (§2), reads callers, runs tests + real-path
  proof, follows §8 for bugs, runs the §7 security pass when triggered, and lands per
  `merge-strategy.md`.
- **Complex** — everything else. Clear 1–3 task work needing no durable spec goes straight
  to `flow-break`; multi-task or architecturally open work uses the earliest incomplete
  step in §5.

---

## 5. Skill routing

| Situation | Skill |
|-----------|-------|
| Session start, context lost, or next step unclear | `flow-start` |
| Vague requirements, open trade-offs, or port/migration behaviour mapping | `flow-grill` |
| Too foggy to plan; questions depend on unanswered questions | `flow-map` |
| Multi-task or non-obvious design settled, needs a durable spec | `flow-spec` |
| Spec or clear 1–3 task scope needs task files (including non-small bugfixes) | `flow-break` |
| Task file ready to build | `flow-implement` |
| Task is `blocked`, or spec/task proved wrong | replan (below) |
| Review finished work | `flow-verify` |
| Last task of an effort **with a spec** has landed | `flow-close` |
| Code expensive to change / debt audit | `flow-architect` |

Take the earliest incomplete step that applies. Announce in one line before auto-entering
`flow-break`, `flow-close`, or `flow-architect` since they write shared planning/close records.

**Replan (no workarounds or over-correction).** When a plan assumption fails, mark the
task `Status: blocked` with `## Blocked` (assumed vs observed + decision needed), update
the spec/decisions (`flow-grill` only if user-owned), and run `flow-break` amend across
remaining tasks. Repair the specific broken assumption — do not discard a sound overall
direction over one local flaw.

---

## 6. Lifecycle

| Object | States | Owner |
|--------|--------|-------|
| Map `maps/<slug>.md` | `charting` → `working` → `clear` | `flow-map` |
| Spec `specs/<effort>.md` | `proposed` → `in progress` → `done` | `flow-spec` (`proposed`) → `flow-implement` (`in progress`, including reopen) → `flow-close` (`done` after explicit user acceptance) |
| Task `tasks/<effort>/<NN>-<slug>.md` | drafted → `active` → (`paused` \| `blocked`) → archived | `flow-break` (drafts / clears `blocked`) → `flow-implement` (`active`, `paused`, `blocked`, archives without `Status`) |
| Debt in `technical-debt.md` | listed → removed | Added on discovery; deleted in the fixing commit, or deleted + logged in `decisions.md` (`Mine: no`) if declined |

**Single source of state.** Task state lives in its task file, effort state in its spec
header, ready queue in `next`. An effort without a spec finishes when its last task lands.
Adding a task to a `done` spec resets it to `in progress` in the same commit, and the next
`flow-close` appends `## Reopened <date>` to `retrospective.md`. Resume `paused` work
before starting new tasks.

**Grounded handoff (pause or session switch).** Before setting `Status: paused` (or
handing off mid-phase), reconcile claims with actual disk state and record in `## Progress`:
completed work + verified checks (do **not** rerun passing checks on unchanged inputs just
for handoff), routes tried that failed + concrete counterexamples (so the next session
skips dead ends), open review findings, branch/worktree, uncommitted work location (tree
or `<effort>/<NN> paused` stash), and the exact next action. Commit the paused task file on
its branch (and push under `pr`) so `next` sees it. When switching sessions with **no**
active task file (mid-`flow-grill`, `flow-architect`, or cross-effort planning), write
`.workflow/HANDOFF.md` (objective/constraints, verified disk facts, failed routes, next
action); `flow-start` reads it and deletes it once absorbed.
---

## 7. Review

Shared across `flow-verify`, `flow-implement`, `flow-close`, and fast paths. Reviewer
criteria live in `.agents/agents/workflow-reviewer.md` and `security-reviewer.md`.

- **Security pass:** runs whenever a change touches a trust boundary (auth/authz,
  credentials/secrets, untrusted input reaching shell/query/path/URL/process/renderer,
  listeners/egress, permissions/sandbox). Reviews the **boundary closure** (changed lines +
  direct callers/callees at the boundary), not the whole diff. State boundaries reviewed
  or one line if none apply.
- **Two briefs vs leaf single-pass:** run Brief A and Brief B as two independent
  `workflow-reviewer` invocations by default. For a localized leaf task (no trust boundary,
  no contract/spec change, ≤3 files or a mechanical migration batch), `flow-verify` may run
  a single `workflow-reviewer` invocation covering both A and B.
- **Verdicts stand:** reviewers label findings `blocking` or `nonblocking`. Only the user
  waives `blocking` (logged in `decisions.md` with `Mine: no`). Declining `nonblocking`
  logs `Mine: yes` only if §1.2 applies.
- **Proportional rechecks (no review loops):** fix a round's findings together and rerun
  affected checks. In-scope fixes that add no new files, callers, sinks, or deliverable
  changes need **no** reviewer rerun. Run one delta review round only for `blocking` fixes
  or fixes that expand the boundary. Record the reviewed base SHA, briefs run, and
  blocking outcomes in `## Progress` so `flow-close` skips re-reviewing unchanged tasks.

---

## 8. Fixing bugs

For every non-hotfix bug (fast path or `bugfix` task):
1. **Reproduce** and record command, input, and failure output (if irreproducible, report what was tried and stop).
2. **Pin** with the smallest failing check (`Check` or fast-path test).
3. **Name the root cause** in 1–2 sentences (`## Progress` or commit body). Symptom-only patching is a hotfix (§4).
4. **Fix cause + check siblings:** inspect every other caller and copy of the faulty logic.
5. **Prove green + real path.** Still red? Revert and return to step 3 — never stack fixes on failed guesses. After two failed attempts, stop and create a `spike` task to find the cause.

Fixing the same bug class twice in `maintenance` or fast path buys an automated check
(test, lint, CI guard) in that same change.

---

## 9. Delegation

Delegating moves work, never proof:
- **Owner proves the task:** the session archiving a task verifies `Check` before/after,
  real-path execution, and §7 review on the assembled result. Never defer a task's `Check`
  to a downstream gate without a user decision (`Mine: no`).
- **Isolated trees and state:** subagent briefs name the absolute worktree path, task
  file, and owned paths; subagents verify `git rev-parse --show-toplevel` before editing
  and never share working trees, ports, DBs, or evidence paths in parallel.
- **Coordinator pace:** a multi-task coordinator (`flow-implement <effort>`) queries
  `.workflow/bin/workflow next --effort <effort> --all --format json`, dispatches
  non-overlapping ready tasks in parallel worktrees (serializing `file_overlaps`), harvests
  and lands each finished subagent deliverable immediately without waiting for the batch,
  and launches newly unblocked tasks. If the same blocker survives two rounds without
  progress, take over the gap or re-slice via `flow-break` amend while independent tasks
  continue. On multi-hour autonomous runs, use `.workflow/bin/workflow pulse --quiet-idle`
  to prevent rule drift; after compaction or resume, reread `next` and active task files.

---

## 10. Scope and proportionality (Anti-OverDefense)

Agents fail by turning *"could improve confidence"* into *"must be built and checked"*,
fortifying around the feature instead of shipping it. **Bound what you propose and build,
never what you look for:** report any real defect reachable through supported use, then
keep implementation and fixes proportional.

- **Minimalism ladder:** before writing custom code, check in order: (1) does this need to
  exist at all? (2) already in this codebase? (3) in the standard library? (4) native
  platform feature (`<input type="date">`, CSS, DB constraint)? (5) already-installed
  dependency? Only then write the smallest clear implementation.
- **HERO calibration (examples, not a dismissal checklist):**
  - `H` (Hashing): hashing spreadsheet rows when cell comparison answers it, or writing checksums nothing reads → **skip**.
  - `E` (Edge cases): hardening accounts on a local tool with no users/deployment, or guarding theoretical symlink/ms races unreachable via supported inputs → **skip**.
  - `R` (Rubrics): auditing a patch in loops instead of shipping, or a reviewer manufacturing findings on clean code → **skip**.
  - `O` (Overbuild): guards guarding guards, single-implementation interfaces, or flags/compat layers for unrequested futures → **skip**.
  - `✓` (Keep/Report): a digest that skips re-reading a large file; a rare-looking input that the project's own docs or public API actually produce → **real value / real bug, act on it**.
- **Check gate:** before running any check or suite, name the live uncertainty it settles
  (including bounded blast-radius checks when changing shared contracts) and what you
  would do differently on failure. Rerunning a suite that already passed against untouched
  code is theatre; skip it.
