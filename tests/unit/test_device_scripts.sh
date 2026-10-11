#!/usr/bin/env bash
# shellcheck disable=SC2016 # stub bodies are single-quoted on purpose
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"

# __repo_env - assembles a scripts/+config/+tests/ tree in a fresh temp dir
# (mirrors the real repo layout the device scripts expect relative to their
# own location) and echoes its path.
__repo_env() {
  local tmp
  tmp="$(mk_tmp)"
  mkdir -p "$tmp/scripts" "$tmp/config" "$tmp/tests"
  cp "$root_dir/scripts/lib.sh" "$tmp/scripts/lib.sh"
  cp "$root_dir/scripts/net-up.sh" "$tmp/scripts/net-up.sh"
  cp "$root_dir/scripts/doctor.sh" "$tmp/scripts/doctor.sh"
  cp "$root_dir/scripts/verify.sh" "$tmp/scripts/verify.sh"
  cp "$root_dir/config/pids.conf" "$tmp/config/pids.conf"
  cp "$root_dir/config/link.conf" "$tmp/config/link.conf"
  cp "$root_dir/tests/link.sh" "$tmp/tests/link.sh"
  cp "$root_dir/tests/bench.sh" "$tmp/tests/bench.sh"
  cp "$root_dir/tests/upgrade.sh" "$tmp/tests/upgrade.sh"
  echo "$tmp"
}

test_net_up_dry_run_default() {
  local repo stub_dir root out cnt
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  root="$(mk_tmp)"
  : >"$root/calls.log"
  mk_stub "$stub_dir" ip 'echo "ip $*" >>"$MGDL_ROOT/calls.log"'

  out="$(MGDL_ROOT="$root" PATH="$stub_dir:$PATH" bash "$repo/scripts/net-up.sh")"
  assert_contains "$out" "DRY: ip addr replace 192.168.20.20/24 dev macncm0"

  cnt="$(grep -c 'addr replace' "$root/calls.log")" || true
  assert_eq "0" "${cnt:-0}"
}

test_net_up_apply_uses_addr_replace() {
  local repo stub_dir root out
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  root="$(mk_tmp)"
  : >"$root/calls.log"
  mk_stub "$stub_dir" ip 'echo "ip $*" >>"$MGDL_ROOT/calls.log"'

  MGDL_ROOT="$root" PATH="$stub_dir:$PATH" bash "$repo/scripts/net-up.sh" --apply >/dev/null
  out="$(cat "$root/calls.log")"
  assert_contains "$out" "ip addr replace 192.168.20.20/24 dev macncm0"
  assert_contains "$out" "ip route replace 192.168.20.17/32 dev macncm0 scope link"
  assert_not_contains "$out" "ip addr add"
}

test_bench_parses_iperf_json() {
  local repo stub_dir out out_dir
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  mk_stub "$stub_dir" iperf3 'echo "{\"end\":{\"sum_received\":{\"bits_per_second\":5.2e9}}}"'
  mk_stub "$stub_dir" ping 'echo "round-trip min/avg/max/stddev = 0.100/0.200/0.300/0.010 ms"'
  mk_stub "$stub_dir" ip 'echo "192.168.20.17 dev macncm0 src 192.168.20.20 uid 0"'
  mk_stub "$stub_dir" lsusb 'echo "1-1: Dev 2: ID 05ac:1905 Apple Inc."'
  mk_stub "$stub_dir" uname 'echo "6.17.0-1-nvidia"'

  out="$(PATH="$stub_dir:$PATH" bash "$repo/tests/bench.sh")"
  assert_contains "$out" "fwd_gbps=5.20"

  out_dir="$(find "$repo/results" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  assert_file_exists "$out_dir/fwd.json"
  assert_file_exists "$out_dir/rev.json"
  assert_file_exists "$out_dir/ping.txt"
  assert_file_exists "$out_dir/meta.txt"
}

test_upgrade_post_requires_new_kernel() {
  local repo stub_dir rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  mk_stub "$stub_dir" uname 'echo "6.17.0-1-nvidia"'

  mkdir -p "$repo/results"
  echo "6.17.0-1-nvidia" >"$repo/results/upgrade-pre.txt"

  PATH="$stub_dir:$PATH" bash "$repo/tests/upgrade.sh" post >"$repo/.out" 2>&1 || rc=$?
  assert_eq "1" "$rc" "$(cat "$repo/.out")"
}

run_tests
