#!/bin/bash
# Realinea: .env del agente, tokens en server, deps del venv y reinicia
set -euo pipefail

ENV_AG="/opt/agent2/.env"
ENV_SRV="/opt/agent2-server/.env"
TOK_SRV="/opt/agent2-server/agents.json"
PORT_DEFAULT="53123"

echo "[INFO] Reparando agente local…"

# Cargar envs existentes
[ -f "$ENV_SRV" ] && . "$ENV_SRV"
SERVER_PORT="${SERVER_PORT:-$PORT_DEFAULT}"

# Asegurar venv y deps del agente
python3 -m venv /opt/agent2/venv
/opt/agent2/venv/bin/pip install --upgrade pip >/dev/null
/opt/agent2/venv/bin/pip install websockets >/dev/null

# Crear .env agente si no existe
if [ ! -f "$ENV_AG" ]; then
  echo "[INFO] Creando $ENV_AG por defecto"
  AGENT_ID="${AGENT_ID:-lxc-gpt-LOCAL}"
  TOKEN="$(openssl rand -hex 24)"
  cat >"$ENV_AG" <<EOF
AGENT_ID=$AGENT_ID
SERVER_URL=ws://127.0.0.1:${SERVER_PORT}/ws
TOKEN=$TOKEN
WORKDIR=/root
EOF
  chmod 600 "$ENV_AG"
fi

# Leer valores actuales del agente
. "$ENV_AG"
AGENT_ID="${AGENT_ID:-lxc-gpt-LOCAL}"
SERVER_URL="ws://127.0.0.1:${SERVER_PORT}/ws"   # forzamos loopback/puerto
if [ -z "${TOKEN:-}" ]; then
  TOKEN="$(openssl rand -hex 24)"
fi

# Reescribir .env agente con ajustes correctos
cat >"$ENV_AG" <<EOF
AGENT_ID=$AGENT_ID
SERVER_URL=$SERVER_URL
TOKEN=$TOKEN
WORKDIR=${WORKDIR:-/root}
EOF
chmod 600 "$ENV_AG"

# Alinear token en agents.json del server
mkdir -p /opt/agent2-server
python3 - "$TOK_SRV" "$AGENT_ID" "$TOKEN" <<'PY'
import json, sys, os
p, aid, tok = sys.argv[1:]
try: data = json.load(open(p))
except Exception: data = {}
data[aid] = tok
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(data, open(p,"w"), indent=2)
PY
chmod 600 "$TOK_SRV"

# Reinicios
systemctl restart agent2-server.service
sleep 1
systemctl restart agent2.service

# Verificación rápida
echo "[INFO] Esperando conexión del agente…"
for i in {1..10}; do
  out="$(curl -sS "http://127.0.0.1:${SERVER_PORT}/agents" || true)"
  echo "$out" | grep -q "$AGENT_ID" && { echo "[OK] Agente conectado: $AGENT_ID"; exit 0; }
  sleep 1
done

echo "[WARN] El agente aún no figura como conectado. Revisa logs:"
journalctl -u agent2.service -n 80 --no-pager || true
exit 2
