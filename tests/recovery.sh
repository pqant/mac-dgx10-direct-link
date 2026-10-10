#!/usr/bin/env bash
#
# S5 recovery drill: uninstall, confirm the kernel falls back to its in-tree
# cdc_ncm, reinstall, then prompt the owner to replug the cable and re-run
# the link smoke test. Requires root unless MGDL_ROOT is set (test seam).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$repo_root/scripts/lib.sh"
mgdl_paths

"$repo_root/scripts/uninstall.sh"

effective_module="$(modinfo -n cdc_ncm 2>/dev/null || true)"
if [[ "$effective_module" != */kernel/drivers/net/usb/* ]]; then
  log_error "expected in-tree cdc_ncm after uninstall, got: $effective_module"
  exit 1
fi

"$repo_root/scripts/install.sh"

echo '[OWNER] unplug/replug the cable, then press Enter'
read -r _ || true

"$repo_root/tests/link.sh"
