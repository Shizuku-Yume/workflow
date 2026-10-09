# Workflow Conventions

Shared rules for all `flow-*` skills. Read once per session.

---

## 0. Evidence before questions

Before asking ANY question: check if the codebase can answer it.

**Never ask about:**
- Current behavior, existing patterns, available APIs
- What the code does, how features work
- Technical constraints, dependencies, configurations

→ Investigate yourself: `grep`, `find`, `read`, dispatch subagents.

**Ask only about:**
- Product intent, user preference, scope
- Risk tolerance, acceptance criteria
- Choosing between options when multiple work

---

## 1. Decision protocol

### 1.1 Facts are yours to find
If it can be answered from the repo, docs, or search: find it. Only decisions the user owns may interrupt them.

### 1.2 Triage before asking
Every open question goes into one bucket:

**A - Look it up** — facts, conventions, prior decisions, what APIs do.

**B - Decide it, log if substantial** — you can name the clearly better option, or it's an implementation detail with no real stakes. Log it in `decisions.md` as a complete five-field entry when the choice affects scope, interfaces, compatibility, risk, or future maintenance. Routine naming/formatting/helper-reuse doesn't need logging.

**C - Ask the user** — the answer changes what gets built, the trade-off is real, you can't resolve it.

### 1.3 Ask in batches
Never drip questions. One round = all questions you can ask right now without inventing answers to other questions.

**Cap: 6 questions per round.** Format:
```
Q1 - <title>
   <question, 2-3 sentences>
   Options: A | B | C
   My pick: <one>, because <one line>
```

Rank by what blocks the most work. If explaining needs more than one screen, the real question is smaller.

### 1.4 Confirm before proceeding
Restate decisions as numbered list. User corrects or confirms. Silence is not agreement.

### 1.5 Stop when unblocked
Grilling has no finish line. Stop when no open decision would change the next step.

---

## 2. File structure

```
AGENTS.md                        workflow block points here
.agents/skills/<name>/SKILL.md   the steps
.agents/agents/<name>.md         review agents
.workflow/
  bin/workflow                   the CLI, committed with the project
  CONVENTIONS.md                 this file
  STYLE.md                       writing rules
  standards.md                   project-specific: commands, layout
  glossary.md                    vocabulary
  decisions.md                   choices made, with runner-up
  technical-debt.md              architecture findings to address
  merge-strategy.md              branch and rebase guidelines
  spike-tasks.md                 exploratory work guidelines
  efforts/<slug>.md              effort definitions and goals
  specs/<slug>.md                what to build
  tasks/<effort>/<NN>-<slug>.md  one task each, in its effort's directory
  maps/<slug>.md                 multi-session planning
  done/<effort>/                 archived tasks, plus retrospective.md written by flow-close
```

