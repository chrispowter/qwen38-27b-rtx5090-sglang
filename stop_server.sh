#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/data/qwen38-sglang}"
VENV_DIR="${VENV_DIR:-$BASE_DIR/venv}"
PID_FILE="$BASE_DIR/run/server.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No SGLang PID file found"
  exit 0
fi

SERVER_PID="$(tr -d '[:space:]' < "$PID_FILE")"
if [[ ! "$SERVER_PID" =~ ^[0-9]+$ ]]; then
  echo "Invalid PID file: $PID_FILE" >&2
  exit 1
fi

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  rm -f "$PID_FILE"
  echo "SGLang process is not running; removed stale PID file"
  exit 0
fi

if ! tr '\0' ' ' < "/proc/$SERVER_PID/cmdline" | grep -Fq "$VENV_DIR/bin/sglang"; then
  echo "Refusing to stop unrelated process $SERVER_PID" >&2
  exit 1
fi

kill "$SERVER_PID"
for _ in $(seq 1 30); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "Stopped SGLang"
    exit 0
  fi
  sleep 1
done

echo "SGLang did not stop after 30 seconds; PID $SERVER_PID is still running" >&2
exit 1
