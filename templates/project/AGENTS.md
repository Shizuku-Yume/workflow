<!-- workflow:start -->
# Project workflow

This project runs on a fixed workflow. Follow it without being asked; it is not
optional and it is not a suggestion.

## Read first

Before any non-trivial work, read `.workflow/standards.md` and
`.workflow/CONVENTIONS.md`. The conventions file is the full rulebook for how
questions are asked, how documents are laid out, and how writing is done. It
applies to everything you produce here.

The skills that drive each step live in `.agents/skills/`. Read
`.agents/skills/<name>/SKILL.md` before running that step:

| Step | Skill | Produces |
| --- | --- | --- |
| Align on what to build | `flow-grill` | `.workflow/decisions.md`, `.workflow/glossary.md` |
| Write it down | `flow-spec` | `.workflow/specs/<slug>.md` |
| Cut it up | `flow-break` | `.workflow/tasks/<NN>-<slug>.md` |
| Build it | `flow-implement` | code, then a review, then a commit |
| Review a change | `flow-verify` | three review axes |
| Plan the unclear | `flow-map` | `.workflow/maps/<slug>.md` |
| Find code worth fixing | `flow-architect` | a report |

## Rules that always hold

1. **Ask in batches, and rarely.** Never ask one question at a time. At most 6
   questions in one round, 8 if they are all genuinely blocking. Decide the small
   things yourself and record them in `.workflow/decisions.md`; ask only what
   changes what gets built.
2. **Find facts yourself.** Do not ask the user anything you could answer by
   reading the repository, the docs, or a search.
3. **Write decisions down as they are made.** A choice not recorded will be
   re-litigated next session. Use the format in `CONVENTIONS.md`.
4. **Use the project's vocabulary.** `.workflow/glossary.md` is the source. Add
   new terms there the moment they are agreed.
5. **Specs and tasks are the input to building.** Do not build a non-trivial
   change that has no spec or task file. If a fact in a spec changes, update the
   spec in the same change.
6. **Verify before you say it is done.** Run the thing. A change is not finished
   because the code was written; it is finished when it has been exercised and
   the result was observed. Run the review skills in `flow-verify` after any
   non-trivial change.
7. **Review with the review agents.** Use `workflow-reviewer` for correctness and
   code quality and `workflow-process` for process. Add `security-reviewer` when
   the change touches auth, user input, secrets, or file paths. Never review your
   own change with a general-purpose worker when these exist.
8. **Keep the whole task in one session.** When a task does not fit, split it
   rather than carrying a stale plan forward.
9. **Delete what is superseded.** When a task ships, move it to
   `.workflow/done/`. Do not leave finished work cluttering the active folders.

## Output style

Read `.workflow/STYLE.md` and follow it. In short: write in the user's language and
do not mix languages inside one document; sound like a person, not a translation;
no filler openings, no summary paragraphs that repeat the text above; use the
project's terms; and never put developer vocabulary in text a user will read on
screen.

<!-- workflow:end -->
