#!/bin/bash
set -euo pipefail

echo "=== Debug Agente local ==="
ENV_AG="/opt/agent2/.env"
ENV_SRV="/opt/agent2-server/.env"
TOK_SRV="/opt/agent2-server/agents.json"

echo -e "\n[1/6] Servicios:"
systemctl is-active agent2.service || true
systemctl status --no-pager --lines=20 agent2.service || true

echo -e "\n[2/6] Entornos:"
echo "--- $ENV_AG ---"; [ -f "$ENV_AG" ] && cat "$ENV_AG" || echo "(no existe)"
echo "--- $ENV_SRV ---"; [ -f "$ENV_SRV" ] && cat "$ENV_SRV" || echo "(no existe)"
echo "--- $TOK_SRV ---"; [ -f "$TOK_SRV" ] && cat "$TOK_SRV" || echo "(no existe)"

echo -e "\n[3/6] Python venv:"
/opt/agent2/venv/bin/python --version 2>/dev/null || echo "venv agente no disponible"
/opt/agent2/venv/bin/pip show websockets 2>/dev/null || echo "websockets no instalado en venv"

echo -e "\n[4/6] Logs recientes del agente:"
journalctl -u agent2.service -n 60 --no-pager || true

echo -e "\n[5/6] Comprobación de URL WS y token:"
if [ -f "$ENV_AG" ]; then
  . "$ENV_AG"
  echo "AGENT_ID=${AGENT_ID:-}"
  echo "SERVER_URL=${SERVER_URL:-}"
  echo "TOKEN (len)=${#TOKEN:-0}"
fi

echo -e "\n[6/6] Agentes conectados en el server:"
. "$ENV_SRV" 2>/dev/null || true
PORT="${SERVER_PORT:-53123}"
curl -sS "http://127.0.0.1:${PORT}/agents" || true

echo -e "\n>>> Si no conecta, ejecuta: ./repair_agent2_local.sh"
