<!-- workflow:start -->
# Project workflow

This project follows a fixed workflow. Its principles are not optional; choose the
stages that apply to the size and clarity of each change.

## Read first

Before non-trivial work, read `.workflow/standards.md` — this project's commands,
layout and rules — and `.workflow/STYLE.md`, which governs everything you write.
`.workflow/CONVENTIONS.md` holds the full rulebook: the decision protocol (§1), the
document layout (§2), and which skill to reach for (§5). Read it before running
any `flow-*` skill.

The steps themselves are skills: `flow-start`, `flow-grill`, `flow-spec`,
`flow-break`, `flow-implement`, `flow-verify`, `flow-map`, `flow-architect`,
installed under `.agents/skills/`. Start a session with `flow-start` when the
next step isn't obvious.

## Rules that always hold

1. **Ask in batches, and rarely.** Never one question at a time. Decide the small
   things yourself; ask only what changes what gets built. CONVENTIONS §1 has the
   protocol.
2. **Find facts yourself.** Never ask the user something the repository, the docs,
   or a search would answer.
3. **Write decisions down as they are made.** Choices affecting scope, interfaces,
   compatibility, or trade-offs need a complete five-field entry in
   `.workflow/decisions.md`; routine implementation details do not.
4. **Verify before you say it is done.** Run the thing and observe the result. A
   change is not finished because the code was written.
5. **Specs and tasks guide building, but current user instruction wins.** If an
   instruction changes the deliverable, update the task/spec rather than
   drifting. A fact a spec states gets fixed in the same change that breaks it.
6. **Review across three checks with two agent roles.** `workflow-reviewer`
   covers built-as-asked and code-quality; `workflow-process` evaluates
   process. Two invocations are enough. Review agents report; they don't edit.
7. **Keep one task in one session.** Run parallel tasks only in separate git
   worktrees or isolated checkout directories; a branch in the same working tree
   is not isolation. When a task does not fit, split it.
8. **Archive what ships.** A finished task moves to `.workflow/done/<effort>/`
   committed together with its code.

<!-- workflow:end -->
