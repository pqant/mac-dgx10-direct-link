#!/usr/bin/env bash
#
# Read-only health check for the Mac <-> DGX10 CDC-NCM link. Never writes
# outside stdout/stderr and never escalates privileges.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "doctor.sh: cannot find lib.sh" >&2
  exit 64
fi
mgdl_paths

pids_file="$script_dir/../config/pids.conf"
link_conf="$script_dir/../config/link.conf"
known_other_pids=("12a8" "12ab")

exit_code=0
pass() { printf 'PASS %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  exit_code=1
}
info() { printf 'INFO %s\n' "$1"; }

# -- Apple device present --------------------------------------------------
apple_lines=""
if command -v lsusb >/dev/null 2>&1; then
  apple_lines="$(lsusb 2>/dev/null | grep -i '05ac:' || true)"
fi
if [ -n "$apple_lines" ]; then
  pass "Apple device present"
else
  fail "Apple device present"
fi

# -- PID in config/pids.conf ------------------------------------------------
configured_pids=""
if [ -r "$pids_file" ]; then
  configured_pids="$(read_pids "$pids_file" 2>/dev/null || true)"
fi

other_pid_count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  pid="$(grep -oiE '05ac:[0-9a-f]{4}' <<<"$line" | head -n1 | cut -d: -f2 | tr '[:upper:]' '[:lower:]')"
  [ -z "$pid" ] && continue
  is_known_other=false
  for other in "${known_other_pids[@]}"; do
    [ "$pid" = "$other" ] && is_known_other=true
  done
  $is_known_other && continue
  other_pid_count=$((other_pid_count + 1))
  if grep -qx "$pid" <<<"$configured_pids"; then
    pass "PID 05ac:$pid in config/pids.conf"
  else
    fail "PID 05ac:$pid not in config/pids.conf - add it and rerun make install"
  fi
done <<<"$apple_lines"
if [ "$other_pid_count" -eq 0 ]; then
  info "no non-phone Apple PID detected"
fi

