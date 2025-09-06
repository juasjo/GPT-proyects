#!/bin/bash
# Agente 2.0 — Instalador (cliente) con venv + systemd
# ----------------------------------------------------
# Configuración por variables de entorno o .env:
#   AGENT_ID   (default: lxc-gpt-02)
#   SERVER_URL (default: ws://gpt.juasjo.com:53123/ws)
#   TOKEN      (OBLIGATORIO)
#   WORKDIR    (default: /root)
#
# Opcional: crea /opt/agent2/.env con líneas KEY=VALUE para persistir config.

set -euo pipefail

# --- Cargar .env si existe ---
if [ -f /opt/agent2/.env ]; then
  set -a
  # shellcheck disable=SC1091
  source /opt/agent2/.env
  set +a
fi

AGENT_ID="${AGENT_ID:-lxc-gpt-02}"
SERVER_URL="${SERVER_URL:-ws://gpt.juasjo.com:53123/ws}"
TOKEN="${TOKEN:-}"
WORKDIR="${WORKDIR:-/root}"

if [ -z "$TOKEN" ]; then
  echo "ERROR: Falta TOKEN. Define TOKEN en entorno o en /opt/agent2/.env" >&2
  exit 1
fi

echo "[INFO] Instalando Agente 2.0"
echo "[INFO] AGENT_ID=$AGENT_ID"
echo "[INFO] SERVER_URL=$SERVER_URL"
echo "[INFO] WORKDIR=$WORKDIR"

# --- Dependencias mínimas ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-venv ca-certificates

# --- Árbol de directorios ---
install -d -m 755 /opt/agent2
install -d -m 755 /var/lib/agent2

# --- Guardar .env resultante (persistente) ---
cat >/opt/agent2/.env <<EOF
AGENT_ID=$AGENT_ID
SERVER_URL=$SERVER_URL
TOKEN=$TOKEN
WORKDIR=$WORKDIR
EOF
chmod 600 /opt/agent2/.env

# --- Entorno virtual aislado ---
python3 -m venv /opt/agent2/venv
/opt/agent2/venv/bin/pip install --upgrade pip >/dev/null
/opt/agent2/venv/bin/pip install websockets >/dev/null

# --- Código del agente ---
cat > /opt/agent2/agent.py <<'PY'
import asyncio, json, uuid, time, os, base64
import websockets

SERVER_URL = os.environ.get("SERVER_URL", "ws://gpt.juasjo.com:53123/ws")
AGENT_ID   = os.environ.get("AGENT_ID", "lxc-gpt-02")
TOKEN      = os.environ.get("TOKEN", "")
WORKDIR    = os.environ.get("WORKDIR", "/root")

async def send(ws, obj):
    obj["msg_id"] = obj.get("msg_id") or str(uuid.uuid4())
    obj["timestamp"] = int(time.time())
    await ws.send(json.dumps(obj))

async def op_shell(args):
    timeout = int(args.get("timeout", 600))
    proc = await asyncio.create_subprocess_shell(
        args.get("cmd"),
        cwd=args.get("cwd", WORKDIR),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        return {"state":"error","exit_code":124,"stderr":"timeout"}
    return {
        "state":"ok",
        "exit_code": proc.returncode,
        "stdout": stdout.decode(errors="ignore"),
        "stderr": stderr.decode(errors="ignore")
    }

def ensure_parent(path):
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)

async def op_write_file(args):
    path = args["path"]
    content = args.get("content","")
    mode = args.get("mode", 0o644)
    ensure_parent(path)
    with open(path, "w") as f:
        f.write(content)
    os.chmod(path, mode)
    return {"state":"ok","path":path}

async def op_read_file(args):
    path = args["path"]
    max_bytes = int(args.get("max_bytes", 2*1024*1024))
    with open(path, "rb") as f:
        data = f.read(max_bytes)
    return {"state":"ok","path":path,"data_b64": base64.b64encode(data).decode()}

