#!/usr/bin/env python3
"""Pick best serving config from vLLM sweep summary.csv."""

from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary-csv", required=True, type=Path)
    parser.add_argument("--max-p99-e2el-ms", type=float, default=None)
    parser.add_argument("--max-median-ttft-ms", type=float, default=None)
    parser.add_argument("--min-output-tps", type=float, default=None)
    args = parser.parse_args()

    df = pd.read_csv(args.summary_csv)
    required_cols = {
        "max_num_seqs",
        "max_num_batched_tokens",
        "request_throughput",
        "output_token_throughput",
        "total_token_throughput",
    }
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise ValueError(f"Missing columns in summary file: {missing}")

    filtered = df.copy()
    if args.max_p99_e2el_ms is not None and "p99_e2el_ms" in filtered.columns:
        filtered = filtered[filtered["p99_e2el_ms"] <= args.max_p99_e2el_ms]
    if args.max_median_ttft_ms is not None and "median_ttft_ms" in filtered.columns:
        filtered = filtered[filtered["median_ttft_ms"] <= args.max_median_ttft_ms]
    if args.min_output_tps is not None:
        filtered = filtered[filtered["output_token_throughput"] >= args.min_output_tps]

    if filtered.empty:
        print("No configuration satisfies constraints.")
        return

    grouped = (
        filtered.groupby(
            ["_benchmark_name", "max_num_seqs", "max_num_batched_tokens"],
            as_index=False,
        )
        .agg(
            request_tps=("request_throughput", "mean"),
            output_tps=("output_token_throughput", "mean"),
            total_tps=("total_token_throughput", "mean"),
            p99_e2el_ms=("p99_e2el_ms", "mean")
            if "p99_e2el_ms" in filtered.columns
            else ("request_throughput", "count"),
            median_ttft_ms=("median_ttft_ms", "mean")
            if "median_ttft_ms" in filtered.columns
            else ("request_throughput", "count"),
        )
        .sort_values(["request_tps", "output_tps"], ascending=False)
    )

    best = grouped.iloc[0]
    print("Best config under constraints:")
    print(
        f"- workload={best['_benchmark_name']}, "
        f"max_num_seqs={int(best['max_num_seqs'])}, "
        f"max_num_batched_tokens={int(best['max_num_batched_tokens'])}"
    )
    print(
        f"- request_tps={best['request_tps']:.2f}, "
        f"output_tps={best['output_tps']:.2f}, total_tps={best['total_tps']:.2f}"
    )
    if "p99_e2el_ms" in grouped.columns:
        print(f"- p99_e2el_ms={best['p99_e2el_ms']:.2f}")
    if "median_ttft_ms" in grouped.columns:
        print(f"- median_ttft_ms={best['median_ttft_ms']:.2f}")

    print("\nTop 10 configs:")
    print(grouped.head(10).to_string(index=False))


if __name__ == "__main__":
    main()
