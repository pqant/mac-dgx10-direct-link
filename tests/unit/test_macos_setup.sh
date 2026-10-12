#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root_dir/macos/setup.sh"

stub_networksetup() {
  local dir=$1
  mk_stub "$dir" networksetup "echo \"\$*\" >>\"$dir/calls\"
if [ \"\$1\" = -listallhardwareports ]; then
  printf 'Hardware Port: Wi-Fi\nDevice: en0\n\nHardware Port: Ethernet Adapter (en3)\nDevice: en3\n'
fi"
}

test_setup_persists_ip_and_mtu() {
  local tmp calls
  tmp="$(mk_tmp)"
  stub_networksetup "$tmp"
  PATH="$tmp:$PATH" LINK_CONF="$root_dir/config/link.conf" bash "$script" >/dev/null
  calls="$(cat "$tmp/calls")"
  assert_contains "$calls" "-setmanual Ethernet Adapter (en3) 192.168.20.17 255.255.255.0"
  assert_contains "$calls" "-setMTU en3 8178"
}

test_setup_mask_for_non_octet_prefix() {
  local tmp
  tmp="$(mk_tmp)"
  stub_networksetup "$tmp"
  printf 'MAC_IP=192.168.20.17/26\r\nMTU=1500\r\n' >"$tmp/link.conf"
  PATH="$tmp:$PATH" LINK_CONF="$tmp/link.conf" bash "$script" >/dev/null
  assert_contains "$(cat "$tmp/calls")" "192.168.20.17 255.255.255.192"
}

test_setup_fails_for_unknown_interface() {
  local tmp
  tmp="$(mk_tmp)"
  stub_networksetup "$tmp"
  PATH="$tmp:$PATH" LINK_CONF="$root_dir/config/link.conf" assert_exit 1 bash "$script" en9
  assert_not_contains "$(cat "$tmp/calls")" "-setmanual"
}

run_tests
