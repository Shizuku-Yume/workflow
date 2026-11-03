# Technical Debt

Track code friction worth fixing later, backed by concrete evidence. Remove entries in the commit that fixes them. If the user declines a fix, delete the entry; log in `decisions.md` (`Decided by: user`) only if future agents are likely to re-propose the same cleanup.

## Format

Add `## <Concrete symptom>` headings under `## Entries`:

```markdown
## Order total computed in three places

- **Where:** <files or modules>
- **Added:** <YYYY-MM-DD>
- **Priority:** fix-now | worth-doing | only-if-grows
- **Problem:** <what is wrong, with evidence>
- **Solution:** <plain-language fix and rough cost>
```

## Entries

<!-- Add yours below. Delete this comment. -->
