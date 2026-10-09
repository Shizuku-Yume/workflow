# Decisions

Every choice that mattered, with the option it beat. Newest last.

This file exists so the same argument is not had twice. A decision recorded here
is settled. This file is strictly append-only: if a decision is reversed or
reopened, never edit or delete the existing entry. Instead, append a new entry
below that references the previous decision and explains what changed and why.

## Why the runner-up is required

A decision recorded without the alternative it beat will be reopened next session.
The person reading this cannot see why the obvious option was rejected.

**Draft entries during `flow-grill`, not after `flow-implement`.** When options are
fresh, you remember why each seemed viable. Write the strongest honest case for
each alternative while evaluating them. If writing "Instead of" feels like
inventing a strawman, that option was never real; use a different one or admit
the decision was obvious and doesn't need logging.

## Format

This is the only copy of the format. `flow-grill` and CONVENTIONS §2 point here.
Every decision is recorded under the `## Entries` section below. Each entry
boundary is a level-2 heading: `## <date> - <title>`. Subsections (`###`) are not
entry boundaries. Fenced code blocks and comments are not entries and are ignored.
Other documents cite an entry by its heading text: `decisions.md: <date> - <title>`.

One mechanical exception to append-only: `workflow hotfix-review --mark-resolved`
rewrites a hotfix entry's `Revisit when` to `resolved`, keeping the old condition.

Every entry must include all five nonempty fields:

- **Decided:** what was chosen
- **Instead of:** real alternative that was seriously considered (not a strawman)
- **Because:** constraint, measurement, or reasoning that eliminated the alternative
- **Mine:** yes if agent decided, no if user decided
- **Revisit when:** the condition or observation that would overturn this

An entry may also carry one optional tag:

- **Effort:** the effort slug this decision belongs to. `workflow decisions
  --effort <slug>` filters by it and `--field Effort` searches it. Omit the tag
  when the decision is not tied to one effort.

The "Instead of" field must pass this test: could you defend that option to
someone who favors it? If not, it's a strawman. Find the real alternative or
acknowledge the choice was obvious (routine decisions don't need entries).

```markdown
## 2026-01-31 - Retries capped at 3, no backoff

- **Decided:** three immediate retries, then fail.
- **Instead of:** exponential backoff with jitter.
- **Because:** the only caller retries within a single user request; a 30-second
  backoff would outlive the request it is serving.
- **Mine:** no (asked the user).
- **Revisit when:** a background job starts calling this.
```

Field names must be in English for automated validation. Field content can be written in any language.

`Mine` records who made the call, so it is clear which decisions came from an
agent and which from a person. An agent-made decision is still a real decision;
it is just one the user is entitled to overturn on sight.

`Revisit when` is the observation that would make this wrong. "Never" is an
acceptable answer but a suspicious one.

## Entries

<!-- Add yours below. Delete this comment. -->
