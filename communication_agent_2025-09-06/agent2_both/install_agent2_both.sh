#!/bin/bash
# Instala Control-Plane (FastAPI+WS) + Agente local que se conecta a 127.0.0.1
# Crea dos servicios systemd: agent2-server.service y agent2.service
# Variables opcionales antes de ejecutar:
#   AGENT_ID   (default: lxc-gpt-LOCAL)
#   SERVER_HOST (default: 0.0.0.0)
#   SERVER_PORT (default: 53123)
#   CORS_ORIGINS (default: *)
#   TOKEN      (si no lo pasas, se genera)
#   WORKDIR    (default: /root)

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

AGENT_ID="${AGENT_ID:-lxc-gpt-LOCAL}"
SERVER_HOST="${SERVER_HOST:-0.0.0.0}"
SERVER_PORT="${SERVER_PORT:-53123}"
CORS_ORIGINS="${CORS_ORIGINS:-*}"
WORKDIR="${WORKDIR:-/root}"
TOKEN="${TOKEN:-}"

echo "[INFO] Instalación servidor+agente en este host"
echo "[INFO] AGENT_ID=$AGENT_ID SERVER=${SERVER_HOST}:${SERVER_PORT} WORKDIR=$WORKDIR"

apt-get update -y
apt-get install -y python3 python3-venv ca-certificates openssl

# -------- Servidor --------
install -d -m 755 /opt/agent2-server
install -d -m 755 /var/lib/agent2-server

cat >/opt/agent2-server/.env <<EOF
SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
CORS_ORIGINS=$CORS_ORIGINS
EOF
chmod 600 /opt/agent2-server/.env

# tokens/agents
if [ -z "${TOKEN}" ]; then
  TOKEN="$(openssl rand -hex 24)"
fi
echo "[INFO] TOKEN asignado al agente local: $TOKEN"

cat >/opt/agent2-server/agents.json <<EOF
{
  "$AGENT_ID": "$TOKEN"
}
EOF
chmod 600 /opt/agent2-server/agents.json

python3 -m venv /opt/agent2-server/venv
/opt/agent2-server/venv/bin/pip install --upgrade pip >/dev/null
/opt/agent2-server/venv/bin/pip install fastapi "uvicorn[standard]" pydantic websockets >/dev/null

cat >/opt/agent2-server/server.py <<'PY'
import json, time, uuid, asyncio, os
from typing import Dict, Any
from pathlib import Path
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

SERVER_HOST = os.environ.get("SERVER_HOST", "0.0.0.0")
SERVER_PORT = int(os.environ.get("SERVER_PORT", "53123"))
CORS_ORIGINS = os.environ.get("CORS_ORIGINS", "*")

DATA_DIR = Path("/opt/agent2-server")
AGENTS_FILE = DATA_DIR / "agents.json"

def load_tokens() -> Dict[str, str]:
    try:
        return json.loads(AGENTS_FILE.read_text())
    except Exception:
        return {}

TOKENS = load_tokens()
app = FastAPI(title="Agent2 Server")

allow_origins = ["*"] if CORS_ORIGINS.strip() == "*" else [o.strip() for o in CORS_ORIGINS.split(",")]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins, allow_methods=["*"], allow_headers=["*"], allow_credentials=True,
)

