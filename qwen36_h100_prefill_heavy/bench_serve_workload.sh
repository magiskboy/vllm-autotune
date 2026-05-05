#!/usr/bin/env bash
set -euo pipefail

MODEL="Qwen/Qwen3.6-35B-A3B-FP8"

SERVE_CMD="vllm serve ${MODEL} \
  --quantization fp8 \
  --kv-cache-dtype fp8_e4m3 \
  --reasoning-parser qwen3 \
  --gpu-memory-utilization 0.92"

BENCH_CMD="vllm bench serve \
  --model ${MODEL} \
  --dataset-name sharegpt \
  --num-prompts 200"

vllm bench sweep serve_workload \
  --serve-cmd "${SERVE_CMD}" \
  --bench-cmd "${BENCH_CMD}" \
  --serve-params "./top_configs.json" \
  --workload-var max_concurrency \
  --workload-iters 10 \
  --num-runs 2 \
  --output-dir "./results" \
  --experiment-name "workload"