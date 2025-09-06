#!/bin/bash
# E2E verbose: emite list_dir y shell, espera resultado con reintentos y enseña logs si falla
set -euo pipefail

ENV_SRV="/opt/agent2-server/.env"
ENV_AG="/opt/agent2/.env"
[ -f "$ENV_SRV" ] && . "$ENV_SRV" || { echo "Falta $ENV_SRV"; exit 1; }
[ -f "$ENV_AG" ] && . "$ENV_AG" || { echo "Falta $ENV_AG"; exit 1; }

PORT="${SERVER_PORT:-53123}"
AGENT="${AGENT_ID:-lxc-gpt-02}"

emit_and_wait () {
  local OP="$1"
  local PAYLOAD="$2"
  local LABEL="$3"

  echo
  echo "=== Emitiendo ${LABEL} (${OP}) a ${AGENT} ==="
  /usr/bin/curl -sS -X POST "http://127.0.0.1:${PORT}/issue" \
    -H 'Content-Type: application/json' \
    -d "{\"agent_id\":\"$AGENT\",\"op\":\"$OP\",\"args\":${PAYLOAD}}" > /tmp/agent2_cmd.json

  CMD_ID="$(python3 - <<'PY'
import json,sys
print(json.load(open("/tmp/agent2_cmd.json")).get("cmd_id",""))
PY
)"
  if [ -z "$CMD_ID" ]; then
    echo "ERROR: no se obtuvo cmd_id"; cat /tmp/agent2_cmd.json; return 2
  fi
  echo "[INFO] cmd_id=$CMD_ID"

  echo "[INFO] Esperando resultado (hasta 60s)…"
  for i in {1..60}; do
    HTTP=$(/usr/bin/curl -sS -o /tmp/agent2_result.json -w "%{http_code}" "http://127.0.0.1:${PORT}/result/${AGENT}/${CMD_ID}" || true)
    if [ "$HTTP" = "200" ]; then
      echo "[OK] Resultado ${LABEL}:"
      cat /tmp/agent2_result.json
      echo
      return 0
    fi
    sleep 1
  done

  echo "[WARN] No se recibió resultado de ${LABEL} a tiempo."
  return 3
}

# Comprobar conectados
echo "[INFO] Agentes conectados:"
/usr/bin/curl -sS "http://127.0.0.1:${PORT}/agents" || true
echo

# 1) list_dir (rápido y seguro)
emit_and_wait "list_dir" "{\"path\":\"/root\"}" "LIST_DIR" || FAIL1=$? || true

# 2) shell básico
emit_and_wait "shell" "{\"cmd\":\"uname -a && id\",\"timeout\":30}" "SHELL_TEST" || FAIL2=$? || true

if [ "${FAIL1:-0}" -eq 0 ] || [ "${FAIL2:-0}" -eq 0 ]; then
  echo "[DONE] Al menos una operación devolvió resultado correctamente."
  exit 0
fi

echo
echo "========== DIAGNÓSTICO =========="
echo "--- Últimos logs del servidor ---"
journalctl -u agent2-server.service -n 80 --no-pager || true
echo "--- Últimos logs del agente ---"
journalctl -u agent2.service -n 80 --no-pager || true
echo "================================="
exit 4
