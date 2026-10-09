# Decisions

## Format

```markdown
## 2025-01-01 - Example hotfix
- **Decided:** hotfix example, not a real decision.
```

## Entries

<!--
## 2025-01-01 - Commented hotfix
- **Decided:** temporary example.
-->

## 2025-01-01 - Emergency patch

- **Decided:** HOTFIX shipped (commit abcdef1234567).
- **Instead of:** redesign.
- **Because:** production outage.
- **Mine:** yes.
- **Revisit when:** durable implementation lands.

## 2025-02-01 - Temporary choice

- **Decided:** A temporary deployment restriction.
- **Instead of:** automated validation.
- **Because:** deadline.
- **Mine:** no.
- **Revisit when:** tests pass.

## 2025-03-01 - Normal change

- **Decided:** Refactor parser.
- **Instead of:** patch.
- **Because:** This is not a hotfix or workaround.
- **Mine:** yes.
- **Revisit when:** never.

## 2025-04-01 - Mine workaround

- **Decided:** Improve deployment.
- **Instead of:** rollback.
- **Because:** routine.
- **Mine:** yes — this workaround is temporary.
- **Revisit when:** metrics improve.

## 2025-05-01 - Quick fix

- **Decided:** We used a quick-fix for the parser.
- **Instead of:** rewrite.
- **Because:** deadline.
- **Mine:** no.
- **Revisit when:** not resolved yet; wait for the replacement.

## 2025-06-01 - Several fixes

- **Decided:**
  - Temporary "cache" workaround; quick fix for the queue.
  - Emergency patch to retry handling.
- **Instead of:** comprehensive redesign.
- **Because:** outage.
- **Mine:** yes.
- **Revisit when:** service rewrite.
- **Commit:** [1234abc](https://example.test/org/repo/commit/1234abc).
- **Commit:** revision fedcba987654321.

## 2025-07-01 - Resolved change

- **Decided:** immediate fix to routing.
- **Instead of:** rewrite.
- **Because:** outage.
- **Mine:** no.
- **Revisit when:** resolved in commit abcd1234.

## 2025-08-01 - Repeated title

- **Decided:** work-around for malformed headers.
- **Instead of:** parser rewrite.
- **Because:** time.
- **Mine:** yes.
- **Revisit when:** parser replacement.

## 2025-08-01 - Repeated title

- **Decided:** quick fix for body parsing.
- **Instead of:** parser rewrite.
- **Because:** time.
- **Mine:** yes.
- **Revisit when:** parser replacement.
