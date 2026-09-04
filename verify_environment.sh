#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/data/qwen38-sglang}"
VENV_DIR="${VENV_DIR:-$BASE_DIR/venv}"
EXPECTED_SGLANG_COMMIT="1cf2b8c54d81802abc15dcf23a29b9cc687bc01e"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "Virtual environment not found: $VENV_DIR" >&2
  exit 1
fi
if [[ ! -f "$BASE_DIR/SGLANG_COMMIT" ]]; then
  echo "Missing $BASE_DIR/SGLANG_COMMIT; run bootstrap.sh first" >&2
  exit 1
fi

RECORDED_SGLANG_COMMIT="$(tr -d '[:space:]' < "$BASE_DIR/SGLANG_COMMIT")"
if [[ "$RECORDED_SGLANG_COMMIT" != "$EXPECTED_SGLANG_COMMIT" ]]; then
  echo "SGLang commit mismatch: expected $EXPECTED_SGLANG_COMMIT, got $RECORDED_SGLANG_COMMIT" >&2
  exit 1
fi

"$VENV_DIR/bin/python" - <<'PY'
from importlib.metadata import version
import platform
import sys

expected = {
    "flashinfer-python": "0.6.17",
    "sglang-kernel": "0.4.6.post1",
    "torch": "2.13.0",
    "transformers": "5.12.1",
}

if sys.version_info[:2] != (3, 11):
    raise SystemExit(f"expected Python 3.11, found {platform.python_version()}")

for package, wanted in expected.items():
    actual = version(package)
    if actual != wanted:
        raise SystemExit(f"{package} mismatch: expected {wanted}, found {actual}")
    print(f"{package}={actual}")

import torch

if torch.version.cuda != "13.0":
    raise SystemExit(f"expected PyTorch CUDA 13.0 runtime, found {torch.version.cuda}")
print(f"python={platform.python_version()}")
print(f"torch_cuda={torch.version.cuda}")
PY

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
fi
