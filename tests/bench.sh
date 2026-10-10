#!/usr/bin/env bash
#
# Runs forward/reverse iperf3 throughput and a ping latency sample against
# the Mac, or (with --stability) one long forward run plus a cdc_ncm
# disconnect-count delta from dmesg. Writes everything under
# results/<YYYYMMDD-HHMM>-<kver>/.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$repo_root/scripts/lib.sh"
mgdl_paths

link_conf="$repo_root/config/link.conf"
load_link_conf "$link_conf"

duration=30
streams=4
server="${MAC_IP%%/*}"
stability=""

usage() {
  echo "Usage: $(basename "$0") [--duration SEC] [--streams N] [--server IP] [--stability SEC]" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --duration)
      duration="$2"
      shift 2
      ;;
    --streams)
      streams="$2"
      shift 2
      ;;
    --server)
      server="$2"
      shift 2
      ;;
    --stability)
      stability="$2"
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

python_bin="${PYTHON:-python3}"
kver="$(uname -r)"
results_root="$repo_root/results"
out_dir="$results_root/$(date -u +%Y%m%d-%H%M)-$kver"
mkdir -p "$out_dir"

write_meta() {
  local route_dev lsusb_line git_rev
  route_dev="$(ip route get "$server" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' | head -n1)"
  lsusb_line="$(lsusb -t 2>/dev/null | grep -i apple || true)"
  git_rev="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo unknown)"
  {
    printf 'kernel=%s\n' "$kver"
    printf 'route_dev=%s\n' "$route_dev"
    printf 'lsusb_apple=%s\n' "$lsusb_line"
    printf 'git_rev=%s\n' "$git_rev"
  } >"$out_dir/meta.txt"
}

gbps_from_json() {
  "$python_bin" -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
bps = data["end"]["sum_received"]["bits_per_second"]
print(f"{bps / 1e9:.2f}")
' "$1"
}

rtt_avg_from_ping() {
  "$python_bin" -c '
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"=\s*[\d.]+/([\d.]+)/", text)
print(f"{float(m.group(1)):.2f}" if m else "0.00")
' "$1"
}

if [ -n "$stability" ]; then
  before_count="$(dmesg 2>/dev/null | grep -c 'cdc_ncm' || true)"
  iperf3 -c "$server" -P "$streams" -t "$stability" -J >"$out_dir/fwd.json"
  after_count="$(dmesg 2>/dev/null | grep -c 'cdc_ncm' || true)"
  delta=$((after_count - before_count))
  printf 'cdc_ncm disconnect lines during %ss: %s\n' "$stability" "$delta" >"$out_dir/stability.txt"
  write_meta
  echo "stability_delta=$delta"
else
  iperf3 -c "$server" -P "$streams" -t "$duration" -J >"$out_dir/fwd.json"
  iperf3 -c "$server" -P "$streams" -t "$duration" -R -J >"$out_dir/rev.json"
  ping -c 100 -i 0.2 "$server" >"$out_dir/ping.txt"
  write_meta

  fwd_gbps="$(gbps_from_json "$out_dir/fwd.json")"
  rev_gbps="$(gbps_from_json "$out_dir/rev.json")"
  rtt_avg_ms="$(rtt_avg_from_ping "$out_dir/ping.txt")"
  echo "fwd_gbps=$fwd_gbps rev_gbps=$rev_gbps rtt_avg_ms=$rtt_avg_ms"
fi
