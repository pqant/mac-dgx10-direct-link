# Quirk patch generation

`reference/apple-mac-05ac-1905.patch` is the ID-table change from Linux upstream commit
[`a5148bc2fa27092862ac4b9e7b5c8340d60cff34`](https://github.com/torvalds/linux/commit/a5148bc2fa27092862ac4b9e7b5c8340d60cff34),
authored by Alex Cheema and committed by Jakub Kicinski. It is kept here for
reference and attribution only; it is **not** applied by any script.

Linux `drivers/net/usb/cdc_ncm.c` explicitly offers a choice of GPL version 2
or the 2-clause BSD license. Any derivative hunk generated from it is
distributed under the same `GPL-2.0-only OR BSD-2-Clause` choice. The
repository's own scripts and documentation remain MIT-licensed.

## `gen-quirk-patch.sh`

This project does not ship a single static patch.
Because the target kernel's exact `cdc_ncm.c` varies per-kernel (Task 5 fetches
the right source for each installed `KVER`), the quirk hunk is generated at
build time by `gen-quirk-patch.sh SRC_C PIDS_FILE`, which prints the patched
source to stdout.

For every PID listed in `config/pids.conf` (in file order), it inserts one
block immediately before the first `/* Ericsson MBM devices` anchor line,
matching the formatting of upstream commit `a5148bc2fa27` :

```c
	/* Mac (direct USB-C networking, PID 0x<pid>) - mac-gx10-direct-link */
	{ USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x<pid>, 0),
		.driver_info = (unsigned long)&apple_private_interface_info,
	},
	{ USB_DEVICE_INTERFACE_NUMBER(0x05ac, 0x<pid>, 2),
		.driver_info = (unsigned long)&apple_private_interface_info,
	},
```

Exit codes:

| Code | Meaning |
| --- | --- |
| `0` | Patched source printed on stdout. |
| `3` | `SRC_C` already contains `0x05ac, 0x<pid>` for one of the listed PIDs; nothing is printed. |
| `4` | `apple_private_interface_info` is not present in `SRC_C`. |
| `5` | The `/* Ericsson MBM devices` anchor is not present in `SRC_C`. |
| `64` | Usage error or invalid PIDs in `PIDS_FILE`. |

`tests/fixtures/get-sources.sh` downloads known-good real sources (`v6.17`,
missing the quirk, and `v7.1`, which has it upstream) so the real-source tests
in `tests/unit/test_gen_quirk_patch.sh` can run end-to-end; it is skipped
(`SKIP`, exit 0) when offline.