# -- USB speed >= 5000M ------------------------------------------------------
speed_found=""
for vendor_file in "$MGDL_ROOT"/sys/bus/usb/devices/*/idVendor; do
  [ -r "$vendor_file" ] || continue
  device_dir="${vendor_file%/idVendor}"
  vendor="$(tr '[:upper:]' '[:lower:]' <"$vendor_file" | tr -d '[:space:]')"
  [ "$vendor" = "05ac" ] || continue
  [ -r "$device_dir/speed" ] || continue
  speed_found="$(tr -d '[:space:]' <"$device_dir/speed")"
  break
done
if [[ "$speed_found" =~ ^[0-9]+$ ]] && [ "$speed_found" -ge 5000 ]; then
  pass "USB speed >= 5000M ($speed_found M)"
else
  fail "USB speed >= 5000M (${speed_found:-unknown})"
fi

# -- Interfaces bound to cdc_ncm --------------------------------------------
bound_ifaces=()
for net_path in "$MGDL_ROOT"/sys/class/net/*; do
  [ -e "$net_path" ] || continue
  driver_link="$net_path/device/driver"
  [ -L "$driver_link" ] || continue
  driver="$(basename "$(readlink -f "$driver_link")")"
  [ "$driver" = "cdc_ncm" ] || continue
  bound_ifaces+=("$(basename "$net_path")")
done
if [ "${#bound_ifaces[@]}" -gt 0 ]; then
  pass "interfaces bound to cdc_ncm: ${bound_ifaces[*]}"
else
  fail "interfaces bound to cdc_ncm"
fi

# -- IFACE_PREFIX+IFACE_NUM has DGX10_IP; routing to MAC_IP ------------------
iface_name=""
if load_link_conf "$link_conf" 2>/dev/null; then
  iface_name="${IFACE_PREFIX}${IFACE_NUM}"
fi

if [ -n "$iface_name" ] && command -v ip >/dev/null 2>&1; then
  addr_out="$(ip -o addr show dev "$iface_name" 2>/dev/null || true)"
  dgx10_ip_nomask="${DGX10_IP%%/*}"
  # M8: grep -F for a literal match; without it, the dots in an IPv4
  # address are regex metacharacters ('.' matches any char), so an
  # unrelated address with the same shape could false-PASS.
  if grep -qF "$dgx10_ip_nomask" <<<"$addr_out"; then
    pass "$iface_name has $DGX10_IP"
  else
    fail "$iface_name has $DGX10_IP"
  fi

  mac_ip_nomask="${MAC_IP%%/*}"
  route_out="$(ip route get "$mac_ip_nomask" 2>/dev/null || true)"
  if grep -qF "dev $iface_name" <<<"$route_out"; then
    pass "route to $mac_ip_nomask via $iface_name"
  else
    fail "route to $mac_ip_nomask via $iface_name"
  fi
else
  fail "${iface_name:-IFACE_PREFIX+IFACE_NUM} has DGX10_IP"
  fail "route to MAC_IP via ${iface_name:-IFACE_PREFIX+IFACE_NUM}"
fi

# -- Throughput tuning (apple-ncm-tune, applied by udev) ----------------------
tune_hint="replug the cable or rerun the udev net trigger"
# read_sys FILE - prints FILE without whitespace, or nothing if unreadable.
read_sys() {
  if [ -r "$1" ]; then
    tr -d '[:space:]' <"$1"
  fi
}
# norm_mask MASK - strips commas and leading zeros from a kernel cpumask.
norm_mask() {
  local m
  m="$(tr -d ',' <<<"$1" | tr '[:upper:]' '[:lower:]' | sed 's/^0*//')"
  echo "${m:-0}"
}
check_eq() {
  if [ "$2" = "$3" ]; then
    pass "$1 = $3"
  else
    fail "$1 = $3 (found ${2:-unknown}) - $tune_hint"
  fi
}
net_dir="$MGDL_ROOT/sys/class/net/${iface_name:-none}"
if [ -n "$iface_name" ] && [ -d "$net_dir" ]; then
  check_eq "$iface_name mtu" "$(read_sys "$net_dir/mtu")" "$MTU"
  check_eq "$iface_name tx_queue_len" "$(read_sys "$net_dir/tx_queue_len")" "$TXQLEN"
  check_eq "$iface_name NTB rx_max" "$(read_sys "$net_dir/cdc_ncm/rx_max")" "$NTB_MAX"
  check_eq "$iface_name NTB tx_max" "$(read_sys "$net_dir/cdc_ncm/tx_max")" "$NTB_MAX"
  check_eq "$iface_name rps_cpus" \
    "$(norm_mask "$(read_sys "$net_dir/queues/rx-0/rps_cpus")")" "$(norm_mask "$TUNE_RPS_MASK")"

  # Same lookup as apple-ncm-tune: the xHCI IRQ is named after a root hub.
  irq_list=""
  d="$(readlink -f "$net_dir/device" 2>/dev/null || true)"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    case "${d##*/}" in usb[0-9]*) break ;; esac
    d="${d%/*}"
  done
  if [ -n "$d" ] && [ "$d" != "/" ] && [ -r "$MGDL_ROOT/proc/interrupts" ]; then
    for bus in "${d%/*}"/usb[0-9]*; do
      irq="$(awk -v n="xhci-hcd:${bus##*/}" '$NF == n { sub(":", "", $1); print $1 }' \
        "$MGDL_ROOT/proc/interrupts")"
      [ -n "$irq" ] && irq_list="$irq_list $irq"
    done
  fi
  if [ -z "$irq_list" ]; then
    info "xHCI IRQ for $iface_name not found, affinity not checked"
  fi
  for irq in $irq_list; do
    check_eq "xHCI IRQ $irq affinity" \
      "$(read_sys "$MGDL_ROOT/proc/irq/$irq/smp_affinity_list")" "$TUNE_IRQ_CPU"
  done
else
  fail "${iface_name:-IFACE_PREFIX+IFACE_NUM} present for tuning checks"
fi
# -- LPM quirk present -------------------------------------------------------
quirks=""
if [ -r "$MGDL_USBCORE_QUIRKS" ]; then
  quirks="$(cat "$MGDL_USBCORE_QUIRKS")"
fi
# M8: check every PID configured in config/pids.conf, not just 1905.
pids_for_lpm=""
if [ -r "$pids_file" ]; then
  pids_for_lpm="$(read_pids "$pids_file" 2>/dev/null || true)"
fi
if [ -z "$pids_for_lpm" ]; then
  pids_for_lpm="1905"
fi
while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  if grep -qiF "05ac:$pid:k" <<<"$quirks"; then
    pass "LPM quirk present for 05ac:$pid"
  else
    fail "LPM quirk present for 05ac:$pid"
  fi
done <<<"$pids_for_lpm"

# -- Secure Boot state (INFO) -------------------------------------------------
if command -v mokutil >/dev/null 2>&1; then
  sb_state="$(mokutil --sb-state 2>/dev/null | head -n1 || true)"
  info "Secure Boot: ${sb_state:-unknown}"
else
  info "Secure Boot: mokutil not installed"
fi

# -- dmesg bind() failure count ----------------------------------------------
if dmesg_out="$(dmesg 2>/dev/null)"; then
  bind_count="$(grep -ciE 'cdc_ncm.*bind\(\) failure' <<<"$dmesg_out" || true)"
  bind_count="${bind_count:-0}"
  if [ "$bind_count" -gt 0 ]; then
    fail "dmesg bind() failure count ($bind_count)"
  else
    pass "dmesg bind() failure count (0)"
  fi
else
  info "run with elevated privileges for dmesg"
fi

exit "$exit_code"
