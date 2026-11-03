# Decisions

Record consequential choices and their alternatives, newest last. This append-only log
settles arguments; reverse one by appending an entry that cites the old heading. Git
union-merges concurrent additions.

## Why record the alternative

Without the real runner-up, a future reader cannot see why it lost. Draft entries while
options are fresh; state each alternative's strongest case. If there was no real
alternative, the choice may not qualify (CONVENTIONS §1.2).

## Format

Entries are level-two headings `## <YYYY-MM-DD> - <title>` under `## Entries`;
subheadings, fenced blocks, and comments are not entries. Cite by heading:
`decisions.md: <date> - <title>`.

Every entry has these five nonempty fields:

- **Decided:** what was chosen
- **Instead of:** the serious alternative
- **Because:** why it lost
- **Mine:** yes if an agent decided, no if the user decided
- **Revisit when:** what observation could make this wrong

Optional: **Effort** names the effort slug. **Supersedes** names the reversed heading;
the only permitted old-entry edit is appending `**Superseded by:** <new heading>`. Follow
that pointer before acting on superseded history.

```markdown
## 2026-01-31 - Retries capped at 3, no backoff

- **Decided:** three immediate retries, then fail.
- **Instead of:** exponential backoff with jitter.
- **Because:** the only caller retries within a single user request; a 30-second
  backoff would outlive the request it is serving.
- **Mine:** no (asked the user).
- **Revisit when:** a background job starts calling this.
```

Field names stay in English for `workflow validate`; their content can be in any
language.

`Mine` shows which calls came from an agent: still real decisions, but ones the
user may overturn on sight. `Revisit when` of "never" is allowed but suspicious;
`flow-close` reads it for every entry of the effort it closes.

## Entries

<!-- Add yours below. Delete this comment. -->
