# mac-gx10-direct-link

A self-retiring DKMS package and toolkit that keeps a direct Apple Mac ↔
ASUS GX10 (DGX OS) USB-C CDC-NCM link working across kernel upgrades.

## Purpose

The MacBook Pro M5 Max and the ASUS Ascent GX10 are connected with a single
USB-C cable as a static point-to-point IP link. It works without Wi-Fi or
DHCP, survives GX10 kernel upgrades with no manual action, retires itself
once the distro kernel ships the upstream Apple CDC-NCM quirk, and provides
reproducible link measurements that feed prefill/decode research (prefill on
GX10, decode on Mac).

## IP plan

| Link | Mac side | GX10 side | Notes |
|---|---|---|---|
| **USB-C (new, static)** | **M5 Max 192.168.20.17/24** | **GX10 192.168.20.20/24** | This project |

**Owner decision:** use `192.168.20.17` (Mac) and `192.168.20.20` (GX10) with mask
`255.255.255.0`. No hostnames are added.

**Known risk (recorded, not mitigated by design):** the USB link shares
`172.16.0.0/24` with Wi-Fi and the wired Ethernet. The kernel may select a
different interface for `192.168.20.17`. Detection: `tests/link.sh` fails if
`ip route get 192.168.20.17` does not resolve to the USB interface, and
`bench.sh` records the egress interface with each result.

## Quick start

```bash
sudo make install   # builds/installs the DKMS module if the in-tree
                     # cdc_ncm lacks the Apple quirk, renders GRUB/udev/netplan
# reboot                       # [OWNER] applies the usbcore.quirks LPM disable
# plug in the USB-C cable      # [OWNER] see macos/setup-ip.md for the Mac side
make doctor          # read-only PASS/FAIL table, no root required
```

See [`macos/setup-ip.md`](macos/setup-ip.md) for the Mac-side static IP steps.

## Everyday commands

- `make verify` - per-kernel table: in-tree quirk status, DKMS status,
  effective module path, alias count. Add `--all-kernels` for every
  installed kernel, not just the running one.
- `make bench` - runs `iperf3` in both directions and records JSON results
  plus ping RTT and metadata under `results/`.
- `sudo make uninstall` - reverses every install step (DKMS removal, GRUB
  drop-in, udev rule, netplan file, depmod override) and leaves no
  `updates/dkms/cdc_ncm*`.

## Safety boundaries

- Read-only scripts (`doctor.sh`, `check-kernel-support.sh`, `verify.sh`)
  never use root or write system paths.
- No script unloads `cdc_ncm` while an SSH session's interface is bound to
  it; driver swap requires `--apply` and an unplugged cable.
- All scripts use `set -euo pipefail`, are shellcheck clean, and never
  hard-code a kernel version.
- This project does not touch Wi-Fi/Ethernet routing, DNS, or provide DHCP.

## License

This project is released under the [MIT License](LICENSE).
The kernel patch under `patches/` follows its upstream Linux license; see [`NOTICE.md`](NOTICE.md).
