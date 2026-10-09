# Decisions

## Entries

## 2026-01-01 - Valid before malformed
- **Decided:** Keep valid first entry.
- **Instead of:** Reject it.
- **Because:** First rationale.
- **Mine:** no
- **Revisit when:** requirements change.

## 2026-02-30 - Impossible date
- **Decided:** Date must not crash the command.
- **Instead of:** Dropping the whole file.
- **Because:** Invalid calendar dates are recoverable warnings.
- **Mine:** yes
- **Revisit when:** corrected.

## Undated malformed heading
- **Decided:** Retain content without a date.
- **Instead of:** Delete evidence.
- **Because:** First reason.
- **Because:** A duplicate reason must also be retained.
- **Mine:** no
- **Revisit when:** review.

## 2026-03-01 - Missing and empty fields
- **Decided:** Continue after this entry.
- **Instead of:**
- **Mine:** yes

## 2026-04-01 - Valid after malformed
- **Decided:** Keep valid final entry.
- **Instead of:** Stop on malformed entries.
- **Because:** Continue parsing the entire log.
- **Mine:** no
- **Revisit when:** never.
