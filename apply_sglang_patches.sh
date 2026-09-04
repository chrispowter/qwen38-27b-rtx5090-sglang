#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/data/qwen38-sglang}"
SOURCE_DIR="${SOURCE_DIR:-$BASE_DIR/source}"
DEPLOY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$DEPLOY_DIR/patches/sglang-sm120-fp8-bmm.patch"

if patch --dry-run --reverse --silent -d "$SOURCE_DIR" -p1 < "$PATCH_FILE" \
  >/dev/null 2>&1; then
  echo "SGLang SM120 FP8 BMM patch already applied"
elif patch --dry-run --silent -d "$SOURCE_DIR" -p1 < "$PATCH_FILE"; then
  patch --silent -d "$SOURCE_DIR" -p1 < "$PATCH_FILE"
  echo "Applied SGLang SM120 FP8 BMM patch"
else
  echo "SGLang source is incompatible with $PATCH_FILE" >&2
  exit 1
fi
