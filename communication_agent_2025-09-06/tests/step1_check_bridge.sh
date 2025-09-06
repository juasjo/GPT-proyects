#!/bin/bash
set -euo pipefail
echo "== Comprobando servicios locales =="
echo "[1] systemd:"
systemctl is-active agent2-server.service || true
systemctl is-active agent2.service || true
echo
echo "[2] Health del bridge (53124):"
curl -sS http://127.0.0.1:53124/health || echo "(no responde)"
echo
echo "[3] Health del server (53123):"
curl -sS http://127.0.0.1:53123/health || echo "(no responde)"
echo
echo "[4] Agentes conectados:"
curl -sS http://127.0.0.1:53123/agents || echo "(no responde)"
echo
echo "[5] Puertos en escucha:"
ss -ltnp | grep -E '(:53123|:53124)' || echo "no veo 53123/53124"
