#!/usr/bin/env python3
"""KV-cache and recurrent-state size math for M7 prefill/decode feasibility.

This module is pure research tooling: it is isolated from the DKMS driver
and system-integration code in this repository and only reasons about model
configuration numbers and measured link throughput.
"""
from __future__ import annotations

import argparse
import json
import sys


def load_config(path: str) -> dict:
    """Loads a model config.json. If a ``text_config`` key exists, returns
    that nested dict (common for multi-modal model configs); otherwise
    returns the top-level dict."""
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    return load_config_dict(data)


def load_config_dict(data: dict) -> dict:
    if "text_config" in data:
        return data["text_config"]
    return data


def full_attention_layers(cfg: dict) -> int:
    """Number of full-attention layers. Prefers an explicit
    ``layer_types`` list (counts ``"full_attention"`` entries); falls back
    to ``num_hidden_layers // full_attention_interval``."""
    layer_types = cfg.get("layer_types")
    if layer_types:
        return sum(1 for t in layer_types if t == "full_attention")
    return cfg["num_hidden_layers"] // cfg["full_attention_interval"]


def kv_bytes_per_token(cfg: dict, dtype_bytes: int) -> int:
    """KV-cache bytes per token across all full-attention layers (key +
    value, hence the factor of 2)."""
    full_layers = full_attention_layers(cfg)
    return (
        2
        * full_layers
        * cfg["num_key_value_heads"]
        * cfg["head_dim"]
        * dtype_bytes
    )


def recurrent_state_bytes(cfg: dict, state_bytes: int = 4) -> int:
    """Bytes of recurrent (e.g. Gated DeltaNet) state across all
    non-full-attention layers. Conv state is excluded (a small additional
    term, noted in ``kv-cache-math.md``)."""
    full_layers = full_attention_layers(cfg)
    linear_layers = cfg["num_hidden_layers"] - full_layers
    return (
        linear_layers
        * cfg["linear_num_value_heads"]
        * cfg["linear_key_head_dim"]
        * cfg["linear_value_head_dim"]
        * state_bytes
    )


def transfer_seconds(nbytes: float, link_bytes_per_s: float) -> float:
    return nbytes / link_bytes_per_s


def link_bytes_per_second(link_json_path: str) -> float:
    with open(link_json_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    return data["end"]["sum_received"]["bits_per_second"] / 8


def render_table(cfg: dict, link_bytes_per_s: float, contexts) -> str:
    lines = [
        "| context | bf16 GB | fp8 GB | transfer s (fp8 + state) |",
        "|---|---|---|---|",
    ]
    state = recurrent_state_bytes(cfg)
    for ctx in contexts:
        bf16_bytes = kv_bytes_per_token(cfg, dtype_bytes=2) * ctx
        fp8_bytes = kv_bytes_per_token(cfg, dtype_bytes=1) * ctx
        bf16_gb = bf16_bytes / 1e9
        fp8_gb = fp8_bytes / 1e9
        t_s = transfer_seconds(fp8_bytes + state, link_bytes_per_s)
        lines.append(
            f"| {ctx} | {bf16_gb:.2f} | {fp8_gb:.2f} | {t_s:.3f} |"
        )
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--link-json", required=True)
    parser.add_argument(
        "--contexts", type=int, nargs="+", default=[8192, 32768, 131072]
    )
    args = parser.parse_args(argv)

    cfg = load_config(args.config)
    link_bytes_per_s = link_bytes_per_second(args.link_json)
    print(render_table(cfg, link_bytes_per_s, args.contexts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
