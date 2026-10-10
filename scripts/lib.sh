#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for mac-gx10-direct-link scripts. This file must have no
# side effects when sourced: no `set -e`/`set -u`, and no stdout/stderr
# output. Every script that sources it is responsible for its own
# `set -euo pipefail` and for calling mgdl_paths to populate MGDL_* defaults.

# mgdl_paths - exports the MGDL_* testability-seam variables, honoring any
# value already present in the environment (tests point these at temp dirs).
mgdl_paths() {
  MGDL_ROOT="${MGDL_ROOT:-}"
  MGDL_MODULES_DIR="${MGDL_MODULES_DIR:-$MGDL_ROOT/lib/modules}"
  MGDL_STATE_DIR="${MGDL_STATE_DIR:-$MGDL_ROOT/var/lib/mac-gx10-direct-link}"
  MGDL_LOG="${MGDL_LOG:-$MGDL_ROOT/var/log/mac-gx10-direct-link.log}"
  MGDL_VERSION_SIGNATURE="${MGDL_VERSION_SIGNATURE:-/proc/version_signature}"
  MGDL_PROC_CMDLINE="${MGDL_PROC_CMDLINE:-/proc/cmdline}"
  MGDL_USBCORE_QUIRKS="${MGDL_USBCORE_QUIRKS:-/sys/module/usbcore/parameters/quirks}"
  MGDL_STABLE_URL_TEMPLATE="${MGDL_STABLE_URL_TEMPLATE:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/net/usb/cdc_ncm.c?h=v%s}"
  export MGDL_ROOT MGDL_MODULES_DIR MGDL_STATE_DIR MGDL_LOG \
    MGDL_VERSION_SIGNATURE MGDL_PROC_CMDLINE MGDL_USBCORE_QUIRKS \
    MGDL_STABLE_URL_TEMPLATE
}

# __mgdl_log LEVEL MSG - always writes "[mgdl] LEVEL MSG" to stderr; also
# appends "<ISO8601> LEVEL MSG" to $MGDL_LOG when that path is writable.
__mgdl_log() {
  local level="$1" msg="$2" log_dir ts
  printf '[mgdl] %s %s\n' "$level" "$msg" >&2
  if [ -n "${MGDL_LOG:-}" ]; then
    log_dir="$(dirname -- "$MGDL_LOG")"
    if { [ -f "$MGDL_LOG" ] && [ -w "$MGDL_LOG" ]; } ||
      { [ ! -e "$MGDL_LOG" ] && [ -d "$log_dir" ] && [ -w "$log_dir" ]; }; then
      ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf '%s %s %s\n' "$ts" "$level" "$msg" >>"$MGDL_LOG" 2>/dev/null || true
    fi
  fi
}

log_info() { __mgdl_log "INFO" "$1"; }
log_warn() { __mgdl_log "WARN" "$1"; }
log_error() { __mgdl_log "ERROR" "$1"; }

# read_pids FILE - prints one lowercase 4-hex PID per line, stripping '#'
# comments, trailing \r, and surrounding whitespace, skipping blank lines and
# de-duplicating while preserving first-seen order. Returns 64 on any token
# that is not 4 hex digits.
read_pids() {
  local file="$1" line token
  declare -A seen=()

  if [ ! -r "$file" ]; then
    log_error "cannot read PID file '$file'"
    return 64
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    token="${line,,}"
    if [[ ! "$token" =~ ^[0-9a-f]{4}$ ]]; then
      log_error "invalid PID '$token' in $file"
      return 64
    fi
    if [ -z "${seen[$token]:-}" ]; then
      seen[$token]=1
      printf '%s\n' "$token"
    fi
  done <"$file"
}

