# Notice

This project relies on the following upstream work.

## Upstream Linux kernel commits

The Apple CDC-NCM ID-table support this project relies on comes from two
upstream Linux kernel commits:

- [`a5148bc2fa27`](https://github.com/torvalds/linux/commit/a5148bc2fa27092862ac4b9e7b5c8340d60cff34)
  - adds Apple VID:PID `05ac:1905`, authored by Alex Cheema.
- [`746fc0787f61`](https://github.com/torvalds/linux/commit/746fc0787f616da418ffc04a110296fe95d53491)
  - adds Apple VID:PID `05ac:1902`.

## Patch license

Linux `drivers/net/usb/cdc_ncm.c` is dual-licensed; any patch adapted from it
in this repository is distributed under `GPL-2.0-only OR BSD-2-Clause`. The
rest of this repository's scripts and documentation remain MIT-licensed.
