#!/usr/bin/env bash
#
# S1 smoke test: diagnostics must pass and the Mac must answer pings.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$repo_root/scripts/lib.sh"
mgdl_paths

link_conf="$repo_root/config/link.conf"
load_link_conf "$link_conf"
mac_addr="${MAC_IP%%/*}"

"$repo_root/scripts/doctor.sh"
ping -c 5 -W 1 "$mac_addr"
