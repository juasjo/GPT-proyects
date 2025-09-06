#!/bin/bash
# Reconfigura ambos servicios en el mismo host.
# Variables que puedes pasar:
#   AGENT_ID, WORKDIR, TOKEN, SERVER_HOST, SERVER_PORT, CORS_ORIGINS
set -euo pipefail

ENV_SRV="/opt/agent2-server/.env"
TOKENS="/opt/agent2-server/agents.json"
ENV_AG="/opt/agent2/.env"

# Cargar actuales si existen
[ -f "$ENV_SRV" ] && . "$ENV_SRV"
[ -f "$ENV_AG" ] && . "$ENV_AG"

SERVER_HOST="${SERVER_HOST:-${SERVER_HOST:-0.0.0.0}}"
SERVER_PORT="${SERVER_PORT:-${SERVER_PORT:-53123}}"
CORS_ORIGINS="${CORS_ORIGINS:-${CORS_ORIGINS:-*}}"
AGENT_ID="${AGENT_ID:-${AGENT_ID:-lxc-gpt-LOCAL}}"
WORKDIR="${WORKDIR:-${WORKDIR:-/root}}"
TOKEN="${TOKEN:-${TOKEN:-}}"

# .env servidor
cat >"$ENV_SRV" <<EOF
SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
CORS_ORIGINS=$CORS_ORIGINS
EOF
chmod 600 "$ENV_SRV"

# agents.json
python3 - "$TOKENS" "$AGENT_ID" "$TOKEN" <<'PY'
import json, sys, os
p, aid, tok = sys.argv[1:]
try: data = json.load(open(p))
except Exception: data = {}
if tok: data[aid] = tok
else:
    if aid not in data: data[aid] = "REPLACE_WITH_TOKEN"
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(data, open(p,"w"), indent=2)
PY
chmod 600 "$TOKENS"

# .env agente
cat >"$ENV_AG" <<EOF
AGENT_ID=$AGENT_ID
SERVER_URL=ws://127.0.0.1:${SERVER_PORT}/ws
TOKEN=$TOKEN
WORKDIR=$WORKDIR
EOF
chmod 600 "$ENV_AG"

systemctl restart agent2-server.service
systemctl restart agent2.service
echo "OK: reconfigurado y reiniciado."
