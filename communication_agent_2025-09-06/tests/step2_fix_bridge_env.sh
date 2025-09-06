#!/bin/bash
set -euo pipefail

ENV="/opt/agent2-bridge/.env"
SERVICE="agent2-bridge.service"

echo "== Bridge ENV antes =="
[ -f "$ENV" ] && cat "$ENV" || echo "(no existe $ENV)"

echo
echo "== Ajustando SERVER_HOST a 127.0.0.1 y SERVER_PORT a 53123 =="

# Cargar valores actuales si existen
if [ -f "$ENV" ]; then . "$ENV"; fi

BRIDGE_HOST="${BRIDGE_HOST:-0.0.0.0}"
BRIDGE_PORT="${BRIDGE_PORT:-53124}"
SERVER_HOST="127.0.0.1"
SERVER_PORT="53123"
DEFAULT_AGENT_ID="${DEFAULT_AGENT_ID:-Lxc-gpt-LOCAL}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"

cat >"$ENV" <<EOF
BRIDGE_HOST=$BRIDGE_HOST
BRIDGE_PORT=$BRIDGE_PORT
SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
DEFAULT_AGENT_ID=$DEFAULT_AGENT_ID
TIMEOUT_SECONDS=$TIMEOUT_SECONDS
EOF
chmod 600 "$ENV"

echo
echo "== Bridge ENV después =="
cat "$ENV"

echo
echo "== Reiniciando servicio =="
systemctl daemon-reload
systemctl restart "$SERVICE"
sleep 1
systemctl is-active "$SERVICE" || true

echo
echo "== Probar /health del bridge =="
curl -sS http://127.0.0.1:${BRIDGE_PORT}/health || echo "(no responde)"

echo
echo "== Probar /agent/run list_dir =="
curl -sS -X POST "http://127.0.0.1:${BRIDGE_PORT}/agent/run" \
  -H 'Content-Type: application/json' \
  -d '{"op":"list_dir","args":{"path":"/root"} }' || true
echo
