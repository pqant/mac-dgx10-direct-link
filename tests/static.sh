#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

status=0

# 1. No tracked text file may contain a carriage return (\r).
mapfile -t tracked_files < <(git ls-files -- '*.sh' '*.conf' '*.rules' '*.yaml' '*.cfg' '*.py')
for f in "${tracked_files[@]:-}"; do
  [ -n "$f" ] || continue
  if grep -Il $'\r' -- "$f" >/dev/null 2>&1; then
    echo "CRLF found in: $f" >&2
    status=1
  fi
done

# 2. shellcheck, if available, must be clean on all *.sh files.
if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t shell_files < <(git ls-files -- '*.sh')
  if [ "${#shell_files[@]}" -gt 0 ]; then
    if ! shellcheck -x "${shell_files[@]}"; then
      status=1
    fi
  fi
else
  echo "SKIP shellcheck (not installed)"
  if [ "${CI:-}" = "true" ]; then
    status=1
  fi
fi

# 3. Every tracked *.sh except sourced libraries must be committed executable.
while read -r mode _ _ path; do
  case "$path" in
    scripts/lib.sh|tests/lib/*) continue ;;
  esac
  if [ "$mode" != "100755" ]; then
    echo "not executable in git (mode $mode): $path" >&2
    status=1
  fi
done < <(git ls-files -s -- '*.sh')

exit "$status"
