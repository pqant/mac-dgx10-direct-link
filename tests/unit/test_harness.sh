#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

test_assert_eq_passes() {
  assert_eq "foo" "foo" "literal strings must match"
}

test_assert_exit_captures_code() {
  assert_exit 3 bash -c 'exit 3'
}

test_mk_stub_on_path() {
  local stub_dir
  stub_dir="$(mk_tmp)"
  mk_stub "$stub_dir" modinfo 'echo stubbed'
  PATH="$stub_dir:$PATH"
  assert_eq "stubbed" "$(modinfo)"
}

# test_meta_catches_non_last_assert_failure - regression test for I1: a test
# function whose FIRST assertion fails but whose LAST assertion passes must
# still be reported "not ok" by run_tests, not "ok".
test_meta_catches_non_last_assert_failure() {
  local tmp script out rc=0 assert_lib
  tmp="$(mk_tmp)"
  assert_lib="$(cd "$(dirname "$0")/../lib" && pwd)/assert.sh"
  script="$tmp/meta.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'source "%s"\n' "$assert_lib"
    printf 'test_should_fail() {\n'
    printf '  assert_eq "a" "b"\n'
    printf '  assert_eq "c" "c"\n'
    printf '}\n'
    printf 'run_tests\n'
  } >"$script"

  out="$(bash "$script" 2>&1)" || rc=$?
  assert_eq "1" "$rc" "$out"
  assert_contains "$out" "not ok test_should_fail" "$out"
}

run_tests
