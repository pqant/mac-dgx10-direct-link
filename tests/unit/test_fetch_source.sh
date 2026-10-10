#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib/assert.sh
source "$(dirname "$0")/../lib/assert.sh"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
script_under_test="$root_dir/scripts/fetch-source.sh"

__valid_src() {
  cat <<'EOF'
static int cdc_ncm_bind(struct usbnet *dev, struct usb_interface *intf)
{
	return 0;
}
static const struct driver_info apple_private_interface_info = { 0 };
EOF
}

__base_env() {
  # Builds a stub dir + MGDL_STATE_DIR tree. Echoes "stub_dir|state_dir".
  local stub_dir state_dir
  stub_dir="$(mk_tmp)"
  state_dir="$(mk_tmp)/state"
  mkdir -p "$state_dir"
  mk_stub "$stub_dir" uname 'echo "6.8.0-generic"'
  echo "$stub_dir|$state_dir"
}

test_cache_hit_no_network() {
  local parts stub_dir state_dir
  parts="$(__base_env)"
  stub_dir="${parts%%|*}"
  state_dir="${parts#*|}"

  mkdir -p "$state_dir/src/6.8.0-generic"
  __valid_src >"$state_dir/src/6.8.0-generic/cdc_ncm.c"
  # Seed a real (non-"cache") origin from a prior fetch, as I5 requires it
  # to survive a cache hit instead of being overwritten with "cache".
  printf 'ubuntu-src linux-signed-hwe-6.8 6.8.0-1.1\nsha256 deadbeef\n' \
    >"$state_dir/src/6.8.0-generic/origin"

  mk_stub "$stub_dir" curl 'exit 99'
  mk_stub "$stub_dir" dpkg-query 'exit 1'
  mk_stub "$stub_dir" apt-get 'exit 1'
  mk_stub "$stub_dir" dpkg-source 'exit 1'

  local rc=0
  PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" \
    bash "$script_under_test" 6.8.0-generic >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc"
  assert_eq "ubuntu-src linux-signed-hwe-6.8 6.8.0-1.1" \
    "$(head -n1 "$state_dir/src/6.8.0-generic/origin")"
}

test_cache_hit_no_prior_origin_uses_cache_label() {
  local parts stub_dir state_dir
  parts="$(__base_env)"
  stub_dir="${parts%%|*}"
  state_dir="${parts#*|}"

  mkdir -p "$state_dir/src/6.8.0-generic"
  __valid_src >"$state_dir/src/6.8.0-generic/cdc_ncm.c"
  # No pre-existing origin file at all (e.g. a manually-dropped cache file).

  mk_stub "$stub_dir" curl 'exit 99'
  mk_stub "$stub_dir" dpkg-query 'exit 1'
  mk_stub "$stub_dir" apt-get 'exit 1'
  mk_stub "$stub_dir" dpkg-source 'exit 1'

  local rc=0
  PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" \
    bash "$script_under_test" 6.8.0-generic >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc"
  assert_eq "cache" "$(head -n1 "$state_dir/src/6.8.0-generic/origin")"
}

test_stable_fallback_writes_origin_and_warning() {
  local parts stub_dir state_dir
  parts="$(__base_env)"
  stub_dir="${parts%%|*}"
  state_dir="${parts#*|}"

  mk_stub "$stub_dir" curl 'printf "static int cdc_ncm_bind(struct usbnet *dev){return 0;}\nstatic const struct driver_info apple_private_interface_info = {0};\n"'
  mk_stub "$stub_dir" dpkg-query 'exit 1'

  local out rc=0
  out="$(PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" MGDL_UPSTREAM_VERSION=6.17.9 \
    bash "$script_under_test" --no-apt 6.17.0-generic 2>&1)" || rc=$?
  assert_eq "0" "$rc" "$out"

  assert_eq "upstream-stable v6.17.9" "$(head -n1 "$state_dir/src/6.17.0-generic/origin")"
  assert_contains "$out" "WARN"
}

