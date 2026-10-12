# ADR-0001: Use standard DKMS with a conditional `dkms.conf`

## Status

Accepted.

## Context

The DGX10 (DGX OS) kernel needs the upstream Apple CDC-NCM quirk
(`v05ACp1905` alias on `cdc_ncm`) so that the Mac's private CDC-NCM
interfaces bind instead of failing with `bind() failure`. Some installed
kernels already carry this quirk in-tree (recent/backported kernels);
others do not. The package must:

- build and install a patched `cdc_ncm` only for kernels that lack the
  quirk (success criterion S3),
- survive unattended `apt full-upgrade` + reboot with zero manual action
  (S2),
- never fail the kernel install if a per-kernel build fails,
- retire itself automatically once every installed kernel has the
  upstream quirk in-tree.

## Options considered

- **A. Standard DKMS with a conditional `dkms.conf`.** `dkms.conf` is
  sourced by DKMS as bash for each `kernelver`; it runs
  `lib.sh::kernel_has_quirk` against that kernel's in-tree `cdc_ncm.ko`
  and sets `BUILD_EXCLUSIVE_KERNEL` to a regex that matches nothing when
  the quirk is already present, so DKMS reports the kernel as skipped
  without failing `apt`. Otherwise it builds normally with
  `PRE_BUILD="prepare.sh"` and `AUTOINSTALL="yes"`.
- **B. `AUTOINSTALL="no"` plus kernel postinst hooks.** Install
  `/etc/kernel/postinst.d` and `header_postinst.d` scripts that call
  `dkms install` explicitly, only for kernels that `kernel_has_quirk`
  reports as unsupported. More control over invocation timing, but
  duplicates logic DKMS already owns (`AUTOINSTALL`) and adds another
  integration surface with the kernel packaging hooks.
- **C. No DKMS; a bespoke build/install system.** Full control, but
  reimplements MOK signing, kernel version tracking, build directory
  management, and cleanup that DKMS already provides. Rejected: highest
  effort, highest maintenance burden, least aligned with Debian/Ubuntu
  kernel tooling conventions.

## Decision

Option **A**: standard DKMS with a conditional `dkms.conf`.
**[ASSUMPTION]** Ubuntu 24.04 DKMS (3.0.x) treats an unmatched
`BUILD_EXCLUSIVE_KERNEL` as a non-fatal skip during kernel postinst.
Verified in M0/M2 against the reference project's findings.

## Trigger for fallback to Option B

If a DGX OS / Ubuntu DKMS version is found where an unmatched
`BUILD_EXCLUSIVE_KERNEL` instead **fails** the kernel postinst step (as
opposed to cleanly skipping it), switch to Option B: set
`AUTOINSTALL="no"` in `dkms.conf` and add
`/etc/kernel/postinst.d/zz-apple-cdc-ncm` /
`header_postinst.d/zz-apple-cdc-ncm` hooks that call
`dkms install -m apple-cdc-ncm -v <version> -k <kernelver>` only when
`lib.sh::kernel_has_quirk <kernelver>` fails. This fallback is not implemented until the trigger condition is
observed.

## Retirement rule

Once every installed kernel reported by `verify.sh --all-kernels` shows
`INTREE_QUIRK=yes`, the DKMS module is no longer needed for any kernel on
the host. At that point:

1. Run `sudo make uninstall` to remove the DKMS module, depmod override,
   and `dkms.conf` registration, while keeping the GRUB
   (`usbcore.quirks=...:k`), udev (`macncm<N>` naming), and netplan
   (`192.168.20.20/24`) system integration in place, since those remain
   required regardless of which `cdc_ncm` provides the quirk.
2. If a future host needs the system integration without ever building
   the DKMS module (e.g. a kernel that already ships the quirk from
   first boot), `install.sh` may gain a `--net-only` flag that skips the
   DKMS steps and only renders GRUB/udev/netplan/depmod.d; this flag does
   not exist yet and must be added before being relied upon.
