#!/bin/bash
set -euo pipefail
systemctl stop agent2.service 2>/dev/null || true
systemctl stop agent2-server.service 2>/dev/null || true
systemctl disable agent2.service 2>/dev/null || true
systemctl disable agent2-server.service 2>/dev/null || true
rm -f /etc/systemd/system/agent2.service
rm -f /etc/systemd/system/agent2-server.service
systemctl daemon-reload
rm -rf /opt/agent2 /opt/agent2-server /var/lib/agent2 /var/lib/agent2-server
echo "[INFO] Todo desinstalado."
