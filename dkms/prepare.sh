#!/usr/bin/env bash
#
# DKMS PRE_BUILD hook. Runs with cwd set to the DKMS build directory
# (/var/lib/dkms/apple-cdc-ncm/1.0.0/build), alongside lib.sh,
# fetch-source.sh, gen-quirk-patch.sh, pids.conf, and Makefile.kbuild.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") KVER" >&2
  exit 1
fi
kver="$1"

# shellcheck source=./lib.sh
source ./lib.sh
mgdl_paths

if ! ./fetch-source.sh --no-apt "$kver"; then
  log_error "no cdc_ncm.c for $kver; run: sudo /usr/src/apple-cdc-ncm-1.0.0/fetch-source.sh $kver (needs network)"
  exit 1
fi

cache_dir="$MGDL_STATE_DIR/src/$kver"
gen_rc=0
./gen-quirk-patch.sh "$cache_dir/cdc_ncm.c" ./pids.conf >./cdc_ncm.c || gen_rc=$?

if [ "$gen_rc" -eq 3 ]; then
  log_warn "source for $kver already contains the quirk; skipping patch, building unmodified source"
  cp "$cache_dir/cdc_ncm.c" ./cdc_ncm.c
elif [ "$gen_rc" -ne 0 ]; then
  exit "$gen_rc"
fi

cp Makefile.kbuild Kbuild

origin_line=""
sha_hex=""
if [ -r "$cache_dir/origin" ]; then
  origin_line="$(sed -n '1p' "$cache_dir/origin")"
  sha_hex="$(sed -n '2p' "$cache_dir/origin")"
  sha_hex="${sha_hex#sha256 }"
fi
log_info "$kver origin=$origin_line sha256=$sha_hex"
