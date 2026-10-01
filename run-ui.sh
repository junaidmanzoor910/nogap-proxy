#!/usr/bin/env bash
# run-ui.sh: Starts the NoGap Proxy Command Center UI on http://127.0.0.1:3130
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="${SCRIPT_DIR}/ui"
PORT="${UI_PORT:-3130}"

# Ensure local forwarder is running
if ! pgrep -f "squid.*nogapfwd" >/dev/null 2>&1; then
  echo "⚡ Local forwarder is not running. Starting forwarder first..."
  "${SCRIPT_DIR}/scripts/start-local-forwarder.sh" || true
fi

echo "=========================================================="
echo "⚡ NOGAP PROXY COMMAND CENTER"
echo "👉 Opening Dashboard at: http://127.0.0.1:${PORT}"
echo "=========================================================="

# Check if port is already running
if ss -tulpn | grep -q ":${PORT} "; then
  echo "UI server is already running on port ${PORT}."
  exit 0
fi

# Try to open in browser if DISPLAY is set
if command -v xdg-open >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  (sleep 1 && xdg-open "http://127.0.0.1:${PORT}") >/dev/null 2>&1 &
fi

exec node "${UI_DIR}/server.js"
