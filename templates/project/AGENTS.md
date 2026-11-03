<!-- workflow:start -->
# Project workflow

Read `.workflow/standards.md` once per session before non-trivial edits. Open `.workflow/CONVENTIONS.md` or `.workflow/STYLE.md` only for the section you need. Unsure where to start: run `flow-start`.

Precedence: user instruction → `standards.md` and repo conventions → `CONVENTIONS.md` → `STYLE.md`.

## Sizing work (CONVENTIONS §3)
- **Question:** answer directly from code, tests, or docs.
- **Small change or bugfix:** edit, run tests and real path, commit. No task file, no `flow-verify`.
- **1–3 clear tasks:** `flow-break` → `flow-implement`. No spec, no `flow-close`.
- **Multi-task or boundary change:** `flow-spec` → `flow-break` → `flow-implement` → `flow-close`.
- **Unclear scope or trade-offs:** run `flow-grill` first, then follow the matching path.

## Rules
1. Check the repo before asking. Ask only about choices the user owns; pick defaults for reversible details (CONVENTIONS §1).
2. Work is done when verified on the real path. Skip redundant reruns when inputs haven't changed, never the task's `Check` or real entry-point run unless the user waives it.
3. When a plan assumption breaks, fix the plan with `flow-break` amend instead of working around it in code.
4. Leave pre-existing dirty files alone unless asked. Give parallel tasks separate worktrees in `.workflow/worktrees/<effort>-<NN>` (CONVENTIONS §7).
5. Reuse before writing: repo → stdlib → platform → installed dependency. No guards for impossible cases, no unrequested wrappers (CONVENTIONS §8). Deliverables carry no trial-and-error notes or AI signatures (`STYLE.md`).
<!-- workflow:end -->
