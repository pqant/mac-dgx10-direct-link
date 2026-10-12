#!/usr/bin/env bash
# shellcheck disable=SC2016 # stub bodies are single-quoted on purpose
set -euo pipefail

# Ensure `ln -s` creates real symlinks (not Windows junctions) on Git Bash
# hosts; no-op / harmless on Linux CI.
if [ -n "${MSYS:-}" ]; then
  export MSYS="$MSYS winsymlinks:nativestrict"
else
  export MSYS="winsymlinks:nativestrict"
fi

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
lib_sh="$root_dir/scripts/lib.sh"
check_kernel_support_sh="$root_dir/scripts/check-kernel-support.sh"
verify_sh="$root_dir/scripts/verify.sh"
doctor_sh="$root_dir/scripts/doctor.sh"
pids_conf="$root_dir/config/pids.conf"
link_conf="$root_dir/config/link.conf"

# __repo_env - assembles a scripts/+config/ tree in a fresh temp dir and
# echoes its path.
__repo_env() {
  local tmp
  tmp="$(mk_tmp)"
  mkdir -p "$tmp/scripts" "$tmp/config"
  cp "$lib_sh" "$tmp/scripts/lib.sh"
  cp "$check_kernel_support_sh" "$tmp/scripts/check-kernel-support.sh"
  cp "$verify_sh" "$tmp/scripts/verify.sh"
  cp "$doctor_sh" "$tmp/scripts/doctor.sh"
  cp "$pids_conf" "$tmp/config/pids.conf"
  cp "$link_conf" "$tmp/config/link.conf"
  echo "$tmp"
}

test_verify_dkms_status_scoped_to_our_module() {
  local repo stub_dir mods_dir state_dir root grub_dir cmdline_file out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  root="$(mk_tmp)"
  mods_dir="$root/lib/modules"
  state_dir="$root/var/lib/mac-dgx10-direct-link"
  grub_dir="$root/etc/default/grub.d"
  cmdline_file="$root/proc_cmdline"

  # Kernel "A" has no in-tree quirk and no cdc_ncm.c cached, so the only way
  # the "dkms status installed OR in-tree quirk" check can PASS is a real
  # apple-cdc-ncm/1.0.0 DKMS install for kernel A.
  mkdir -p "$mods_dir/A/kernel/drivers/net/usb"
  : >"$mods_dir/A/kernel/drivers/net/usb/cdc_ncm.ko"
  mkdir -p "$grub_dir"
  : >"$grub_dir/apple-ncm.cfg"
  printf 'BOOT_IMAGE=/vmlinuz usbcore.quirks=05ac:1905:k,05ac:1902:k root=/dev/sda1\n' >"$cmdline_file"

  mk_stub "$stub_dir" modinfo '
case "$*" in
  "-k A -F alias cdc_ncm")
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in00*\n"
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in02*\n"
    ;;
  "-k A -n cdc_ncm")
    echo "/lib/modules/A/kernel/drivers/net/usb/cdc_ncm.ko"
    ;;
  *)
    exit 1
    ;;
esac
'
  # I6: an unrelated DKMS module ("nvidia") is installed for kernel A, and
  # the old unscoped "dkms status | grep $k.*installed" would false-PASS on
  # it. The scoped query for apple-cdc-ncm must return nothing here.
  mk_stub "$stub_dir" uname 'echo "A"'
  mk_stub "$stub_dir" dkms '
case "$*" in
  "status -m apple-cdc-ncm -v 1.0.0 -k A")
    exit 0
    ;;
  status)
    echo "nvidia/580.95, A, x86_64: installed"
    ;;
  *)
    exit 1
    ;;
esac
'

  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root" MGDL_MODULES_DIR="$mods_dir" \
    MGDL_STATE_DIR="$state_dir" MGDL_PROC_CMDLINE="$cmdline_file" \
    bash "$repo/scripts/verify.sh")" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "FAIL A: dkms status installed OR in-tree quirk"
}

