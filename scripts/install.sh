#!/usr/bin/env bash
#
# Installs the apple-cdc-ncm DKMS package plus the GRUB/udev/netplan/depmod.d
# system integration. Requires root unless MGDL_ROOT is set (test seam).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "install.sh: cannot find lib.sh" >&2
  exit 64
fi
mgdl_paths

repo_root="$(cd "$script_dir/.." && pwd)"
pids_conf="$repo_root/config/pids.conf"
link_conf="$repo_root/config/link.conf"

usage() {
  echo "Usage: $(basename "$0") [--dry-run]" >&2
}

dry_run=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      dry_run=1
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
  echo "install.sh must run as root" >&2
  exit 64
fi

# -- Step 0: validate config right after argument parsing, before any side
# effect (I2/I3). A bare failing call here aborts under `set -e` with the
# exit code read_pids/load_link_conf returned (64 for a bad config).
load_link_conf "$link_conf"
pids_out="$(read_pids "$pids_conf")"

# run_cmd CMD... - runs CMD, or prints "DRY: CMD..." instead when --dry-run.
run_cmd() {
  if [ "$dry_run" -eq 1 ]; then
    printf 'DRY: %s\n' "$*"
  else
    "$@"
  fi
}

# render_template TEMPLATE DEST [TOKEN VALUE]... - substitutes each
# TOKEN with VALUE in TEMPLATE's content and writes it to DEST (mode 600,
# never world-readable even momentarily), or prints "DRY: render DEST"
# instead when --dry-run.
render_template() {
  local template="$1" dst="$2" content
  shift 2
  content="$(cat "$template")"
  while [ "$#" -ge 2 ]; do
    content="${content//"$1"/"$2"}"
    shift 2
  done
  if [ "$dry_run" -eq 1 ]; then
    printf 'DRY: render %s\n' "$dst"
  else
    mkdir -p "$(dirname "$dst")"
    install -m 600 /dev/null "$dst"
    printf '%s\n' "$content" >"$dst"
  fi
}

# -- Step 1: required tools + headers ---------------------------------------
required_tools=(dkms make gcc modinfo depmod update-grub udevadm netplan)
running_kver="$(uname -r)"
missing=()
for t in "${required_tools[@]}"; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
headers_dir="$MGDL_MODULES_DIR/$running_kver/build"
[ -d "$headers_dir" ] || missing+=("$headers_dir")
if [ "${#missing[@]}" -gt 0 ]; then
  echo "missing required tools/headers: ${missing[*]}" >&2
  exit 2
fi

# -- Step 2: Secure Boot gate ------------------------------------------------
mok_der="$MGDL_ROOT/var/lib/shim-signed/mok/MOK.der"
if command -v mokutil >/dev/null 2>&1; then
  sb_state="$(mokutil --sb-state 2>/dev/null || true)"
  if [[ "$sb_state" == *enabled* ]]; then
    test_key_out="$(mokutil --test-key "$mok_der" 2>/dev/null || true)"
    if [[ "$test_key_out" != *"is already enrolled"* ]]; then
      echo "run: sudo scripts/secureboot-enroll.sh" >&2
      exit 10
    fi
  fi
elif [ -d "$MGDL_ROOT/sys/firmware/efi/efivars" ]; then
  log_warn "mokutil not installed; cannot verify Secure Boot state on this UEFI system"
fi

