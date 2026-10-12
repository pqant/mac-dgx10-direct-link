#!/usr/bin/env bash
#
# Generate the Apple Mac CDC-NCM quirk hunk from config/pids.conf and print
# the patched source to stdout. See patches/README.md for the exit codes.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/../scripts/lib.sh" ]; then
  # shellcheck source=../scripts/lib.sh
  source "$script_dir/../scripts/lib.sh"
elif [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "gen-quirk-patch.sh: cannot find lib.sh" >&2
  exit 64
fi

usage() {
  echo "Usage: $(basename "$0") SRC_C PIDS_FILE" >&2
}

if [ "$#" -ne 2 ]; then
  usage
  exit 64
fi

src_c="$1"
pids_file="$2"

if [ ! -r "$src_c" ]; then
  echo "gen-quirk-patch.sh: cannot read source '$src_c'" >&2
  exit 64
fi

pids_out=""
if ! pids_out="$(read_pids "$pids_file")"; then
  exit 64
fi

pids=()
if [ -n "$pids_out" ]; then
  while IFS= read -r pid; do
    pids+=("$pid")
  done <<<"$pids_out"
fi

if [ "${#pids[@]}" -eq 0 ]; then
  echo "gen-quirk-patch.sh: no PIDs found in '$pids_file'" >&2
  exit 64
fi

for pid in "${pids[@]}"; do
  if grep -Eiq "0x05ac,[[:space:]]*0x${pid}" "$src_c"; then
    exit 3
  fi
done

if ! grep -q 'apple_private_interface_info' "$src_c"; then
  exit 4
fi

anchor='/* Ericsson MBM devices'
if ! grep -qF "$anchor" "$src_c"; then
  exit 5
fi

block_file="$(mktemp)"
trap 'rm -f "$block_file"' EXIT

{
  for pid in "${pids[@]}"; do
    printf '\t/* Mac (direct USB-C networking, PID 0x%s) - mac-dgx10-direct-link */\n' "$pid"
    printf '\t{ USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x%s, 0),\n' "$pid"
    printf '\t\t.driver_info = (unsigned long)&apple_private_interface_info,\n'
    printf '\t},\n'
    printf '\t{ USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x%s, 2),\n' "$pid"
    printf '\t\t.driver_info = (unsigned long)&apple_private_interface_info,\n'
    printf '\t},\n'
    printf '\n'
  done
} >"$block_file"

awk -v block_file="$block_file" -v anchor="$anchor" '
  BEGIN {
    while ((getline line < block_file) > 0) {
      block = block line "\n"
    }
  }
  !inserted && index($0, anchor) {
    printf "%s", block
    inserted = 1
  }
  { print }
' "$src_c"

exit 0
