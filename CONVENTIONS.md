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
  tasks/<NN>-<slug>.md           one task each
  maps/<slug>.md                 multi-session planning
  done/<effort>/                 archived tasks, plus retrospective.md when the effort closes
```

**Rules:**
- `standards.md` is the entry point. Keep it under one screen.
- One spec per effort, updated in place when code changes facts.
- `decisions.md` is append-only. Five fields required: `Decided`, `Instead of`, `Because`, `Mine`, `Revisit when`. Optional `**Effort:** <slug>` tags an entry to one effort so `workflow decisions --effort <slug>` can find it. Reversals append new entries referencing old. Refer to an entry by its heading text: `decisions.md: <date> - <title>`.
- `technical-debt.md` tracks architecture findings. Use `workflow debt` command to manage.
- `merge-strategy.md` and `spike-tasks.md` are reference docs, rarely change.
- Effort definitions in `efforts/<slug>.md` track goal, scope, success criteria and priority. Optional, but `flow-break` creates one (`workflow effort create <slug>`) so `workflow next` can rank the effort's tasks.
- Tasks follow strict format:
  - Filename: `.workflow/tasks/<NN>-<slug>.md`; heading `# <NN>: <Title>` (NN matches filename).
  - `NN` is unique within an effort, not across efforts. Unambiguous reference: `<effort>/<NN>`.
  - Fields are `Name: value` lines, plain or bold (`**Effort:** <slug>`). Every `workflow` command reads them through one shared parser, so the spelling rules below are the same everywhere.
  - Required (`workflow validate` errors): `Effort` (lowercase slug `[a-z0-9]+(-[a-z0-9]+)*`); `Blocked by` (`None`, or comma-list of `NN` (same effort) or `<effort>/NN` (cross-effort), numbers only, no titles); `Check` (command and the result that means it works, or a `## Check` section).
  - Expected from `flow-break`, not machine-checked: `Delivers`, `Files`, `Read first`, and the `Done when` checklist.
  - Optional: `Task type:` `feature | bugfix | refactor | spike` (default `feature`); `Base commit:` `<commit-sha>` when drafted, real SHA when started; `Started:`/`Finished:` ISO 8601 timestamps; `Status: active | paused | blocked` for interruption tracking.
  - The same problems inside `done/<effort>/` archives are warnings, not errors: history is not rewritten to satisfy today's checks.
- Archive to `done/<effort>/` before committing. Task archive, code, and docs land together in one commit.
- A blocker archived under `done/<effort>/` in HEAD is finished: `workflow next` stops counting it, so dependents become ready without rewriting their `Blocked by`.
- After writing or editing tasks or decisions, run `workflow validate`. Errors block; fix the file, not the validator.

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

Hotfix path: skip grill/spec/break/verify, fix immediately, verify where the
failure was observed. If you can't reach production, say so and hand that check
to the user.
**Mandatory follow-up before the session ends:** write decision entry explaining
temporary fix, long-term plan, and why shortcuts were justified. If explanation
can't be written honestly, it wasn't a hotfix.

Start that entry's `Decided` field with `Hotfix:`. The prefix is the marker
`workflow hotfix-review` relies on; it also catches wording such as
"temporary" or "workaround", but the prefix is the contract.

**Small task** — ALL of these:
- Single behavior change or bug fix
- Impact radius: change affects <3 modules' behavior
- Requirements clear
- No architectural decisions
- Rollback cost: can revert in <5 minutes if wrong

Small tasks skip `flow-grill`, `flow-spec`, `flow-break`, `flow-verify`. Still require: reading code, running tests, proof, commit message.

Impact radius matters more than file count: changing a core type definition in 1
file but affecting 20 modules is not small. Adding an isolated utility touching 5
files but affecting nothing else is small.

**Complex** — everything else. Run full workflow from earliest incomplete step.

---

## 5. Skill routing

| Situation | Skill |
|-----------|-------|
| Start of session, unclear next step | `flow-start` |
| Vague requirements, design questions | `flow-grill` |
| Too big/foggy to plan directly | `flow-map` |
| Decisions settled, need writing down | `flow-spec` |
| Spec bigger than one session | `flow-break` |
| Task file ready to build | `flow-implement` |
| Review finished work | `flow-verify` |
| Code expensive to change | `flow-architect` |

When two apply, take the earliest incomplete. If user knows what they want, skip ahead.