# -- Step 3: fetch-source.sh for every installed kernel ----------------------
kernels=()
if [ -d "$MGDL_MODULES_DIR" ]; then
  for d in "$MGDL_MODULES_DIR"/*/; do
    [ -d "$d" ] || continue
    kernels+=("$(basename "$d")")
  done
fi
for k in "${kernels[@]}"; do
  fetch_rc=0
  run_cmd "$script_dir/fetch-source.sh" "$k" || fetch_rc=$?
  if [ "$fetch_rc" -ne 0 ]; then
    if [ "$k" = "$running_kver" ]; then
      log_error "fetch-source.sh failed for running kernel $k"
      exit 1
    fi
    log_warn "fetch-source.sh failed for $k; continuing"
  fi
done

# -- Step 4: assemble /usr/src tree, rebuild the DKMS module ----------------
# Always remove+add+install (rather than relying on `dkms autoinstall`,
# which skips kernels DKMS already thinks are built): a pids.conf edit
# changes the quirk patch DKMS bakes into the module, so a kernel/module
# combo that looks "already installed" may actually be stale (I4).
src_dir="$MGDL_ROOT/usr/src/apple-cdc-ncm-1.0.0"
if [ "$dry_run" -eq 1 ]; then
  printf 'DRY: install DKMS source tree at %s\n' "$src_dir"
else
  mkdir -p "$src_dir"
  cp "$repo_root/dkms/dkms.conf" "$src_dir/dkms.conf"
  cp "$repo_root/dkms/prepare.sh" "$src_dir/prepare.sh"
  cp "$repo_root/dkms/Makefile.kbuild" "$src_dir/Makefile.kbuild"
  cp "$repo_root/patches/gen-quirk-patch.sh" "$src_dir/gen-quirk-patch.sh"
  cp "$script_dir/fetch-source.sh" "$src_dir/fetch-source.sh"
  cp "$script_dir/lib.sh" "$src_dir/lib.sh"
  cp "$pids_conf" "$src_dir/pids.conf"
  chmod +x "$src_dir/prepare.sh" "$src_dir/fetch-source.sh" "$src_dir/gen-quirk-patch.sh"
fi

run_cmd dkms remove apple-cdc-ncm/1.0.0 --all || true
run_cmd dkms add -m apple-cdc-ncm -v 1.0.0
for k in "${kernels[@]}"; do
  [ -d "$MGDL_MODULES_DIR/$k/build" ] || continue
  install_rc=0
  run_cmd dkms install -m apple-cdc-ncm -v 1.0.0 -k "$k" || install_rc=$?
  if [ "$install_rc" -ne 0 ]; then
    if [ "$k" = "$running_kver" ]; then
      log_error "dkms install failed for running kernel $k"
      exit 1
    fi
    log_warn "dkms install failed for $k; continuing"
  fi
done

# -- Step 5: depmod -a, override if the effective module is still in-tree ---
run_cmd depmod -a
quirk_rc=0
kernel_has_quirk "$running_kver" || quirk_rc=$?
effective_module="$(modinfo -n cdc_ncm 2>/dev/null || true)"
if [ "$quirk_rc" -ne 0 ] && [[ "$effective_module" != *updates/dkms* ]]; then
  depmodd_dir="$MGDL_ROOT/etc/depmod.d"
  if [ "$dry_run" -eq 1 ]; then
    printf 'DRY: install %s/apple-ncm.conf\n' "$depmodd_dir"
  else
    mkdir -p "$depmodd_dir"
    cp "$repo_root/system/depmod.d/apple-ncm.conf" "$depmodd_dir/apple-ncm.conf"
  fi
  run_cmd depmod -a
  if [ "$dry_run" -ne 1 ]; then
    effective_module="$(modinfo -n cdc_ncm 2>/dev/null || true)"
    if [[ "$effective_module" != *updates/dkms* ]]; then
      log_error "cdc_ncm is still not loaded from updates/dkms for $running_kver"
      exit 1
    fi
  fi
fi

# -- Step 6: render templates, reload grub/udev/netplan ----------------------
iface="${IFACE_PREFIX}${IFACE_NUM}"

quirks=""
while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  if [ -z "$quirks" ]; then
    quirks="05ac:$pid:k"
  else
    quirks="$quirks,05ac:$pid:k"
  fi
done <<<"$pids_out"

render_template "$repo_root/system/grub/apple-ncm.cfg" \
  "$MGDL_ROOT/etc/default/grub.d/apple-ncm.cfg" \
  "@QUIRKS@" "$quirks"
render_template "$repo_root/system/udev/90-apple-ncm.rules" \
  "$MGDL_ROOT/etc/udev/rules.d/90-apple-ncm.rules" \
  "@PREFIX@" "$IFACE_PREFIX"
render_template "$repo_root/system/netplan/60-apple-ncm.yaml" \
  "$MGDL_ROOT/etc/netplan/60-apple-ncm.yaml" \
  "@IFACE@" "$iface" "@GX10_IP@" "$GX10_IP" "@MTU@" "$MTU"

run_cmd update-grub
run_cmd udevadm control --reload
run_cmd netplan generate

# -- Step 7: owner follow-up --------------------------------------------------
echo '[OWNER] reboot required for usbcore.quirks; then plug the Mac and run: make doctor'
