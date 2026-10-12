# KV-cache and recurrent-state math (M7)

**Status:** partial. The tooling and its tests are complete; the real
benchmark numbers and the GO/NO-GO verdict require manual **[OWNER]**
runs on both machines and have not been produced yet. This document will be completed
(method, verified config values, full table, measured prefill numbers,
verdict) once the owner returns the two `llama-bench` JSON files.

## Method

1. Load the model's `config.json` (`kv_math.load_config`); if the config
   nests parameters under `text_config`, that nested dict is used.
2. Count full-attention layers: an explicit `layer_types` list is
   preferred (count of `"full_attention"` entries); otherwise
   `num_hidden_layers // full_attention_interval`.
3. KV-cache bytes per token (all full-attention layers, key + value):
   `2 * full_layers * num_key_value_heads * head_dim * dtype_bytes`.
4. Recurrent (Gated DeltaNet) state bytes, across all non-full-attention
   layers: `(num_hidden_layers - full_layers) * linear_num_value_heads *
   linear_key_head_dim * linear_value_head_dim * state_bytes`. Conv state
   is a small additional term and is excluded here.
5. Transfer time: `(fp8_kv_bytes + state_bytes) / link_bytes_per_second`,
   where `link_bytes_per_second` comes from `end.sum_received.bits_per_second
   / 8` in a `tests/bench.sh` `fwd.json` result.
6. Go/no-go: GO for a context length when
   `prefill_time_dgx10 + transfer_time < prefill_time_mac` (measured via
   `llama-bench`); an overall verdict of GO is recorded if
   any tested context is GO.

## Model config used for the unit-test fixture **[ASSUMPTION - synthetic, not the real model]**

The test fixture in `research/tests/test_kv_math.py` uses representative,
round numbers to exercise the formulas, not `Qwen/Qwen3.8-27B`'s real
config:

| Field | Value |
|---|---|
| `num_hidden_layers` | 64 |
| `full_attention_interval` | 4 |
| `num_key_value_heads` | 4 |
| `head_dim` | 256 |
| `linear_num_value_heads` | 48 |
| `linear_key_head_dim` | 128 |
| `linear_value_head_dim` | 128 |

Derived: `full_layers=16`, `kv_bf16_per_token=65536 B`,
`kv_fp8_per_token=32768 B`, `recurrent_state=150994944 B` (~144 MiB).

## Pending: verified config, measured prefill, and verdict

Not yet available - requires:

- **[OWNER]** Download
  `https://huggingface.co/Qwen/Qwen3.8-27B/resolve/main/config.json` to
  `research/data/config.json` and re-derive the table above from the real
  values.
- **[OWNER]** Install llama.cpp on both machines (Metal on the Mac, CUDA
  on the DGX10) and obtain a `Qwen3.8-27B` GGUF at the same quantization on
  both.
- **[OWNER]** Run `research/prefill-bench/run.sh` on each machine and
  return both JSON files, plus a `tests/bench.sh` `fwd.json` link measurement.
- Then run `kv_math.py` and `go_nogo.py` with the real inputs and replace
  this section with the method, verified config values, table, measured
  prefill numbers, and a recorded `GO`/`NO-GO` verdict.
