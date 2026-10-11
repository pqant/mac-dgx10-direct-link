#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
script_under_test="$root_dir/patches/gen-quirk-patch.sh"
cache_dir="$root_dir/tests/fixtures/cache"

__pids_file() {
  local dir="$1"
  shift
  printf '%s\n' "$@" >"$dir/pids.conf"
}

__synthetic_src() {
  local dir="$1" with_info="${2:-1}" with_anchor="${3:-1}" extra_pid="${4:-}"
  local info_line='static const struct driver_info apple_private_interface_info = { 0 };'
  local anchor_line='	/* Ericsson MBM devices like F5521gw */'
  {
    echo 'static const struct usb_device_id cdc_devs[] = {'
    if [ "$with_info" = "1" ]; then
      echo "$info_line"
    fi
    if [ -n "$extra_pid" ]; then
      printf '\t{ USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x%s, 0),\n' "$extra_pid"
      printf '\t\t.driver_info = (unsigned long)&apple_private_interface_info,\n'
      printf '\t},\n'
    fi
    if [ "$with_anchor" = "1" ]; then
      echo "$anchor_line"
    fi
    echo '	{ .match_flags = USB_DEVICE_ID_MATCH_INT_INFO },'
    echo '};'
  } >"$dir/cdc_ncm.c"
}

test_patches_synthetic() {
  local tmp out rc=0
  tmp="$(mk_tmp)"
  __synthetic_src "$tmp"
  __pids_file "$tmp" 1905 1902

  out="$(bash "$script_under_test" "$tmp/cdc_ncm.c" "$tmp/pids.conf")" || rc=$?
  assert_eq "0" "$rc"

  local count anchor_line last_pid_line
  count="$(grep -c 'USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x19' <<<"$out")"
  assert_eq "4" "$count"

  anchor_line="$(grep -n 'Ericsson MBM devices' <<<"$out" | head -n1 | cut -d: -f1)"
  last_pid_line="$(grep -n 'USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x19' <<<"$out" | tail -n1 | cut -d: -f1)"
  if [ "$last_pid_line" -ge "$anchor_line" ]; then
    echo "expected all PID lines before the anchor" >&2
    return 1
  fi
}

test_already_present_exit3() {
  local tmp out rc=0
  tmp="$(mk_tmp)"
  __synthetic_src "$tmp" 1 1 1905
  __pids_file "$tmp" 1905 1902

  out="$(bash "$script_under_test" "$tmp/cdc_ncm.c" "$tmp/pids.conf")" || rc=$?
  assert_eq "3" "$rc"
  assert_eq "" "$out"
}

test_missing_info_exit4() {
  local tmp rc=0
  tmp="$(mk_tmp)"
  __synthetic_src "$tmp" 0 1
  __pids_file "$tmp" 1905

  bash "$script_under_test" "$tmp/cdc_ncm.c" "$tmp/pids.conf" >/dev/null 2>&1 || rc=$?
  assert_eq "4" "$rc"
}

test_missing_anchor_exit5() {
  local tmp rc=0
  tmp="$(mk_tmp)"
  __synthetic_src "$tmp" 1 0
  __pids_file "$tmp" 1905

  bash "$script_under_test" "$tmp/cdc_ncm.c" "$tmp/pids.conf" >/dev/null 2>&1 || rc=$?
  assert_eq "5" "$rc"
}

test_real_v617() {
  local src="$cache_dir/v6.17/cdc_ncm.c"
  if [ ! -s "$src" ]; then
    echo "skip: $src not present (offline)"
    return 0
  fi
  local tmp out rc=0
  tmp="$(mk_tmp)"
  __pids_file "$tmp" 1905 1902

  out="$(bash "$script_under_test" "$src" "$tmp/pids.conf")" || rc=$?
  assert_eq "0" "$rc"

  printf '%s\n' "$out" >"$tmp/patched.c"
  local diff_out removed
  diff_out="$(diff -u "$src" "$tmp/patched.c" || true)"
  removed="$(grep -c '^-[^-]' <<<"$diff_out" || true)"
  assert_eq "0" "$removed" "real v6.17 patch must be additions only"
}

test_real_v71_noop() {
  local src="$cache_dir/v7.1/cdc_ncm.c"
  if [ ! -s "$src" ]; then
    echo "skip: $src not present (offline)"
    return 0
  fi
  local tmp rc=0
  tmp="$(mk_tmp)"
  __pids_file "$tmp" 1905 1902

  bash "$script_under_test" "$src" "$tmp/pids.conf" >/dev/null 2>&1 || rc=$?
  assert_eq "3" "$rc"
}

test_semantic_equals_upstream() {
  local src_old="$cache_dir/v6.17/cdc_ncm.c"
  local src_new="$cache_dir/v7.1/cdc_ncm.c"
  if [ ! -s "$src_old" ] || [ ! -s "$src_new" ]; then
    echo "skip: fixtures not present (offline)"
    return 0
  fi
  local tmp out rc=0
  tmp="$(mk_tmp)"
  __pids_file "$tmp" 1905 1902

  out="$(bash "$script_under_test" "$src_old" "$tmp/pids.conf")" || rc=$?
  assert_eq "0" "$rc"

  local generated_tuples upstream_tuples
  generated_tuples="$(grep -oE 'USB_DEVICE_INTERFACE_NUMBER\(0x05ac, 0x19[0-9a-f]{2}, [02]\)' <<<"$out" | sort -u)"
  upstream_tuples="$(grep -oE 'USB_DEVICE_INTERFACE_NUMBER\(0x05ac, 0x19[0-9a-f]{2}, [02]\)' "$src_new" | sort -u)"

  local tuple
  while IFS= read -r tuple; do
    [ -n "$tuple" ] || continue
    if ! grep -qF "$tuple" <<<"$generated_tuples"; then
      echo "missing upstream tuple: $tuple" >&2
      return 1
    fi
  done <<<"$upstream_tuples"

  while IFS= read -r tuple; do
    [ -n "$tuple" ] || continue
    local line_no next_line
    line_no="$(grep -nF "$tuple" <<<"$out" | head -n1 | cut -d: -f1)"
    next_line="$(sed -n "$((line_no + 1))p" <<<"$out")"
    assert_contains "$next_line" '.driver_info = (unsigned long)&apple_private_interface_info,'
  done <<<"$generated_tuples"
}

run_tests
