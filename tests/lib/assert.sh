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

# __assert_fail MSG - prints MSG to stderr and records a failure for the
# test currently running (via $ASSERT_STATUS_FILE, set by run_tests), so
# run_tests can detect it even if it is not the test function's last
# command. Always returns 1.
__assert_fail() {
  echo "$1" >&2
  if [ -n "${ASSERT_STATUS_FILE:-}" ]; then
    echo fail >>"$ASSERT_STATUS_FILE"
  fi
  return 1
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    __assert_fail "assert_eq failed: expected [$expected] got [$actual] ${msg}"
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    __assert_fail "assert_contains failed: [$haystack] does not contain [$needle] ${msg}"
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    __assert_fail "assert_not_contains failed: [$haystack] contains [$needle] ${msg}"
    return 1
  fi
}

assert_exit() {
  local expected_code="$1"
  shift
  local actual_code=0
  "$@" || actual_code=$?
  if [ "$actual_code" != "$expected_code" ]; then
    __assert_fail "assert_exit failed: expected [$expected_code] got [$actual_code] for: $*"
    return 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [ ! -e "$path" ]; then
    __assert_fail "assert_file_exists failed: [$path] does not exist"
    return 1
  fi
}

assert_file_absent() {
  local path="$1"
  if [ -e "$path" ]; then
    __assert_fail "assert_file_absent failed: [$path] exists"
    return 1
  fi
}

# run_tests - runs every declared test_* function and reports "ok"/"not ok".
# A test is reported "not ok" if its last command fails (normal bash exit
# status) OR if any assert_* call inside it failed, even if that failure was
# not the function's last command (see I1: bash's `set -e` has no effect
# inside an `if` condition or a subshell run as one, so relying on the
# function's own exit status alone hides every non-last assertion failure).
# Each test runs with errexit disabled (so a failing assert does not abort
# the function before later asserts run) and reports failures through a
# per-test status file rather than through `set -e`.
run_tests() {
  local test_names test_name failed=0
  test_names=$(declare -F | awk '{print $3}' | grep '^test_' || true)
  for test_name in $test_names; do
    local status_file rc=0
    status_file="$(mktemp)"
    set +e
    (
      ASSERT_STATUS_FILE="$status_file"
      export ASSERT_STATUS_FILE
      "$test_name"
    )
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && [ ! -s "$status_file" ]; then
      echo "ok $test_name"
    else
      echo "not ok $test_name"
      failed=1
    fi
    rm -f "$status_file"
  done
  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
}