**Rules:**
- Run the CLI as `.workflow/bin/workflow <command>` from the project root. It is copied in by `workflow init`, committed, and needs nothing on PATH, so it works in every clone, in CI and in cloud agents.
- `standards.md` is the entry point. Keep it under one screen.
- One spec per effort, updated in place when code changes facts.
- `decisions.md` is append-only. Five fields required: `Decided`, `Instead of`, `Because`, `Mine`, `Revisit when`. Optional `**Effort:** <slug>` tags an entry to one effort so `.workflow/bin/workflow decisions --effort <slug>` can find it. Refer to an entry by its heading text: `decisions.md: <date> - <title>`.
- A reversal is a new entry carrying `**Supersedes:** <heading of the old entry>`. In the same change, append one line to the old entry, `**Superseded by:** <heading of the new entry>`; that line is the only edit an old entry ever gets besides `hotfix-review --mark-resolved`. An entry carrying `Superseded by` is history, not a rule: follow the pointer before acting on it.
- `technical-debt.md` tracks architecture findings. Use `.workflow/bin/workflow debt` command to manage.
- `merge-strategy.md` and `spike-tasks.md` are reference docs, rarely change. How finished work reaches the main branch (`Landing:` in `standards.md`), how a task is claimed, and when dependents may start are defined in `merge-strategy.md`.
- Effort definitions in `efforts/<slug>.md` track goal, scope, success criteria and priority. Optional, but `flow-break` creates one (`.workflow/bin/workflow effort create <slug>`) so `.workflow/bin/workflow next` can rank the effort's tasks.
- Tasks follow strict format:
  - Filename: `.workflow/tasks/<effort>/<NN>-<slug>.md`; heading `# <NN>: <Title>` (NN matches filename). The directory names the effort, so two efforts can both have `01-setup.md`. Files directly under `tasks/` (the layout before 2.3) are still read; move them with `git mv` when convenient.
  - `NN` is unique within an effort, not across efforts. Unambiguous reference: `<effort>/<NN>`, written with at least two digits.
  - Fields are `Name: value` lines, plain or bold (`**Effort:** <slug>`). Every `workflow` command reads them through one shared parser, so the spelling rules below are the same everywhere.
  - Required (`.workflow/bin/workflow validate` errors): `Effort` (lowercase slug `[a-z0-9]+(-[a-z0-9]+)*`, the same as the task's directory); `Blocked by` (`None`, or comma-list of `NN` (same effort) or `<effort>/NN` (cross-effort), numbers only, no titles); `Check` (command and the result that means it works, or a `## Check` section).
  - Expected from `flow-break`, not machine-checked: `Delivers`, `Files`, `Read first`, and the `Done when` checklist.
  - Optional: `Task type:` `feature | bugfix | refactor | spike` (default `feature`); `Base commit:` `<commit-sha>` when drafted, real SHA when started; `Started:`/`Finished:` ISO 8601 timestamps; `Status: active | paused | blocked` (§6 says who sets each); `Covers:` the spec check IDs this task makes pass (`W1, W3`); `Base branch:` the unlanded blocker branch a task was stacked on (`merge-strategy.md`).
  - Sections a task file may grow: `## Progress` (the Check result before the change, a bug's root cause, review findings and what happened to them, and the handoff when paused), `## Blocked` (why the plan under the task failed, §5), `## Findings` (spike answers).
  - The same problems inside `done/<effort>/` archives are warnings, not errors: history is not rewritten to satisfy today's checks.
- Archive to `done/<effort>/` before committing. Task archive, code, and docs land together in one commit.
- A blocker archived under `done/<effort>/` in HEAD is finished: `.workflow/bin/workflow next` stops counting it, so dependents become ready without rewriting their `Blocked by`.
- After writing or editing tasks or decisions, run `.workflow/bin/workflow validate`. Errors block; fix the file, not the validator.

---

## 3. Writing

`.workflow/STYLE.md` governs everything: chat, documents, commits, comments, UI text. Read it.

---

## 4. Task sizing

**Trivial** — question, clarification, greeting. Answer directly.

**Hotfix** — production outage or critical bug requiring immediate fix. ALL of these:
- System is degraded or down affecting users
- Fix is localized and well-understood
- Risk of not fixing immediately exceeds risk of skipping process

If any one fails (users are not affected now, the fix is unclear, it can wait
hours), it is a small or complex task instead.

Hotfix path: skip grill/spec/break/verify, fix immediately, verify where the
failure was observed. If you can't reach production, say so and hand that check
to the user. The security pass (§7) is not skipped.
**Mandatory follow-up before the session ends:** a decision entry in
`.workflow/decisions.md`:

- **Decided:** `Hotfix:` followed by the temporary fix applied
- **Instead of:** the proper solution (or "unclear, needs investigation")
- **Because:** why the immediate fix was necessary and the shortcuts justified
- **Mine:** yes
- **Revisit when:** when the proper fix or follow-up investigation happens

If that entry can't be written honestly (the fix wasn't localized, the risk
wasn't that high, it could have waited), it wasn't a hotfix: reclassify.

The `Hotfix:` prefix is the marker `.workflow/bin/workflow hotfix-review` relies
on; it also catches wording such as "temporary" or "workaround", but the prefix
is the contract. When the proper fix lands, run
`.workflow/bin/workflow hotfix-review --mark-resolved <id>` in the same commit.

**Also before the session ends:** draft the proper fix as a `Task type: bugfix`
task (§8) in the effort that owns the code, or in effort `maintenance` when none
does, with `Read first` naming the hotfix entry. A hotfix with no follow-up task
is only remembered when somebody happens to run `hotfix-review`.

**Small task** — ALL of these:
- Single behavior change or bug fix
- Impact radius: change affects <3 modules' behavior
- Requirements clear
- No architectural decisions
- Rollback cost: can revert in <5 minutes if wrong

When unsure between small and complex, it is complex: under-planning genuinely
unclear work costs more than over-planning it.

Small tasks skip `flow-grill`, `flow-spec`, `flow-break`, `flow-verify`. Still require: reading code, running tests, proof, commit message. A bug follows §8 on the fast path too. The security pass (§7) is not skipped.

Impact radius matters more than file count: changing a core type definition in 1
file but affecting 20 modules is not small. Adding an isolated utility touching 5
files but affecting nothing else is small.

The first classification is a guess made before much code was read. Before
building, read the callers of what you will change; that is where impact radius
shows. Then, while building, any one of these makes the task complex on the
spot, mid-change included:

- a public interface, data shape, schema or persisted data has to change
- a new dependency is needed
- the change reaches a third module
- a third decision comes up, or one that changes what gets built

Stop, say which tripwire fired, keep what you have (uncommitted, or a named
stash), and route through §5. The work so far is input to the plan, not a
reason to skip it.

**Complex** — everything else. Run full workflow from earliest incomplete step.

---

## 5. Skill routing

This is the only routing table; `flow-start` and the skills point here.

| Situation | Skill |
|-----------|-------|
| Start of session, context lost, or next step unclear | `flow-start` |
| Vague requirements, design questions, or "grill me" | `flow-grill` |
| Too big or foggy to plan; questions depend on other unanswered questions | `flow-map` |
| Decisions settled, need writing down | `flow-spec` |
| Spec or settled conversation needs tasks (always, even for one task) | `flow-break` |
| Bug that is neither small nor a hotfix | `flow-break`: one `bugfix` task, behind a spike if the cause is unknown (§8) |
| Task file ready to build | `flow-implement` |
| A task is `Status: blocked`, or building showed the spec or task is wrong | replan (below) |
| Review finished work | `flow-verify` |
| Last task of an effort has landed | `flow-close` |
| Code expensive to change | `flow-architect` |

When two apply, take the earliest incomplete. If the user knows what they want,
skip ahead, but building complex work always goes through a task file: it carries
the Base commit, the Check and the archive that later steps rely on.

**Replan.** A plan that turns out wrong is fixed in the plan, not worked around in
code. The task that hit it gets `Status: blocked` and a `## Blocked` section
(`flow-implement` writes both). Then: `flow-grill` if the fix needs a decision only
the user can make, otherwise update the spec directly (with a decision entry when
§1.2 calls for one); then `flow-break` in amend mode goes through every remaining
task of the effort, because tasks written against the old spec may all be stale.

---

## 6. Lifecycle

Every status field has one owner. A skill that moves a status writes it in the
same change as the work that justified it. A status nobody moves makes `next`,
`tasks` and `effort` lie.

| Object | States | Who moves it |
|--------|--------|--------------|
| Map `maps/<slug>.md` | `charting` → `working` → `clear` | `flow-map`: `charting` when written, `working` when the first question is answered, `clear` when no question or fog is left |
| Spec `specs/<slug>.md` | `proposed` → `in progress` → `done` | `flow-spec` writes `proposed`; `flow-implement` sets `in progress` when the effort's first task starts; `flow-close` sets `done` |
| Effort `efforts/<slug>.md` | `planning` → `active` → `complete` | `flow-break` creates it (`planning`); `flow-implement` sets `active` when the first task starts; `flow-close` runs `effort complete` |
| Task `tasks/<effort>/<NN>-<slug>.md` | drafted → `active` → (`paused` or `blocked`) → archived | `flow-break` drafts it (no `Status`, placeholder `Base commit`); `flow-implement` sets `active` on start, `paused` when the session stops before it is done (handoff below), `blocked` when the plan under it is wrong (§5); `flow-break` amend clears `blocked`; `flow-implement` archives it to `done/<effort>/` and drops `Status` |

`.workflow/bin/workflow next` never offers a `blocked` task. A `paused` task is
offered and should be resumed before anything new starts.

**Pause handoff.** A paused task is resumed by a session that never saw the one
that paused it. Before setting `Status: paused`, `## Progress` must say: what is
done, the next concrete step, review findings still open, the branch or worktree,
and where uncommitted work is (left in the tree, or a stash named
`<effort>/<NN> paused`). If the next session would need this conversation to
continue, the handoff is incomplete.

---

## 7. Review

Rules every review path shares: `flow-verify`, the review step of
`flow-implement` at every level, `flow-close`, and the fast paths.

**Security pass.** Runs whenever a change touches authentication, authorisation,
input reaching a query or shell, secrets, file paths, or anything crossing a trust
boundary, on every path: small task, hotfix, `quick`, `standard`, `thorough`. Size
and intensity decide how much review runs; they don't decide whether a change that
crosses a trust boundary gets looked at. Use a security-review agent if the harness
has one, otherwise a general subagent briefed for it. When it doesn't apply, say so
in one line.

**The reviewer classifies.** Each finding comes back marked `blocking` or
`nonblocking` by the reviewer. The implementer does not reclassify.

**Only the user waives a blocking finding.** A blocking finding is fixed, or the
user accepts it, and that acceptance is a decision entry with `Mine: no`. The agent
that wrote the change cannot wave off a blocking finding on its own say-so. A
nonblocking finding the agent disagrees with gets a `Mine: yes` entry, so the next
review doesn't raise it again.

**Fixes get rechecked, sized to the fix.** Before fixing, stage the reviewed state
(`git add -A`); afterwards `git diff` plus
`git ls-files --others --exclude-standard` is exactly the fix. A fix that stays in
the lines the finding named is rechecked by running the thing that was wrong. A
fix that touches a file the finding didn't name, or changes more than about 30
lines, goes back to the same reviewer role with only that delta. Neither reruns
the whole review.

**Findings are kept.** Each blocking finding and what happened to it (fixed,
accepted with the decision heading) goes into the task's `## Progress`, so the
archived task carries its review history and `flow-close` can see patterns.

---

## 8. Fixing bugs

Every bug outside a hotfix goes this way: a small fix on the fast path and a
`Task type: bugfix` task alike.

1. **Reproduce.** Make it fail and record how: command, input or steps, and what
   came out. A bug you cannot reproduce is not ready to fix; say what you tried.
2. **Pin it with a failing check.** The smallest test or script that fails because
   of the bug. It is the task's `Check`; on the fast path it is the proof.
3. **Name the root cause.** One or two sentences on why the code does the wrong
   thing, not where the symptom shows, written in the task's `## Progress` (in the
   commit body on the fast path). Patching the symptom while the cause is unknown
   is a hotfix by another name; if that is what this is, §4 applies.
4. **Fix the cause, then look sideways.** Check every other caller and every copy
   of the faulty rule. The sibling path left broken is the usual second bug.
5. **Watch the check go green,** then run the real path once.

Cause still unknown after reproducing? Finding it is its own task: `Task type:
spike`, question "what causes <symptom>?", time box stated as what to stop after.
The fix task is `Blocked by` the spike.
