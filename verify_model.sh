#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/data/qwen38-sglang}"
MODEL_DIR="${MODEL_DIR:-$BASE_DIR/models/Qwen3.8-27B-NVFP4}"
DEPLOY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$MODEL_DIR" ]]; then
  echo "Model directory not found: $MODEL_DIR" >&2
  exit 1
fi

cd "$MODEL_DIR"
sha256sum --check --strict "$DEPLOY_DIR/model.sha256"
