#!/usr/bin/env bash
set -euo pipefail

MODEL="Qwen/Qwen3.6-35B-A3B-FP8"

SERVE_CMD="vllm serve ${MODEL} \
  --quantization fp8 \
  --kv-cache-dtype fp8_e4m3 \
  --reasoning-parser qwen3 \
  --gpu-memory-utilization 0.92"

BENCH_CMD="vllm bench serve \
  --model ${MODEL}"

vllm bench sweep serve \
  --serve-cmd "${SERVE_CMD}" \
  --bench-cmd "${BENCH_CMD}" \
  --serve-params "./serve_params.json" \
  --bench-params "./bench_params.json" \
  --num-runs 1 \
  --output-dir "./results" \
  --experiment-name "prefill_heavy" \
  --resume
