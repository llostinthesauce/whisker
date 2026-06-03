#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
DEFAULT_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
ROOT="${WHISKER_REMOTE_ROOT:-$DEFAULT_ROOT}"
ENV_FILE="${WHISKER_REMOTE_ENV:-$ROOT/server/.env}"
PYTHON="${WHISKER_REMOTE_PYTHON:-$ROOT/server/.venv/bin/python}"

cd "$ROOT"

if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
fi

if [ ! -x "$PYTHON" ]; then
    echo "Missing Python runtime: $PYTHON" >&2
    echo "Create it with: python3 -m venv server/.venv && server/.venv/bin/python -m pip install -r server/requirements.txt" >&2
    exit 2
fi

exec "$PYTHON" -m uvicorn server.app:app \
    --host "${WHISKER_BIND_HOST:-127.0.0.1}" \
    --port "${WHISKER_PORT:-8787}"
