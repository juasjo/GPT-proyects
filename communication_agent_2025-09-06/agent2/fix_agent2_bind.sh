#!/bin/bash
# Corrige el bind del Agent2 Server a 0.0.0.0 y verifica /health
set -euo pipefail

ENV="/opt/agent2-server/.env"
SERVICE="agent2-server.service"
PORT_DEFAULT="53123"

if [ ! -f "$ENV" ]; then
  echo "ERROR: No existe $ENV. ¿Instalaste el servidor?" >&2
  exit 1
fi

# Cargar valores actuales
. "$ENV"

SERVER_HOST="${SERVER_HOST:-0.0.0.0}"
SERVER_PORT="${SERVER_PORT:-$PORT_DEFAULT}"
CORS_ORIGINS="${CORS_ORIGINS:-*}"

echo "[INFO] Valores actuales: HOST=$SERVER_HOST PORT=$SERVER_PORT CORS=$CORS_ORIGINS"
if [[ "$SERVER_HOST" != "0.0.0.0" && "$SERVER_HOST" != "127.0.0.1" ]]; then
  echo "[INFO] Ajustando SERVER_HOST -> 0.0.0.0"
  SERVER_HOST="0.0.0.0"
fi

# Reescribir .env de forma segura
cat > "$ENV" <<EOF
SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
CORS_ORIGINS=$CORS_ORIGINS
EOF
chmod 600 "$ENV"

# Reiniciar servicio
echo "[INFO] Reiniciando $SERVICE ..."
systemctl daemon-reload
systemctl restart "$SERVICE"

# Esperar a que escuche en el puerto
echo "[INFO] Comprobando puerto $SERVER_PORT ..."
for i in {1..10}; do
  if ss -ltnp 2>/dev/null | grep -q ":${SERVER_PORT}"; then
    echo "[OK] Puerto ${SERVER_PORT} en escucha"
    break
  fi
  sleep 1
  if [ $i -eq 10 ]; then
    echo "[WARN] No veo el puerto en escucha. Logs:"
    journalctl -u "$SERVICE" -n 100 --no-pager || true
    exit 2
  fi
done

# Probar /health
echo "[INFO] Probando /health ..."
set +e
OUT="$(curl -sS "http://127.0.0.1:${SERVER_PORT}/health")"
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "[WARN] /health no responde por HTTP local. Logs recientes:"
  journalctl -u "$SERVICE" -n 60 --no-pager || true
  exit 3
fi

echo "[OK] /health respondió:"
echo "$OUT"

echo
echo ">>> Si aparece vacío 'agents_connected', el agente local tardará unos segundos en reconectar."
echo ">>> Para comprobar el agente local:  journalctl -u agent2.service -n 40 --no-pager"
