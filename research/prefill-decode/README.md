# M8: distributed prefill/decode experiment protocol

**Status:** tooling scaffold only. This experiment is worth running only
after the M7 prefill research (`../kv-cache-math.md`) records a GO verdict,
which needs **[OWNER]** benchmark runs that have not happened yet. The
owner runs, real CSVs, and the `results.md` verdict remain pending.

## Scope

Compares, for the same `Qwen3.8-27B` model and the same prompts, four
execution modes across the USB-C link configured by this repository:

1. **Mac alone** - `llamacpp-rpc.sh local` on the Mac (single-device
   baseline, no GX10 involvement).
2. **GX10 alone** - `llamacpp-rpc.sh local` on the GX10 (single-device
   baseline, no Mac involvement).
3. **RPC split** - `llamacpp-rpc.sh server` on the GX10, `llamacpp-rpc.sh
   client` on the Mac, using llama.cpp's built-in `rpc-server`/`--rpc`
   backend split over the USB-C link.
4. **EXO split** - a prefill(GX10)/decode(Mac) split via EXO, if
   supported; see [`exo.md`](exo.md).

Isolation from the driver: this directory only depends on the link being
up (`tests/link.sh`) and on `llama-cli`/`rpc-server`/EXO being
installed by the owner; it does not touch `dkms/`, `scripts/`, or
`system/`.

## Protocol

For each of 3 prompt lengths (short/medium/long, chosen to match the
M7 contexts where feasible: 8192, 32768, 131072 tokens), run all four
modes and record `ttft_ms,tokens_per_s` per run:

```bash
# GX10
research/prefill-decode/llamacpp-rpc.sh server MODEL.gguf &
research/prefill-decode/llamacpp-rpc.sh local MODEL.gguf prompt-8k.txt

# Mac
research/prefill-decode/llamacpp-rpc.sh local MODEL.gguf prompt-8k.txt
research/prefill-decode/llamacpp-rpc.sh client MODEL.gguf prompt-8k.txt
```

`client` mode appends one CSV row per run to
`results/research/rpc-<date>.csv`. EXO runs follow the separate procedure
in `exo.md` and record their own CSV in the same directory.

## Pending

- **[OWNER]** Run the 3 prompt lengths × 4 modes and return the
  resulting CSVs.
- Once the CSVs exist, write `results.md` with the comparison
  table and an honest verdict (including an explicit "EXO: not supported"
  outcome if that procedure fails).
