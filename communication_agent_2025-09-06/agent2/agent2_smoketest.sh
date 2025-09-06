#!/bin/bash
# Lanza un 'uname -a' al agente local y recupera el resultado
set -euo pipefail

ENV_SRV="/opt/agent2-server/.env"
ENV_AG="/opt/agent2/.env"
[ -f "$ENV_SRV" ] && . "$ENV_SRV" || { echo "Falta $ENV_SRV"; exit 1; }
[ -f "$ENV_AG" ] && . "$ENV_AG" || { echo "Falta $ENV_AG"; exit 1; }

PORT="${SERVER_PORT:-53123}"
AGENT="${AGENT_ID:-lxc-gpt-LOCAL}"

echo "[INFO] Emisión de comando a $AGENT"
/usr/bin/curl -sS -X POST "http://127.0.0.1:${PORT}/issue" \
  -H 'Content-Type: application/json' \
  -d "{\"agent_id\":\"$AGENT\",\"op\":\"shell\",\"args\":{\"cmd\":\"uname -a && id\"}}" > /tmp/agent2_cmd.json

CMD_ID="$(python3 - <<'PY'
import json,sys
print(json.load(open("/tmp/agent2_cmd.json")).get("cmd_id",""))
PY
)"
if [ -z "$CMD_ID" ]; then
  echo "ERROR: no se obtuvo cmd_id"; cat /tmp/agent2_cmd.json; exit 2
fi
echo "[INFO] cmd_id=$CMD_ID"

echo "[INFO] Polling de resultado…"
for i in {1..15}; do
  if curl -sS "http://127.0.0.1:${PORT}/result/${AGENT}/${CMD_ID}" -o /tmp/agent2_result.json; then
    echo "[OK] Resultado:"
    cat /tmp/agent2_result.json
    echo
    exit 0
  fi
  sleep 1
done

echo "[WARN] No se recibió resultado a tiempo."
exit 3
