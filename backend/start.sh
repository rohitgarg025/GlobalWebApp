#!/bin/bash
# Start the FastAPI backend server
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d ".venv" ]; then
  echo "Setting up Python virtual environment..."
  python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
fi

echo "Starting backend on http://127.0.0.1:8765"
.venv/bin/uvicorn app.main_api:app --host 127.0.0.1 --port 8765 --reload
