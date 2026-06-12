#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/Backend/OrionProxyServer"
ENV_FILE="$BACKEND_DIR/.env"
PORT_VALUE="${PORT:-8788}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[PulsarOrionBackend] Missing $ENV_FILE"
  echo "[PulsarOrionBackend] Copy Backend/OrionProxyServer/.env.example to .env and set OPENAI_API_KEY."
  exit 1
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi

echo "[PulsarOrionBackend] Starting local Orion OpenAI proxy"
echo "[PulsarOrionBackend] Simulator backend URL: http://127.0.0.1:${PORT_VALUE}"
if [[ -n "$LAN_IP" ]]; then
  echo "[PulsarOrionBackend] Physical iPhone backend URL: http://${LAN_IP}:${PORT_VALUE}"
else
  echo "[PulsarOrionBackend] Physical iPhone backend URL: run 'ipconfig getifaddr en0' and use http://<MAC_LOCAL_IP>:${PORT_VALUE}"
fi
echo "[PulsarOrionBackend] Health check: curl http://127.0.0.1:${PORT_VALUE}/health"

cd "$BACKEND_DIR"
exec npm start
