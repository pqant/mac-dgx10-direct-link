#!/usr/bin/env bash
# shellcheck disable=SC2016 # stub bodies are single-quoted on purpose
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
kver="6.17.0-1-nvidia"

# __repo_env - assembles a scripts/+config/+dkms/+patches/+system/ tree in a
# fresh temp dir (mirrors the real repo layout install.sh/uninstall.sh
# expect relative to their own location) and echoes its path.
__repo_env() {
  local tmp
  tmp="$(mk_tmp)"
  mkdir -p "$tmp/scripts" "$tmp/config" "$tmp/dkms" "$tmp/patches" \
    "$tmp/system/grub" "$tmp/system/udev" "$tmp/system/netplan" "$tmp/system/depmod.d" \
    "$tmp/system/tune" "$tmp/system/sysctl"
  cp "$root_dir/scripts/lib.sh" "$tmp/scripts/lib.sh"
  cp "$root_dir/scripts/install.sh" "$tmp/scripts/install.sh"
  cp "$root_dir/scripts/uninstall.sh" "$tmp/scripts/uninstall.sh"
  cp "$root_dir/scripts/secureboot-enroll.sh" "$tmp/scripts/secureboot-enroll.sh"
  cp "$root_dir/scripts/fetch-source.sh" "$tmp/scripts/fetch-source.sh"
  cp "$root_dir/config/pids.conf" "$tmp/config/pids.conf"
  cp "$root_dir/config/link.conf" "$tmp/config/link.conf"
  cp "$root_dir/dkms/dkms.conf" "$tmp/dkms/dkms.conf"
  cp "$root_dir/dkms/prepare.sh" "$tmp/dkms/prepare.sh"
  cp "$root_dir/dkms/Makefile.kbuild" "$tmp/dkms/Makefile.kbuild"
  cp "$root_dir/patches/gen-quirk-patch.sh" "$tmp/patches/gen-quirk-patch.sh"
  cp "$root_dir/system/grub/apple-ncm.cfg" "$tmp/system/grub/apple-ncm.cfg"
  cp "$root_dir/system/udev/90-apple-ncm.rules" "$tmp/system/udev/90-apple-ncm.rules"
  cp "$root_dir/system/netplan/60-apple-ncm.yaml" "$tmp/system/netplan/60-apple-ncm.yaml"
  cp "$root_dir/system/depmod.d/apple-ncm.conf" "$tmp/system/depmod.d/apple-ncm.conf"
  cp "$root_dir/system/tune/apple-ncm-tune" "$tmp/system/tune/apple-ncm-tune"
  cp "$root_dir/system/sysctl/60-apple-ncm.conf" "$tmp/system/sysctl/60-apple-ncm.conf"
  echo "$tmp"
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

# __stub_dir - a PATH dir with stubs for every external command install.sh
# and uninstall.sh call. Every stub appends its invocation to
# "$MGDL_ROOT/calls.log". `dkms status` reports empty until `dkms add` has
# run (tracked via a marker file under $MGDL_ROOT), to exercise the
# idempotent-add behavior. `modinfo -n cdc_ncm` reports a path under
# updates/dkms once $MGDL_ROOT/etc/depmod.d/apple-ncm.conf exists.
# sb_state/test_key select the mokutil --sb-state / --test-key output.
__stub_dir() {
  local sb_state="${1:-disabled}" test_key="${2:-is already enrolled}" dir
  dir="$(mk_tmp)"
  mk_stub "$dir" uname "echo '$kver'"
  mk_stub "$dir" make ':'
  mk_stub "$dir" gcc ':'
  mk_stub "$dir" dkms '
echo "dkms $*" >>"$MGDL_ROOT/calls.log"
case "$1" in
  status)
    [ -f "$MGDL_ROOT/.dkms-added" ] &&
      echo "apple-cdc-ncm/1.0.0, '"$kver"', x86_64: installed"
    ;;
  add)
    touch "$MGDL_ROOT/.dkms-added"
    ;;
  remove)
    if [ -f "$MGDL_ROOT/.dkms-remove-fail" ]; then
      exit 1
    fi
    rm -f "$MGDL_ROOT/.dkms-added"
    ;;
  install)
    :
    ;;
esac
true
'
  mk_stub "$dir" modinfo '
echo "modinfo $*" >>"$MGDL_ROOT/calls.log"
case "$*" in
  *"-F alias"*)
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in00*\n"
    ;;
  *"-n cdc_ncm"*)
    if [ -f "$MGDL_ROOT/etc/depmod.d/apple-ncm.conf" ]; then
      echo "/lib/modules/'"$kver"'/updates/dkms/cdc_ncm.ko"
    else
      echo "/lib/modules/'"$kver"'/kernel/drivers/net/usb/cdc_ncm.ko"
    fi
    ;;
