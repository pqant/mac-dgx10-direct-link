#!/usr/bin/env bash
# Runs the three llama.cpp RPC-split experiment modes for M8. Isolated
# research tooling; does not touch the DKMS driver.
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") server MODEL_GGUF" >&2
  echo "       $(basename "$0") client MODEL_GGUF PROMPT_FILE" >&2
  echo "       $(basename "$0") local MODEL_GGUF PROMPT_FILE" >&2
}

mode="${1:-}"

rpc_host="192.168.20.20"
rpc_port="50052"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd not found" >&2
    exit 2
  fi
}

# parse_timing TEXT - extracts "ttft_ms,tokens_per_s" from llama-cli timing
# output. Looks for the prompt-eval time (ms) as time-to-first-token and
# the eval tokens-per-second line.
parse_timing() {
  local text="$1"
  local ttft_ms tokens_per_s
  ttft_ms="$(printf '%s\n' "$text" | grep -o 'prompt eval time =[^,]*' \
    | grep -o '[0-9.]\+' | head -n1 || true)"
  tokens_per_s="$(printf '%s\n' "$text" | grep -o 'eval time =.*tokens per second' \
    | grep -o '[0-9.]\+ tokens per second' | grep -o '^[0-9.]\+' || true)"
  echo "${ttft_ms:-0},${tokens_per_s:-0}"
}

case "$mode" in
  server)
    model="${2:-}"
    if [ -z "$model" ]; then
      usage
      exit 64
    fi
    require_cmd rpc-server
    rpc-server -H "$rpc_host" -p "$rpc_port"
    ;;
  client)
    model="${2:-}"
    prompt_file="${3:-}"
    if [ -z "$model" ] || [ -z "$prompt_file" ]; then
      usage
      exit 64
    fi
    require_cmd llama-cli
    results_dir="$(cd "$(dirname "$0")/../.." && pwd)/results/research"
    mkdir -p "$results_dir"
    out_csv="$results_dir/rpc-$(date -u +%Y%m%d).csv"
    output="$(llama-cli -m "$model" --rpc "$rpc_host:$rpc_port" \
      -f "$prompt_file" -n 256 --no-display-prompt 2>&1)"
    echo "$output"
    parse_timing "$output" >>"$out_csv"
    ;;
  local)
    model="${2:-}"
    prompt_file="${3:-}"
    if [ -z "$model" ] || [ -z "$prompt_file" ]; then
      usage
      exit 64
    fi
    require_cmd llama-cli
    llama-cli -m "$model" -f "$prompt_file" -n 256 --no-display-prompt
    ;;
  *)
    usage
    exit 64
    ;;
esac
