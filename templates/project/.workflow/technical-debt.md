# Technical Debt

Track costly code so reviews retain evidence and the reason it remains. `flow-architect`
or any skill that finds debt may add an entry.

## Format

Use a level-two heading naming the concrete symptom under `## Entries`; cite by heading.

```markdown
## Order total computed in three places

- **Where:** <files or modules>
- **Added:** <YYYY-MM-DD>
- **Priority:** fix-now | worth-doing | only-if-grows
- **Problem:** <what is wrong, with evidence>
- **Impact:** <what gets harder while it stays>
- **Solution:** <the change, in plain terms>
- **Cost:** <what the fix risks, how big it is>
```

Remove entries when fixed (in the fixing commit). If the user declines a fix, delete the
entry and append a `decisions.md` entry (`Mine: no`) recording the choice and when to revisit.

## Entries

<!-- Add yours below. Delete this comment. -->