esac
'
  mk_stub "$dir" depmod 'echo "depmod $*" >>"$MGDL_ROOT/calls.log"'
  mk_stub "$dir" update-grub 'echo "update-grub $*" >>"$MGDL_ROOT/calls.log"'
  mk_stub "$dir" udevadm 'echo "udevadm $*" >>"$MGDL_ROOT/calls.log"'
  mk_stub "$dir" netplan 'echo "netplan $*" >>"$MGDL_ROOT/calls.log"'
  mk_stub "$dir" nmcli 'echo "nmcli $*" >>"$MGDL_ROOT/calls.log"'
  mk_stub "$dir" sysctl 'echo "sysctl $*" >>"$MGDL_ROOT/calls.log"'
  mk_stub "$dir" mokutil '
echo "mokutil $*" >>"$MGDL_ROOT/calls.log"
case "$1" in
  --sb-state) echo "SecureBoot '"$sb_state"'" ;;
  --test-key) echo "'"$test_key"'" ;;
  --import) : ;;
esac
'
  echo "$dir"
}

# __good_env - a repo tree + stub dir + MGDL_ROOT with headers/module/cached
# source present for $kver, Secure Boot disabled. Echoes
# "repo|stub_dir|root".
__good_env() {
  local repo stub_dir root
  repo="$(__repo_env)"
  stub_dir="$(__stub_dir disabled)"
  root="$(mk_tmp)"
  mkdir -p "$root/lib/modules/$kver/build"
  mkdir -p "$root/lib/modules/$kver/kernel/drivers/net/usb"
  : >"$root/lib/modules/$kver/kernel/drivers/net/usb/cdc_ncm.ko"
  mkdir -p "$root/var/lib/mac-gx10-direct-link/src/$kver"
  __synthetic_src "$root/var/lib/mac-gx10-direct-link/src/$kver/cdc_ncm.c"
  : >"$root/calls.log"
  echo "$repo|$stub_dir|$root"
}

__run_install() {
  local repo="$1" stub_dir="$2" root="$3"
  shift 3
  PATH="$stub_dir:$PATH" MGDL_ROOT="$root" bash "$repo/scripts/install.sh" "$@"
}

__run_uninstall() {
  local repo="$1" stub_dir="$2" root="$3"
  shift 3
  PATH="$stub_dir:$PATH" MGDL_ROOT="$root" bash "$repo/scripts/uninstall.sh" "$@"
}

test_install_renders_files() {
  local parts repo stub_dir root rc=0
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out")"

  assert_contains "$(cat "$root/etc/default/grub.d/apple-ncm.cfg")" \
    "usbcore.quirks=05ac:1905:k,05ac:1902:k"
  assert_contains "$(cat "$root/etc/netplan/60-apple-ncm.yaml")" "addresses: [192.168.20.20/32]"
  # A /24 on the link would add a subnet route that could hijack another LAN.
  assert_not_contains "$(cat "$root/etc/netplan/60-apple-ncm.yaml")" "/24"
  assert_contains "$(cat "$root/etc/netplan/60-apple-ncm.yaml")" "macncm0"
  # Only a host route to the Mac: never a default route or gateway.
  assert_contains "$(cat "$root/etc/netplan/60-apple-ncm.yaml")" "routes: [{to: 192.168.20.17/32, scope: link}]"
  assert_not_contains "$(cat "$root/etc/netplan/60-apple-ncm.yaml")" "default"
  assert_not_contains "$(cat "$root/etc/netplan/60-apple-ncm.yaml")" "via"
  assert_not_contains "$(cat "$root/etc/netplan/60-apple-ncm.yaml")" "nameservers"
  assert_contains "$(cat "$root/etc/udev/rules.d/90-apple-ncm.rules")" 'NAME="macncm0"'
  assert_contains "$(cat "$root/etc/udev/rules.d/90-apple-ncm.rules")" 'NAME="macncm2"'
  # DRIVERS + ATTRS would need one parent to match both, which never happens.
  assert_not_contains "$(cat "$root/etc/udev/rules.d/90-apple-ncm.rules")" 'DRIVERS=='
  assert_contains "$(cat "$root/etc/udev/rules.d/90-apple-ncm.rules")" '/sys/bus/usb/drivers/cdc_ncm/bind'
  assert_contains "$(cat "$root/etc/udev/rules.d/90-apple-ncm.rules")" 'ENV{ID_USB_INTERFACE_NUM}!="00", ENV{NM_UNMANAGED}="1"'
  # Without a reload, a running NetworkManager keeps the old link address.
  assert_contains "$(cat "$root/calls.log")" "nmcli connection reload"
  assert_contains "$(cat "$root/etc/netplan/60-apple-ncm.yaml")" "mtu: 8178"
  # Tuning: the udev rule runs the rendered tune script for the link interface.
  assert_contains "$(cat "$root/etc/udev/rules.d/90-apple-ncm.rules")" 'ENV{ID_USB_INTERFACE_NUM}=="00", RUN+="/usr/bin/systemd-run --no-block --collect /usr/local/sbin/apple-ncm-tune"'
  assert_eq "yes" "$([ -x "$root/usr/local/sbin/apple-ncm-tune" ] && echo yes || echo no)"
  assert_contains "$(cat "$root/usr/local/sbin/apple-ncm-tune")" "IF=macncm0"
  assert_contains "$(cat "$root/usr/local/sbin/apple-ncm-tune")" "NTB_MAX=32764"
  assert_contains "$(cat "$root/usr/local/sbin/apple-ncm-tune")" "MTU=8178"
  assert_not_contains "$(cat "$root/usr/local/sbin/apple-ncm-tune")" "@"
  assert_contains "$(cat "$root/.out")" "reboot required"
  assert_contains "$(cat "$root/etc/sysctl.d/60-apple-ncm.conf")" "net.core.netdev_max_backlog = 10000"
  assert_contains "$(cat "$root/calls.log")" "sysctl -q -p $root/etc/sysctl.d/60-apple-ncm.conf"
}