peers: Dict[str, WebSocket] = {}
queues: Dict[str, asyncio.Queue] = {}
results: Dict[str, Dict[str, Any]] = {}

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
    import time, uuid
    cmd_id = str(uuid.uuid4())
    msg = {
        "type":"command","agent_id":"server","seq":0,"msg_id":str(uuid.uuid4()),
        "timestamp":int(time.time()),
        "payload":{"cmd_id":cmd_id,"op":req.op,"args":req.args}
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
    global TOKENS
    TOKENS = {**TOKENS, **{k:str(v) for k, v in body.items()}}
    AGENTS_FILE.write_text(json.dumps(TOKENS, indent=2))
    return {"ok": True, "count": len(TOKENS)}

@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    agent_id = None
    try:
        data = await ws.receive_json()
        if data.get("type") != "handshake":
            await ws.close(code=4000); return
        agent_id = data.get("agent_id")
        token = (data.get("payload") or {}).get("token")
        if not agent_id or not token or TOKENS.get(agent_id) != token:
            await ws.close(code=4003); return
        peers[agent_id] = ws
        queues.setdefault(agent_id, asyncio.Queue())
        results.setdefault(agent_id, {})
        await ws.send_json({"type":"ack","reply_to":data.get("msg_id"),"agent_id":"server","seq":0,"timestamp":int(time.time())})

        async def sender():
            while True:
                msg = await queues[agent_id].get()
                await ws.send_json(msg)
        send_task = asyncio.create_task(sender())

        while True:
            obj = await ws.receive_json()
            if obj.get("type") == "result":
                payload = obj.get("payload") or {}
                cmd_id = payload.get("cmd_id")
                if cmd_id:
                    results.setdefault(agent_id, {})[cmd_id] = payload
            await ws.send_json({"type":"ack","reply_to":obj.get("msg_id"),"agent_id":"server","seq":0,"timestamp":int(time.time())})
    except WebSocketDisconnect:
        pass
    finally:
        if agent_id and peers.get(agent_id) is ws:
            del peers[agent_id]
PY
chmod 755 /opt/agent2-server/server.py

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

# -------- Agente local --------
install -d -m 755 /opt/agent2
install -d -m 755 /var/lib/agent2

cat >/opt/agent2/.env <<EOF
AGENT_ID=$AGENT_ID
SERVER_URL=ws://127.0.0.1:${SERVER_PORT}/ws
TOKEN=$TOKEN
WORKDIR=$WORKDIR
EOF
chmod 600 /opt/agent2/.env

python3 -m venv /opt/agent2/venv
/opt/agent2/venv/bin/pip install --upgrade pip >/dev/null
/opt/agent2/venv/bin/pip install websockets >/dev/null

cat > /opt/agent2/agent.py <<'PY'
import asyncio, json, uuid, time, os, base64
import websockets
SERVER_URL = os.environ.get("SERVER_URL", "ws://127.0.0.1:53123/ws")
AGENT_ID   = os.environ.get("AGENT_ID", "lxc-gpt-LOCAL")
TOKEN      = os.environ.get("TOKEN", "")
WORKDIR    = os.environ.get("WORKDIR", "/root")

async def send(ws, obj):
    obj["msg_id"] = obj.get("msg_id") or str(uuid.uuid4())
    obj["timestamp"] = int(time.time())
    await ws.send(json.dumps(obj))

async def op_shell(args):
    timeout = int(args.get("timeout", 600))
    proc = await asyncio.create_subprocess_shell(
        args.get("cmd"), cwd=args.get("cwd", WORKDIR),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill(); return {"state":"error","exit_code":124,"stderr":"timeout"}
    return {"state":"ok","exit_code":proc.returncode,
            "stdout":stdout.decode(errors="ignore"), "stderr":stderr.decode(errors="ignore")}

def ensure_parent(path):
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)

async def op_write_file(args):
    path = args["path"]; content = args.get("content",""); mode = args.get("mode",0o644)
    ensure_parent(path); open(path,"w").write(content); os.chmod(path, mode)
    return {"state":"ok","path":path}

async def op_read_file(args):
    path = args["path"]; max_bytes = int(args.get("max_bytes", 2*1024*1024))
    data = open(path,"rb").read(max_bytes)
    return {"state":"ok","path":path,"data_b64": base64.b64encode(data).decode()}

async def op_list_dir(args):
    path = args.get("path", WORKDIR); items=[]
    for name in os.listdir(path):
        p = os.path.join(path, name)
        try: items.append({"name":name,"is_dir":os.path.isdir(p),"size":os.path.getsize(p)})
        except FileNotFoundError: pass
    return {"state":"ok","path":path,"items":items}

async def op_chmod(args):
    path = args["path"]; mode = args["mode"]
    if isinstance(mode,str): mode=int(mode,8)
    os.chmod(path, mode); return {"state":"ok","path":path}

async def op_upload_init(args):
    path=args["path"]; ensure_parent(path); open(path,"wb").close(); return {"state":"ok","path":path}

async def op_upload_chunk(args):
    path=args["path"]; chunk=base64.b64decode(args["data_b64"])
    with open(path,"ab") as f: f.write(chunk)
    return {"state":"ok","path":path,"len":len(chunk)}

async def op_download(ws, cmd_id, args):
    path=args["path"]; chunk_size=int(args.get("chunk_size",256*1024))
    size=os.path.getsize(path); total=(size+chunk_size-1)//chunk_size; idx=0
    with open(path,"rb") as f:
        while True:
            c=f.read(chunk_size)
            if not c: break
            await send(ws, {"type":"chunk","agent_id":AGENT_ID,"payload":{
                "cmd_id":cmd_id,"index":idx,"total":total,"data_b64": base64.b64encode(c).decode()
            }})
            idx+=1
    return {"state":"ok","path":path,"size":size,"chunks":total}

OPS = {"shell":op_shell,"write_file":op_write_file,"read_file":op_read_file,
       "list_dir":op_list_dir,"chmod":op_chmod,"upload_init":op_upload_init,"upload_chunk":op_upload_chunk}

async def handle_command(ws, payload):
    op = payload.get("op"); args = payload.get("args", {}); cmd_id = payload.get("cmd_id")
    try:
        if op == "download": res = await op_download(ws, cmd_id, args)
        else:
            fn = OPS.get(op)
            if not fn: return {"cmd_id":cmd_id, "state":"error", "stderr": f"op no soportada: {op}"}
            res = await fn(args)
        res.update({"cmd_id":cmd_id}); return res
    except Exception as e:
        return {"cmd_id":cmd_id, "state":"error", "stderr": str(e)}

async def run():
    if not TOKEN: raise SystemExit("Falta TOKEN en entorno")
    backoff=1
    while True:
        try:
            async with websockets.connect(SERVER_URL, max_size=None, ping_interval=10, ping_timeout=10) as ws:
                await send(ws, {"type":"handshake","agent_id":AGENT_ID,
                                "payload":{"token":TOKEN,"capabilities":list(OPS.keys())+["download"],"cwd":WORKDIR}})
                backoff=1
                while True:
                    obj = json.loads(await ws.recv())
                    if obj.get("type")=="command":
                        res = await handle_command(ws, obj["payload"])
                        await send(ws, {"type":"result","agent_id":AGENT_ID,"payload":res})
        except Exception:
            await asyncio.sleep(backoff); backoff=min(backoff*2,30)

if __name__=="__main__":
    asyncio.run(run())
PY
chmod 755 /opt/agent2/agent.py

cat >/etc/systemd/system/agent2.service <<'UNIT'
[Unit]
Description=Agente 2.0 WebSocket (local)
After=network.target
[Service]
User=root
EnvironmentFile=/opt/agent2/.env
ExecStart=/opt/agent2/venv/bin/python /opt/agent2/agent.py
Restart=always
RestartSec=3
WorkingDirectory=/opt/agent2
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now agent2.service

echo
echo "=== RESUMEN ==="
echo "Servidor: agent2-server.service (WS en :$SERVER_PORT)"
echo "Agente   : agent2.service (ID=$AGENT_ID, URL=ws://127.0.0.1:$SERVER_PORT/ws)"
echo "Token guardado en: /opt/agent2/.env  y agents.json"
echo
echo "Prueba rápida (HTTP):  curl http://127.0.0.1:${SERVER_PORT}/health"
