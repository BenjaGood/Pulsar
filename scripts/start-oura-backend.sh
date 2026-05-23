#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/Backend/OuraOAuthServer"
ENV_FILE="$BACKEND_DIR/.env"
PORT_VALUE="${PORT:-8787}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[PulsarOuraBackend] Missing $ENV_FILE"
  echo "[PulsarOuraBackend] Copy Backend/OuraOAuthServer/.env.example to .env and set OURA_CLIENT_ID, OURA_CLIENT_SECRET, and OURA_REDIRECT_URI."
  exit 1
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi

echo "[PulsarOuraBackend] Starting local Oura token exchange backend"
echo "[PulsarOuraBackend] Simulator backend URL: http://127.0.0.1:${PORT_VALUE}"
if [[ -n "$LAN_IP" ]]; then
  echo "[PulsarOuraBackend] Physical iPhone backend URL: http://${LAN_IP}:${PORT_VALUE}"
else
  echo "[PulsarOuraBackend] Physical iPhone backend URL: run 'ipconfig getifaddr en0' and use http://<MAC_LOCAL_IP>:${PORT_VALUE}"
fi
echo "[PulsarOuraBackend] Health check: curl http://127.0.0.1:${PORT_VALUE}/health"

cd "$BACKEND_DIR"
exec npm start
