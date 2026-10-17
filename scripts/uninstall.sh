#!/usr/bin/env bash
#
# Removes the apple-cdc-ncm DKMS package plus the GRUB/udev/netplan/depmod.d
# system integration. Every removal tolerates already-missing targets so the
# script is safe to re-run (idempotent uninstall). Requires root unless
# MGDL_ROOT is set (test seam).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "uninstall.sh: cannot find lib.sh" >&2
  exit 64
fi
mgdl_paths

usage() {
  echo "Usage: $(basename "$0") [--dry-run] [--purge]" >&2
}

dry_run=0
purge=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      dry_run=1
      ;;
    --purge)
      purge=1
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

if [ -z "${MGDL_ROOT:-}" ] && [ "$(id -u 2>/dev/null || echo 0)" -ne 0 ]; then
  echo "uninstall.sh must run as root" >&2
  exit 64
fi

run_cmd() {
  if [ "$dry_run" -eq 1 ]; then
    printf 'DRY: %s\n' "$*"
  else
    "$@"
  fi
}

# -- dkms remove, only if it is actually installed ---------------------------
dkms_status=""
if command -v dkms >/dev/null 2>&1; then
  dkms_status="$(dkms status apple-cdc-ncm/1.0.0 2>/dev/null || true)"
fi
if [ -n "$dkms_status" ]; then
  run_cmd dkms remove apple-cdc-ncm/1.0.0 --all || log_warn "dkms remove apple-cdc-ncm/1.0.0 failed; continuing with file cleanup"
fi

# -- remove source tree and all system-integration files ---------------------
run_cmd rm -rf "$MGDL_ROOT/usr/src/apple-cdc-ncm-1.0.0"
run_cmd rm -f "$MGDL_ROOT/etc/default/grub.d/apple-ncm.cfg"
run_cmd rm -f "$MGDL_ROOT/etc/udev/rules.d/90-apple-ncm.rules"
run_cmd rm -f "$MGDL_ROOT/etc/netplan/60-apple-ncm.yaml"
run_cmd rm -f "$MGDL_ROOT/etc/depmod.d/apple-ncm.conf"
run_cmd rm -f "$MGDL_ROOT/usr/local/sbin/apple-ncm-tune"
run_cmd rm -f "$MGDL_ROOT/etc/sysctl.d/60-apple-ncm.conf"

if [ "$purge" -eq 1 ]; then
  run_cmd rm -rf "$MGDL_STATE_DIR" "$MGDL_LEGACY_STATE_DIR"
fi

run_cmd depmod -a
# Drop the DKMS cdc_ncm from every initramfs it was packed into.
if command -v update-initramfs >/dev/null 2>&1; then
  run_cmd update-initramfs -u -k all || log_warn "update-initramfs failed"
fi
run_cmd update-grub
run_cmd udevadm control --reload
run_cmd netplan generate

modinfo -n cdc_ncm 2>/dev/null || true
