#!/usr/bin/env bash
#
# Kernel-upgrade regression check: "pre" verifies every installed kernel and
# records the running kernel version; "post" (after rebooting into a newer
# kernel) refuses to pass against the same kernel, then re-runs the link
# smoke test and benchmark.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$repo_root/scripts/lib.sh"
mgdl_paths

usage() {
  echo "Usage: $(basename "$0") pre|post" >&2
}

mode="${1:-}"
case "$mode" in
  pre | post) ;;
  *)
    usage
    exit 64
    ;;
esac

results_root="$repo_root/results"
mkdir -p "$results_root"
pre_file="$results_root/upgrade-pre.txt"

if [ "$mode" = "pre" ]; then
  "$repo_root/scripts/verify.sh" --all-kernels
  uname -r >"$pre_file"
  exit 0
fi

# mode = post
pre_kver=""
[ -r "$pre_file" ] && pre_kver="$(cat "$pre_file")"
running_kver="$(uname -r)"
if [ "$running_kver" = "$pre_kver" ]; then
  echo "running kernel ($running_kver) is unchanged since 'upgrade.sh pre'" >&2
  exit 1
fi

"$repo_root/tests/link.sh"
"$repo_root/tests/bench.sh"
