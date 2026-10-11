#!/usr/bin/env bash
#
# Read-only table of per-kernel CDC-NCM quirk status. Never writes outside
# stdout/stderr and never escalates privileges.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "check-kernel-support.sh: cannot find lib.sh" >&2
  exit 64
fi
mgdl_paths

usage() {
  echo "Usage: $(basename "$0") [--all-kernels | KVER]" >&2
}

all_kernels=false
kver=""

case "${1:-}" in
  --all-kernels)
    all_kernels=true
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  "")
    kver="$(uname -r)"
    ;;
  *)
    kver="$1"
    ;;
esac

if [ "$#" -gt 1 ]; then
  usage
  exit 64
fi

kernels=()
if $all_kernels; then
  if [ -d "$MGDL_MODULES_DIR" ]; then
    for d in "$MGDL_MODULES_DIR"/*/; do
      [ -d "$d" ] || continue
      kernels+=("$(basename "$d")")
    done
  fi
else
  kernels=("$kver")
fi

printf '%s %s %s %s\n' "KERNEL" "INTREE_QUIRK" "EFFECTIVE_MODULE" "ALIASES"

exit_code=0
for k in "${kernels[@]}"; do
  quirk_rc=0
  kernel_has_quirk "$k" || quirk_rc=$?
  case "$quirk_rc" in
    0) intree="yes" ;;
    1) intree="no" ;;
    *) intree="none" ;;
  esac

  effective_module="$(modinfo -k "$k" -n cdc_ncm 2>/dev/null || true)"
  [ -n "$effective_module" ] || effective_module="unknown"

  aliases_out="$(modinfo -k "$k" -F alias cdc_ncm 2>/dev/null || true)"
  alias_count="$(grep -ciE 'v05acp(1905|1902).*in0[02]' <<<"$aliases_out" || true)"
  alias_count="${alias_count:-0}"

  printf '%s %s %s %s\n' "$k" "$intree" "$effective_module" "$alias_count"

  if [ "$alias_count" -lt 2 ]; then
    exit_code=2
  fi
done

exit "$exit_code"
