# Standards

Fill this in at project setup and keep it under one screen. Delete lines that do not apply and replace every placeholder. This file overrides `CONVENTIONS.md` and `STYLE.md`.

## Project

<TODO: one or two sentences on what this project does and any untrusted exposure>

## Commands

```sh
<TODO: install command>
<TODO: run command>
<TODO: test command>
<TODO: lint or typecheck command>
```

Real path: <TODO: how to exercise the app or CLI end to end>

## Layout

<TODO: one line per major directory>

## Code conventions

<TODO: 2-3 non-obvious project rules, or delete this section>

## Branches and landing

Landing: <TODO: direct | local-merge | pr>
- `direct`: commit on the current branch (solo work).
- `local-merge`: merge task branches locally (parallel worktrees in `.workflow/worktrees/<effort>-<NN>`).
- `pr`: land through pull requests (shared remote).
See CONVENTIONS §7. Name the main branch here if it is not `main` or `master`.
