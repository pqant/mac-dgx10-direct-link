#!/usr/bin/env python3
"""Go/no-go decision for DGX10-prefill + Mac-decode vs. Mac-only prefill.

Isolated research tooling; does not touch the DKMS driver or system
integration code in this repository.
"""
from __future__ import annotations

import argparse
import json
import sys

import kv_math


def decide(prefill_dgx10_s: float, prefill_mac_s: float, transfer_s: float) -> bool:
    """GO when DGX10 prefill plus the KV/state transfer is still faster than
    prefill done directly on the Mac."""
    return prefill_dgx10_s + transfer_s < prefill_mac_s


def load_bench(path: str) -> dict:
    """Reads a llama-bench ``-o json`` file and returns
    ``{n_prompt: avg_seconds}`` for the prefill entries (``n_prompt`` > 0)."""
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    result = {}
    for entry in data:
        n_prompt = entry.get("n_prompt", 0)
        if n_prompt:
            result[n_prompt] = entry["avg_ns"] / 1e9
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dgx10", required=True)
    parser.add_argument("--mac", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--link-json", required=True)
    args = parser.parse_args(argv)

    dgx10_bench = load_bench(args.dgx10)
    mac_bench = load_bench(args.mac)
    cfg = kv_math.load_config(args.config)
    link_bytes_per_s = kv_math.link_bytes_per_second(args.link_json)
    state = kv_math.recurrent_state_bytes(cfg)

    any_go = False
    for context in sorted(set(dgx10_bench) & set(mac_bench)):
        prefill_dgx10_s = dgx10_bench[context]
        prefill_mac_s = mac_bench[context]
        fp8_bytes = kv_math.kv_bytes_per_token(cfg, dtype_bytes=1) * context
        transfer_s = kv_math.transfer_seconds(
            fp8_bytes + state, link_bytes_per_s
        )
        go = decide(prefill_dgx10_s, prefill_mac_s, transfer_s)
        any_go = any_go or go
        verdict = "GO" if go else "NO-GO"
        print(
            f"context={context} dgx10={prefill_dgx10_s:.3f}s "
            f"mac={prefill_mac_s:.3f}s transfer={transfer_s:.3f}s "
            f"{verdict}"
        )

    print("GO" if any_go else "NO-GO")
    return 0


if __name__ == "__main__":
    sys.exit(main())
