# Technical Debt

## Status: Active

### Fix Now

## [urgent] Duplicated validation

**Where:** src/api
**Added:** 1970-01-01
**Priority:** fix-now
**Status:** active

**Problem:** Repeated validation in several routes.
Evidence spans multiple lines.

**Impact:** Fixes can drift.

---

### Worth Doing

## [medium] Slow query

**Location:** src/db
**Added:** 1970-01-01T05:30:00+05:30
**Priority:** worth-doing
**Status:** active

**Problem:** The query scans unnecessary rows.

---

### Only If It Grows

## [minor] Repeated adapter

**Where:** src/api
**Added:** 1970-01-01T00:00:00.000Z
**Priority:** only-if-grows
**Status:** active

**Problem:** Two similar adapters are small today.

---

## Status: Resolved

## [fixed] Shared response encoder

**Where:** src/api
**Added:** 1970-01-01T01:00:00+01:00
**Priority:** worth-doing
**Status:** resolved

**Problem:** Two response encoders diverged.

**Resolution:** Consolidated the encoders.
**Commit:** abc1234
**PR:** #7

---

## Status: Accepted

## [accepted-compatibility] Old wire format

**Where:** src/legacy
**Added:** 1970-01-01T00:00Z
**Priority:** only-if-grows
**Status:** accepted

**Problem:** Old wire format remains in production.

**Resolution:** Required for compatibility.

---

## Entry Template

```markdown
## [ID] Brief symptom
**Where:** file/module paths
**Added:** YYYY-MM-DD
**Priority:** fix-now | worth-doing | only-if-grows
**Status:** active | resolved | accepted
```