test_ubuntu_src_preferred() {
  local parts stub_dir state_dir
  parts="$(__base_env)"
  stub_dir="${parts%%|*}"
  state_dir="${parts#*|}"

  mk_stub "$stub_dir" dpkg-query 'echo "linux-signed-hwe-6.8 6.8.0-1.1"'
  mk_stub "$stub_dir" apt-get '
printf "stub dsc\n" >"$(pwd)/linux-signed-hwe-6.8_6.8.0-1.1.dsc"
'
  mk_stub "$stub_dir" dpkg-source '
dest="${!#}"
mkdir -p "$dest/drivers/net/usb"
cat >"$dest/drivers/net/usb/cdc_ncm.c" <<EOF
static int cdc_ncm_bind(struct usbnet *dev){ return 0; }
static const struct driver_info apple_private_interface_info = { 0 };
EOF
'
  mk_stub "$stub_dir" curl 'touch "$(dirname "$0")/.curl-called-marker" 2>/dev/null || true; exit 99'

  local rc=0
  PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" \
    bash "$script_under_test" 6.8.0-generic >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc"
  assert_contains "$(head -n1 "$state_dir/src/6.8.0-generic/origin")" "ubuntu-src"
  assert_file_absent "$stub_dir/.curl-called-marker"
}

test_invalid_download_discarded() {
  local parts stub_dir state_dir
  parts="$(__base_env)"
  stub_dir="${parts%%|*}"
  state_dir="${parts#*|}"

  mk_stub "$stub_dir" dpkg-query 'exit 1'
  mk_stub "$stub_dir" curl 'echo "<html><body>404 not found</body></html>"'

  local rc=0
  PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" MGDL_UPSTREAM_VERSION=6.8.5 \
    bash "$script_under_test" --no-apt 6.8.0-generic >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc"
  assert_file_absent "$state_dir/src/6.8.0-generic/cdc_ncm.c"
}

test_all_fail_exit1() {
  local parts stub_dir state_dir
  parts="$(__base_env)"
  stub_dir="${parts%%|*}"
  state_dir="${parts#*|}"

  mk_stub "$stub_dir" dpkg-query 'exit 1'
  mk_stub "$stub_dir" curl 'exit 99'

  local err rc=0
  err="$(PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" \
    bash "$script_under_test" --no-apt 6.8.0-generic 2>&1 >/dev/null)" || rc=$?
  assert_eq "1" "$rc"
  assert_contains "$err" "6.8.0-generic"
  # M7: the per-kver state dir should not be left behind empty after a
  # total fetch failure.
  assert_file_absent "$state_dir/src/6.8.0-generic"
}

test_ubuntu_src_falls_back_to_linux_modules_package() {
  local parts stub_dir state_dir
  parts="$(__base_env)"
  stub_dir="${parts%%|*}"
  state_dir="${parts#*|}"

  # I7: no linux-image-$kver package, but linux-modules-$kver exists.
  mk_stub "$stub_dir" dpkg-query '
case "$*" in
  *"linux-image-6.8.0-generic"*) exit 1 ;;
  *"linux-modules-6.8.0-generic"*) echo "linux-signed-hwe-6.8 6.8.0-1.1" ;;
  *) exit 1 ;;
esac
'
  mk_stub "$stub_dir" apt-get '
printf "stub dsc\n" >"$(pwd)/linux-signed-hwe-6.8_6.8.0-1.1.dsc"
'
  mk_stub "$stub_dir" dpkg-source '
dest="${!#}"
mkdir -p "$dest/drivers/net/usb"
cat >"$dest/drivers/net/usb/cdc_ncm.c" <<EOF
static int cdc_ncm_bind(struct usbnet *dev){ return 0; }
static const struct driver_info apple_private_interface_info = { 0 };
EOF
'
  mk_stub "$stub_dir" curl 'exit 99'

  local rc=0
  PATH="$stub_dir:$PATH" MGDL_STATE_DIR="$state_dir" \
    bash "$script_under_test" 6.8.0-generic >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc"
  assert_contains "$(head -n1 "$state_dir/src/6.8.0-generic/origin")" "ubuntu-src"
}

run_tests
