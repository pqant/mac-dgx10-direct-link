# Architecture


## Roles

The Mac acts as a USB device exposing Apple's private CDC-NCM functions.
The GX10 (DGX OS, Linux) acts as the USB host and binds those functions to
`cdc_ncm`.

```text
Apple Silicon Mac                         GX10 (Linux)
-----------------                        -------------
AppleUSBDeviceNCMPrivateEthernetInterface USB host controller
USB VID:PID 05ac:1905 (or 1902)  <---->   cdc_ncm
macOS enX                                 Linux macncm<N>
192.168.20.17/24                    <---->   192.168.20.20/24
```

Apple exposes two private data functions, using interface numbers 0 and 2.
A supported Linux driver can therefore create two network devices. This
project configures only one selected pair (`IFACE_NUM` in
`config/link.conf`) and leaves the second untouched.

## Chosen approach: standard DKMS with a conditional `dkms.conf`

`dkms.conf` is sourced by DKMS as bash for each `kernelver`. It inspects
that kernel's **in-tree** `cdc_ncm.ko` aliases:

- in-tree module already has `v05ACp1905` → `BUILD_EXCLUSIVE_KERNEL` is set
  to a regex that matches nothing → DKMS reports the kernel as skipped
  without failing `apt` (success criterion S3).
- otherwise → normal build with `PRE_BUILD="prepare.sh"`,
  `AUTOINSTALL="yes"`, DKMS-managed MOK signing.

Rejected: a bespoke build system without DKMS (it would reimplement
signing, kernel tracking, and cleanup that DKMS already provides).

## Data flow

### New kernel arrives

```
apt installs linux-image-X + linux-headers-X
 → DKMS sources dkms.conf with kernelver=X
   → kernel_has_quirk X ?
      yes → BUILD_EXCLUSIVE no-match → skipped; in-tree module used   (S3)
      no  → PRE_BUILD prepare.sh X
              source order (stop at first success):
                1. cache  /var/lib/mac-gx10-direct-link/src/X/cdc_ncm.c
                2. Ubuntu source package for X (only if deb-src configured)
                3. kernel.org stable  v<base>/drivers/net/usb/cdc_ncm.c  → WARNING
              none → fail with explicit message; never use another major.minor
              source contains 0x05ac,0x1905 → fail (guard; should be unreachable)
              gen-quirk-patch.sh → patched cdc_ncm.c → Makefile.kbuild
          → make → DKMS signs (MOK if Secure Boot) → updates/dkms/ → depmod
```

`make install` runs `fetch-source.sh` so the cache is warm before an
unattended `apt` run; `verify.sh --all-kernels` reports kernels without
cached source. Log: `/var/log/mac-gx10-direct-link.log` records kernel,
source origin, SHA-256, and result.

### Cable plug-in

```
Mac enumerates 05ac:1905|1902 (LPM already disabled via usbcore.quirks at boot)
 → cdc_ncm binds interfaces 0 and 2
 → udev renames by ID_USB_INTERFACE_NUM → macncm0, macncm2
 → netplan applies 192.168.20.20/24 to macncm<IFACE_NUM>
```

### LPM quirk

Set on the kernel command line, not by udev (udev runs after enumeration,
too late for the first plug-in): `system/grub/apple-ncm.cfg` is installed
to `/etc/default/grub.d/`, appends
`usbcore.quirks=05ac:1905:k,05ac:1902:k`, then `update-grub` runs. Takes
effect after the next reboot **[OWNER]**.

### Mac side

`macos/setup-ip.md`: `networksetup -setmanual "<service>" 192.168.20.17
255.255.255.0` with no router and no DNS, so Wi-Fi remains the default
route. Service name is discovered with `networksetup -listallnetworkservices`.

## Why older generic binding fails

The generic CDC-NCM driver profile includes `FLAG_LINK_INTR`, which
requires an interrupt/status endpoint. Apple's private interfaces have no
such endpoint. Without a product-specific match, endpoint discovery fails
and the kernel logs `bind() failure`.

The upstream quirk maps both Apple Mac functions to
`apple_private_interface_info`. That profile omits `FLAG_LINK_INTR` while
retaining the NCM framing and Apple-specific zero-length-packet behaviour.

## Data path

After the driver binds and each side has an address, the path is ordinary
IP:

```text
application socket
  -> IP routing
  -> Mac enX
  -> CDC-NCM NTBs over USB
  -> GX10 macncm<N>
  -> application socket
```

No bridge, default-route replacement, DNS change, or Internet Connection
Sharing is required for a point-to-point subnet.

## Boundaries

- USB negotiation speed is not application throughput.
- Interface names and ordering are not stable identifiers; the udev rule
  pins `macncm<N>` by USB interface number.
- The repository does not select a function automatically for
  configuration; `IFACE_NUM` in `config/link.conf` picks it.
- The repository does not provide DHCP.
- Kernel support must be determined from the actual installed module, not
  only the kernel release string (`lib.sh::kernel_has_quirk`).
