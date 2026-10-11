#!/usr/bin/env bash
#
# Read-only PASS/FAIL verification of the CDC-NCM quirk state. Never writes
# outside stdout/stderr and never escalates privileges.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "verify.sh: cannot find lib.sh" >&2
  exit 64
fi
mgdl_paths

usage() {
  echo "Usage: $(basename "$0") [--all-kernels]" >&2
}

all_kernels=false
case "${1:-}" in
  --all-kernels)
    all_kernels=true
    ;;
  "") ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 64
    ;;
esac

kernels=()
if $all_kernels; then
  if [ -d "$MGDL_MODULES_DIR" ]; then
    for d in "$MGDL_MODULES_DIR"/*/; do
      [ -d "$d" ] || continue
      [[ "$(basename "$d")" =~ ^[0-9] ]] || continue
      kernels+=("$(basename "$d")")
    done
  fi
else
  kernels=("$(uname -r)")
fi

exit_code=0
pass() { printf 'PASS %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  exit_code=1
}

for k in "${kernels[@]}"; do
  quirk_rc=0
  kernel_has_quirk "$k" || quirk_rc=$?
  in_tree_quirk=false
  [ "$quirk_rc" -eq 0 ] && in_tree_quirk=true

  aliases_out="$(modinfo -k "$k" -F alias cdc_ncm 2>/dev/null || true)"
  alias_count="$(grep -ciE 'v05acp(1905|1902).*in0[02]' <<<"$aliases_out" || true)"
  alias_count="${alias_count:-0}"
  if [ "$alias_count" -ge 2 ]; then
    pass "$k: aliases >= 2"
  else
    fail "$k: aliases >= 2"
  fi

  effective_module="$(modinfo -k "$k" -n cdc_ncm 2>/dev/null || true)"
  if [[ "$effective_module" == *updates/dkms* ]] || $in_tree_quirk; then
    pass "$k: effective module under updates/dkms OR in-tree quirk"
  else
    fail "$k: effective module under updates/dkms OR in-tree quirk"
  fi

  dkms_installed=false
  if command -v dkms >/dev/null 2>&1; then
    # I6: scope the query to our own module/version/kernel so an unrelated
    # DKMS module mentioning this kernel can't false-PASS the check.
    if dkms status -m apple-cdc-ncm -v 1.0.0 -k "$k" 2>/dev/null | grep -q ': installed'; then
      dkms_installed=true
    fi
  fi
  if $dkms_installed || $in_tree_quirk; then
    pass "$k: dkms status installed OR in-tree quirk (skipped by design)"
  else
    fail "$k: dkms status installed OR in-tree quirk (skipped by design)"
  fi

  if [ -r "$MGDL_STATE_DIR/src/$k/cdc_ncm.c" ] || $in_tree_quirk; then
    pass "$k: source cached OR in-tree quirk"
  else
    fail "$k: source cached OR in-tree quirk"
  fi
done

grub_dropin="$MGDL_ROOT/etc/default/grub.d/apple-ncm.cfg"
if [ -r "$grub_dropin" ]; then
  pass "GRUB drop-in present"
else
  fail "GRUB drop-in present"
fi

cmdline=""
if [ -r "$MGDL_PROC_CMDLINE" ]; then
  cmdline="$(cat "$MGDL_PROC_CMDLINE")"
fi
quirks_value=""
if [[ "$cmdline" =~ usbcore\.quirks=([^[:space:]]+) ]]; then
  quirks_value="${BASH_REMATCH[1]}"
fi
# M8: check every PID configured in config/pids.conf, not just 1905.
pids_conf="$script_dir/../config/pids.conf"
pids_for_cmdline=""
if [ -r "$pids_conf" ]; then
  pids_for_cmdline="$(read_pids "$pids_conf" 2>/dev/null || true)"
fi
if [ -z "$pids_for_cmdline" ]; then
  pids_for_cmdline="1905"
fi
while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  if [[ ",$quirks_value," == *",05ac:$pid:k,"* ]]; then
    pass "cmdline contains usbcore.quirks=05ac:$pid:k"
  else
    fail "cmdline contains usbcore.quirks=05ac:$pid:k"
  fi
done <<<"$pids_for_cmdline"

exit "$exit_code"
