#!/bin/bash

if [ $1 == '' ]
    vllm serve "Qwen/Qwen3.6-35B-A3B-FP8" \
      --max-num-seqs 256 \
      --max-num-batched-tokens 32768 \
      --quantization fp8 \
      --kv-cache-dtype fp8_e4m3 \
      --reasoning-parser qwen3 \
      --gpu-memory-utilization 0.92
else
    LMCACHE_CONFIG_FILE=$1
    vllm serve "Qwen/Qwen3.6-35B-A3B-FP8" \
      --max-num-seqs 256 \
      --max-num-batched-tokens 32768 \
      --quantization fp8 \
      --kv-cache-dtype fp8_e4m3 \
      --reasoning-parser qwen3 \
      --gpu-memory-utilization 0.92 \
      --kv-transfer-config '{"kv_connector":"LMCacheConnectorV1", "kv_role":"kv_both"}'
fi
