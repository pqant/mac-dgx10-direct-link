#!/usr/bin/env bash
set -euo pipefail

# Resolve a usable Python interpreter for later tasks (research/tests, Task 15+).
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  PYTHON="python"
fi
export PYTHON

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
tests_dir="$root_dir/tests/unit"

status=0

for test_file in "$tests_dir"/test_*.sh; do
  [ -e "$test_file" ] || continue
  echo "# $test_file"
  if ! bash "$test_file"; then
    status=1
  fi
done

if [ -d "$root_dir/research/tests" ]; then
  echo "# research/tests (python unittest discovery)"
  if ! "$PYTHON" -m unittest discover -s "$root_dir/research/tests"; then
    status=1
  fi
fi

exit "$status"
