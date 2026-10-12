# EXO prefill(DGX10)/decode(Mac) split procedure

**[ASSUMPTION]** EXO (`exo-explore/exo`) supports a heterogeneous
prefill/decode split for `Qwen3.8-27B` across a CUDA node (DGX10) and a
Metal node (Mac) over a plain IP link. This has not been verified yet;
the first run of this procedure must confirm it and record "not
supported" as a valid, honest result if EXO cannot express this split
(for example, if it only balances layers across nodes rather than
splitting prefill and decode roles).

## Pinned versions

- `exo` repository: `exo-explore/exo`, tag/commit to be pinned by the
  owner at the time of the first run (record the exact commit SHA in
  `results.md`); this document intentionally does not invent a commit
  SHA that was never checked out.
- Python: the version bundled with each machine's existing toolchain
  (record `python3 --version` output from both machines in `results.md`).
- Model: the same `Qwen3.8-27B` GGUF/weights used for the M7/M8
  llama.cpp runs, at the same quantization on both machines.

## Procedure

1. **[OWNER]** On both the DGX10 and the Mac, clone the pinned `exo`
   commit and install its dependencies per its own `README.md`
   instructions (do not substitute package versions).
2. **[OWNER]** Configure EXO's cluster discovery or static peer list to
   use the USB-C link addresses from this repository
   (`DGX10_IP=192.168.20.20`, `MAC_IP=192.168.20.17`; see `config/link.conf`),
   not the Wi-Fi/Ethernet addresses, so the experiment measures this
   project's link.
3. **[OWNER]** Attempt to pin the model's prefill stage to the DGX10 node
   and the decode stage to the Mac node, following EXO's own
   partitioning/placement configuration. If EXO has no mechanism to pin
   prefill vs. decode roles to specific nodes (as opposed to balancing
   layers by node capability), stop here and record "EXO: not supported
   for prefill/decode role pinning" in `results.md`; do not force an
   unsupported configuration.
4. If role pinning is supported, run the same 3 prompt lengths used in
   the llama.cpp RPC-split protocol (`README.md` in this directory) and
   record `ttft_ms,tokens_per_s` (or EXO's equivalent metrics, labelled
   accordingly) into `results/research/exo-<date>.csv`.
5. Return the CSV (or the "not supported" note) so it can be written
   into `results.md`.

## Notes

- This procedure is read/owner-driven only; no script in this repository
  automates EXO installation or cluster configuration, since EXO's setup
  is environment-specific and outside this project's scope.
- Any throughput or latency number in `results.md` must come from an
  actual EXO run recorded here, never an estimate.