test_install_quirk_active_applies_tuning_without_reboot() {
  local parts repo stub_dir root rc=0
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"
  mkdir -p "$root/proc" "$root/sys/class/net/macncm0/cdc_ncm"
  echo "ro quiet usbcore.quirks=05ac:1905:k,05ac:1902:k" >"$root/proc/cmdline"

  __run_install "$repo" "$stub_dir" "$root" --dry-run >"$root/.out" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out")"
  assert_contains "$(cat "$root/.out")" "DRY: $root/usr/local/sbin/apple-ncm-tune"
  assert_contains "$(cat "$root/.out")" "no reboot needed"
  assert_not_contains "$(cat "$root/.out")" "reboot required"
}

test_install_idempotent() {
  local parts repo stub_dir root rc=0 grub1 grub2 udev1 udev2 netplan1 netplan2
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out1" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out1")"
  grub1="$(cat "$root/etc/default/grub.d/apple-ncm.cfg")"
  udev1="$(cat "$root/etc/udev/rules.d/90-apple-ncm.rules")"
  netplan1="$(cat "$root/etc/netplan/60-apple-ncm.yaml")"

  rc=0
  __run_install "$repo" "$stub_dir" "$root" >"$root/.out2" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out2")"
  grub2="$(cat "$root/etc/default/grub.d/apple-ncm.cfg")"
  udev2="$(cat "$root/etc/udev/rules.d/90-apple-ncm.rules")"
  netplan2="$(cat "$root/etc/netplan/60-apple-ncm.yaml")"

  assert_eq "$grub1" "$grub2"
  assert_eq "$udev1" "$udev2"
  assert_eq "$netplan1" "$netplan2"
  # I4: install.sh now always removes+re-adds+reinstalls the DKMS module on
  # every run (so a pids.conf edit is always picked up), so re-running
  # install twice produces two `dkms add` calls, not one.
  assert_eq "2" "$(grep -c '^dkms add ' "$root/calls.log")"
}

test_install_rebuild_after_pids_change() {
  local parts repo stub_dir root rc=0 grub1 grub2
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out1" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out1")"
  grub1="$(cat "$root/etc/default/grub.d/apple-ncm.cfg")"
  assert_not_contains "$grub1" "05ac:1234:k"

  printf '1234\n' >>"$repo/config/pids.conf"

  rc=0
  __run_install "$repo" "$stub_dir" "$root" >"$root/.out2" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out2")"
  grub2="$(cat "$root/etc/default/grub.d/apple-ncm.cfg")"
  assert_contains "$grub2" "05ac:1234:k"

  assert_contains "$(cat "$root/calls.log")" "dkms remove apple-cdc-ncm/1.0.0 --all"
  assert_eq "2" "$(grep -c '^dkms add ' "$root/calls.log")"
  assert_eq "2" "$(grep -c '^dkms install ' "$root/calls.log")"
}

test_install_skips_old_kernels_silently() {
  local parts repo stub_dir root rc=0 old="6.11.0-1-nvidia"
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"
  mkdir -p "$root/lib/modules/$old/build" "$root/lib/modules/kernel"

  MGDL_STABLE_URL_TEMPLATE="file:///nonexistent/%s" \
    __run_install "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out")"
  assert_not_contains "$(cat "$root/.out")" "$old"
  assert_not_contains "$(cat "$root/.out")" "for kernel"
  assert_eq "1" "$(grep -c '^dkms install ' "$root/calls.log")"
  assert_contains "$(cat "$root/calls.log")" "dkms install -m apple-cdc-ncm -v 1.0.0 -k $kver"
}

