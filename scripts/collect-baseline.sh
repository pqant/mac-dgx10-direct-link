#!/usr/bin/env bash
#
# Read-only M0 baseline collector. Prints a series of "## <name>" sections
# describing the host's kernel, Secure Boot, DKMS, GRUB, APT, and Apple
# CDC-NCM USB networking state. Runs with the caller's existing privileges
# only, and never writes outside stdout except to --output FILE when the
# caller explicitly requests it.
set -euo pipefail

MGDL_ROOT="${MGDL_ROOT:-}"
MGDL_VERSION_SIGNATURE="${MGDL_VERSION_SIGNATURE:-/proc/version_signature}"

output_file=""

usage() {
  echo "Usage: $(basename "$0") [--output FILE]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      output_file="${2:-}"
      shift 2
      ;;
    --output=*)
      output_file="${1#--output=}"
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

have() {
  command -v "$1" >/dev/null 2>&1
}

# run_cmd NAME [ARGS...] - runs NAME if installed, else reports it missing.
run_cmd() {
  local name="$1"
  shift || true
  if have "$name"; then
    "$name" "$@" 2>&1 || true
  else
    echo "$name: NOT INSTALLED"
  fi
}

section() {
  printf '## %s\n' "$1"
}

collect_kernel() {
  section "kernel"
  run_cmd uname -r
  if [[ -r "$MGDL_VERSION_SIGNATURE" ]]; then
    cat "$MGDL_VERSION_SIGNATURE" 2>/dev/null || true
  else
    echo "version_signature: NOT AVAILABLE"
  fi
  echo
}

collect_secureboot() {
  section "secureboot"
  run_cmd mokutil --sb-state
  echo
}

collect_dkms() {
  section "dkms"
  run_cmd dkms --version
  echo
}

collect_grub() {
  section "grub"
  local grub_file="$MGDL_ROOT/etc/default/grub"
  local grub_d="$MGDL_ROOT/etc/default/grub.d"
  if [[ -e "$grub_file" ]]; then
    echo "/etc/default/grub: present"
  else
    echo "/etc/default/grub: absent"
  fi
  if [[ -d "$grub_d" ]]; then
    echo "/etc/default/grub.d/: present"
  else
    echo "/etc/default/grub.d/: absent"
  fi
  if have update-grub; then
    echo "update-grub: $(command -v update-grub)"
  else
    echo "update-grub: NOT INSTALLED"
  fi
  echo
}

collect_kernel_source_package() {
  section "kernel-source-package"
  local kver
  kver="$(uname -r 2>/dev/null || true)"
  if have dpkg-query; then
    dpkg-query -W -f='${source:Package} ${source:Version}\n' "linux-image-${kver}" 2>&1 || true
  else
    echo "dpkg-query: NOT INSTALLED"
  fi
  echo
}

collect_deb_src() {
  section "deb-src"
  local apt_dir="$MGDL_ROOT/etc/apt"
  local count=0
  if [[ -d "$apt_dir" ]]; then
    count="$( { grep -rhE '^[[:space:]]*deb-src[[:space:]]' "$apt_dir" 2>/dev/null || true
                grep -rhE '^[[:space:]]*Types:.*deb-src' "$apt_dir" 2>/dev/null || true
              } | grep -c . || true )"
  fi
  echo "deb-src entries: $count"
  echo
}

collect_cdc_ncm() {
  section "cdc_ncm"
  if have modinfo; then
    modinfo -n cdc_ncm 2>&1 || true
    modinfo cdc_ncm 2>/dev/null | grep -iE '^alias:.*05ac' || echo "no 05ac alias lines found"
  else
    echo "modinfo: NOT INSTALLED"
  fi
  echo
}

collect_usb() {
  section "usb"
  if have lsusb; then
    lsusb 2>&1 | grep -i '05ac' || echo "no 05ac devices found"
    lsusb -t 2>&1 || true
  else
    echo "lsusb: NOT INSTALLED"
  fi
  echo
}

collect_apple_interfaces() {
  section "apple-interfaces"
  local net_dir="$MGDL_ROOT/sys/class/net"
  local found_any=false
  local iface_path iface driver_link driver
  if [[ -d "$net_dir" ]]; then
    for iface_path in "$net_dir"/*; do
      [[ -e "$iface_path" ]] || continue
      driver_link="$iface_path/device/driver"
      [[ -L "$driver_link" ]] || continue
      driver="$(basename "$(readlink -f "$driver_link")" 2>/dev/null || true)"
      [[ "$driver" == "cdc_ncm" ]] || continue
      found_any=true
      iface="$(basename "$iface_path")"
      echo "iface: $iface"
      if have udevadm; then
        udevadm info "$iface_path" 2>/dev/null | grep 'ID_USB_INTERFACE_NUM' || true
      else
        echo "udevadm: NOT INSTALLED"
      fi
      if [[ -r "$iface_path/operstate" ]]; then
        printf 'operstate: %s\n' "$(<"$iface_path/operstate")"
      fi
      if [[ -r "$iface_path/carrier" ]]; then
        printf 'carrier: %s\n' "$(<"$iface_path/carrier")"
      fi
    done
  fi
  if ! $found_any; then
    echo "no cdc_ncm-bound interfaces found"
  fi
  echo
}

collect_lan() {
  section "lan"
  if have ip; then
    ip -br addr 2>&1 || true
  else
    echo "ip: NOT INSTALLED"
  fi
  local net_dir="$MGDL_ROOT/sys/class/net"
  local iface_path iface
  if [[ -d "$net_dir" ]]; then
    for iface_path in "$net_dir"/*; do
      [[ -e "$iface_path" ]] || continue
      iface="$(basename "$iface_path")"
      [[ "$iface" == "lo" ]] && continue
      if have ethtool; then
        echo "iface: $iface"
        ethtool -i "$iface" 2>&1 || true
      else
        echo "ethtool: NOT INSTALLED"
        break
      fi
    done
  fi
  echo
}

collect_ssh() {
  section "ssh"
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local peer
    peer="$(awk '{print $1}' <<<"$SSH_CONNECTION")"
    if have ip; then
      ip route get "$peer" 2>&1 || true
    else
      echo "ip: NOT INSTALLED"
    fi
  else
    echo "SSH_CONNECTION not set"
  fi
}

collect_all() {
  collect_kernel
  collect_secureboot
  collect_dkms
  collect_grub
  collect_kernel_source_package
  collect_deb_src
  collect_cdc_ncm
  collect_usb
  collect_apple_interfaces
  collect_lan
  collect_ssh
}

if [[ -n "$output_file" ]]; then
  collect_all >"$output_file"
else
  collect_all
fi

exit 0
