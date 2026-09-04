#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/data/qwen38-sglang}"
VENV_DIR="${VENV_DIR:-$BASE_DIR/venv}"
SOURCE_DIR="${SOURCE_DIR:-$BASE_DIR/source}"
PYTHON_BIN="${PYTHON_BIN:-python3.11}"
DEPLOY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SGLANG_COMMIT="1cf2b8c54d81802abc15dcf23a29b9cc687bc01e"
SGLANG_ARCHIVE_SHA256="dd3bfb47b24ee2e38d4ce882844fff0bf3207b5fd080a92bb0b803b3018f55e8"
SGLANG_ARCHIVE="$BASE_DIR/sglang-$SGLANG_COMMIT.tar.gz"
SGLANG_URL="https://codeload.github.com/sgl-project/sglang/tar.gz/$SGLANG_COMMIT"

for command_name in curl patch readelf sha256sum tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing prerequisite: $command_name" >&2
    exit 1
  fi
done

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python executable not found: $PYTHON_BIN" >&2
  echo "Install Python 3.11 or set PYTHON_BIN to an existing Python 3.11 executable." >&2
  exit 1
fi

PYTHON_VERSION="$($PYTHON_BIN -c 'import platform; print(platform.python_version())')"
PYTHON_SERIES="$($PYTHON_BIN -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$PYTHON_SERIES" != "3.11" ]]; then
  echo "Expected Python 3.11, found $PYTHON_VERSION" >&2
  exit 1
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)"
  echo "Detected GPU: $GPU_NAME"
  if [[ "$GPU_NAME" != *"RTX 5090"* ]]; then
    echo "Warning: this recipe was only validated on an RTX 5090." >&2
  fi
else
  echo "Warning: nvidia-smi is unavailable; GPU and driver checks were skipped." >&2
fi

mkdir -p "$BASE_DIR"

if [[ ! -f "$SGLANG_ARCHIVE" ]]; then
  curl --fail --location --retry 5 --output "$SGLANG_ARCHIVE" "$SGLANG_URL"
fi
printf '%s  %s\n' "$SGLANG_ARCHIVE_SHA256" "$SGLANG_ARCHIVE" | sha256sum --check --strict

if [[ -d "$SOURCE_DIR" ]]; then
  if [[ ! -f "$BASE_DIR/SGLANG_COMMIT" ]]; then
    echo "Existing source has no SGLANG_COMMIT marker: $SOURCE_DIR" >&2
    exit 1
  fi
  RECORDED_COMMIT="$(tr -d '[:space:]' < "$BASE_DIR/SGLANG_COMMIT")"
  if [[ "$RECORDED_COMMIT" != "$SGLANG_COMMIT" ]]; then
    echo "Existing source commit mismatch: expected $SGLANG_COMMIT, got $RECORDED_COMMIT" >&2
    exit 1
  fi
else
  EXTRACT_PARENT="$BASE_DIR/source-extract"
  if [[ -e "$EXTRACT_PARENT" ]]; then
    echo "Refusing to reuse unexpected extraction path: $EXTRACT_PARENT" >&2
    exit 1
  fi
  mkdir "$EXTRACT_PARENT"
  tar -xzf "$SGLANG_ARCHIVE" -C "$EXTRACT_PARENT"
  EXTRACTED_DIR="$EXTRACT_PARENT/sglang-$SGLANG_COMMIT"
  if [[ ! -d "$EXTRACTED_DIR/python" ]]; then
    echo "Unexpected SGLang archive layout" >&2
    exit 1
  fi
  mv "$EXTRACTED_DIR" "$SOURCE_DIR"
  rmdir "$EXTRACT_PARENT"
  printf '%s\n' "$SGLANG_COMMIT" > "$BASE_DIR/SGLANG_COMMIT"
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install \
  "pip==26.2.1" "setuptools==84.0.0" wheel
"$VENV_DIR/bin/python" -m pip install -r "$DEPLOY_DIR/requirements.lock.txt"

# This inference recipe does not use SGLang's optional in-tree Rust extensions.
# The published sglang-kernel wheel remains installed from requirements.lock.txt.
SGLANG_BUILD_RUST_EXTS=none "$VENV_DIR/bin/python" -m pip install \
  --no-deps --editable "$SOURCE_DIR/python"

"$DEPLOY_DIR/apply_sglang_patches.sh"
"$DEPLOY_DIR/verify_environment.sh"

echo "Bootstrap complete. Run ./complete_install.sh to download the model and start the server."
