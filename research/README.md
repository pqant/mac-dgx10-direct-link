# M7: prefill/decode feasibility research

## Scope

This directory investigates whether running prefill for `Qwen/Qwen3.8-27B`
on the GX10 (CUDA) and transferring the resulting KV cache / recurrent
state to the Mac (Metal) over the USB-C link, then decoding on the Mac, is
faster than running prefill directly on the Mac.

**Isolation from the driver:** nothing here touches the DKMS package,
`dkms/`, `scripts/`, `system/`, or the udev/GRUB/netplan integration. It
only depends on:

- a model `config.json` (for KV-cache/state size math),
- a measured link result (`results/<dir>/fwd.json`, produced by
  `tests/bench.sh`, Task 9),
- `llama-bench` JSON output from each machine (Task 15 Step 5/6,
  **[OWNER]**).

Research code is pure Python/bash with no dependency on this
repository's bash test harness beyond being hooked into
`tests/run-unit.sh` via `python -m unittest discover research/tests`.

## How to run

1. Unit tests (hermetic, no network, no GPU):

   ```bash
   python -m unittest discover research/tests
   ```

2. KV-cache/state size table, given a model config and a measured link
   result:

   ```bash
   python research/kv_math.py --config research/data/config.json \
     --link-json results/<dir>/fwd.json \
     --contexts 8192 32768 131072
   ```

3. Prefill benchmark on each machine (**[OWNER]**, requires `llama-bench`
   and a GGUF of the model):

   ```bash
   research/prefill-bench/run.sh MODEL.gguf gx10-bench.json   # on GX10
   research/prefill-bench/run.sh MODEL.gguf mac-bench.json    # on the Mac
   ```

4. Go/no-go verdict combining both benches, the config, and the measured
   link:

   ```bash
   python research/go_nogo.py --gx10 gx10-bench.json --mac mac-bench.json \
     --config research/data/config.json --link-json results/<dir>/fwd.json
   ```

See [`kv-cache-math.md`](kv-cache-math.md) for the method and the result
once the owner-gated steps (5 and 6) are complete.
