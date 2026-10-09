#!/usr/bin/env bash
set -eu
[ "$1" = --multiline ]
cat > "$2" <<'EOF'
Editor supplied the first line.
Editor supplied the second line with literal \n and C:\tools\bin.

---

Further Markdown evidence.

```markdown
## [sample] This is code, not a real debt entry.
**Status:** illustrative
```
EOF
