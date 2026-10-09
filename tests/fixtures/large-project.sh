#!/usr/bin/env bash
# Create a deterministic 120-task, 120-decision fixture in a supplied directory.
set -euo pipefail
root=${1:?fixture root required}
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$root/.workflow/tasks" "$root/.workflow/efforts"
cat > "$root/.workflow/efforts/bulk.md" <<'EOF'
# Effort: bulk
Status: active
Priority: normal

## Goal
Keep large workflow projects responsive.
EOF
for ((n=1; n<=120; n++)); do
  printf -v number '%03d' "$n"
  blockers=None
  if (( n > 1 )); then blockers=$((n - 1)); fi
  cat > "$root/.workflow/tasks/$number-bulk.md" <<EOF
# $n: Bulk task $n
**Effort:** bulk
**Blocked by:** $blockers
**Check:** Verify result $n.
EOF
done
cp "$fixture_dir/decisions-large.md" "$root/.workflow/decisions.md"
