#!/bin/bash
# Agente 2.0 — Servidor (FastAPI+WebSocket) instalador con venv + systemd
# -----------------------------------------------------------------------
# Variables opcionales antes de ejecutar:
#   SERVER_HOST   (default: 0.0.0.0)
#   SERVER_PORT   (default: 53123)
#   CORS_ORIGINS  (default: *)
#   SEED_AGENT_ID y SEED_TOKEN  (para precargar un agente en agents.json)
#
# Persistencia de configuración:
#   - /opt/agent2-server/.env
#   - /opt/agent2-server/agents.json   (mapa agent_id -> token)

set -euo pipefail

SERVER_HOST="${SERVER_HOST:-0.0.0.0}"
SERVER_PORT="${SERVER_PORT:-53123}"
CORS_ORIGINS="${CORS_ORIGINS:-*}"
SEED_AGENT_ID="${SEED_AGENT_ID:-}"
SEED_TOKEN="${SEED_TOKEN:-}"

echo "[INFO] Instalando servidor del Agente 2.0"
echo "[INFO] HOST=$SERVER_HOST PORT=$SERVER_PORT CORS=$CORS_ORIGINS"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-venv ca-certificates

install -d -m 755 /opt/agent2-server
install -d -m 755 /var/lib/agent2-server

# --- .env persistente ---
cat >/opt/agent2-server/.env <<EOF
SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
CORS_ORIGINS=$CORS_ORIGINS
EOF
chmod 600 /opt/agent2-server/.env

# --- agents.json inicial ---
if [ -n "$SEED_AGENT_ID" ] && [ -n "$SEED_TOKEN" ]; then
  cat >/opt/agent2-server/agents.json <<EOF
{
  "$SEED_AGENT_ID": "$SEED_TOKEN"
}
EOF
else
  cat >/opt/agent2-server/agents.json <<'EOF'
{
  "example-agent-id": "REPLACE_WITH_TOKEN"
}
EOF
fi
chmod 600 /opt/agent2-server/agents.json

# --- venv + deps ---
python3 -m venv /opt/agent2-server/venv
/opt/agent2-server/venv/bin/pip install --upgrade pip >/dev/null
/opt/agent2-server/venv/bin/pip install fastapi "uvicorn[standard]" pydantic websockets >/dev/null

# --- Código del servidor ---
cat >/opt/agent2-server/server.py <<'PY'
import json, time, uuid, asyncio
from typing import Dict, Any
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# --- Config ---
import os
SERVER_HOST = os.environ.get("SERVER_HOST", "0.0.0.0")
SERVER_PORT = int(os.environ.get("SERVER_PORT", "53123"))
CORS_ORIGINS = os.environ.get("CORS_ORIGINS", "*")

DATA_DIR = Path("/opt/agent2-server")
AGENTS_FILE = DATA_DIR / "agents.json"   # agent_id -> token

def load_tokens() -> Dict[str, str]:
    try:
        return json.loads(AGENTS_FILE.read_text())
    except Exception:
        return {}

TOKENS = load_tokens()

app = FastAPI(title="Agent2 Server")

# --- CORS ---
allow_origins = ["*"] if CORS_ORIGINS.strip() == "*" else [o.strip() for o in CORS_ORIGINS.split(",")]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_credentials=True,
)

# --- Estado en memoria ---
peers: Dict[str, WebSocket] = {}
queues: Dict[str, asyncio.Queue] = {}
results: Dict[str, Dict[str, Any]] = {}  # results[agent_id][cmd_id] -> last payload

class IssueCommand(BaseModel):
    agent_id: str
    op: str
    args: Dict[str, Any] = {}

@app.get("/health")
def health():
    return {"ok": True, "agents_connected": list(peers.keys())}

@app.get("/agents")
def agents():
    return {"connected": list(peers.keys())}

