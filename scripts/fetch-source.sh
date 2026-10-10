#!/usr/bin/env bash
# Per-kernel cdc_ncm.c source fetcher. For each requested KVER, resolves a
# valid drivers/net/usb/cdc_ncm.c (one that still contains cdc_ncm_bind and
# apple_private_interface_info) in this order: existing cache, Ubuntu
# deb-src package (unless --no-apt), then the matching upstream-stable tag.
# Writes $MGDL_STATE_DIR/src/KVER/cdc_ncm.c and an "origin" file whose first
# line records how it was obtained and whose second line is "sha256 <hex>".
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/../scripts/lib.sh" ]; then
  # shellcheck source=../scripts/lib.sh
  source "$script_dir/../scripts/lib.sh"
elif [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "fetch-source.sh: cannot find lib.sh" >&2
  exit 64
fi

mgdl_paths

no_apt=0
kvers=()

usage() {
  echo "Usage: $(basename "$0") [--no-apt] [KVER...]" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-apt)
      no_apt=1
      shift
      ;;
    --)
      shift
      kvers+=("$@")
      break
      ;;
    -*)
      usage
      exit 64
      ;;
    *)
      kvers+=("$1")
      shift
      ;;
  esac
done

if [ "${#kvers[@]}" -eq 0 ]; then
  shopt -s nullglob
  for dir in "$MGDL_MODULES_DIR"/*; do
    [ -d "$dir" ] && kvers+=("$(basename "$dir")")
  done
  shopt -u nullglob
fi

if [ "${#kvers[@]}" -eq 0 ]; then
  log_error "no KVER given and none found under $MGDL_MODULES_DIR"
  exit 1
fi

# __valid_src FILE - 0 if FILE contains both markers a real cdc_ncm.c needs.
__valid_src() {
  local file="$1"
  grep -q 'cdc_ncm_bind' "$file" 2>/dev/null &&
    grep -q 'apple_private_interface_info' "$file" 2>/dev/null
}

# __write_origin DIR ORIGIN_LINE SRC_FILE - writes origin (line 1 + sha256).
__write_origin() {
  local dir="$1" origin_line="$2" src_file="$3" sha
  sha="$(sha256sum "$src_file" | awk '{print $1}')"
  {
    printf '%s\n' "$origin_line"
    printf 'sha256 %s\n' "$sha"
  } >"$dir/origin"
}

# __try_cache KVER DEST_DIR - 0 if an existing valid cache file was kept.
__try_cache() {
  local kver="$1" dest_dir="$2"
  [ -s "$dest_dir/cdc_ncm.c" ] || return 1
  __valid_src "$dest_dir/cdc_ncm.c" || return 1
  __write_origin "$dest_dir" "cache" "$dest_dir/cdc_ncm.c"
  return 0
}

# __try_ubuntu_src KVER DEST_DIR - 0 if a deb-src package yielded a valid
# cdc_ncm.c, copied into DEST_DIR/cdc_ncm.c with origin "ubuntu-src pkg ver".
__try_ubuntu_src() {
  local kver="$1" dest_dir="$2" pkg_ver pkg ver work

  command -v dpkg-query >/dev/null 2>&1 || return 1
  pkg_ver="$(dpkg-query -W -f='${source:Package} ${source:Version}' "linux-image-$kver" 2>/dev/null)" || return 1
  [ -n "$pkg_ver" ] || return 1
  pkg="${pkg_ver%% *}"
  ver="${pkg_ver#* }"
  [ -n "$pkg" ] && [ -n "$ver" ] && [ "$pkg" != "$ver" ] || return 1

  command -v apt-get >/dev/null 2>&1 || return 1
  command -v dpkg-source >/dev/null 2>&1 || return 1

  work="$(mktemp -d)"
  (
    cd "$work" &&
      apt-get source --download-only "$pkg=$ver" >/dev/null 2>&1 &&
      dpkg-source -x --no-check ./*.dsc src >/dev/null 2>&1
  )
  local rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$work/src/drivers/net/usb/cdc_ncm.c" ]; then
    rm -rf -- "$work"
    return 1
  fi
  if ! __valid_src "$work/src/drivers/net/usb/cdc_ncm.c"; then
    rm -rf -- "$work"
    return 1
  fi
  cp "$work/src/drivers/net/usb/cdc_ncm.c" "$dest_dir/cdc_ncm.c"
  __write_origin "$dest_dir" "ubuntu-src $pkg $ver" "$dest_dir/cdc_ncm.c"
  rm -rf -- "$work"
  return 0
}

# __try_upstream_stable KVER DEST_DIR - 0 if the matching upstream-stable tag
# yielded a valid cdc_ncm.c.
__try_upstream_stable() {
  local kver="$1" dest_dir="$2" version tag url tmp_file

  version="$(upstream_version "$kver")" || return 1
  tag="$(stable_tag "$version")"
  url="$(printf "$MGDL_STABLE_URL_TEMPLATE" "${tag#v}")"

  command -v curl >/dev/null 2>&1 || return 1
  tmp_file="$(mktemp)"
  if ! curl -fsSL "$url" >"$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file"
    return 1
  fi
  if ! __valid_src "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  cp "$tmp_file" "$dest_dir/cdc_ncm.c"
  rm -f "$tmp_file"
  __write_origin "$dest_dir" "upstream-stable $tag" "$dest_dir/cdc_ncm.c"
  log_warn "using upstream stable $tag for $kver; vendor patches may differ"
  return 0
}

fetch_one() {
  local kver="$1" dest_dir="$MGDL_STATE_DIR/src/$kver"
  mkdir -p "$dest_dir"

  if __try_cache "$kver" "$dest_dir"; then
    return 0
  fi
  if [ "$no_apt" -eq 0 ] && __try_ubuntu_src "$kver" "$dest_dir"; then
    return 0
  fi
  if __try_upstream_stable "$kver" "$dest_dir"; then
    return 0
  fi
  rm -f "$dest_dir/cdc_ncm.c" "$dest_dir/origin"
  return 1
}

failed=0
for kver in "${kvers[@]}"; do
  if ! fetch_one "$kver"; then
    log_error "no matching cdc_ncm.c for $kver"
    failed=1
  fi
done

exit "$failed"
