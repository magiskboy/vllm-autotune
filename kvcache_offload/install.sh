#!/bin/bash

VLLM_VERSION=0.18.0
LMCACHE_VERSION=0.4.2

uv pip install "vllm[bench]==${VLLM_VERSION}" --torch-backend=auto

uv pip install lmcache==${LMCACHE_VERSION} \
    --extra-index-url https://download.pytorch.org/whl/cu130 \
    --find-links https://github.com/LMCache/LMCache/releases/expanded_assets/v${LMCACHE_VERSION}-cu13 \
    --index-strategy unsafe-best-match
