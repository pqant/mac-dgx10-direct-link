#!/usr/bin/env bash
# Runs llama-bench prefill benchmarks for the M7 prefill/decode feasibility
# check. Isolated research tooling; does not touch the DKMS driver.
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") MODEL_GGUF OUT_JSON" >&2
}

if [ "$#" -ne 2 ]; then
  usage
  exit 64
fi

model="$1"
out_json="$2"

if ! command -v llama-bench >/dev/null 2>&1; then
  echo "llama-bench not found" >&2
  exit 2
fi

llama-bench -m "$model" -p 8192,32768,131072 -n 0 -r 3 -o json >"$out_json"