# load_link_conf FILE - sources FILE (after stripping \r) into the caller's
# shell. Validates GX10_IP/MAC_IP and IFACE_NUM, returning 64 on any
# violation.
load_link_conf() {
  local file="$1"

  if [ ! -r "$file" ]; then
    log_error "cannot read link conf '$file'"
    return 64
  fi

  # shellcheck disable=SC1090
  if ! source <(sed 's/\r$//' "$file"); then
    log_error "failed to source link conf '$file'"
    return 64
  fi

  if [[ ! "${GX10_IP:-}" =~ ^[0-9.]+/[0-9]+$ ]]; then
    log_error "invalid GX10_IP '${GX10_IP:-}' in $file"
    return 64
  fi
  if [[ ! "${MAC_IP:-}" =~ ^[0-9.]+/[0-9]+$ ]]; then
    log_error "invalid MAC_IP '${MAC_IP:-}' in $file"
    return 64
  fi
  if [ "${IFACE_NUM:-}" != "0" ] && [ "${IFACE_NUM:-}" != "2" ]; then
    log_error "invalid IFACE_NUM '${IFACE_NUM:-}' in $file"
    return 64
  fi
}

# intree_cdc_ncm KVER - prints the path to the first in-tree cdc_ncm module
# for KVER under $MGDL_MODULES_DIR, or returns 1 if none is present.
intree_cdc_ncm() {
  local kver="$1" matches=()

  shopt -s nullglob
  matches=("$MGDL_MODULES_DIR/$kver/kernel/drivers/net/usb/cdc_ncm.ko"*)
  shopt -u nullglob

  if [ "${#matches[@]}" -eq 0 ]; then
    return 1
  fi
  printf '%s\n' "${matches[0]}"
}

# kernel_has_quirk KVER - 0 if the in-tree cdc_ncm module already advertises
# the Apple private-interface quirk for both interface 0 and interface 2,
# 1 if it does not, 2 if there is no in-tree module for KVER.
kernel_has_quirk() {
  local kver="$1" mod_path alias_out

  mod_path="$(intree_cdc_ncm "$kver")" || return 2
  alias_out="$(modinfo -F alias "$mod_path" 2>/dev/null || true)"

  if grep -qiE 'v05acp1905.*in00' <<<"$alias_out" &&
    grep -qiE 'v05acp1905.*in02' <<<"$alias_out"; then
    return 0
  fi
  return 1
}

# kver_major_minor KVER - prints "6.17" for "6.17.0-1008-nvidia".
kver_major_minor() {
  local kver="$1"
  if [[ "$kver" =~ ^([0-9]+\.[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

# upstream_version KVER - prints the upstream stable version matching KVER.
# Order: $MGDL_UPSTREAM_VERSION env override; else, if KVER is the running
# kernel, the last field of $MGDL_VERSION_SIGNATURE; else the first
# "Upstream stable to"/"Rebase to" version in the kernel's changelog. Returns
# 1 if no version is found, or if its major.minor differs from KVER's.
upstream_version() {
  local kver="$1" mm version="" running changelog line

  mm="$(kver_major_minor "$kver")"

  if [ -n "${MGDL_UPSTREAM_VERSION:-}" ]; then
    version="$MGDL_UPSTREAM_VERSION"
  else
    running="$(uname -r)"
    if [ "$kver" = "$running" ] && [ -r "${MGDL_VERSION_SIGNATURE:-}" ]; then
      local sig
      sig="$(cat "$MGDL_VERSION_SIGNATURE")"
      version="${sig##* }"
    fi

    if [ -z "$version" ]; then
      changelog="$MGDL_ROOT/usr/share/doc/linux-image-$kver/changelog.Debian.gz"
      if [ -r "$changelog" ]; then
        line="$(zcat "$changelog" 2>/dev/null |
          grep -iE '(Upstream stable to|Rebase to)[[:space:]]+v?[0-9]+\.[0-9]+(\.[0-9]+)?' |
          head -n1 || true)"
        if [[ "$line" =~ (Upstream[[:space:]]stable[[:space:]]to|Rebase[[:space:]]to)[[:space:]]+v?([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
          version="${BASH_REMATCH[2]}"
        fi
      fi
    fi
  fi

  if [ -z "$version" ]; then
    return 1
  fi
  if [ "$(kver_major_minor "$version")" != "$mm" ]; then
    return 1
  fi
  printf '%s\n' "$version"
}

# stable_tag VERSION - prints "v6.17" for "6.17.0", otherwise "v<VERSION>".
stable_tag() {
  local version="$1"
  if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.0$ ]]; then
    printf 'v%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf 'v%s\n' "$version"
  fi
}
