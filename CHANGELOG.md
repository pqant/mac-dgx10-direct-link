# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Repository scaffold: license, notice, changelog, Makefile, and the plain-bash
  test harness (`tests/lib/assert.sh`, `tests/run-unit.sh`, `tests/static.sh`).
- Quirk patch generator (`patches/gen-quirk-patch.sh`), reference upstream
  patch, and `tests/fixtures/get-sources.sh` for real-kernel-source fixtures.
- `scripts/fetch-source.sh`: per-kernel source cache with Ubuntu source
  package and kernel.org stable fallbacks.
- `dkms/dkms.conf`, `dkms/Makefile.kbuild`, `dkms/prepare.sh`: conditional
  DKMS package that skips cleanly when the in-tree `cdc_ncm` already has the
  Apple quirk.
- `scripts/check-kernel-support.sh`, `scripts/verify.sh`, `scripts/doctor.sh`:
  read-only diagnostics with no root requirement.
- System integration: `system/grub/apple-ncm.cfg`, `system/udev/90-apple-ncm.rules`,
  `system/netplan/60-apple-ncm.yaml`, `system/depmod.d/apple-ncm.conf`,
  `scripts/install.sh`, `scripts/uninstall.sh`, `scripts/secureboot-enroll.sh`.
- `scripts/net-up.sh` (dry-run-by-default link bring-up/teardown),
  `macos/setup-ip.md`, and device test scripts `tests/link.sh`,
  `tests/bench.sh`, `tests/upgrade.sh`, `tests/recovery.sh`.
