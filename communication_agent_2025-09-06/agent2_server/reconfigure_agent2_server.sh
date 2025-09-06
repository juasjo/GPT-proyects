#!/bin/bash
# Reconfigurador del servidor Agent2
# Puedes pasar variables:
#   SERVER_HOST, SERVER_PORT, CORS_ORIGINS
#   AGENT_ID, TOKEN   (para añadir/actualizar en agents.json)
set -euo pipefail

ENV_FILE="/opt/agent2-server/.env"
TOK_FILE="/opt/agent2-server/agents.json"

install -d -m 755 /opt/agent2-server

# Cargar actuales
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

SERVER_HOST="${SERVER_HOST:-${SERVER_HOST:-0.0.0.0}}"
SERVER_PORT="${SERVER_PORT:-${SERVER_PORT:-53123}}"
CORS_ORIGINS="${CORS_ORIGINS:-${CORS_ORIGINS:-*}}"

cat >"$ENV_FILE" <<EOF
SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
CORS_ORIGINS=$CORS_ORIGINS
EOF
chmod 600 "$ENV_FILE"

# Tokens
if [ -n "${AGENT_ID:-}" ] && [ -n "${TOKEN:-}" ]; then
  tmp="$(mktemp)"
  if [ -f "$TOK_FILE" ]; then
    python3 - "$TOK_FILE" "$AGENT_ID" "$TOKEN" > "$tmp" <<'PY'
import json, sys
p, aid, tok = sys.argv[1:]
try:
    data = json.load(open(p))
except Exception:
    data = {}
data[aid] = tok
json.dump(data, open(p, "w"), indent=2)
print(open(p).read())
PY
  else
    echo "{\"$AGENT_ID\":\"$TOKEN\"}" > "$TOK_FILE"
  fi
  chmod 600 "$TOK_FILE"
fi

systemctl restart agent2-server.service
echo "OK: servidor reconfigurado y reiniciado."
