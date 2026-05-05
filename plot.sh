#!/usr/bin/env bash
set -euo pipefail

EXPERIMENT_DIR=$1

if [ -z "$EXPERIMENT_DIR" ]; then
    echo "Usage: $0 <experiment_dir>"
    exit 1
fi

METRICS="duration request_throughput output_throughput total_token_throughput max_output_tokens_per_s mean_ttft_ms median_ttft_ms std_ttft_ms p99_ttft_ms mean_tpot_ms median_tpot_ms std_tpot_ms p99_tpot_ms mean_itl_ms median_itl_ms std_itl_ms p99_itl_ms mean_e2el_ms median_e2el_ms std_e2el_ms p99_e2el_ms"

mkdir -p "$EXPERIMENT_DIR/viz"

for m in $METRICS; do
    vllm bench sweep plot "$EXPERIMENT_DIR" --fig-dir viz --fig-name "xBat_tokens_y_${m}" --var-x max_num_batched_tokens --var-y "$m" --curve-by max_num_seqs
done

for m in $METRICS; do
    vllm bench sweep plot "$EXPERIMENT_DIR" --fig-dir viz --fig-name "xSeqs_y_${m}" --var-x max_num_seqs --var-y "$m" --curve-by max_num_batched_tokens
done

vllm bench sweep plot_pareto "$EXPERIMENT_DIR" --label-by max_num_seqs,max_num_batched_tokens --user-count-var max_concurrent_requests

cp "$EXPERIMENT_DIR/pareto"/*.png "$EXPERIMENT_DIR/viz/"

echo "Plotted figures saved to $EXPERIMENT_DIR/viz/"