test_verify_mixed_kernels() {
  local repo stub_dir mods_dir state_dir root grub_dir cmdline_file out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  root="$(mk_tmp)"
  mods_dir="$root/lib/modules"
  state_dir="$root/var/lib/mac-dgx10-direct-link"
  grub_dir="$root/etc/default/grub.d"
  cmdline_file="$root/proc_cmdline"

  mkdir -p "$mods_dir/6.0.0-a/kernel/drivers/net/usb" "$mods_dir/6.0.0-b/kernel/drivers/net/usb"
  : >"$mods_dir/6.0.0-a/kernel/drivers/net/usb/cdc_ncm.ko"
  : >"$mods_dir/6.0.0-b/kernel/drivers/net/usb/cdc_ncm.ko"
  mkdir -p "$state_dir/src/6.0.0-b"
  : >"$state_dir/src/6.0.0-b/cdc_ncm.c"
  mkdir -p "$grub_dir"
  : >"$grub_dir/apple-ncm.cfg"
  printf 'BOOT_IMAGE=/vmlinuz usbcore.quirks=05ac:1905:k,05ac:1902:k root=/dev/sda1\n' >"$cmdline_file"

  mk_stub "$stub_dir" modinfo '
args="$*"
case "$args" in
  "-k 6.0.0-a -F alias cdc_ncm" | "-k 6.0.0-b -F alias cdc_ncm")
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in00*\n"
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in02*\n"
    ;;
  "-k 6.0.0-c -F alias cdc_ncm")
    printf "alias: usb:v05ACp12A8d*dc*dsc*dp*ic*isc*ip*in00*\n"
    ;;
  *"-F alias"*"/6.0.0-a/"*)
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in00*\n"
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in02*\n"
    ;;
  *"-F alias"*)
    printf "alias: usb:v05ACp12A8d*dc*dsc*dp*ic*isc*ip*in00*\n"
    ;;
  "-k 6.0.0-a -n cdc_ncm")
    echo "/lib/modules/6.0.0-a/kernel/drivers/net/usb/cdc_ncm.ko"
    ;;
  "-k 6.0.0-b -n cdc_ncm")
    echo "/lib/modules/6.0.0-b/updates/dkms/cdc_ncm.ko"
    ;;
  "-k 6.0.0-c -n cdc_ncm")
    echo "/lib/modules/6.0.0-c/kernel/drivers/net/usb/cdc_ncm.ko"
    ;;
  *)
    exit 1
    ;;
esac
'
  mk_stub "$stub_dir" dkms '
case "$*" in
  "status -m apple-cdc-ncm -v 1.0.0 -k 6.0.0-b")
    echo "apple-cdc-ncm/1.0.0, 6.0.0-b, x86_64: installed"
    ;;
  *)
    exit 1
    ;;
esac
'

  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root" MGDL_MODULES_DIR="$mods_dir" \
    MGDL_STATE_DIR="$state_dir" MGDL_PROC_CMDLINE="$cmdline_file" \
    bash "$repo/scripts/verify.sh" --all-kernels)" || rc=$?
  assert_eq "0" "$rc"
  assert_not_contains "$out" "FAIL"

  mkdir -p "$mods_dir/6.0.0-c/kernel/drivers/net/usb"
  : >"$mods_dir/6.0.0-c/kernel/drivers/net/usb/cdc_ncm.ko"

  rc=0
  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root" MGDL_MODULES_DIR="$mods_dir" \
    MGDL_STATE_DIR="$state_dir" MGDL_PROC_CMDLINE="$cmdline_file" \
    bash "$repo/scripts/verify.sh" --all-kernels)" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "FAIL 6.0.0-c:"
  assert_not_contains "$(grep 'FAIL' <<<"$out" | grep -v '^FAIL 6.0.0-c:' || true)" "FAIL"
}

test_doctor_unknown_pid() {
  local repo stub_dir out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  mk_stub "$stub_dir" lsusb 'echo "Bus 001 Device 003: ID 05ac:1906 Apple, Inc."'

  out="$(PATH="$stub_dir:$PATH" bash "$repo/scripts/doctor.sh")" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "not in config/pids.conf"
}

test_doctor_wrong_route() {
  local repo stub_dir out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  mk_stub "$stub_dir" lsusb 'echo "Bus 001 Device 003: ID 05ac:1905 Apple, Inc."'
  mk_stub "$stub_dir" ip '
case "$*" in
  "-o addr show dev macncm0")
    echo "3: macncm0    inet 192.168.20.20/24 brd 192.168.20.255 scope global macncm0"
    ;;
  "route get 192.168.20.17")
    echo "192.168.20.17 dev wlan0 src 172.16.0.5 uid 1000"
    ;;
  *)
    exit 1
    ;;
esac
'

  out="$(PATH="$stub_dir:$PATH" bash "$repo/scripts/doctor.sh")" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "FAIL route to 192.168.20.17 via macncm0"
}

