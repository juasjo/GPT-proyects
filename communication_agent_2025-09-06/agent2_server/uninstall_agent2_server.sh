#!/bin/bash
# Desinstalador del servidor Agent2 (FastAPI + WebSocket)
set -euo pipefail

systemctl stop agent2-server.service 2>/dev/null || true
systemctl disable agent2-server.service 2>/dev/null || true
rm -f /etc/systemd/system/agent2-server.service
systemctl daemon-reload

rm -rf /opt/agent2-server
rm -rf /var/lib/agent2-server

echo "[INFO] Servidor Agent2 eliminado."
