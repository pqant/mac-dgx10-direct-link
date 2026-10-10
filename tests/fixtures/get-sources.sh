#!/usr/bin/env bash
# Download real drivers/net/usb/cdc_ncm.c sources at known tags into
# tests/fixtures/cache/<tag>/cdc_ncm.c for the Task 4 real-source tests.
# Skips files already present. Prints "SKIP <reason>" and exits 0 if offline.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache_dir="$script_dir/cache"

tags=(v6.17 v7.1)
url_template="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/net/usb/cdc_ncm.c?h=%s"

if ! command -v curl >/dev/null 2>&1; then
  echo "SKIP curl is not installed"
  exit 0
fi

for tag in "${tags[@]}"; do
  dest_dir="$cache_dir/$tag"
  dest_file="$dest_dir/cdc_ncm.c"
  if [ -s "$dest_file" ]; then
    continue
  fi
  mkdir -p "$dest_dir"
  url="$(printf "$url_template" "$tag")"
  if ! curl -fsSL "$url" -o "$dest_file.tmp"; then
    rm -f "$dest_file.tmp"
    echo "SKIP network unavailable for $tag"
    exit 0
  fi
  if ! grep -q 'cdc_ncm_bind' "$dest_file.tmp"; then
    rm -f "$dest_file.tmp"
    echo "SKIP downloaded $tag content looks invalid"
    exit 0
  fi
  mv "$dest_file.tmp" "$dest_file"
done

exit 0
