# Decisions

The preamble includes field documentation, not actual entries:
- **Decided:** example choice
- **Instead of:** example alternative
- **Because:** example rationale

```markdown
## Entries
## 2099-01-01 - Fenced preamble example
- **Decided:** Not an entry.
```

## Entries

<!--
## 2099-01-01 - Commented fake decision
- **Decided:** Also not an entry.
-->

## 2026-01-01 - Authentication boundary
### Context
Context before the first field is not field content.
- **Decided:** Use bearer tokens.
  Keep the token opaque.
- **Instead of:** Session cookies.
- **Because:** AUTH needs a stable interface.
  This rationale spans multiple lines.

  A second paragraph mentions "quotes" and C:\auth\tokens.
  - A nested list supplies more evidence.
- **Mine:** no
- **Revisit when:** The threat model changes.

~~~markdown
## 2099-01-02 - Fenced fake decision
- **Decided:** Not an entry either.
~~~

## 2026-02-01 - Persistence boundary
- **Decided:** Store auth records in files.
- **Instead of:** A database.
- **Because:** Volume is small. <!-- inline comment is ignored -->
- **Mine:** yes
- **Revisit when:** Volume grows.