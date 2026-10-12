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

| Link | Mac side | GX10 side |
|---|---|---|
| USB-C (static) | M5 Max 192.168.20.17/24 | GX10 192.168.20.20/24 |

No gateway, DNS, or hostnames are set on this link. It uses its own subnet,
so it never overlaps the LAN, and it avoids `10.x`, which VPN or zero-trust
clients on the Mac may capture. Detection: `tests/link.sh`
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

On the Mac, run `bash macos/setup.sh` once; it persists the static IP and
MTU. See [`macos/setup-ip.md`](macos/setup-ip.md) for details.

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

Hardware: MacBook Pro M5 Max (macOS 27) and ASUS Ascent GX10 (DGX OS,
kernel 7.0), one USB-C cable, negotiated at 10 Gbit/s (USB 3.2 Gen 2x1).
TCP throughput from `iperf3`, 4 parallel streams, 10 s runs.

| Setup | Mac → GX10 | GX10 → Mac |
|---|---|---|
| Untuned (MTU 1500, 16 KiB NTB, IRQ on CPU0) | 0.73 Gbit/s | 0.97 Gbit/s |
| xHCI interrupt moved to a big core | 3.5 Gbit/s | 3.9 Gbit/s |
| + RPS on four more big cores | 6.0 Gbit/s | 4.1 Gbit/s |
| + MTU 8178 and 32 KiB NTB (installed default) | **7.8 Gbit/s** | **6.0 Gbit/s** |

RTT is about 2-3 ms. Larger socket buffers, a larger softirq budget, other
CPU choices, and pinning `iperf3` changed nothing measurable, so the
remaining limit is the `cdc_ncm`/`usbnet` path itself: every outgoing
packet is copied into an NTB, and `usbnet` has no NAPI or offloads. Gen 2x1
carries about 8.5-8.8 Gbit/s of payload at best.

What made the difference, all applied by `make install`:

- **xHCI interrupt off CPU0.** Every interrupt from the USB controller lands
  on CPU0, a small core that saturates at 100 % softirq near 1 Gbit/s. The
  tune script moves it to `TUNE_IRQ_CPU` (default 5, a Cortex-X925 core).
- **RPS** spreads receive processing over `TUNE_RPS_MASK` (default `3c0`,
  CPUs 6-9).
- **32 KiB NTBs.** The Mac offers 32764-byte NTBs but the driver settles on
  16 KiB; the tune script raises `rx_max`/`tx_max` to `NTB_MAX`.
- **MTU 8178 on both sides.** On its own a larger MTU made things worse;
  it pays off only together with 32 KiB NTBs. Set the same MTU on the Mac
  (see `macos/setup-ip.md`).
- `txqueuelen 10000` and `netdev_max_backlog`/`netdev_budget` in
  `/etc/sysctl.d/60-apple-ncm.conf`.

Leave `tx_timer_usecs` at its default (400): 0 lowers GX10 → Mac. Do not add
`notrack` firewall rules on this interface: with ufw active, untracked
packets are dropped and the link stops.

Values live in `config/link.conf` and the script runs from udev each time
the interface appears (`/usr/local/sbin/apple-ncm-tune`).

### Stability under sustained load

> **Stable.** 1 hour of full load in both directions at once, 4.95 TB in
> total, plus 5 minutes per direction, with no link drops, no USB resets
> and 0 interface errors.

**1 hour, both directions at once** (`iperf3 --bidir -P 2 -t 3600`), a
heavier load than any real workload on this link:

| Direction | Average | Data | Retransmits |
|---|---|---|---|
| Mac → GX10 | **7.12 Gbit/s** | 2.91 TB | not reported (counted on the Mac) |
| GX10 → Mac | **5.00 Gbit/s** | 2.04 TB | 5534 (< 4 per million segments) |

- Throughput was flat from start to end, with no slowdown over time.
- USB stayed at 10000M, with no resets and no `cdc_ncm` kernel messages.
- 0 RX/TX errors, 0 qdisc drops. The driver counted about 5500 TX drops
  (about 13 per million packets); TCP recovered them.
- Peak temperature 62.5 °C, settling at 45 °C.
- `make doctor` passed every check afterwards.

**5 minutes per direction** (`iperf3 -P 2 -t 300`):

| Test (`iperf3 -P 2 -t 300`) | Average | Min / max per 30 s | Data | Retransmits |
|---|---|---|---|---|
| Mac → GX10 | **7.73 Gbit/s** | 7.69 / 7.80 | 270 GB | 4 |
| GX10 → Mac | **6.02 Gbit/s** | 5.91 / 6.04 | 210 GB | 3 |

Ping from the Mac while the link was saturated: 0 % loss, 1.37 ms average,
3.4 ms max. Two notes for anyone repeating this:

- Ping from the GX10 to the Mac gets no reply when macOS firewall stealth
  mode is on. TCP traffic is not affected.
- Run `ping` on the Mac in the foreground. macOS throttles low-priority
  background processes, so a backgrounded `ping` stops sending and reports
  false timeouts.

## Future work

- **The cable is not the limit.** The GX10 ports offer 20 Gbit/s (Gen 2x2),
  but the Mac in USB device mode links at 10 Gbit/s (Gen 2x1) even with an
  80 Gbit/s cable. Apple controllers do not support Gen 2x2.
- **Second cable.** A second link (`macncm1`/`en4`) could carry about
  12-15 Gbit/s in total across several flows. A single flow stays at one
  link's speed. This needs multi-interface support in the installer and
  config. Untested: whether a second Mac port also works in device mode.
- **Small CPU-side gains (maybe 5-10 %), with trade-offs.** IOMMU
  passthrough (needs a reboot and drops DMA isolation), and exempting this
  interface from conntrack without breaking ufw.
- **Different link.** The GX10 ConnectX-7 QSFP port to a Thunderbolt
  25/40GbE adapter on the Mac could exceed 20 Gbit/s. Not researched yet.

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
