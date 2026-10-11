#!/usr/bin/env bash
#
# Enrolls the DKMS signing key into the Secure Boot MOK list. Idempotent:
# generates a new signing key only if one does not already exist.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$script_dir/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$script_dir/lib.sh"
else
  echo "secureboot-enroll.sh: cannot find lib.sh" >&2
  exit 64
fi
mgdl_paths

mok_der="$MGDL_ROOT/var/lib/shim-signed/mok/MOK.der"

if [ ! -r "$mok_der" ]; then
  update-secureboot-policy --new-key
fi

mokutil --import "$mok_der"

echo '[OWNER] reboot, choose "Enroll MOK" in MokManager, enter the one-time password'
