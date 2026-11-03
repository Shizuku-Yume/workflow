# Standards

Fill this in once, at the start of the project. Keep it under one screen: it is
read at the start of every session, so every extra line costs attention that the
real work needs.

Delete the lines that do not apply. Replace every `<...>`. Where this file
disagrees with CONVENTIONS.md or STYLE.md, this file wins.

## What this project is

<One or two sentences: what it does, who uses it, and any untrusted exposure or adversary
(otherwise a cooperating local operator is assumed, CONVENTIONS §10).>

## Running it

```sh
<install command>      # e.g. npm install, uv sync, cargo build
<run command>          # e.g. npm run dev
<test command>         # e.g. pytest, npm test
<typecheck command>    # e.g. tsc --noEmit
<lint command>         # e.g. ruff check .
```

Run the test command before claiming anything works.

Real path: <how to run the product the way a user does, and where test credentials
or devices come from, so a Check can use the real thing instead of a stand-in.>

Evidence: <where logs, screenshots and receipts go, e.g. `.workflow/evidence/`
(gitignored) or a directory outside the repository. Never a temporary directory.>

## Layout

<Where the parts live, one line each. Keep it short: `src/api` - HTTP handlers.
Not a file tree.>

Workflow files live where CONVENTIONS §2 says.

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

`direct` commits on the current branch; `local-merge` lands locally; `pr` uses pull
requests. Use `pr` when people share a remote. An effort that cannot land piece by
piece names an integration branch in its spec (not under `direct`). See
`.workflow/merge-strategy.md`; name the main branch if it is neither `main` nor `master`.
