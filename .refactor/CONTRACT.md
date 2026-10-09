# Workflow 2.5 refactor — shared design contract

Every agent works from this file. It fixes the design so that parallel edits stay
globally consistent. If something here conflicts with what you find in the repo,
this file wins; if this file is silent, keep the repo's current behaviour.

## Repo, branch, ownership

- Repo: https://github.com/Shizuku-Yume/workflow (public). Default branch is `master`.
- Integration branch: `refactor/lighter-2.5` (already exists; based on master).
- Clone it: `git clone -q -b refactor/lighter-2.5 https://github.com/Shizuku-Yume/workflow.git /home/user/wf`
- Edit ONLY the files you own (listed in your prompt). Never edit, create or delete
  anything else. If you see a problem in a file you don't own, put it in your report.
- Commit with the gumloop SDK from the sandbox (see "Committing" below), onto
  `refactor/lighter-2.5`, in one or two commits. Commit message: one imperative line.
- Version string for this release: `2.5.0`.

## Design philosophy (the user's, apply it everywhere)

1. Lightweight: little context load on the model, behaviour constraints only, no ceremony.
2. Global consistency: every rule has one home; others point to it (`CONVENTIONS §N`).
   No contradictions between files.
3. Solve real problems: don't write what a capable model does anyway.
Writing: English, plain and short, imperative. Prefer stating the target behaviour
over lists of "don't" (negations pull the banned behaviour into context). Don't
restate a rule owned elsewhere; point to it.

## Fixed anchors (other files cite these — keep them)

CONVENTIONS keeps section numbers and titles: §0 Evidence before questions, §1 Decision
protocol, §2 File structure, §3 Writing, §4 Task sizing, §5 Skill routing, §6 Lifecycle,
§7 Review, §8 Fixing bugs. A short unnumbered "Precedence" paragraph goes before §0.
Skill names unchanged: flow-start, flow-grill, flow-spec, flow-break, flow-implement,
flow-verify, flow-close, flow-architect, flow-map. Agent names unchanged:
workflow-reviewer, workflow-process.

## Decisions (D1–D23)

**D1 CLI surface.** 2.5 commands: `.workflow/bin/workflow init | update | uninstall |
doctor | hook install|uninstall|status | validate | next | version`.
Removed: `tasks`, `deps`, `decisions`, `effort`, `debt`, `hotfix-review` (and shell
completions). Docs must not mention removed commands. Agents read Markdown directly:
- decisions: read the newest entries at the end of `.workflow/decisions.md`, plus
  `grep -n -i '<term>' .workflow/decisions.md` for the area you will touch, or
  `grep -n 'Effort:\*\* <slug>' .workflow/decisions.md` for one effort's entries.
- active tasks: `.workflow/bin/workflow next` (ready tasks ranked by priority; also
  lists paused and blocked tasks), or read `.workflow/tasks/*/` files directly.
- debt: read / grep `.workflow/technical-debt.md`.
`validate` checks task files and the decision log (exit 0 valid, 1 warnings, 2 errors).
Implementation: `bin/workflow` stays Bash and must run on Bash 3.2 (stock macOS, BSD
tools). `validate` and `next` live in `bin/workflow-core.py` (Python 3.8+, stdlib only);
`bin/workflow` runs it as `python3 "<dir of bin/workflow>/workflow-core.py" <cmd> ...`.
Runtime requirements: Bash 3.2+, git, python3, POSIX awk/sed (BSD or GNU).

**D2 Effort merged into spec.** `.workflow/efforts/` and effort definitions are gone.
An effort is the slug grouping tasks (`tasks/<effort>/`, `done/<effort>/`). Its spec,
when it has one, is `.workflow/specs/<effort>.md` (same slug). Spec header:
```
**Status:** proposed | in progress | done
**Priority:** critical | high | normal | low
```
`Priority` optional, default `normal`, read by `next`. The spec is the only state
machine of an effort: flow-spec writes `proposed`; flow-implement sets `in progress`
when the effort's first task starts; flow-close sets `done`. An effort without a spec
(lone bugfix, spike, `maintenance`) has no status: it is finished when no task of it is
left under `tasks/<effort>/`. Maps keep their own statuses (charting/working/clear).

**D3 flow-close only for efforts with a spec.** An effort without a spec is done when
its last task lands: no close, no retrospective.

**D4 Planning documents get committed.** Rule owned by CONVENTIONS §2: a skill that
writes planning documents (decisions, glossary, specs, maps, tasks) commits them when it
finishes, onto the main branch, before any task branch is cut; under `Landing: pr` they
go through a PR like any change. A task can start only when its task file is committed
on the main branch. Concretely: flow-break (normal and amend) commits spec, decisions,
glossary and tasks together after `validate`, one commit; flow-map commits the map and
any decision entries at the end of each session; flow-grill or flow-spec commit what
they wrote only when the session ends there (no flow-break follows).

