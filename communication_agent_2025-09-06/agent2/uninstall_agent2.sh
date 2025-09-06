#!/bin/bash
# Desinstalador Agente 2.0
set -euo pipefail

echo "[INFO] Deteniendo servicio agent2..."
systemctl stop agent2.service 2>/dev/null || true

echo "[INFO] Deshabilitando servicio..."
systemctl disable agent2.service 2>/dev/null || true

echo "[INFO] Eliminando unidad systemd..."
rm -f /etc/systemd/system/agent2.service
systemctl daemon-reload

echo "[INFO] Eliminando directorios del agente..."
rm -rf /opt/agent2
rm -rf /var/lib/agent2

echo "[INFO] Limpieza completada."
