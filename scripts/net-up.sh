#!/usr/bin/env bash
#
# Brings the Mac <-> GX10 USB-C CDC-NCM link up or down. Dry-run by default;
# only touches the named interface and its address (no default route, no
# DNS).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "net-up.sh: cannot find lib.sh" >&2
  exit 64
fi
mgdl_paths

repo_root="$(cd "$script_dir/.." && pwd)"
link_conf="$repo_root/config/link.conf"
load_link_conf "$link_conf"

iface="${IFACE_PREFIX}${IFACE_NUM}"
apply=0
down=0

usage() {
  echo "Usage: $(basename "$0") [--apply] [--down] [--interface IFACE]" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      apply=1
      shift
      ;;
    --down)
      down=1
      shift
      ;;
    --interface)
      [ "$#" -ge 2 ] || {
        usage
        exit 64
      }
      iface="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

command -v ip >/dev/null 2>&1 || {
  echo "ip is not installed" >&2
  exit 69
}

run_or_print() {
  if [ "$apply" -eq 1 ]; then
    "$@"
  else
    printf 'DRY: %s\n' "$*"
  fi
}

# A /32 host route wins over a LAN that shares the link's /24.
mac_host="${MAC_IP%%/*}/32"
# /32, not the /24: a subnet route here would steal the LAN from Wi-Fi.
gx10_host="${GX10_IP%%/*}/32"
if [ "$down" -eq 1 ]; then
  run_or_print ip route del "$mac_host" dev "$iface"
  run_or_print ip addr del "$gx10_host" dev "$iface"
else
  run_or_print ip addr replace "$gx10_host" dev "$iface"
  run_or_print ip link set "$iface" up
  run_or_print ip route replace "$mac_host" dev "$iface" scope link
fi

if [ "$apply" -eq 0 ]; then
  echo "No changes made. Re-run with --apply after review."
fi
