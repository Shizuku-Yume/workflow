# workflow-skills

A small set of agent skills for running a project end to end: settle what to
build, write it down, cut it into work a session can finish, and check the result.

The design comes from four things worth reading:

- [mattpocock/skills](https://github.com/mattpocock/skills) - the grilling to spec
  to tickets flow, and the idea that a question round beats a question drip.
- [mindfold-ai/Trellis](https://github.com/mindfold-ai/Trellis) - specs and
  vocabulary kept in the repository, injected per task instead of remembered.
- [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) - the
  ladder (does this need to exist, is it already here, does the standard library
  do it), and reporting cuts as counted line deltas.
- [czm15053/write-notes-like-deepseek](https://github.com/czm15053/write-notes-like-deepseek) -
  the document discipline: the rejected option is half the record, consequences
  carry costs as well as gains, verification lands on something checkable.

What changed: questions are batched with a hard cap and triaged so most of them
never reach the user; the architecture review is plain Markdown and counts what it
saves instead of rendering an HTML report; the review runs three axes instead of
two, adding whether the work followed the project's own process; and everything
is written for a general agent harness rather than one vendor's conventions.

## Skills

| Skill | Does | Writes |
| --- | --- | --- |
| `flow-grill` | Align on what to build; decide the small things, ask the big ones in batches | `.workflow/decisions.md`, `.workflow/glossary.md` |
| `flow-spec` | Write the settled design down | `.workflow/specs/<slug>.md` |
| `flow-break` | Cut a spec into session-sized tasks with dependencies | `.workflow/tasks/<NN>-<slug>.md` |
| `flow-verify` | Three-axis review: built as asked, code quality, process followed | report |
| `flow-architect` | Find the code that resists change; report cuts and reshapes | report |
| `flow-map` | Plan work whose route is not visible yet, one question per session | `.workflow/maps/<slug>.md` |

`CONVENTIONS.md` holds the shared rules: the decision protocol, the document
layout, and how to write. Every skill assumes it. It is deliberately not a skill;
it is the contract the skills implement.

## The loop

```
flow-grill  ->  flow-spec  ->  flow-break  ->  build  ->  flow-verify
    ^                                                          |
    +---------------------- flow-architect --------------------+
```

`flow-map` replaces the first three when the work is too big or too foggy to plan
directly. Any step can be skipped: small work goes `flow-grill` then straight to
building.

## Install

Every skill is one directory with a `SKILL.md`, which is what an agent harness
looks for. Link them into the harness's skill root:

```sh
./install.sh          # links into ~/.agents/skills
./install.sh --uninstall
```

Linking rather than copying means edits here take effect immediately. The target
directory must not contain same-named skills from another source; the first match
by name wins when the harness loads them.
