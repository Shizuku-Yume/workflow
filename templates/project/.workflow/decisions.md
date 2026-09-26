# Decisions

Every choice that mattered, with the option it beat. Newest last.

This file exists so the same argument is not had twice. A decision recorded here
is settled; if someone wants to reopen it, they say why the entry below is now
wrong, and the entry gets updated.

## Why the runner-up is required

A decision recorded without the alternative it beat is a decision someone will
reopen next session, usually for a good reason: they cannot see why the obvious
option was rejected. Write the strongest case for the losing option, then the
constraint that killed it. A strawman rejection is worse than no record.

## Format

```markdown
## 2026-01-31 - Retries capped at 3, no backoff

- **Decided:** three immediate retries, then fail.
- **Instead of:** exponential backoff with jitter.
- **Because:** the only caller retries within a single user request; a 30-second
  backoff would outlive the request it is serving.
- **Mine:** no (asked the user).
- **Revisit when:** a background job starts calling this.
```

`Mine` records who made the call, so it is clear which decisions came from an
agent and which from a person. An agent-made decision is still a real decision;
it is just one the user is entitled to overturn on sight.

`Revisit when` is the observation that would make this wrong. "Never" is an
acceptable answer but a suspicious one.

## Entries

<!-- Add yours below. Delete this comment. -->
