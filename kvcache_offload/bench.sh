#!/bin/bash

vllm bench serve \
    --model "Qwen/Qwen3.6-35B-A3B-FP8" \
    --num-prompts 200 \
    --dataset-name 'prefix_repetition' \
    --backend openai \
    --host '127.0.0.1' \
    --port 8000 \
    --max-concurrency 200 \
    --input-len 5000 \
    --output-len 100 \
    --label "$1" \
    --save-result True \
    --save-detailed True \
    --result-dir 'result' \
    --metric-percentiles '50,75,90,99' \
    --plot-timeline True