@app.post("/issue")
async def issue_command(req: IssueCommand):
    aid = req.agent_id
    if aid not in queues or aid not in peers:
        raise HTTPException(404, "Agente no conectado")
    cmd_id = str(uuid.uuid4())
    msg = {
        "type":"command",
        "agent_id":"server",
        "seq":0,
        "msg_id":str(uuid.uuid4()),
        "timestamp":int(time.time()),
        "payload":{
            "cmd_id":cmd_id,
            "op":req.op,
            "args":req.args
        }
    }
    await queues[aid].put(msg)
    return {"cmd_id": cmd_id, "status":"sent"}

@app.get("/result/{agent_id}/{cmd_id}")
def get_result(agent_id: str, cmd_id: str):
    r = results.get(agent_id, {}).get(cmd_id)
    if not r:
        raise HTTPException(404, "Sin resultados")
    return r

@app.post("/reload_tokens")
def reload_tokens(body: Dict[str, Any] = Body(...)):
    # Permite reemplazar tokens desde un cuerpo JSON {agent_id: token, ...}
    global TOKENS
    TOKENS = {**TOKENS, **{k:str(v) for k, v in body.items()}}
    AGENTS_FILE.write_text(json.dumps(TOKENS, indent=2))
    return {"ok": True, "count": len(TOKENS)}

@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    agent_id = None
    try:
        # Primer mensaje debe ser handshake
        data = await ws.receive_json()
        if data.get("type") != "handshake":
            await ws.close(code=4000)
            return
        agent_id = data.get("agent_id")
        token = (data.get("payload") or {}).get("token")
        if not agent_id or not token:
            await ws.close(code=4001)
            return
        if TOKENS.get(agent_id) != token:
            await ws.close(code=4003)  # auth fail
            return

        # Registrar
        peers[agent_id] = ws
        queues.setdefault(agent_id, asyncio.Queue())
        results.setdefault(agent_id, {})

        # ACK handshake
        await ws.send_json({"type":"ack","reply_to":data.get("msg_id"),"agent_id":"server","seq":0,"timestamp":int(time.time())})

        async def sender():
            while True:
                msg = await queues[agent_id].get()
                await ws.send_json(msg)

        send_task = asyncio.create_task(sender())

        while True:
            obj = await ws.receive_json()
            t = obj.get("type")
            if t == "result":
                payload = obj.get("payload") or {}
                cmd_id = payload.get("cmd_id")
                if cmd_id:
                    results.setdefault(agent_id, {})[cmd_id] = payload
            # ACK genérico
            await ws.send_json({"type":"ack","reply_to":obj.get("msg_id"),"agent_id":"server","seq":0,"timestamp":int(time.time())})

    except WebSocketDisconnect:
        pass
    finally:
        try:
            if agent_id and peers.get(agent_id) is ws:
                del peers[agent_id]
        except Exception:
            pass
PY
chmod 755 /opt/agent2-server/server.py

# --- Servicio systemd ---
cat >/etc/systemd/system/agent2-server.service <<'UNIT'
[Unit]
Description=Agent2 Control-Plane (FastAPI + WebSocket)
After=network.target

[Service]
User=root
EnvironmentFile=/opt/agent2-server/.env
WorkingDirectory=/opt/agent2-server
ExecStart=/opt/agent2-server/venv/bin/uvicorn server:app --host ${SERVER_HOST} --port ${SERVER_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now agent2-server.service

echo
echo "=== Estado del servidor ==="
sleep 2
systemctl is-active agent2-server.service && echo "Service: active" || (echo "Service: not running" && exit 1)
journalctl -u agent2-server.service -n 30 --no-pager || true

echo
echo "Listo. Endpoints principales:"
echo "  GET  /health"
echo "  GET  /agents"
echo "  POST /issue           {\"agent_id\":\"...\",\"op\":\"shell\",\"args\":{\"cmd\":\"echo hi\"}}"
echo "  GET  /result/{agent_id}/{cmd_id}"
