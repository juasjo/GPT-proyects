#!/bin/bash
set -euo pipefail

echo "[INFO] Reparando Agent2 Server"

ENV="/opt/agent2-server/.env"
[ -f "$ENV" ] && . "$ENV" || { echo "ERROR: Falta $ENV"; exit 1; }

SERVER_HOST="${SERVER_HOST:-0.0.0.0}"
SERVER_PORT="${SERVER_PORT:-53123}"

echo "[INFO] Config: HOST=$SERVER_HOST PORT=$SERVER_PORT"

# 1) Asegurar venv y deps
python3 -m venv /opt/agent2-server/venv
/opt/agent2-server/venv/bin/pip install --upgrade pip >/dev/null
/opt/agent2-server/venv/bin/pip install fastapi "uvicorn[standard]" pydantic websockets >/dev/null

# 2) Validar que server.py existe
if [ ! -f /opt/agent2-server/server.py ]; then
  echo "ERROR: /opt/agent2-server/server.py no existe"; exit 1
fi

# 3) Probar arranque en primer plano (5s) para capturar errores
echo "[INFO] Test de arranque de uvicorn (5s, primer plano)"
set +e
timeout 5s /opt/agent2-server/venv/bin/uvicorn server:app \
  --host "${SERVER_HOST}" --port "${SERVER_PORT}" \
  --app-dir /opt/agent2-server >/tmp/agent2_uvicorn_test.out 2>/tmp/agent2_uvicorn_test.err
RC=$?
set -e
echo "[INFO] uvicorn test RC=$RC (0 o 124 suele ser OK para este smoke test)"
echo "------ stdout ------"; tail -n +1 /tmp/agent2_uvicorn_test.out || true
echo "------ stderr ------"; tail -n +1 /tmp/agent2_uvicorn_test.err || true

# 4) Reiniciar servicio y verificar
echo "[INFO] Reiniciando servicio systemd"
systemctl daemon-reload
systemctl restart agent2-server.service
sleep 2
systemctl status --no-pager --lines=30 agent2-server.service || true

echo "[INFO] Comprobando puerto 53123"
if ss -ltnp | grep -q ":${SERVER_PORT}"; then
  echo "[OK] Puerto ${SERVER_PORT} en escucha"
else
  echo "[WARN] Puerto ${SERVER_PORT} no en escucha. Revisa logs:"
  journalctl -u agent2-server.service -n 100 --no-pager || true
  exit 2
fi

echo "[INFO] Probando /health (localhost)"
set +e
curl -sS "http://127.0.0.1:${SERVER_PORT}/health" || true
echo
set -e

echo "[DONE] Reparación completada."
