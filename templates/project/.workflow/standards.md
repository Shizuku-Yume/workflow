# Standards

Fill this in once, at the start of the project. Keep it under one screen: it is
read at the start of every session, so every extra line costs attention that the
real work needs.

Delete the lines that do not apply. Replace every `<...>`.

## What this project is

<One or two sentences. What it does, who uses it. Enough that someone can tell
whether a change belongs here.>

## Running it

```sh
<install command>      # e.g. npm install, uv sync, cargo build
<run command>          # e.g. npm run dev
<test command>         # e.g. pytest, npm test
<typecheck command>    # e.g. tsc --noEmit
<lint command>         # e.g. ruff check .
```

Run the test command before claiming anything works.

## Layout

<Where the parts live, one line each. Keep it short: `src/api` - HTTP handlers.
Not a file tree.>

## How code is written here

<The rules that a reviewer would enforce and that are not obvious from reading
three files. Two or three lines each, no more. For example: errors are returned,
never thrown; every database call goes through the repository layer; tests are
named after the behaviour, not the function.>

If a rule is long enough to need a section, it belongs in its own document under
`.workflow/`, linked from here.

## What we do not do

<The approaches this project has ruled out, with the reason. This is the section
that stops the same argument from being had again.>

## Branches and landing

Landing: <direct | local-merge | pr>

How a finished task reaches the main branch; `.workflow/merge-strategy.md`
describes each mode. `direct`: commit straight onto the current branch.
`local-merge`: a branch per task, rebased and fast-forwarded into the main branch
locally. `pr`: a branch per task, pushed, merged through a pull request. Unset
means `local-merge`. Name the main branch here if it is neither `main` nor
`master`.

## Where things go

Local files below are the workflow task and spec source unless a supported tracker integration exists.

- Decisions: `.workflow/decisions.md`
- Specs: `.workflow/specs/`
- Tasks: `.workflow/tasks/<effort>/`
- Finished tasks: `.workflow/done/<effort>/`
- Vocabulary: `.workflow/glossary.md`
- CLI: `.workflow/bin/workflow` (committed; run from the project root)
