#!/usr/bin/env bash
# shellcheck shell=bash
# Minimal plain-bash assertion and test-runner library for tests/unit/*.sh.
set -euo pipefail

# Accumulated temp dirs created by mk_tmp, removed once on EXIT.
__assert_tmp_dirs=()

__assert_cleanup_tmp_dirs() {
  local dir
  for dir in "${__assert_tmp_dirs[@]:-}"; do
    if [ -n "$dir" ] && [ -d "$dir" ]; then
      rm -rf -- "$dir"
    fi
  done
  return 0
}
trap __assert_cleanup_tmp_dirs EXIT

mk_tmp() {
  local dir
  dir="$(mktemp -d)"
  __assert_tmp_dirs+=("$dir")
  echo "$dir"
}

mk_stub() {
  local dir="$1" name="$2" body="$3"
  mkdir -p "$dir"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$body"
  } >"$dir/$name"
  chmod +x "$dir/$name"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "assert_eq failed: expected [$expected] got [$actual] ${msg}" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "assert_contains failed: [$haystack] does not contain [$needle] ${msg}" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "assert_not_contains failed: [$haystack] contains [$needle] ${msg}" >&2
    return 1
  fi
}

assert_exit() {
  local expected_code="$1"
  shift
  local actual_code=0
  "$@" || actual_code=$?
  if [ "$actual_code" != "$expected_code" ]; then
    echo "assert_exit failed: expected [$expected_code] got [$actual_code] for: $*" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [ ! -e "$path" ]; then
    echo "assert_file_exists failed: [$path] does not exist" >&2
    return 1
  fi
}

assert_file_absent() {
  local path="$1"
  if [ -e "$path" ]; then
    echo "assert_file_absent failed: [$path] exists" >&2
    return 1
  fi
}

run_tests() {
  local test_names test_name failed=0
  test_names=$(declare -F | awk '{print $3}' | grep '^test_' || true)
  for test_name in $test_names; do
    if (set -euo pipefail; "$test_name"); then
      echo "ok $test_name"
    else
      echo "not ok $test_name"
      failed=1
    fi
  done
  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
}
