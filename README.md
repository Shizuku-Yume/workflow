# workflow

A project workflow for coding agents: settle what to build, write it down, cut it
into work a session can finish, build it, and check the result.

It installs **into a project**, not globally. Everything it writes is committed
with that project, so a teammate who clones the repo gets the same workflow with
no extra step.

## Install

```sh
git clone <this-repo> ~/tools/workflow
~/tools/workflow/bin/workflow init
```

Then fill in the blanks in `AGENTS.md` and `.workflow/standards.md`. That takes
five minutes and is the only manual step. Commit the result.

| Command | Does |
| --- | --- |
| `workflow init` | install into the current project |
| `workflow update` | re-copy the skills and rules after this toolkit changes |
| `workflow doctor` | report what is installed and what is missing |
| `workflow uninstall` | remove the installed files, keeping your documents |

Installs into the nearest git repository above the current directory. Nothing is
written outside that project.

## What it installs

```
AGENTS.md                     the rules, inside workflow:start / workflow:end markers
.agents/skills/flow-*/        the six steps
.omp/agents/workflow-*.md     the review agents
.workflow/
  CONVENTIONS.md              the full rulebook: questions, documents, writing
  STYLE.md                    how everything you write should read
  standards.md                this project: commands, layout, conventions
  glossary.md                 what things are called
  decisions.md                every choice made, with the one it beat
  specs/  tasks/  maps/  done/
```

`AGENTS.md` is read at the start of every session, so it holds only the rules an
agent must not miss, plus a pointer to `.workflow/CONVENTIONS.md` for the rest.
Depth in the file everyone always reads is depth nobody reads.

Skills are copied rather than linked, so a project keeps working if this toolkit
is moved. Run `workflow update` to pull in newer versions. The installer never
overwrites your own files: existing `standards.md`, `decisions.md`, and
locally-edited agent files are left alone.

## The steps

| Step | Does | Produces |
| --- | --- | --- |
| `flow-grill` | Align on what to build. Decides the small things itself, asks the big ones in one batch of at most six. | `decisions.md`, `glossary.md` |
| `flow-spec` | Write the settled design down. No interview. | `specs/<slug>.md` |
| `flow-break` | Cut the spec into tasks a single session can finish, with dependencies. | `tasks/<NN>-<slug>.md` |
| `flow-implement` | Build one task, prove it, review it, commit it, archive it. Runs to the end without being asked for each step. | code, then `done/` |
| `flow-verify` | Three-axis review via the project's review agents: as asked, code quality, process. | report |
| `flow-architect` | Find the code that resists change. Reports cuts and reshapes; changes nothing. | report |
| `flow-map` | Plan work whose route is not visible yet, one open question per session. | `maps/<slug>.md` |

```
flow-grill → flow-spec → flow-break → flow-implement → (flow-verify inside it)
     ↑                                                       |
     +------------------- flow-architect --------------------+
```

`flow-map` replaces the first three when the work is too big or too foggy to plan
directly. Any step can be skipped: small work goes `flow-grill` then straight to
building.

## Where this came from

- [mattpocock/skills](https://github.com/mattpocock/skills) — the grill to spec to
  tickets shape, and asking in rounds rather than one question at a time.
- [mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis) — keeping specs and
  vocabulary in the repository and loading them per task instead of remembering them.
- [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) — the ladder
  (does this need to exist, is it already here, does the standard library do it) and
  reporting deletions as counted line deltas.
- [czm15053/write-notes-like-deepseek](https://github.com/czm15053/write-notes-like-deepseek) —
  the document discipline: the rejected option is half the record, consequences
  carry costs as well as gains, verification lands on something checkable.

What changed from those: questions are triaged so most never reach the user and
the rest arrive in one batch; the architecture review is plain Markdown that counts
what it saves instead of rendering an HTML report; the review runs three axes
including whether the work followed the project's own process; review uses
dedicated read-only agents rather than a general worker; and everything is written
for any agent harness rather than one vendor's conventions.

## Layout

```
bin/workflow                  the installer
CONVENTIONS.md                the rulebook, copied into each project
STYLE.md                      the writing rules, copied into each project
skills/flow-*/SKILL.md        the steps
templates/project/            what init writes into a project
```
