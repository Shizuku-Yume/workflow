# Decisions

Append-only log of hard-to-reverse choices where a real alternative was rejected
(CONVENTIONS §1). Skip routine implementation details. Git union-merges concurrent
additions.

## Format

Add `## <YYYY-MM-DD> - <title>` entries under `## Entries` (newest last). Cite as
`decisions.md: <date> - <title>`. Every entry requires three non-empty English field names
(values may be in any language):

- **Decided:** what was chosen
- **Instead of:** the strongest alternative that lost
- **Because:** why it lost here

Optional: **Decided by** (`user` or `agent`), **Revisit when**
(condition to reconsider), and **Supersedes** (`<old heading>`,
adding `**Superseded by:** <new heading>` to the old entry).

```markdown
## 2026-01-31 - Retries capped at 3, no backoff

- **Decided:** three immediate retries, then fail.
- **Instead of:** exponential backoff with jitter.
- **Because:** the only caller retries within a single user request; a 30-second
  backoff would outlive the request it is serving.
- **Decided by:** user
- **Revisit when:** a background job starts calling this.
```

## Entries

<!-- Add yours below. Delete this comment. -->