**D5 Foreign dirty files.** Rule owned by CONVENTIONS §2: when a task starts, run
`git status --porcelain`; paths already modified or untracked belong to someone else.
Record them in the task's `## Progress` as `Dirty at start:` (or `none`). Never stage or
commit them; stage the task's own paths by name (`git add -- <paths>`). If the task turns
out to need one of them, ask. The small-task fast path checks the same before starting.
CONVENTIONS §7's "stage the reviewed state" uses `git add -- <the task's paths>`, not
`git add -A`.

**D6 Task types and the Check.** Owned by CONVENTIONS §2 (task type field):
- `feature`, `bugfix`: Check fails (or can't run yet) before the change, passes after.
- `refactor`: behaviour must not change; Check passes before and after; review confirms
  no behaviour changed.
- `spike`: no Check-before; the deliverable is an answer.
flow-implement and the workflow-process brief follow this.

**D7 Landing for work without a task file.** Owned by merge-strategy.md; CONVENTIONS §4
points there. `direct`: commit on the current branch. `local-merge` / `pr`: branch
`small/<slug>` (hotfix: `hotfix/<slug>`) from the main branch, landed like a task branch.
Nothing to archive.

**D8 Precedence.** Owned by CONVENTIONS (paragraph before §0); AGENTS.md has one line:
"When rules disagree: the user's current instruction, then `.workflow/standards.md` and
the repository's existing conventions (commit style in `git log`, lint and formatter
config, CONTRIBUTING), then CONVENTIONS.md, then STYLE.md."
STYLE commit messages: follow the repo's existing convention (`git log --oneline -10`);
when it has none, one imperative line saying what changed and why.

**D9 Hotfix tracking = the follow-up task.** Remove `hotfix-review`, `--mark-resolved`,
and any "the `Hotfix:` prefix is the contract" wording. Keep: hotfix decision entry
(five fields, `Decided:` starts with `Hotfix:` as a readable convention) and the
mandatory follow-up `Task type: bugfix` task whose `Read first` names that entry (in the
effort owning the code, else `maintenance`). The open task is the reminder; flow-start
reports open bugfix tasks that name a hotfix entry. decisions.md becomes strictly
append-only with exactly one exception: appending a `**Superseded by:**` line to an old
entry when a new entry reverses it.

**D10 Technical debt simplified.** `technical-debt.md` is a flat list under `## Entries`,
one entry per finding:
```
## <concrete symptom>

- **Where:** <files or modules>
- **Added:** <YYYY-MM-DD>
- **Priority:** fix-now | worth-doing | only-if-grows
- **Problem:** ...
- **Impact:** ...
- **Solution:** ...
- **Cost:** ...
```
No status field, no IDs (refer by heading). Fixed: the task that fixes it deletes the
entry in its commit. Declined by the user: delete the entry and append a decision entry
(Decided: not fixing <symptom>; Instead of: fixing it; Because; Mine: no; Revisit when),
so reviews don't re-propose it. CONVENTIONS §6 lists debt entries: added by
flow-architect (or any skill that finds one), removed by the fixing task or by a decline
with a decision entry.

**D11 AGENTS.md block** (about 15 lines): what to read, when to use flow-start, the
precedence line, and four invariants: (1) find facts yourself, ask the user only what
they own, in batches; (2) run it and observe before saying it is done; (3) a plan that
turns out wrong is fixed in the plan (CONVENTIONS §5); (4) one task at a time per working
tree. No review mechanics, no "not optional" tone.

**D12 Intensity.** `quick` is removed (trivial work is a small task with no task file).
flow-implement levels: `standard` (default, flow-verify) and `thorough` (flow-verify,
then flow-architect on the touched area). argument-hint `"<effort>/<NN> [thorough]"`.
The CONVENTIONS §7 security pass runs whenever its trigger applies, on every path.

