#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/data/qwen38-sglang}"
VENV_DIR="${VENV_DIR:-$BASE_DIR/venv}"
DEPLOY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$BASE_DIR/run/server.pid"
LOG_FILE="$BASE_DIR/logs/server.log"

mkdir -p "$BASE_DIR/run" "$BASE_DIR/logs"

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(tr -d '[:space:]' < "$PID_FILE")"
  if [[ "$OLD_PID" =~ ^[0-9]+$ ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    if tr '\0' ' ' < "/proc/$OLD_PID/cmdline" | grep -Fq "$VENV_DIR/bin/sglang"; then
      echo "SGLang is already running with PID $OLD_PID"
      exit 0
    fi
    echo "PID file points to an unrelated running process: $OLD_PID" >&2
    exit 1
  fi
  rm -f "$PID_FILE"
fi

nohup "$DEPLOY_DIR/run_server.sh" > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"
echo "Started SGLang with PID $SERVER_PID"
echo "Log: $LOG_FILE"
