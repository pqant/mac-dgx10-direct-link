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

run_tests
