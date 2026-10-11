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
`255.255.255.0`. No hostnames are added. The link uses its own subnet, so it
never overlaps the LAN (`172.16.0.0/24`), and it avoids `10.x`, which VPN
or zero-trust clients on the Mac may capture. Detection: `tests/link.sh`
fails if `ip route get 192.168.20.17` does not resolve to the USB interface,
and `bench.sh` records the egress interface with each result.

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

## Measured performance

First measurement on the USB-C link, before any tuning (MTU 1500, default
`cdc_ncm` buffers). Hardware: MacBook Pro M5 Max (macOS 27) and ASUS Ascent
GX10 (DGX OS, kernel 7.0). TCP throughput comes from a memory-to-memory socket
test with 10 s runs; `iperf3` was not installed on either side.

| Direction | 1 stream | 4 streams | 8 streams |
|---|---|---|---|
| Mac → GX10 | 0.98 Gbit/s | 0.94 Gbit/s | 0.94 Gbit/s |
| GX10 → Mac | 1.16 Gbit/s | 0.83 Gbit/s | 0.76 Gbit/s |

| Metric | Value |
|---|---|
| RTT (50 pings) | min 1.87 / avg 2.52 / max 3.11 ms, 0 % loss |
| USB negotiated speed | 10 Gbit/s (USB 3.2 Gen 2) |
| Same test over loopback | 36 Gbit/s, so the tool is not the bottleneck |

The link currently delivers about 1 Gbit/s, roughly 10 % of the USB bus rate.
Likely limits: the NTB buffers settle at 16 KiB although the device offers
32 KiB, the GX10 side runs MTU 1500 while the Mac uses 8178, and the GX10
interface shows dropped RX packets. Tuning these is the next step; results
will be added here.

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
