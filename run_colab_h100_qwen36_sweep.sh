#!/usr/bin/env bash
set -euo pipefail

# Colab H100 preset for Qwen/Qwen3.6-35B-A3B-FP8.
# Goal: find max sustainable request load and serving config.
#
# Usage:
#   bash benchmarks/auto_tune/run_colab_h100_qwen36_sweep.sh
#
# Optional env overrides:
#   MODEL=Qwen/Qwen3.6-35B-A3B-FP8
#   MAX_MODEL_LEN=32768
#   EXP_PREFIX=qwen36_h100
#   NUM_RUNS=2
#   WORKLOAD_ITERS=8
#   OUTPUT_DIR=benchmarks/results

MODEL="${MODEL:-Qwen/Qwen3.6-35B-A3B-FP8}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
EXP_PREFIX="${EXP_PREFIX:-qwen36_h100_colab}"
NUM_RUNS="${NUM_RUNS:-2}"
WORKLOAD_ITERS="${WORKLOAD_ITERS:-8}"
OUTPUT_DIR="${OUTPUT_DIR:-benchmarks/results}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SERVE_PARAMS_JSON="${SCRIPT_DIR}/colab_h100_qwen36_serve_params.json"
BENCH_PARAMS_JSON="${SCRIPT_DIR}/colab_h100_qwen36_bench_params.json"

if [[ ! -f "${SERVE_PARAMS_JSON}" ]]; then
  echo "Missing ${SERVE_PARAMS_JSON}" >&2
  exit 1
fi
if [[ ! -f "${BENCH_PARAMS_JSON}" ]]; then
  echo "Missing ${BENCH_PARAMS_JSON}" >&2
  exit 1
fi

SERVE_CMD="vllm serve ${MODEL} \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.92 \
  --quantization fp8 \
  --kv-cache-dtype fp8_e4m3 \
  --max-model-len ${MAX_MODEL_LEN} \
  --language-model-only \
  --reasoning-parser qwen3"

BENCH_CMD="vllm bench serve \
  --backend vllm \
  --model ${MODEL} \
  --endpoint /v1/chat/completions \
  --ignore-eos"

echo "== Phase 1: coarse grid over max_num_seqs/max_num_batched_tokens =="
vllm bench sweep serve \
  --serve-cmd "${SERVE_CMD}" \
  --bench-cmd "${BENCH_CMD}" \
  --serve-params "${SERVE_PARAMS_JSON}" \
  --bench-params "${BENCH_PARAMS_JSON}" \
  --num-runs "${NUM_RUNS}" \
  --output-dir "${OUTPUT_DIR}" \
  --experiment-name "${EXP_PREFIX}_grid"

echo "== Phase 2: workload exploration (capacity curve) =="
vllm bench sweep serve_workload \
  --serve-cmd "${SERVE_CMD}" \
  --bench-cmd "${BENCH_CMD}" \
  --serve-params "${SERVE_PARAMS_JSON}" \
  --bench-params "${BENCH_PARAMS_JSON}" \
  --workload-var max_concurrency \
  --workload-iters "${WORKLOAD_ITERS}" \
  --num-runs "${NUM_RUNS}" \
  --output-dir "${OUTPUT_DIR}" \
  --experiment-name "${EXP_PREFIX}_workload"

echo "Done."
echo "Grid summary:     ${OUTPUT_DIR}/${EXP_PREFIX}_grid/summary.csv"
echo "Workload summary: ${OUTPUT_DIR}/${EXP_PREFIX}_workload/summary.csv"
