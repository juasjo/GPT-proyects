#!/bin/bash
# Instala un Bridge HTTP para simplificar las llamadas desde un agente GPT
# Expone POST /agent/run -> {agent_id, op, args} -> resultado
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Config por defecto (puedes cambiar antes de ejecutar o luego en /opt/agent2-bridge/.env)
BRIDGE_HOST="${BRIDGE_HOST:-0.0.0.0}"
BRIDGE_PORT="${BRIDGE_PORT:-53124}"
SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-53123}"
DEFAULT_AGENT_ID="${DEFAULT_AGENT_ID:-Lxc-gpt-LOCAL}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"

echo "[INFO] Instalando Agent2 Bridge en :${BRIDGE_PORT} -> server http://${SERVER_HOST}:${SERVER_PORT}"

apt-get update -y
apt-get install -y python3 python3-venv ca-certificates

install -d -m 755 /opt/agent2-bridge
cat >/opt/agent2-bridge/.env <<EOF
BRIDGE_HOST=$BRIDGE_HOST
BRIDGE_PORT=$BRIDGE_PORT
SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
DEFAULT_AGENT_ID=$DEFAULT_AGENT_ID
TIMEOUT_SECONDS=$TIMEOUT_SECONDS
EOF
chmod 600 /opt/agent2-bridge/.env

python3 -m venv /opt/agent2-bridge/venv
/opt/agent2-bridge/venv/bin/pip install --upgrade pip >/dev/null
/opt/agent2-bridge/venv/bin/pip install fastapi "uvicorn[standard]" httpx >/dev/null

cat >/opt/agent2-bridge/bridge.py <<'PY'
import os, time, json, asyncio
from typing import Any, Dict, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx

BRIDGE_HOST = os.environ.get("BRIDGE_HOST","0.0.0.0")
BRIDGE_PORT = int(os.environ.get("BRIDGE_PORT","53124"))
SERVER_HOST = os.environ.get("SERVER_HOST","127.0.0.1")
SERVER_PORT = int(os.environ.get("SERVER_PORT","53123"))
DEFAULT_AGENT_ID = os.environ.get("DEFAULT_AGENT_ID","Lxc-gpt-LOCAL")
TIMEOUT_SECONDS = int(os.environ.get("TIMEOUT_SECONDS","60"))

BASE = f"http://{SERVER_HOST}:{SERVER_PORT}"

class RunReq(BaseModel):
    agent_id: Optional[str] = None
    op: str
    args: Dict[str, Any] = {}

app = FastAPI(title="Agent2 Bridge")

@app.get("/health")
async def health():
    async with httpx.AsyncClient(timeout=10.0) as cli:
        try:
            r = await cli.get(f"{BASE}/health")
            return {"ok": True, "bridge": {"host": BRIDGE_HOST, "port": BRIDGE_PORT}, "server": r.json()}
        except Exception as e:
            return {"ok": False, "error": str(e)}

@app.post("/agent/run")
async def agent_run(req: RunReq):
    agent_id = req.agent_id or DEFAULT_AGENT_ID
    payload = {"agent_id": agent_id, "op": req.op, "args": req.args}

    async with httpx.AsyncClient(timeout=10.0) as cli:
        # 1) issue
        try:
            ir = await cli.post(f"{BASE}/issue", json=payload)
            if ir.status_code != 200:
                raise HTTPException(ir.status_code, f"issue failed: {ir.text}")
            cmd_id = ir.json().get("cmd_id")
            if not cmd_id:
                raise HTTPException(500, f"no cmd_id in issue response: {ir.text}")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(500, f"issue exception: {e}")

        # 2) poll result
        deadline = time.time() + TIMEOUT_SECONDS
        last_err = None
        while time.time() < deadline:
            try:
                rr = await cli.get(f"{BASE}/result/{agent_id}/{cmd_id}")
                if rr.status_code == 200:
                    return rr.json()
                # 404 "Sin resultados" -> aún no listo
                await asyncio.sleep(1.0)
            except Exception as e:
                last_err = e
                await asyncio.sleep(1.0)
        raise HTTPException(504, f"timeout waiting result ({TIMEOUT_SECONDS}s). last_err={last_err}")
PY
chmod 755 /opt/agent2-bridge/bridge.py

cat >/etc/systemd/system/agent2-bridge.service <<'UNIT'
[Unit]
Description=Agent2 Bridge (HTTP facade for /issue + /result)
After=network.target

[Service]
User=root
EnvironmentFile=/opt/agent2-bridge/.env
WorkingDirectory=/opt/agent2-bridge
ExecStart=/opt/agent2-bridge/venv/bin/uvicorn bridge:app --host ${BRIDGE_HOST} --port ${BRIDGE_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now agent2-bridge.service

echo
echo "=== Bridge instalado ==="
echo "  HEALTH:  curl http://127.0.0.1:${BRIDGE_PORT}/health"
echo "  RUN:     curl -X POST http://127.0.0.1:${BRIDGE_PORT}/agent/run -H 'Content-Type: application/json' \\"
echo "           -d '{\"op\":\"shell\",\"args\":{\"cmd\":\"uname -a\"}}'"
