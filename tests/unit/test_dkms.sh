#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031,SC2034 # PATH is scoped to subshells on purpose; MGDL_* vars are read by the sourced lib.sh
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
dkms_conf="$root_dir/dkms/dkms.conf"
prepare_sh="$root_dir/dkms/prepare.sh"
makefile_kbuild="$root_dir/dkms/Makefile.kbuild"
lib_sh="$root_dir/scripts/lib.sh"
fetch_source_sh="$root_dir/scripts/fetch-source.sh"
gen_quirk_patch_sh="$root_dir/patches/gen-quirk-patch.sh"

# __mods_env - builds $tmp/lib/modules/{A,B}/kernel/drivers/net/usb/cdc_ncm.ko,
# plus a modinfo stub that reports the Apple quirk present for kernel "A"
# only. Echoes "stub_dir|mods_dir".
__mods_env() {
  local tmp stub_dir mods_dir
  tmp="$(mk_tmp)"
  stub_dir="$(mk_tmp)"
  mods_dir="$tmp/lib/modules"
  mkdir -p "$mods_dir/A/kernel/drivers/net/usb" "$mods_dir/B/kernel/drivers/net/usb"
  : >"$mods_dir/A/kernel/drivers/net/usb/cdc_ncm.ko.zst"
  : >"$mods_dir/B/kernel/drivers/net/usb/cdc_ncm.ko.zst"
  mk_stub "$stub_dir" modinfo '
case "$*" in
  *"/A/"*)
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in00*\n"
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in02*\n"
    ;;
  *)
    printf "alias: usb:v05ACp12A8d*dc*dsc*dp*ic*isc*ip*in00*\n"
    ;;
esac
'
  echo "$stub_dir|$mods_dir"
}

test_dkms_conf_per_kernel() {
  local parts stub_dir mods_dir out
  parts="$(__mods_env)"
  stub_dir="${parts%%|*}"
  mods_dir="${parts#*|}"

  out="$(PATH="$stub_dir:$PATH" MGDL_MODULES_DIR="$mods_dir" kernelver=A \
    bash -c ". '$dkms_conf'; echo \"\${BUILD_EXCLUSIVE_KERNEL:-unset}\"")"
  assert_eq "^mgdl-upstream-quirk-present$" "$out"

  out="$(PATH="$stub_dir:$PATH" MGDL_MODULES_DIR="$mods_dir" kernelver=B \
    bash -c ". '$dkms_conf'; echo \"\${BUILD_EXCLUSIVE_KERNEL:-unset}\"")"
  assert_eq "unset" "$out"

  local tmp_out rc=0
  tmp_out="$(mk_tmp)/out.txt"
  PATH="$stub_dir:$PATH" MGDL_MODULES_DIR="$mods_dir" \
    bash -c ". '$dkms_conf'; echo \"\${BUILD_EXCLUSIVE_KERNEL:-unset}\"" >"$tmp_out" 2>&1 || rc=$?
  out="$(cat "$tmp_out")"
  assert_eq "0" "$rc"
  assert_eq "unset" "$out"
}

test_dkms_conf_matches_lib() {
  local parts stub_dir mods_dir decision_a decision_b lib_a_rc lib_b_rc
  parts="$(__mods_env)"
  stub_dir="${parts%%|*}"
  mods_dir="${parts#*|}"

  decision_a="$(PATH="$stub_dir:$PATH" MGDL_MODULES_DIR="$mods_dir" kernelver=A \
    bash -c ". '$dkms_conf'; echo \"\${BUILD_EXCLUSIVE_KERNEL:-unset}\"")"
  decision_b="$(PATH="$stub_dir:$PATH" MGDL_MODULES_DIR="$mods_dir" kernelver=B \
    bash -c ". '$dkms_conf'; echo \"\${BUILD_EXCLUSIVE_KERNEL:-unset}\"")"

  lib_a_rc=0
  (
    # shellcheck source=../../scripts/lib.sh
    source "$lib_sh"
    MGDL_MODULES_DIR="$mods_dir"
    PATH="$stub_dir:$PATH"
    kernel_has_quirk A
  ) || lib_a_rc=$?
  lib_b_rc=0
  (
    # shellcheck source=../../scripts/lib.sh
    source "$lib_sh"
    MGDL_MODULES_DIR="$mods_dir"
    PATH="$stub_dir:$PATH"
    kernel_has_quirk B
  ) || lib_b_rc=$?

  if [ "$lib_a_rc" = "0" ]; then
    assert_eq "^mgdl-upstream-quirk-present$" "$decision_a"
  else
    assert_eq "unset" "$decision_a"
  fi
  if [ "$lib_b_rc" = "0" ]; then
    assert_eq "^mgdl-upstream-quirk-present$" "$decision_b"
  else
    assert_eq "unset" "$decision_b"
  fi
}

