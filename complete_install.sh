#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/data/qwen38-sglang}"
VENV_DIR="${VENV_DIR:-$BASE_DIR/venv}"
MODEL_DIR="${MODEL_DIR:-$BASE_DIR/models/Qwen3.8-27B-NVFP4}"
DEPLOY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATUS_FILE="$BASE_DIR/run/deployment.status"
DOWNLOAD_LOG="$BASE_DIR/logs/model-download.log"
SMOKE_LOG="$BASE_DIR/logs/smoke-test.json"
DOWNLOAD_BACKEND="${DOWNLOAD_BACKEND:-huggingface}"
HF_MODEL_ID="RadixArk/Qwen3.8-27B-NVFP4"
HF_COMMIT="319f741cce68d7914884900c138a1fbb70a42f30"

mkdir -p "$BASE_DIR/run" "$BASE_DIR/logs" "$MODEL_DIR"

mark_failed() {
  EXIT_CODE=$?
  printf 'failed exit_code=%s time=%s\n' "$EXIT_CODE" "$(date --iso-8601=seconds)" > "$STATUS_FILE"
  exit "$EXIT_CODE"
}
trap mark_failed ERR

if [[ -n "${PROXY_URL:-}" ]]; then
  export http_proxy="$PROXY_URL"
  export https_proxy="$PROXY_URL"
fi

"$DEPLOY_DIR/verify_environment.sh" >> "$DOWNLOAD_LOG" 2>&1

# Keep the compiler used by FlashInfer JIT aligned with PyTorch's CUDA 13.0
# runtime. Do not independently upgrade one member of this set.
"$VENV_DIR/bin/python" -m pip install --no-deps \
  -r "$DEPLOY_DIR/cuda-jit-requirements.txt" >> "$DOWNLOAD_LOG" 2>&1

export MODELSCOPE_DOWNLOAD_PARALLEL_WORKERS="${MODELSCOPE_DOWNLOAD_PARALLEL_WORKERS:-8}"
export MODELSCOPE_DOWNLOAD_PARALLEL_THRESHOLD_MB="${MODELSCOPE_DOWNLOAD_PARALLEL_THRESHOLD_MB:-500}"

MODEL_READY=0
MAX_DOWNLOAD_ATTEMPTS="${MAX_DOWNLOAD_ATTEMPTS:-60}"
for ATTEMPT in $(seq 1 "$MAX_DOWNLOAD_ATTEMPTS"); do
  printf 'downloading backend=%s attempt=%s/%s time=%s\n' \
    "$DOWNLOAD_BACKEND" "$ATTEMPT" "$MAX_DOWNLOAD_ATTEMPTS" "$(date --iso-8601=seconds)" > "$STATUS_FILE"

  if [[ "$DOWNLOAD_BACKEND" == "huggingface" ]]; then
    if ! "$VENV_DIR/bin/hf" download "$HF_MODEL_ID" \
      --revision "$HF_COMMIT" --local-dir "$MODEL_DIR" >> "$DOWNLOAD_LOG" 2>&1; then
      printf 'Hugging Face download failed on attempt %s; retrying\n' "$ATTEMPT" >> "$DOWNLOAD_LOG"
    fi
  elif [[ "$DOWNLOAD_BACKEND" == "modelscope" ]]; then
    if ! "$VENV_DIR/bin/modelscope" download \
      --repo-type model --revision master --local-dir "$MODEL_DIR" --max-workers 1 \
      "$HF_MODEL_ID" >> "$DOWNLOAD_LOG" 2>&1; then
      printf 'ModelScope download failed on attempt %s; retrying\n' "$ATTEMPT" >> "$DOWNLOAD_LOG"
    fi
  else
    echo "Unsupported DOWNLOAD_BACKEND: $DOWNLOAD_BACKEND" >&2
    exit 1
  fi

  if "$DEPLOY_DIR/verify_model.sh" >> "$DOWNLOAD_LOG" 2>&1; then
    MODEL_READY=1
    break
  fi

  printf 'model snapshot incomplete or mismatched on attempt %s; retrying in 30 seconds\n' \
    "$ATTEMPT" >> "$DOWNLOAD_LOG"
  sleep 30
done

if [[ "$MODEL_READY" -ne 1 ]]; then
  echo "Model download or integrity verification did not complete" >&2
  exit 1
fi

cat > "$BASE_DIR/MODEL_SOURCE" <<EOF
model_id=$HF_MODEL_ID
huggingface_commit=$HF_COMMIT
download_backend=$DOWNLOAD_BACKEND
integrity_manifest=$DEPLOY_DIR/model.sha256
EOF

printf 'starting time=%s\n' "$(date --iso-8601=seconds)" > "$STATUS_FILE"
"$DEPLOY_DIR/start_server.sh" >> "$DOWNLOAD_LOG" 2>&1

PORT="${PORT:-30000}"
READY=0
for _ in $(seq 1 180); do
  if "$VENV_DIR/bin/python" -c \
    "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$PORT/v1/models', timeout=2).read()" \
    >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 10
done

if [[ "$READY" -ne 1 ]]; then
  echo "SGLang did not become ready within 30 minutes" >&2
  exit 1
fi

SGLANG_BASE_URL="http://127.0.0.1:$PORT" \
  "$VENV_DIR/bin/python" "$DEPLOY_DIR/acceptance_test.py" --output "$SMOKE_LOG"

trap - ERR
printf 'complete time=%s acceptance_log=%s\n' "$(date --iso-8601=seconds)" "$SMOKE_LOG" > "$STATUS_FILE"
cat "$STATUS_FILE"