async def op_list_dir(args):
    path = args.get("path", WORKDIR)
    items = []
    for name in os.listdir(path):
        p = os.path.join(path, name)
        try:
            items.append({"name":name,"is_dir":os.path.isdir(p),"size":os.path.getsize(p)})
        except FileNotFoundError:
            pass
    return {"state":"ok","path":path,"items":items}

async def op_chmod(args):
    path = args["path"]
    mode = args["mode"]
    if isinstance(mode, str):
        mode = int(mode, 8)
    os.chmod(path, mode)
    return {"state":"ok","path":path}

async def op_upload_init(args):
    path = args["path"]
    ensure_parent(path)
    with open(path, "wb") as f:
        pass
    return {"state":"ok","path":path}

async def op_upload_chunk(args):
    path = args["path"]
    data_b64 = args["data_b64"]
    chunk = base64.b64decode(data_b64)
    with open(path, "ab") as f:
        f.write(chunk)
    return {"state":"ok","path":path,"len":len(chunk)}

async def op_download(ws, cmd_id, args):
    path = args["path"]
    chunk_size = int(args.get("chunk_size", 256*1024))
    size = os.path.getsize(path)
    total = (size + chunk_size - 1) // chunk_size
    idx = 0
    with open(path, "rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            await send(ws, {
                "type":"chunk",
                "agent_id":AGENT_ID,
                "payload":{
                    "cmd_id":cmd_id,
                    "index":idx,
                    "total":total,
                    "data_b64": base64.b64encode(chunk).decode()
                }
            })
            idx += 1
    return {"state":"ok","path":path,"size":size,"chunks":total}

OPS = {
    "shell": op_shell,
    "write_file": op_write_file,
    "read_file": op_read_file,
    "list_dir": op_list_dir,
    "chmod": op_chmod,
    "upload_init": op_upload_init,
    "upload_chunk": op_upload_chunk,
}

async def handle_command(ws, payload):
    op = payload.get("op")
    args = payload.get("args", {})
    cmd_id = payload.get("cmd_id")
    try:
        if op == "download":
            res = await op_download(ws, cmd_id, args)
        else:
            fn = OPS.get(op)
            if not fn:
                return {"cmd_id":cmd_id, "state":"error", "stderr": f"op no soportada: {op}"}
            res = await fn(args)
        res.update({"cmd_id":cmd_id})
        return res
    except Exception as e:
        return {"cmd_id":cmd_id, "state":"error", "stderr": str(e)}

async def run():
    if not TOKEN:
        raise SystemExit("Falta TOKEN en entorno")
    backoff = 1
    while True:
        try:
            async with websockets.connect(
                SERVER_URL, max_size=None, ping_interval=10, ping_timeout=10
            ) as ws:
                await send(ws, {
                    "type":"handshake",
                    "agent_id":AGENT_ID,
                    "payload":{"token":TOKEN, "capabilities":list(OPS.keys())+["download"], "cwd":WORKDIR}
                })
                backoff = 1
                while True:
                    msg = await ws.recv()
                    obj = json.loads(msg)
                    if obj.get("type") == "command":
                        res = await handle_command(ws, obj["payload"])
                        await send(ws, {"type":"result","agent_id":AGENT_ID,"payload":res})
        except Exception:
            await asyncio.sleep(backoff)
            backoff = min(backoff*2, 30)

if __name__ == "__main__":
    asyncio.run(run())
PY
chmod 755 /opt/agent2/agent.py

# --- Unidad systemd (usa venv) ---
cat > /etc/systemd/system/agent2.service <<'UNIT'
[Unit]
Description=Agente 2.0 WebSocket
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
echo "=== Estado del agente ==="
sleep 2
systemctl is-active agent2.service && echo "Service: active" || (echo "Service: not running" && exit 1)
journalctl -u agent2.service -n 20 --no-pager || true
