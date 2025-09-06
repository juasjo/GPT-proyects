#!/bin/bash
# Actualiza /opt/agent2/.env y reinicia el servicio
set -euo pipefail
install -d -m 755 /opt/agent2

# Tomar valores existentes si no se pasan nuevos
if [ -f /opt/agent2/.env ]; then
  # shellcheck disable=SC1091
  source /opt/agent2/.env
fi

AGENT_ID="${AGENT_ID:-${AGENT_ID:-lxc-gpt-02}}"
SERVER_URL="${SERVER_URL:-${SERVER_URL:-ws://gpt.juasjo.com:53123/ws}}"
TOKEN="${TOKEN:-${TOKEN:-}}"
WORKDIR="${WORKDIR:-${WORKDIR:-/root}}"

if [ -z "$TOKEN" ]; then
  echo "ERROR: TOKEN requerido (define TOKEN en entorno o ya existente en .env)" >&2
  exit 1
fi

cat >/opt/agent2/.env <<EOF
AGENT_ID=$AGENT_ID
SERVER_URL=$SERVER_URL
TOKEN=$TOKEN
WORKDIR=$WORKDIR
EOF
chmod 600 /opt/agent2/.env

systemctl restart agent2.service
echo "OK: reconfigurado y reiniciado."

