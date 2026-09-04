#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/data/qwen38-sglang}"
VENV_DIR="${VENV_DIR:-$BASE_DIR/venv}"
MODEL_DIR="${MODEL_DIR:-$BASE_DIR/models/Qwen3.8-27B-NVFP4}"
DEPLOY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$DEPLOY_DIR/verify_environment.sh"
"$DEPLOY_DIR/apply_sglang_patches.sh"
"$DEPLOY_DIR/verify_model.sh"

PYTHON_SITE="$($VENV_DIR/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
CUDA_ROOT="$PYTHON_SITE/nvidia/cu13"

if [[ ! -d "$CUDA_ROOT/lib" ]]; then
  echo "CUDA 13 runtime directory not found: $CUDA_ROOT/lib" >&2
  exit 1
fi

# NVIDIA's cu13 wheel uses lib/ and ships only a versioned libcudart. SGLang's
# JIT linker expects lib64/libcudart.so. Without these links it can fall back to
# an older system CUDA runtime and produce 'invalid resource handle'.
if [[ ! -e "$CUDA_ROOT/lib64" ]]; then
  ln -s lib "$CUDA_ROOT/lib64"
fi
if [[ ! -e "$CUDA_ROOT/lib/libcudart.so" ]]; then
  ln -s libcudart.so.13 "$CUDA_ROOT/lib/libcudart.so"
fi

# Preserve JIT artifacts that were linked against CUDA 11 instead of deleting
# them. They are unsafe to reuse even after LD_LIBRARY_PATH is corrected.
STALE_JIT_SO="$(find "$HOME/.cache/sglang/jit" -type f -name '*.so' -print -quit 2>/dev/null || true)"
if [[ -n "$STALE_JIT_SO" ]] \
  && readelf -d "$STALE_JIT_SO" | grep -q 'libcudart.so.11.0'; then
  mkdir -p "$BASE_DIR/cache-backup"
  mv "$HOME/.cache/sglang/jit" \
    "$BASE_DIR/cache-backup/jit-cudart11-$(date +%Y%m%dT%H%M%S)"
fi

export CUDA_HOME="$CUDA_ROOT"
export PATH="$CUDA_ROOT/bin:$VENV_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_ROOT/lib64:$CUDA_ROOT/lib:$PYTHON_SITE/nvidia/cudnn/lib:$PYTHON_SITE/nvidia/nccl/lib:${LD_LIBRARY_PATH:-}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export PYTHONUNBUFFERED=1

# FlashInfer otherwise lets ninja use every CPU. Blackwell FP4 templates are
# memory-heavy; two jobs kept the verified 64 GiB host responsive.
export MAX_JOBS="${MAX_JOBS:-2}"

exec "$VENV_DIR/bin/sglang" serve \
  --trust-remote-code \
  --model-path "$MODEL_DIR" \
  --served-model-name "${SERVED_MODEL_NAME:-Qwen3.8-27B}" \
  --host "${BIND_HOST:-127.0.0.1}" \
  --port "${PORT:-30000}" \
  --context-length "${CONTEXT_LENGTH:-65536}" \
  --kv-cache-dtype fp8_e4m3 \
  --mem-fraction-static "${MEM_FRACTION_STATIC:-0.86}" \
  --attention-backend flashinfer \
  --chunked-prefill-size "${CHUNKED_PREFILL_SIZE:-2048}" \
  --max-running-requests "${MAX_RUNNING_REQUESTS:-1}" \
  --disable-prefill-cuda-graph \
  --cuda-graph-max-bs-decode "${CUDA_GRAPH_MAX_BS_DECODE:-1}" \
  --reasoning-parser qwen3 \
  --tool-call-parser qwen3_coder \
  --mamba-radix-cache-strategy extra_buffer_lazy \
  --mamba-ssm-dtype bfloat16 \
  --max-mamba-cache-size "${MAX_MAMBA_CACHE_SIZE:-4}" \
  "$@"
