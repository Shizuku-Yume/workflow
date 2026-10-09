# Decisions

## Entries

## 2025-12-31T23:30:00-02:00 - Offset inside January
- **Decided:** Account for the negative UTC offset.
- **Instead of:** Compare strings.
- **Because:** This instant is January 1 at 01:30 UTC.
- **Mine:** no
- **Revisit when:** timezone requirements change.

## 2026-01-01T00:30:00+02:00 - Offset before January
- **Decided:** Account for the positive UTC offset.
- **Instead of:** Compare strings.
- **Because:** This instant is December 31 at 22:30 UTC.
- **Mine:** no
- **Revisit when:** timezone requirements change.

## 2026-01-01 - January midnight
- **Decided:** Include the lower bound.
- **Instead of:** Exclude the lower bound.
- **Because:** Bounds are inclusive.
- **Mine:** no
- **Revisit when:** filter semantics change.

## 2026-01-01T23:59:59.5Z - January last instant
- **Decided:** Include the entire date-only before day.
- **Instead of:** Stop at midnight at the start of that day.
- **Because:** Fractional seconds remain part of this day.
- **Mine:** no
- **Revisit when:** filter semantics change.

## 2026-01-02T00:00Z - Next midnight
- **Decided:** Exclude the next day.
- **Instead of:** Include midnight after the upper-bound day.
- **Because:** The next midnight is not January 1.
- **Mine:** no
- **Revisit when:** filter semantics change.

## 2024-02-29 - Leap day
- **Decided:** Accept leap days in leap years.
- **Instead of:** Accept February 29 in every year.
- **Because:** Calendar validation must precede filtering.
- **Mine:** no
- **Revisit when:** another calendar is required.
