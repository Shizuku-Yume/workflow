#!/usr/bin/env bash
# Link the flow-* skills into an agent harness skill root.
#
# The harness loads one level under <root>/skills, so each skill must be its own
# directory with a SKILL.md. Linking (not copying) means edits in this repo take
# effect without reinstalling.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills"
usage() {
  printf 'usage: %s [skills-root] [--uninstall]\n' "$(basename "$0")"
  printf '  skills-root   defaults to ~/.agents (skills land in <root>/skills)\n'
}

UNINSTALL=0
ROOT=""
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    *) ROOT="$arg" ;;
  esac
done

ROOT="${ROOT:-$HOME/.agents}"
DEST="$ROOT/skills"

if [ ! -d "$SRC" ]; then
  printf 'no skills directory at %s\n' "$SRC" >&2
  exit 1
fi

mkdir -p "$DEST"

for dir in "$SRC"/*/; do
  name="$(basename "$dir")"
  [ -f "$dir/SKILL.md" ] || continue
  target="$DEST/$name"

  if [ "$UNINSTALL" = 1 ]; then
    if [ -L "$target" ]; then
      rm "$target"
      printf 'unlinked %s\n' "$name"
    elif [ -e "$target" ]; then
      printf 'skip %s: not a link, leaving it alone\n' "$name" >&2
    fi
    continue
  fi

  if [ -L "$target" ]; then
    rm "$target"
  elif [ -e "$target" ]; then
    printf 'skip %s: %s exists and is not a link\n' "$name" "$target" >&2
    continue
  fi

  ln -s "${dir%/}" "$target"
  printf 'linked %s -> %s\n' "$target" "${dir%/}"
done

if [ "$UNINSTALL" = 0 ]; then
  printf '\nRestart the agent, then check that the flow-* skills appear in its skill list.\n'
else
  printf '\nRestart the agent to drop the skills.\n'
fi
