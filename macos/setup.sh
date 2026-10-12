#!/usr/bin/env bash
# Persist the Mac side of the link: static IPv4 and MTU from config/link.conf.
# Runs on macOS (bash 3.2). Settings survive reboots and cable replugs.
# Usage: bash macos/setup.sh [interface]   (default: en3)
set -euo pipefail

conf="${LINK_CONF:-$(cd "$(dirname "$0")/.." && pwd)/config/link.conf}"
iface="${1:-en3}"

conf_value() {
  sed -n "s/^$1=\([^[:space:]#]*\).*/\1/p" "$conf" | tr -d '\r' | head -n 1
}

prefix_to_mask() {
  local bits=$1 mask="" _ octet
  for _ in 1 2 3 4; do
    if [ "$bits" -ge 8 ]; then
      octet=255
      bits=$((bits - 8))
    else
      octet=$((256 - (1 << (8 - bits))))
      [ "$bits" -eq 0 ] && octet=0
      bits=0
    fi
    mask="$mask${mask:+.}$octet"
  done
  echo "$mask"
}

mac_ip="$(conf_value MAC_IP)"
mtu="$(conf_value MTU)"
case "$mac_ip" in
  */*) ;;
  *) echo "MAC_IP missing or not in a.b.c.d/nn form in $conf" >&2; exit 64 ;;
esac
case "$mtu" in
  '' | *[!0-9]*) echo "MTU missing or invalid in $conf" >&2; exit 64 ;;
esac
ip="${mac_ip%/*}"
mask="$(prefix_to_mask "${mac_ip#*/}")"

service="$(networksetup -listallhardwareports |
  awk -v dev="$iface" '/^Hardware Port:/ { sub(/^Hardware Port: /, ""); port = $0 }
    $0 == "Device: " dev { print port; exit }')"
if [ -z "$service" ]; then
  echo "no network service found for $iface; plug in the cable and retry" >&2
  exit 1
fi

networksetup -setmanual "$service" "$ip" "$mask"
networksetup -setMTU "$iface" "$mtu"

echo "$service ($iface): $ip/$mask mtu $mtu"
networksetup -getinfo "$service" | sed -n '1,3p'
networksetup -getMTU "$iface"