test_install_invalid_pid_aborts_before_change() {
  local parts repo stub_dir root rc=0
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  printf '19g5\n' >"$repo/config/pids.conf"

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "64" "$rc" "$(cat "$root/.out")"
  assert_file_absent "$root/etc/default/grub.d/apple-ncm.cfg"
  assert_file_absent "$root/usr/src/apple-cdc-ncm-1.0.0"
  assert_eq "" "$(cat "$root/calls.log")"
}

test_install_invalid_link_conf_aborts_before_change() {
  local parts repo stub_dir root rc=0
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  printf 'GX10_IP=192.168.20.20/24\nMAC_IP=192.168.20.17/24\nMTU=1500\nIFACE_NUM=9\nIFACE_PREFIX=macncm\n' \
    >"$repo/config/link.conf"

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "64" "$rc" "$(cat "$root/.out")"
  assert_file_absent "$root/etc/default/grub.d/apple-ncm.cfg"
  assert_file_absent "$root/usr/src/apple-cdc-ncm-1.0.0"
  assert_eq "" "$(cat "$root/calls.log")"
}

test_install_secureboot_gate() {
  local parts repo root rc=0 stub_dir
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"
  stub_dir="$(__stub_dir enabled "needs to be enrolled")"

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "10" "$rc" "$(cat "$root/.out")"
  assert_contains "$(cat "$root/.out")" "secureboot-enroll.sh"
  assert_file_absent "$root/etc/default/grub.d/apple-ncm.cfg"
}

test_install_missing_tools() {
  local parts repo root rc=0 stub_dir real_stub_dir
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  real_stub_dir="${parts%%|*}"
  root="${parts#*|}"

  stub_dir="$(mk_tmp)"
  for cmd in make gcc modinfo depmod update-grub udevadm netplan uname; do
    cp "$real_stub_dir/$cmd" "$stub_dir/$cmd"
  done

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "2" "$rc" "$(cat "$root/.out")"
  assert_contains "$(cat "$root/.out")" "dkms"
}

test_uninstall_removes_all() {
  local parts repo stub_dir root rc=0
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out")"

  rc=0
  __run_uninstall "$repo" "$stub_dir" "$root" >"$root/.out2" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out2")"

  assert_file_absent "$root/etc/default/grub.d/apple-ncm.cfg"
  assert_file_absent "$root/etc/udev/rules.d/90-apple-ncm.rules"
  assert_file_absent "$root/etc/netplan/60-apple-ncm.yaml"
  assert_file_absent "$root/etc/depmod.d/apple-ncm.conf"
  assert_file_absent "$root/usr/local/sbin/apple-ncm-tune"
  assert_file_absent "$root/etc/sysctl.d/60-apple-ncm.conf"
  assert_file_absent "$root/usr/src/apple-cdc-ncm-1.0.0"
  assert_contains "$(cat "$root/calls.log")" "dkms remove apple-cdc-ncm/1.0.0 --all"
}

test_uninstall_dkms_remove_failure_warns_and_continues() {
  local parts repo stub_dir root rc=0
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  __run_install "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out")"

  touch "$root/.dkms-remove-fail"
  rc=0
  __run_uninstall "$repo" "$stub_dir" "$root" >"$root/.out2" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out2")"
  assert_contains "$(cat "$root/.out2")" "WARN"

  assert_file_absent "$root/etc/default/grub.d/apple-ncm.cfg"
  assert_file_absent "$root/etc/udev/rules.d/90-apple-ncm.rules"
  assert_file_absent "$root/etc/netplan/60-apple-ncm.yaml"
  assert_file_absent "$root/etc/depmod.d/apple-ncm.conf"
  assert_file_absent "$root/usr/src/apple-cdc-ncm-1.0.0"
}

test_uninstall_partial() {
  local parts repo stub_dir root rc=0
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  __run_uninstall "$repo" "$stub_dir" "$root" >"$root/.out" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out")"
}

test_dry_run_changes_nothing() {
  local parts repo stub_dir root rc=0
  parts="$(__good_env)"
  repo="${parts%%|*}"
  parts="${parts#*|}"
  stub_dir="${parts%%|*}"
  root="${parts#*|}"

  __run_install "$repo" "$stub_dir" "$root" --dry-run >"$root/.out" 2>&1 || rc=$?
  assert_eq "0" "$rc" "$(cat "$root/.out")"
  assert_contains "$(cat "$root/.out")" "DRY:"
  assert_file_absent "$root/etc/default/grub.d/apple-ncm.cfg"
  assert_file_absent "$root/etc/udev/rules.d/90-apple-ncm.rules"
  assert_file_absent "$root/etc/netplan/60-apple-ncm.yaml"
  assert_file_absent "$root/usr/src/apple-cdc-ncm-1.0.0"
}

run_tests
