#!/bin/bash
set -euo pipefail

echo "=== Agent2 Debug ==="

echo -e "\n[1/6] Versiones Python:"
python3 --version || true
/opt/agent2-server/venv/bin/python --version 2>/dev/null || true
/opt/agent2/venv/bin/python --version 2>/dev/null || true

echo -e "\n[2/6] Servicios systemd:"
systemctl is-active agent2-server.service || true
systemctl is-active agent2.service || true
systemctl status --no-pager --lines=20 agent2-server.service || true
systemctl status --no-pager --lines=20 agent2.service || true

echo -e "\n[3/6] Archivos clave:"
ls -l /opt/agent2-server /opt/agent2 || true
echo "--- /opt/agent2-server/.env ---"
[ -f /opt/agent2-server/.env ] && cat /opt/agent2-server/.env || echo "(no existe)"
echo "--- /opt/agent2-server/agents.json ---"
[ -f /opt/agent2-server/agents.json ] && cat /opt/agent2-server/agents.json || echo "(no existe)"
echo "--- /opt/agent2/.env ---"
[ -f /opt/agent2/.env ] && cat /opt/agent2/.env || echo "(no existe)"

echo -e "\n[4/6] Dependencias en venv servidor:"
/opt/agent2-server/venv/bin/pip show fastapi uvicorn websockets pydantic || true

echo -e "\n[5/6] Puertos en escucha:"
ss -ltnp 2>/dev/null | grep -E '(:53123)' || echo "Puerto 53123 no en escucha"

echo -e "\n[6/6] Últimos logs:"
echo "--- agent2-server.service ---"
journalctl -u agent2-server.service -n 80 --no-pager || true
echo "--- agent2.service ---"
journalctl -u agent2.service -n 80 --no-pager || true

echo -e "\n>>> Sugerencia: si el puerto 53123 no está en escucha o el servicio está 'failed', ejecuta ./repair_agent2_server.sh"