**D13 Reference docs.** `templates/project/.workflow/thinking.md` is deleted; its
essence becomes about five lines inside flow-grill step 2 (restate the problem without a
solution, list hard constraints, ask what breaks if a piece is removed, build up from
constraints, name the cheapest experiment). Nothing references thinking.md.
`phase-boundaries.md` stays, compressed to ≤ ~300 words, framed as advice the agent gives
the user (agents usually can't clear or compact their own window).

**D14 One plan review.** When flow-spec and flow-break run in the same session (the
normal case), flow-spec doesn't stop for confirmation; flow-break presents the spec
summary plus the task breakdown as one review round, and that approval settles both. If
the session ends after the spec, flow-spec asks for confirmation as before. flow-grill
keeps its closing restatement of decisions; flow-spec never re-asks decisions already
confirmed there.

**D15 Brownfield.** flow-start step 1: if `.workflow/standards.md` still contains
`<...>` placeholders, fill what the repository answers (commands from package manifests,
Makefile, CI config, lint config; layout from the tree; `Landing:` from how the repo uses
branches), leave the rest marked, show the user the filled file in one message, ask them
to correct it, then continue with the request.

**D16 Retro output.** flow-close "What changes": a mechanical pattern (banned API, import
shape, file location, missing test) becomes a check (lint rule, test, CI step) built in
this change or drafted as a task; only a judgement call becomes a line in standards.md.

**D17 Wide refactors.** flow-break: a mechanical change whose blast radius breaks many
call sites at once (rename a column, retype a shared symbol) can't be a vertical slice;
sequence it expand → migrate in batches (each a task blocked by the expand) → contract
(blocked by every batch).

**D18 Failed fix.** CONVENTIONS §8: still red after the fix? Revert that fix and go back
to step 3 (root cause); a fix stacked on a wrong fix hides the cause.

**D19 Union merge.** `init`/`update` write a managed block into the project's
`.gitattributes`:
```
# workflow:start
.workflow/decisions.md merge=union
.workflow/glossary.md merge=union
# workflow:end
```
`uninstall` removes the block (and the file if it becomes empty); `doctor` reports a
missing block. CONVENTIONS §2 says in one line that both files use git's union merge so
parallel branches adding entries don't conflict.

**D20 standards.md template.** Remove the "unless a supported tracker integration
exists" sentence and the "Where things go" section (CONVENTIONS §2 owns layout); keep a
one-line pointer.

**D21 Review rules.** CONVENTIONS §7 owns shared review rules (security pass, reviewer
labels blocking/nonblocking, only the user waives a blocking finding, rechecks sized to
the fix, findings kept in `## Progress`). Skills point to §7 instead of restating it.
What to look for lives in the two reviewer briefs.

**D22 flow-implement** ≤ ~1000 words; reads only the CONVENTIONS sections it uses (§6
pause handoff, §7 review findings, §8 bugs), not the whole file.

**D23 STYLE.md** keeps artifact rules: language, terms, front-end text, code comments,
commit messages (D8), length and reporting. Chat-voice advice shrinks to two or three
lines at most. Positive phrasing.

## CLI interface contract (for core, installer, lint agents)

- `python3 bin/workflow-core.py validate [--strict] [--format text|json] [--no-color]`
  and `python3 bin/workflow-core.py next [--format text|json] [--no-color]`; `--help` on
  each. `--fix` (validate) and `--interactive` (next) are dropped. `NO_COLOR` env and
  non-tty disable colour. Project root: `git rev-parse --show-toplevel` from cwd, else cwd.
- validate JSON (stdout), same shape as 2.4:
  `{"valid":bool,"errors":int,"warnings":int,"tasks":int,"issues":[{"severity":"ERROR|WARNING","file":"<root-relative>","line":int,"message":str,"suggestion":str}]}`.
  `valid` is true only with zero errors and zero warnings. Diagnostics text to stdout in
  text mode as before; exit 0/1/2. Problems inside `done/` are warnings. No "effort
  definition missing" warning any more.
- next JSON, same shape as 2.4:
  `{"ready_count":int,"task_count":int,"blocked_count":int,"ready_tasks":[{"number":int,"title":str,"effort":str,"priority":str,"goal":str,"check":str,"start_command":"flow-implement <effort>/<NN>"}],"blockers":[...]}`.
  `priority` from `specs/<effort>.md` `Priority:` (default `normal`); `goal` is the first
  non-empty line under the spec's `## What this is for` (else `(not specified)`). No
  warning when a spec is missing. Tasks with `Status: blocked` are never ready.
- `bin/workflow` dispatches `validate|next` to the core; a missing `python3` gives a clear
  error. A removed command prints `workflow <cmd> was removed in 2.5: <hint>` to stderr
  and exits 2. `bin/workflow` no longer sources `workflow-lib.bash` (deleted).
- `update` removes managed copies the toolkit no longer ships (old CLI files in
  `.workflow/bin/`, `.workflow/thinking.md`) when unmodified; edited ones are kept with a
  warning (same rule as other managed files).

## Committing (gumloop SDK, inside sandbox_python)

```python
from gumloop import Gumloop
import time
client = Gumloop()
files = [{"path": "CONVENTIONS.md", "content": open("/home/user/wf/CONVENTIONS.md").read()}]
for attempt in range(4):
    r = client.mcp.execute("github", "create_or_update_file", {
        "owner": "Shizuku-Yume", "repo_name": "workflow", "branch": "refactor/lighter-2.5",
        "message": "<imperative one-line message>", "files": files}).results[0]
    if r.status == "success": print(r.decoded_content); break
    print("retry", r.error); time.sleep(5)
# deletions:
# client.mcp.execute("github", "delete_files", {"owner": "Shizuku-Yume", "repo_name": "workflow",
#     "branch": "refactor/lighter-2.5", "message": "...", "paths": ["bin/old-file"]})
```
Server and tool names must be string literals in the call (not variables). Updating an
existing file keeps its executable bit; new files are created 100644.
After committing, verify: `git -C /home/user/wf pull -q` and check your files.
