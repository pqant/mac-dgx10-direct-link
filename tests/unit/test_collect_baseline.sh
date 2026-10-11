#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

script_under_test="$(cd "$(dirname "$0")/../.." && pwd)/scripts/collect-baseline.sh"

__stub_env() {
  # Builds a stub dir with every external command the script touches and a
  # fake MGDL_ROOT tree. Echoes "$stub_dir $root_dir $sig_file" on success.
  local stub_dir root_dir sig_file
  stub_dir="$(mk_tmp)"
  root_dir="$(mk_tmp)"
  sig_file="$(mk_tmp)/version_signature"

  mk_stub "$stub_dir" uname 'echo "6.8.0-generic"'
  mk_stub "$stub_dir" mokutil 'echo "SecureBoot disabled"'
  mk_stub "$stub_dir" dkms 'echo "dkms-stub 3.0"'
  mk_stub "$stub_dir" update-grub 'echo "ok"'
  mk_stub "$stub_dir" dpkg-query 'echo "linux-signed-hwe-6.8 6.8.0-1"'
  mk_stub "$stub_dir" modinfo 'echo "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in*"'
  mk_stub "$stub_dir" lsusb 'echo "Bus 001 Device 002: ID 05ac:1905 Apple, Inc."'
  mk_stub "$stub_dir" udevadm 'echo "E: ID_USB_INTERFACE_NUM=00"'
  mk_stub "$stub_dir" ip 'echo "stubbed ip output"'
  mk_stub "$stub_dir" ethtool 'echo "driver: cdc_ncm"'

  mkdir -p "$root_dir/etc/default/grub.d"
  printf 'GRUB_DEFAULT=0\n' >"$root_dir/etc/default/grub"
  mkdir -p "$root_dir/etc/apt/sources.list.d"
  printf 'deb http://archive.ubuntu.com/ubuntu jammy main\n' >"$root_dir/etc/apt/sources.list"
  mkdir -p "$root_dir/sys/class/net/lo"
  printf '6.8.0-generic\n' >"$sig_file"

  echo "$stub_dir|$root_dir|$sig_file"
}

test_sections_in_order() {
  local env_parts stub_dir root_dir sig_file out
  env_parts="$(__stub_env)"
  stub_dir="${env_parts%%|*}"
  env_parts="${env_parts#*|}"
  root_dir="${env_parts%%|*}"
  sig_file="${env_parts#*|}"

  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root_dir" MGDL_VERSION_SIGNATURE="$sig_file" bash "$script_under_test")"

  local headers expected
  headers="$(grep -E '^## ' <<<"$out")"
  expected=$'## kernel\n## secureboot\n## dkms\n## grub\n## kernel-source-package\n## deb-src\n## cdc_ncm\n## usb\n## apple-interfaces\n## lan\n## ssh'
  assert_eq "$expected" "$headers" "section headers must appear in the required order"
}

test_missing_command_continues() {
  if command -v mokutil >/dev/null 2>&1; then
    echo "skip: a real mokutil is present on this host"
    return 0
  fi

  local env_parts stub_dir root_dir sig_file out
  env_parts="$(__stub_env)"
  stub_dir="${env_parts%%|*}"
  env_parts="${env_parts#*|}"
  root_dir="${env_parts%%|*}"
  sig_file="${env_parts#*|}"
  rm -f "$stub_dir/mokutil"

  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root_dir" MGDL_VERSION_SIGNATURE="$sig_file" bash "$script_under_test")"
  local rc=0
  PATH="$stub_dir:$PATH" MGDL_ROOT="$root_dir" MGDL_VERSION_SIGNATURE="$sig_file" bash "$script_under_test" >/dev/null || rc=$?

  assert_contains "$out" "mokutil: NOT INSTALLED" "missing command must be reported, not fatal"
  assert_eq "0" "$rc" "script must always exit 0"
}

test_no_sudo_in_script() {
  assert_not_contains "$(cat "$script_under_test")" "sudo" "read-only scripts must never call sudo"
}

run_tests