# __tuned_net ROOT - builds a macncm0 bound to cdc_ncm under a fake xHCI with
# root hubs usb3/usb4, with the throughput tuning from config/link.conf applied.
__tuned_net() {
  local root="$1" ctrl net="$1/sys/class/net/macncm0"
  ctrl="$root/sys/devices/pci0000:00/0000:00:14.0"
  mkdir -p "$ctrl/usb3" "$ctrl/usb4/4-1/4-1:1.0" "$root/sys/bus/usb/drivers/cdc_ncm"
  ln -s "$root/sys/bus/usb/drivers/cdc_ncm" "$ctrl/usb4/4-1/4-1:1.0/driver"
  mkdir -p "$net/cdc_ncm" "$net/queues/rx-0"
  ln -s "$ctrl/usb4/4-1/4-1:1.0" "$net/device"
  echo 8178 >"$net/mtu"
  echo 10000 >"$net/tx_queue_len"
  echo 32764 >"$net/cdc_ncm/rx_max"
  echo 32764 >"$net/cdc_ncm/tx_max"
  echo 000003c0 >"$net/queues/rx-0/rps_cpus"
  mkdir -p "$root/proc/irq/33"
  printf ' 33:  10  20  GICv3 108 Level  xhci-hcd:usb3\n' >"$root/proc/interrupts"
  echo 5 >"$root/proc/irq/33/smp_affinity_list"
}

test_doctor_healthy() {
  local repo stub_dir root out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  root="$(mk_tmp)"

  mkdir -p "$root/sys/bus/usb/devices/1-1"
  printf '05ac' >"$root/sys/bus/usb/devices/1-1/idVendor"
  printf '1905' >"$root/sys/bus/usb/devices/1-1/idProduct"
  printf '5000' >"$root/sys/bus/usb/devices/1-1/speed"

  __tuned_net "$root"

  mkdir -p "$(dirname "$root/sys/module/usbcore/parameters/quirks")"
  printf '05ac:1905:k,05ac:1902:k' >"$root/sys/module/usbcore/parameters/quirks"

  mk_stub "$stub_dir" lsusb 'echo "Bus 001 Device 003: ID 05ac:1905 Apple, Inc."'
  mk_stub "$stub_dir" ip '
case "$*" in
  "-o addr show dev macncm0")
    echo "3: macncm0    inet 192.168.20.20/24 brd 192.168.20.255 scope global macncm0"
    ;;
  "route get 192.168.20.17")
    echo "192.168.20.17 dev macncm0 src 192.168.20.20 uid 1000"
    ;;
  *)
    exit 1
    ;;
esac
'
  mk_stub "$stub_dir" mokutil 'echo "SecureBoot enabled"'
  mk_stub "$stub_dir" dmesg 'echo "cdc_ncm 1-1:1.0 macncm0: register .. link up"'

  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root" \
    MGDL_USBCORE_QUIRKS="$root/sys/module/usbcore/parameters/quirks" \
    bash "$repo/scripts/doctor.sh")" || rc=$?
  assert_eq "0" "$rc"
  assert_not_contains "$out" "FAIL"
}

test_doctor_literal_ip_match_not_regex() {
  local repo stub_dir out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  mk_stub "$stub_dir" lsusb 'echo "Bus 001 Device 003: ID 05ac:1905 Apple, Inc."'
  # M8: without -F, GX10_IP "192.168.20.20" is a regex where '.' matches any
  # char, so an address that merely has the same shape (but isn't the
  # configured IP) would wrongly match.
  mk_stub "$stub_dir" ip '
case "$*" in
  "-o addr show dev macncm0")
    echo "3: macncm0    inet 192a168b20c20/24 brd 192.168.20.255 scope global macncm0"
    ;;
  "route get 192.168.20.17")
    echo "192.168.20.17 dev wlan0 src 172.16.0.5 uid 1000"
    ;;
  *)
    exit 1
    ;;
esac
'

  out="$(PATH="$stub_dir:$PATH" bash "$repo/scripts/doctor.sh")" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "FAIL macncm0 has 192.168.20.20/24"
}

test_doctor_missing_tuning() {
  local repo stub_dir root out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  root="$(mk_tmp)"
  __tuned_net "$root"
  # Tuning lost, e.g. a replug before the udev rule was installed.
  echo 1500 >"$root/sys/class/net/macncm0/mtu"
  echo 0 >"$root/sys/class/net/macncm0/queues/rx-0/rps_cpus"
  echo 0-19 >"$root/proc/irq/33/smp_affinity_list"
  mk_stub "$stub_dir" lsusb 'echo "Bus 004 Device 002: ID 05ac:1905 Apple, Inc."'
  mk_stub "$stub_dir" ip 'exit 1'
  mk_stub "$stub_dir" dmesg 'exit 1'

  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root" bash "$repo/scripts/doctor.sh")" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "FAIL macncm0 mtu = 8178 (found 1500)"
  assert_contains "$out" "FAIL macncm0 rps_cpus = 3c0 (found 0)"
  assert_contains "$out" "FAIL xHCI IRQ 33 affinity = 5 (found 0-19)"
  assert_contains "$out" "PASS macncm0 NTB rx_max = 32764"
}

