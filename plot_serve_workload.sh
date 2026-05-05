#!/usr/bin/env bash
set -euo pipefail

EXPERIMENT_DIR=${1:-}
WORKLOAD_VAR=${2:-max_concurrency}
CURVE_BY=${CURVE_BY:-max_num_seqs,max_num_batched_tokens}
FIG_SUBDIR=${FIG_SUBDIR:-viz_serve_workload}

if [ -z "$EXPERIMENT_DIR" ]; then
    echo "Usage: $0 <experiment_dir> [workload_var]" >&2
    echo "  experiment_dir: directory passed to -o/-e of sweep (contains summary.csv)" >&2
    echo "  workload_var:  max_concurrency (default) or request_rate — must match sweep --workload-var" >&2
    exit 1
fi

METRICS="duration request_throughput output_throughput total_token_throughput max_output_tokens_per_s mean_ttft_ms median_ttft_ms std_ttft_ms p99_ttft_ms mean_tpot_ms median_tpot_ms std_tpot_ms p99_tpot_ms mean_itl_ms median_itl_ms std_itl_ms p99_itl_ms mean_e2el_ms median_e2el_ms std_e2el_ms p99_e2el_ms"

mkdir -p "$EXPERIMENT_DIR/$FIG_SUBDIR"

# Primary: workload level vs each metric; one curve per serve configuration.
for m in $METRICS; do
    vllm bench sweep plot "$EXPERIMENT_DIR" \
        --fig-dir "$FIG_SUBDIR" \
        --fig-name "wl_${WORKLOAD_VAR}_y_${m}" \
        --var-x "$WORKLOAD_VAR" \
        --var-y "$m" \
        --curve-by "$CURVE_BY"
done

# Throughput vs latency tradeoffs across workload levels.
for pair in \
    "total_token_throughput median_ttft_ms" \
    "total_token_throughput p99_ttft_ms" \
    "output_throughput median_tpot_ms" \
    "total_token_throughput median_e2el_ms"; do
    set -- $pair
    vx=$1
    vy=$2
    vllm bench sweep plot "$EXPERIMENT_DIR" \
        --fig-dir "$FIG_SUBDIR" \
        --fig-name "tradeoff_${vx}_${vy}" \
        --var-x "$vx" \
        --var-y "$vy" \
        --curve-by "$CURVE_BY"
done

vllm bench sweep plot_pareto "$EXPERIMENT_DIR" \
    --label-by max_num_seqs,max_num_batched_tokens \
    --user-count-var "$WORKLOAD_VAR"

if [ -d "$EXPERIMENT_DIR/pareto" ]; then
    cp "$EXPERIMENT_DIR/pareto"/*.png "$EXPERIMENT_DIR/$FIG_SUBDIR/" 2>/dev/null || true
fi

echo "Plotted figures saved to $EXPERIMENT_DIR/$FIG_SUBDIR/"