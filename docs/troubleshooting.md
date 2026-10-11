# Troubleshooting


## 1. `lsusb` shows `05ac:1905`, but speed is `480M`

`480M` is USB 2.0 High Speed, not USB 3.x. The likely causes are a
charge-only or USB 2.0 cable, an adapter that lacks SuperSpeed lanes, a
USB 2.0 port, or an incomplete connection.

Try a short certified data cable and a direct USB 3.x/USB4-capable port.
Confirm speed from the matching device directory in
`/sys/bus/usb/devices/.../speed`.

## 2. Speed is `10000M`, but `cdc_ncm` reports `bind() failure`

The physical link is SuperSpeed+, but the driver probably lacks the Apple
private-interface quirk. Check aliases for both interface numbers:

```bash
./scripts/check-kernel-support.sh --product 1905
```

If both aliases are absent, prefer a newer or backported distribution
kernel, or run `make install` so DKMS builds the quirked module for the
running kernel. Otherwise build only from exact matching source. Do not
repeatedly rebind the generic driver while the system is carrying
important traffic.

## 3. Module built, but loading says `Key was rejected by service`

Secure Boot/module signature enforcement rejected an unsigned or
untrusted module. Do not disable Secure Boot as a shortcut. Run
`scripts/secureboot-enroll.sh` to enrol a local MOK, reboot to complete
enrolment **[OWNER]**, then re-run `make install`. `doctor.sh` reports this
stage as a FAIL line.

## 4. Interfaces exist, but ping fails

The driver can bind without either peer having an IPv4 address. Check:

```bash
ip -br link
ip -br addr
ip route get 192.168.20.17
```

Confirm that Mac and GX10 use different addresses in the same `/24`, both
interfaces are up, and the route selects the USB (`macncm<N>`) interface.
Check host firewalls without changing the default route or DNS.

## 5. Link negotiates 10 Gb/s, but `iperf3` measures about 5 Gb/s

This can be normal. `10000M` describes USB signalling, not guaranteed TCP
payload throughput. CDC-NCM framing, USB transfer sizes, host-controller
and driver behaviour, CPU scheduling, TCP direction, and stream count all
add overhead.

`tests/bench.sh` records forward and reverse JSON results plus the egress
interface and kernel version with every run. Do not advertise 10 Gb/s
application throughput unless it is measured reproducibly.

## 6. `modinfo` has the aliases, but no `macncm*` device appears

Check which module is actually loaded (`modinfo -n cdc_ncm`), inspect the
exact USB interfaces with `lsusb -v` (possibly requiring elevated read
access), and read relevant `dmesg` lines. A vendor kernel can ship a
different module than the source tree you inspected. `doctor.sh` and
`tests/link.sh` both report this as a FAIL with the missing interface
name.

## 7. Apple PID is `1902`, not `1905`

`1902` has its own upstream change. The patch in this repository
intentionally does not rewrite its product ID. Use `--product 1902` for
inspection and prefer a kernel containing upstream commit
`746fc0787f61`.

## 8. Cold cache: `fetch-source.sh` has nothing for the running kernel

`prepare.sh` only ever uses source matching the exact `kernelver` being
built; it never substitutes another major/minor. Run
`scripts/fetch-source.sh` (optionally with explicit kernel versions) to
warm the cache ahead of an unattended `apt full-upgrade`, or check
`verify.sh --all-kernels` for kernels missing cached source.

## 9. `install.sh` exits with code `10`

This is the Secure Boot gate: Secure Boot is enabled and no MOK is
enrolled yet. Run `scripts/secureboot-enroll.sh`, reboot and complete the
MOK enrolment screen **[OWNER]**, then re-run `make install`.

## 10. `tests/link.sh` fails with the wrong route

`ip route get 192.168.20.17` resolved to an interface other than the USB
link. Check that no other interface uses `192.168.20.0/24`; if one does,
add a more specific route or policy rule so traffic to the Mac's
`192.168.20.17` prefers `macncm<N>`; do not change the default route.

## 11. `config/pids.conf` has an unknown/invalid PID

`lib.sh::read_pids` rejects any token that is not a 4-hex-digit USB
product ID with `invalid PID '<token>' in <file>` and refuses to load the
file. Fix or remove the offending line; every PID must match an Apple
private CDC-NCM function this project supports.

## 12. No `macncm*` interface after a successful DKMS build

If `cdc_ncm` loaded (aliases present, no `bind() failure`) but
`ip -br link` never shows `macncm<N>`, the udev rule
(`system/udev/90-apple-ncm.rules`) may not have been installed or
reloaded. Re-run `make install`, then `udevadm trigger` after plugging
the cable back in.
