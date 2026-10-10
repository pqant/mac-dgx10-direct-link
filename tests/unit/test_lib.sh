#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
lib_under_test="$root_dir/scripts/lib.sh"

# shellcheck source=../../scripts/lib.sh
source "$lib_under_test"

test_read_pids_normalizes() {
  local tmp pid_file out
  tmp="$(mk_tmp)"
  pid_file="$tmp/pids.conf"
  printf '%s' $'# c\r\n1905\r\n\r\n  1902  # mac\r\nABCD\r\n1905\r\n' >"$pid_file"
  out="$(read_pids "$pid_file")"
  assert_eq "$(printf '1905\n1902\nabcd')" "$out"
}

test_read_pids_rejects_invalid() {
  local tmp pid_file
  tmp="$(mk_tmp)"
  pid_file="$tmp/pids.conf"
  printf '19g5\n' >"$pid_file"
  assert_exit 64 read_pids "$pid_file"
}

test_load_link_conf_crlf() {
  local tmp conf bad
  tmp="$(mk_tmp)"
  conf="$tmp/link.conf"
  sed 's/$/\r/' "$root_dir/config/link.conf" >"$conf"
  load_link_conf "$conf"
  assert_eq "192.168.20.17/24" "$MAC_IP"

  bad="$tmp/link_bad.conf"
  printf 'GX10_IP=192.168.20.20/24\r\nMAC_IP=192.168.20.17/24\r\nMTU=1500\r\nIFACE_NUM=1\r\nIFACE_PREFIX=macncm\r\n' >"$bad"
  assert_exit 64 load_link_conf "$bad"
}

test_kernel_has_quirk_present() {
  local tmp stub_dir mods_dir kver
  tmp="$(mk_tmp)"
  stub_dir="$(mk_tmp)"
  kver="6.17.0-1-nvidia"
  mods_dir="$tmp/lib/modules"
  mkdir -p "$mods_dir/$kver/kernel/drivers/net/usb"
  : >"$mods_dir/$kver/kernel/drivers/net/usb/cdc_ncm.ko.zst"
  mk_stub "$stub_dir" modinfo 'printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in00*\nalias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in02*\n"'

  MGDL_MODULES_DIR="$mods_dir"
  PATH="$stub_dir:$PATH"
  assert_exit 0 kernel_has_quirk "$kver"
}

test_kernel_has_quirk_absent() {
  local tmp stub_dir mods_dir kver1 kver2
  tmp="$(mk_tmp)"
  stub_dir="$(mk_tmp)"
  kver1="6.17.0-1-nvidia"
  kver2="6.17.0-2-nvidia"
  mods_dir="$tmp/lib/modules"
  mkdir -p "$mods_dir/$kver1/kernel/drivers/net/usb"
  : >"$mods_dir/$kver1/kernel/drivers/net/usb/cdc_ncm.ko.zst"
  mk_stub "$stub_dir" modinfo 'printf "alias: usb:v05ACp12A8d*dc*dsc*dp*ic*isc*ip*in00*\n"'

  MGDL_MODULES_DIR="$mods_dir"
  PATH="$stub_dir:$PATH"
  assert_exit 1 kernel_has_quirk "$kver1"
  assert_exit 2 kernel_has_quirk "$kver2"
}

test_upstream_version_signature() {
  local tmp stub_dir sig_file kver out
  tmp="$(mk_tmp)"
  stub_dir="$(mk_tmp)"
  sig_file="$tmp/version_signature"
  kver="6.17.0-1-nvidia"
  printf 'Ubuntu 6.17.0-1.1-nvidia 6.17.9\n' >"$sig_file"
  mk_stub "$stub_dir" uname 'echo "6.17.0-1-nvidia"'

  unset -v MGDL_UPSTREAM_VERSION || true
  MGDL_VERSION_SIGNATURE="$sig_file"
  PATH="$stub_dir:$PATH"
  out="$(upstream_version "$kver")"
  assert_eq "6.17.9" "$out"
}

test_upstream_version_changelog() {
  local tmp stub_dir root changelog_dir changelog_path kver out
  tmp="$(mk_tmp)"
  stub_dir="$(mk_tmp)"
  root="$tmp/root"
  kver="6.17.0-2-nvidia"
  changelog_dir="$root/usr/share/doc/linux-image-$kver"
  mkdir -p "$changelog_dir"
  changelog_path="$changelog_dir/changelog.Debian.gz"
  if command -v gzip >/dev/null 2>&1; then
    printf '  * Upstream stable to v6.17.4\n' | gzip -c >"$changelog_path"
  else
    mk_stub "$stub_dir" zcat 'printf "  * Upstream stable to v6.17.4\n"'
    : >"$changelog_path"
  fi
  mk_stub "$stub_dir" uname 'echo "6.17.0-1-nvidia"'

  unset -v MGDL_UPSTREAM_VERSION || true
  MGDL_ROOT="$root"
  PATH="$stub_dir:$PATH"
  out="$(upstream_version "$kver")"
  assert_eq "6.17.4" "$out"
}

test_upstream_version_mismatch_refused() {
  local tmp stub_dir sig_file kver
  tmp="$(mk_tmp)"
  stub_dir="$(mk_tmp)"
  sig_file="$tmp/version_signature"
  kver="6.17.0-1-nvidia"
  printf 'Ubuntu 6.17.0-1.1-nvidia 6.16.3\n' >"$sig_file"
  mk_stub "$stub_dir" uname 'echo "6.17.0-1-nvidia"'

  unset -v MGDL_UPSTREAM_VERSION || true
  MGDL_VERSION_SIGNATURE="$sig_file"
  PATH="$stub_dir:$PATH"
  assert_exit 1 upstream_version "$kver"
}

test_stable_tag() {
  assert_eq "v6.17" "$(stable_tag 6.17.0)"
  assert_eq "v6.17.9" "$(stable_tag 6.17.9)"
}

run_tests
