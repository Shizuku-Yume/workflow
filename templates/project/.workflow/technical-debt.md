# Technical Debt

Track code issues that make changes expensive. Items come from `flow-architect` findings or discovered during work.

## Status: Active

Items that need addressing, ranked by impact.

### Fix Now

High-priority items blocking current work or causing frequent pain.

### Worth Doing

Medium-priority improvements that would help but aren't blocking.

### Only If It Grows

Low-priority items to fix only if the affected area expands.

## Status: Resolved

Moved here when fixed, with link to commit/PR.

## Status: Accepted

Decided not to fix, with reason. Prevents re-proposing.

---

## Entry Template

When adding debt, use this format:

```markdown
## [ID] Brief symptom

**Where:** file/module paths
**Added:** YYYY-MM-DD
**Priority:** fix-now | worth-doing | only-if-grows
**Status:** active | resolved | accepted

**Problem:** Specific issue with evidence (e.g., "same validation logic in 3 files", "untested database code")

**Impact:** What gets harder: more places to edit, can't test X, requires Y every time

**Solution:** Concrete change in plain terms

**Cost:** What the fix itself risks, how big the change is

**Resolution:** (filled when resolved/accepted) What was done or why accepted
```
