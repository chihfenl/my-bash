#!/usr/bin/env bash
# Run every tests/NN_*.sh under both bash and zsh (cross-shell guarantee).
cd "$(dirname "$0")" || exit 1
status=0
for f in [0-9]*_*.sh; do
  [ -e "$f" ] || continue
  for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || continue
    printf '== %s (%s) ==\n' "$f" "$sh"
    "$sh" "$f" || status=1
  done
done
[ "$status" -eq 0 ] && printf '\nSUITE PASS\n' || printf '\nSUITE FAIL\n'
exit "$status"