# __build_dir_env - assembles the flat DKMS build-dir layout in a fresh temp
# dir and echoes "build_dir|state_dir".
__build_dir_env() {
  local build_dir state_dir
  build_dir="$(mk_tmp)"
  state_dir="$(mk_tmp)/state"
  mkdir -p "$state_dir"
  cp "$prepare_sh" "$build_dir/prepare.sh"
  cp "$lib_sh" "$build_dir/lib.sh"
  cp "$fetch_source_sh" "$build_dir/fetch-source.sh"
  cp "$gen_quirk_patch_sh" "$build_dir/gen-quirk-patch.sh"
  cp "$makefile_kbuild" "$build_dir/Makefile.kbuild"
  chmod +x "$build_dir/prepare.sh" "$build_dir/fetch-source.sh" "$build_dir/gen-quirk-patch.sh"
  printf '1905\n1902\n' >"$build_dir/pids.conf"
  echo "$build_dir|$state_dir"
}

__synthetic_src() {
  local file="$1" extra_pid="${2:-}"
  local info_line='static const struct driver_info apple_private_interface_info = { 0 };'
  local anchor_line='	/* Ericsson MBM devices like F5521gw */'
  {
    echo 'static int cdc_ncm_bind(struct usbnet *dev, struct usb_interface *intf) { return 0; }'
    echo 'static const struct usb_device_id cdc_devs[] = {'
    echo "$info_line"
    if [ -n "$extra_pid" ]; then
      printf '\t{ USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x%s, 0),\n' "$extra_pid"
      printf '\t\t.driver_info = (unsigned long)&apple_private_interface_info,\n'
      printf '\t},\n'
    fi
    echo "$anchor_line"
    echo '	{ .match_flags = USB_DEVICE_ID_MATCH_INT_INFO },'
    echo '};'
  } >"$file"
}

test_prepare_patches() {
  local parts build_dir state_dir stub_dir rc=0
  parts="$(__build_dir_env)"
  build_dir="${parts%%|*}"
  state_dir="${parts#*|}"
  stub_dir="$(mk_tmp)"

  mkdir -p "$state_dir/src/6.17.0-1-nvidia"
  __synthetic_src "$state_dir/src/6.17.0-1-nvidia/cdc_ncm.c"

  (
    cd "$build_dir" &&
      PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" \
        bash prepare.sh 6.17.0-1-nvidia
  ) || rc=$?
  assert_eq "0" "$rc"
  assert_contains "$(cat "$build_dir/cdc_ncm.c")" "0x1905, 2)"
  assert_eq "obj-m := cdc_ncm.o" "$(cat "$build_dir/Kbuild")"
}

test_prepare_cold_cache_message() {
  local parts build_dir state_dir stub_dir err rc=0
  parts="$(__build_dir_env)"
  build_dir="${parts%%|*}"
  state_dir="${parts#*|}"
  stub_dir="$(mk_tmp)"
  mk_stub "$stub_dir" curl 'exit 99'
  mk_stub "$stub_dir" dpkg-query 'exit 1'
  mk_stub "$stub_dir" uname 'echo "6.17.0-1-nvidia"'

  (
    cd "$build_dir" &&
      PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" \
        bash prepare.sh 6.17.0-1-nvidia
  ) 2>"$build_dir/.stderr" || rc=$?
  err="$(cat "$build_dir/.stderr")"
  assert_eq "1" "$rc"
  assert_contains "$err" "fetch-source.sh 6.17.0-1-nvidia"
}

test_prepare_skips_already_quirked_source() {
  local parts build_dir state_dir stub_dir err rc=0
  parts="$(__build_dir_env)"
  build_dir="${parts%%|*}"
  state_dir="${parts#*|}"
  stub_dir="$(mk_tmp)"

  mkdir -p "$state_dir/src/6.17.0-1-nvidia"
  __synthetic_src "$state_dir/src/6.17.0-1-nvidia/cdc_ncm.c" 1905

  (
    cd "$build_dir" &&
      PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" \
        bash prepare.sh 6.17.0-1-nvidia
  ) 2>"$build_dir/.stderr" || rc=$?
  err="$(cat "$build_dir/.stderr")"
  assert_eq "0" "$rc"
  assert_contains "$err" "already contains"
  assert_eq "$(cat "$state_dir/src/6.17.0-1-nvidia/cdc_ncm.c")" "$(cat "$build_dir/cdc_ncm.c")"
  assert_not_contains "$(cat "$build_dir/cdc_ncm.c")" "mac-dgx10-direct-link"
  assert_eq "obj-m := cdc_ncm.o" "$(cat "$build_dir/Kbuild")"
}

run_tests
