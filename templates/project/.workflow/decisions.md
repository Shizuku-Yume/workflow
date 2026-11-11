# Decisions

Append-only log of hard-to-reverse choices where a real alternative was rejected
(CONVENTIONS §1). Skip routine implementation details. Git union-merges concurrent
additions, so entries may interleave out of date order; cite by
`decisions.md: <date> - <title>`.

## Format

Add `## <YYYY-MM-DD> - <title>` entries under `## Entries`. Every entry requires three
non-empty English field names (values may be in any language):

- **Decided:** what was chosen
- **Instead of:** the strongest alternative that lost
- **Because:** why it lost here

Optional: **Effort** (the `<slug>` the decision belongs to), **Decided by** (`user` or
`agent`), **Revisit when** (condition that reopens the decision as a question for
`flow-grill`, and that `flow-architect` consults), and **Supersedes**
(`<YYYY-MM-DD> - <old title>`; leave the older entry untouched so the file stays
strictly append-only).

User waivers of a `Check` or a review finding are recorded in the task file
(`Check waived` / `Review: waived`), not here.

```markdown
## 2026-01-31 - Retries capped at 3, no backoff

- **Decided:** three immediate retries, then fail.
- **Instead of:** exponential backoff with jitter.
- **Because:** the only caller retries within a single user request; a 30-second
  backoff would outlive the request it is serving.
- **Effort:** demo
- **Decided by:** user
- **Revisit when:** a background job starts calling this.
```

## Entries

<!-- Add yours below. Delete this comment. -->