test_doctor_lpm_quirk_checks_all_configured_pids() {
  local repo stub_dir root out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  root="$(mk_tmp)"

  mkdir -p "$root/sys/bus/usb/devices/1-1"
  printf '05ac' >"$root/sys/bus/usb/devices/1-1/idVendor"
  printf '1905' >"$root/sys/bus/usb/devices/1-1/idProduct"
  printf '5000' >"$root/sys/bus/usb/devices/1-1/speed"

  __tuned_net "$root"

  # M8: config/pids.conf has both 1905 and 1902, but the usbcore quirks
  # mask only carries 1905 - the per-PID check must catch the missing 1902.
  mkdir -p "$(dirname "$root/sys/module/usbcore/parameters/quirks")"
  printf '05ac:1905:k' >"$root/sys/module/usbcore/parameters/quirks"

  mk_stub "$stub_dir" lsusb 'echo "Bus 001 Device 003: ID 05ac:1905 Apple, Inc."'
  mk_stub "$stub_dir" ip '
case "$*" in
  "-o addr show dev macncm0")
    echo "3: macncm0    inet 192.168.20.20/24 brd 192.168.20.255 scope global macncm0"
    ;;
  "route get 192.168.20.17")
    echo "192.168.20.17 dev macncm0 src 192.168.20.20 uid 1000"
    ;;
  *)
    exit 1
    ;;
esac
'
  mk_stub "$stub_dir" mokutil 'echo "SecureBoot enabled"'
  mk_stub "$stub_dir" dmesg 'echo "cdc_ncm 1-1:1.0 macncm0: register .. link up"'

  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root" \
    MGDL_USBCORE_QUIRKS="$root/sys/module/usbcore/parameters/quirks" \
    bash "$repo/scripts/doctor.sh")" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "FAIL LPM quirk present for 05ac:1902"
  assert_contains "$out" "PASS LPM quirk present for 05ac:1905"
}

test_verify_cmdline_checks_all_configured_pids() {
  local repo stub_dir mods_dir state_dir root grub_dir cmdline_file out rc=0
  repo="$(__repo_env)"
  stub_dir="$(mk_tmp)"
  root="$(mk_tmp)"
  mods_dir="$root/lib/modules"
  state_dir="$root/var/lib/mac-dgx10-direct-link"
  grub_dir="$root/etc/default/grub.d"
  cmdline_file="$root/proc_cmdline"

  mkdir -p "$mods_dir/A/kernel/drivers/net/usb"
  : >"$mods_dir/A/kernel/drivers/net/usb/cdc_ncm.ko"
  mkdir -p "$grub_dir"
  : >"$grub_dir/apple-ncm.cfg"
  # M8: config/pids.conf has both 1905 and 1902, but the kernel cmdline
  # only carries the 1905 quirk - the check must catch the missing 1902.
  printf 'BOOT_IMAGE=/vmlinuz usbcore.quirks=05ac:1905:k root=/dev/sda1\n' >"$cmdline_file"

  mk_stub "$stub_dir" uname 'echo "A"'
  mk_stub "$stub_dir" modinfo '
case "$*" in
  "-k A -F alias cdc_ncm")
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in00*\n"
    printf "alias: usb:v05ACp1905d*dc*dsc*dp*ic*isc*ip*in02*\n"
    ;;
  "-k A -n cdc_ncm")
    echo "/lib/modules/A/kernel/drivers/net/usb/cdc_ncm.ko"
    ;;
  *)
    exit 1
    ;;
esac
'
  mk_stub "$stub_dir" dkms '
case "$*" in
  "status -m apple-cdc-ncm -v 1.0.0 -k A")
    echo "apple-cdc-ncm/1.0.0, A, x86_64: installed"
    ;;
  *)
    exit 1
    ;;
esac
'

  out="$(PATH="$stub_dir:$PATH" MGDL_ROOT="$root" MGDL_MODULES_DIR="$mods_dir" \
    MGDL_STATE_DIR="$state_dir" MGDL_PROC_CMDLINE="$cmdline_file" \
    bash "$repo/scripts/verify.sh")" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$out" "FAIL cmdline contains usbcore.quirks=05ac:1902:k"
  assert_contains "$out" "PASS cmdline contains usbcore.quirks=05ac:1905:k"
}

test_readonly_scripts_no_sudo() {
  assert_not_contains "$(cat "$check_kernel_support_sh")" "sudo"
  assert_not_contains "$(cat "$verify_sh")" "sudo"
  assert_not_contains "$(cat "$doctor_sh")" "sudo"
}

run_tests
