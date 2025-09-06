#!/bin/bash
# Sigue los logs en vivo de server y agente (Ctrl+C para salir)
set -euo pipefail
echo "=== agent2-server.service (tail -f) ==="
journalctl -u agent2-server.service -f -n 20 &
P1=$!
echo "=== agent2.service (tail -f) ==="
journalctl -u agent2.service -f -n 20 &
P2=$!
trap "kill $P1 $P2 2>/dev/null || true" INT TERM
wait
