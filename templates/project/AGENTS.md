<!-- workflow:start -->
# Project workflow

Before non-trivial work, read `.workflow/standards.md` (commands, layout, landing) and
`.workflow/STYLE.md`. Read only the `.workflow/CONVENTIONS.md` sections named by the
active skill; do not preload the whole rulebook. Workflow skills live in
`.agents/skills/`; when the next step is unclear, run `flow-start`.

Precedence: the user's current instruction → `.workflow/standards.md` and existing repo
conventions (`git log`, linter/formatter config, CONTRIBUTING) → `CONVENTIONS.md` → `STYLE.md`.

## Core workflow
1. Find facts in the repo first; ask only user-owned trade-offs in batches. Keep momentum: when options are reasonable and reversible, pick one and note the trade-off (CONVENTIONS §0, §1).
2. Prove changes on the real path before calling them done. Done means landed, and for a spec effort, accepted by the user (CONVENTIONS §6).
3. Fix a broken plan in the plan, never with code workarounds (CONVENTIONS §5).
4. One task per working tree; parallel tasks use separate worktrees. Delegating moves work, not proof (CONVENTIONS §9).

## Scope limits (bound what you propose, never what you look for — CONVENTIONS §10)
Report any real defect reachable through this project's supported use (documented inputs, public interfaces, real data — even rare-looking ones). Keep fixes proportional:
1. **Threat model (E):** Assume a cooperating operator on their own machine unless the project states an adversary. Skip exotic encodings, symlink/ms races, and cases only constructible in principle.
2. **Hashes (H):** Add no hash, checksum, or fingerprint unless it replaces a materially costlier operation AND changes what happens next.
3. **No overbuild (O):** No unrequested feature flags, migration frameworks, compat layers, or single-use wrappers. Reuse codebase → stdlib → native platform before adding code or dependencies.
4. **Judgement over rubrics (R):** Judge directly; do not invent scoring tables, checklists, or re-run settled checks. Before running a check, know what live failure it detects and what changes if it fails. Say plainly when code is right; never manufacture findings.
5. **Clean deliverables:** Present only the final result — no trial-and-error traces, per-paragraph caveats, leaked prompt rules, or AI signatures/filler (`STYLE.md`).
6. **Explicit work stands:** None of this overrides security, migration, verification, or review required by the user, `standards.md`, or a task's `Check`.
<!-- workflow:end -->
