#!/bin/bash
# Agent2 Autoinstall — servidor y/o agente con verificación y pruebas
# Requisitos: root, Ubuntu/Debian, conexión a Internet
set -euo pipefail

must_root(){ [ "$EUID" -eq 0 ] || { echo "ERROR: Ejecuta como root."; exit 1; }; }
ask() { # ask "Pregunta" "valor_por_defecto"
  local p="$1" d="${2:-}"
  read -rp "$p [${d}]: " v || true
  echo "${v:-$d}"
}
yesno(){ # yes/no prompt -> 0/1
  local p="$1" d="${2:-y}"
  read -rp "$p (y/n) [${d}]: " v || true
  v="${v:-$d}"; [[ "$v" =~ ^[Yy]$ ]] && return 0 || return 1
}
hr(){ echo "---------------------------------------------"; }

ensure_pkg(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y "$@"
}

ensure_venv(){
  local path="$1"; python3 -m venv "$path"
  "$path/bin/pip" install --upgrade pip >/dev/null
}

write_file(){ local f="$1"; shift; umask 022; cat >"$f" <<EOF
$*
EOF
}

install_server(){
  echo "[INFO] Instalando SERVIDOR…"
  local SERVER_HOST="$1" SERVER_PORT="$2" CORS_ORIGINS="$3" SEED_AGENT_ID="$4" SEED_TOKEN="$5"
  ensure_pkg python3 python3-venv ca-certificates
  install -d -m 755 /opt/agent2-server /var/lib/agent2-server
  write_file /opt/agent2-server/.env "SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
CORS_ORIGINS=$CORS_ORIGINS"
  chmod 600 /opt/agent2-server/.env
  if [ -n "$SEED_AGENT_ID" ] && [ -n "$SEED_TOKEN" ]; then
    write_file /opt/agent2-server/agents.json "{
  \"$SEED_AGENT_ID\": \"$SEED_TOKEN\"
}"
  else
    write_file /opt/agent2-server/agents.json "{}"
  fi
  chmod 600 /opt/agent2-server/agents.json
  ensure_venv /opt/agent2-server/venv
  /opt/agent2-server/venv/bin/pip install fastapi "uvicorn[standard]" pydantic websockets >/dev/null
  write_file /opt/agent2-server/server.py "$(cat <<'PY'
import json, time, uuid, asyncio, os
from typing import Dict, Any
from pathlib import Path
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

SERVER_HOST=os.environ.get("SERVER_HOST","0.0.0.0")
SERVER_PORT=int(os.environ.get("SERVER_PORT","53123"))
CORS_ORIGINS=os.environ.get("CORS_ORIGINS","*")
DATA_DIR=Path("/opt/agent2-server"); AGENTS_FILE=DATA_DIR/"agents.json"
def load_tokens():
    try: return json.loads(AGENTS_FILE.read_text())
    except Exception: return {}
TOKENS=load_tokens()

app=FastAPI(title="Agent2 Server")
allow_origins=["*"] if CORS_ORIGINS.strip()=="*" else [o.strip() for o in CORS_ORIGINS.split(",")]
app.add_middleware(CORSMiddleware,allow_origins=allow_origins,allow_methods=["*"],allow_headers=["*"],allow_credentials=True)

peers:Dict[str,WebSocket]={}; queues:Dict[str,asyncio.Queue]={}; results:Dict[str,Dict[str,Any]]={}
class IssueCommand(BaseModel):
    agent_id:str; op:str; args:Dict[str,Any]={}

@app.get("/health")
def health(): return {"ok":True,"agents_connected":list(peers.keys())}
@app.get("/agents")
def agents(): return {"connected":list(peers.keys())}
@app.post("/issue")
async def issue_command(req:IssueCommand):
    if req.agent_id not in queues or req.agent_id not in peers: raise HTTPException(404,"Agente no conectado")
    cmd_id=str(uuid.uuid4()); msg={"type":"command","agent_id":"server","seq":0,"msg_id":str(uuid.uuid4()),"timestamp":int(time.time()),
        "payload":{"cmd_id":cmd_id,"op":req.op,"args":req.args}}
    await queues[req.agent_id].put(msg); return {"cmd_id":cmd_id,"status":"sent"}
@app.get("/result/{agent_id}/{cmd_id}")
def get_result(agent_id:str, cmd_id:str):
    r=results.get(agent_id,{}).get(cmd_id)
    if not r: raise HTTPException(404,"Sin resultados")
    return r
@app.post("/reload_tokens")
def reload_tokens(body:Dict[str,Any]=Body(...)):
    global TOKENS; TOKENS={**TOKENS, **{k:str(v) for k,v in body.items()}}
    AGENTS_FILE.write_text(json.dumps(TOKENS,indent=2)); return {"ok":True,"count":len(TOKENS)}

@app.websocket("/ws")
async def ws_endpoint(ws:WebSocket):
    await ws.accept(); agent_id=None
    try:
        data=await ws.receive_json()
        if data.get("type")!="handshake": await ws.close(code=4000); return
        agent_id=data.get("agent_id"); token=(data.get("payload") or {}).get("token")
        if not agent_id or not token or TOKENS.get(agent_id)!=token: await ws.close(code=4003); return
        peers[agent_id]=ws; queues.setdefault(agent_id,asyncio.Queue()); results.setdefault(agent_id,{})
        await ws.send_json({"type":"ack","reply_to":data.get("msg_id"),"agent_id":"server","seq":0,"timestamp":int(time.time())})
        async def sender():
            while True:
                await ws.send_json(await queues[agent_id].get())
        asyncio.create_task(sender())
        while True:
            obj=await ws.receive_json()
            if obj.get("type")=="result":
                p=obj.get("payload") or {}; cid=p.get("cmd_id")
                if cid: results.setdefault(agent_id,{})[cid]=p
            await ws.send_json({"type":"ack","reply_to":obj.get("msg_id"),"agent_id":"server","seq":0,"timestamp":int(time.time())})
    except WebSocketDisconnect:
        pass
    finally:
        if agent_id and peers.get(agent_id) is ws: del peers[agent_id]
PY
)"
  write_file /etc/systemd/system/agent2-server.service "[Unit]
Description=Agent2 Control-Plane (FastAPI + WebSocket)
After=network.target

[Service]
User=root
EnvironmentFile=/opt/agent2-server/.env
WorkingDirectory=/opt/agent2-server
ExecStart=/opt/agent2-server/venv/bin/uvicorn server:app --host \${SERVER_HOST} --port \${SERVER_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target"
  systemctl daemon-reload
  systemctl enable --now agent2-server.service
}

install_agent(){
  echo "[INFO] Instalando AGENTE…"
  local AGENT_ID="$1" SERVER_URL="$2" TOKEN="$3" WORKDIR="$4"
  ensure_pkg python3 python3-venv ca-certificates
  install -d -m 755 /opt/agent2 /var/lib/agent2
  write_file /opt/agent2/.env "AGENT_ID=$AGENT_ID
SERVER_URL=$SERVER_URL
TOKEN=$TOKEN
WORKDIR=$WORKDIR"
  chmod 600 /opt/agent2/.env
  ensure_venv /opt/agent2/venv
  /opt/agent2/venv/bin/pip install websockets >/dev/null
  write_file /opt/agent2/agent.py "$(cat <<'PY'
import asyncio, json, uuid, time, os, base64
import websockets
SERVER_URL=os.environ.get("SERVER_URL","ws://127.0.0.1:53123/ws")
AGENT_ID=os.environ.get("AGENT_ID","lxc-gpt-LOCAL")
TOKEN=os.environ.get("TOKEN","")
WORKDIR=os.environ.get("WORKDIR","/root")

async def send(ws,obj):
    obj["msg_id"]=obj.get("msg_id") or str(uuid.uuid4())
    obj["timestamp"]=int(time.time()); await ws.send(json.dumps(obj))

async def op_shell(args):
    to=int(args.get("timeout",600))
    p=await asyncio.create_subprocess_shell(args.get("cmd"), cwd=args.get("cwd",WORKDIR),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try: out,err=await asyncio.wait_for(p.communicate(), timeout=to)
    except asyncio.TimeoutError: p.kill(); return {"state":"error","exit_code":124,"stderr":"timeout"}
    return {"state":"ok","exit_code":p.returncode,"stdout":out.decode(errors="ignore"),"stderr":err.decode(errors="ignore")}

def ensure_parent(path): os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
async def op_write_file(args):
    path=args["path"]; content=args.get("content",""); mode=args.get("mode",0o644)
    ensure_parent(path); open(path,"w").write(content); os.chmod(path,mode); return {"state":"ok","path":path}
async def op_read_file(args):
    path=args["path"]; maxb=int(args.get("max_bytes",2*1024*1024))
    data=open(path,"rb").read(maxb); return {"state":"ok","path":path,"data_b64":base64.b64encode(data).decode()}
async def op_list_dir(args):
    path=args.get("path",WORKDIR); items=[]
    for n in os.listdir(path):
        p=os.path.join(path,n)
        try: items.append({"name":n,"is_dir":os.path.isdir(p),"size":os.path.getsize(p)})
        except FileNotFoundError: pass
    return {"state":"ok","path":path,"items":items}
async def op_chmod(args):
    path=args["path"]; m=args["mode"]; m=int(m,8) if isinstance(m,str) else m; os.chmod(path,m); return {"state":"ok","path":path}
async def op_upload_init(args):
    path=args["path"]; ensure_parent(path); open(path,"wb").close(); return {"state":"ok","path":path}
async def op_upload_chunk(args):
    path=args["path"]; chunk=base64.b64decode(args["data_b64"])
    with open(path,"ab") as f: f.write(chunk); return {"state":"ok","path":path,"len":len(chunk)}
async def op_download(ws,cid,args):
    path=args["path"]; sz=os.path.getsize(path); cs=int(args.get("chunk_size",256*1024)); total=(sz+cs-1)//cs; i=0
    with open(path,"rb") as f:
        while True:
            c=f.read(cs)
            if not c: break
            await send(ws,{"type":"chunk","agent_id":AGENT_ID,"payload":{"cmd_id":cid,"index":i,"total":total,"data_b64":base64.b64encode(c).decode()}})
            i+=1
    return {"state":"ok","path":path,"size":sz,"chunks":total}

OPS={"shell":op_shell,"write_file":op_write_file,"read_file":op_read_file,"list_dir":op_list_dir,"chmod":op_chmod,"upload_init":op_upload_init,"upload_chunk":op_upload_chunk}

async def handle(ws,payload):
    op=payload.get("op"); args=payload.get("args",{}); cid=payload.get("cmd_id")
    try:
        if op=="download": res=await op_download(ws,cid,args)
        else:
            fn=OPS.get(op)
            if not fn: return {"cmd_id":cid,"state":"error","stderr":f"op no soportada: {op}"}
            res=await fn(args)
        res.update({"cmd_id":cid}); return res
    except Exception as e:
        return {"cmd_id":cid,"state":"error","stderr":str(e)}

async def run():
    if not TOKEN: raise SystemExit("Falta TOKEN")
    back=1
    while True:
        try:
            async with websockets.connect(SERVER_URL,max_size=None,ping_interval=10,ping_timeout=10) as ws:
                await send(ws,{"type":"handshake","agent_id":AGENT_ID,"payload":{"token":TOKEN,"capabilities":list(OPS.keys())+["download"],"cwd":WORKDIR}})
                back=1
                while True:
                    obj=json.loads(await ws.recv())
                    if obj.get("type")=="command":
                        res=await handle(ws,obj["payload"])
                        await send(ws,{"type":"result","agent_id":AGENT_ID,"payload":res})
        except Exception:
            await asyncio.sleep(back); back=min(back*2,30)
if __name__=="__main__": asyncio.run(run())
PY
)"
  write_file /etc/systemd/system/agent2.service "[Unit]
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
WantedBy=multi-user.target"
  systemctl daemon-reload
  systemctl enable --now agent2.service
}

fix_bind_if_needed(){
  local ENV="/opt/agent2-server/.env"
  [ -f "$ENV" ] || return 0
  # Si SERVER_HOST es un FQDN/IP pública, cambiar a 0.0.0.0
  . "$ENV"; local changed=0
  if [[ "${SERVER_HOST}" != "0.0.0.0" && "${SERVER_HOST}" != "127.0.0.1" && "${SERVER_HOST}" != "::" ]]; then
    echo "[INFO] Ajustando SERVER_HOST -> 0.0.0.0 (evita bind a IP no local)"
    SERVER_HOST="0.0.0.0"; changed=1
  fi
  if [ $changed -eq 1 ]; then
    write_file "$ENV" "SERVER_HOST=$SERVER_HOST
SERVER_PORT=${SERVER_PORT:-53123}
CORS_ORIGINS=${CORS_ORIGINS:-*}"
    chmod 600 "$ENV"
    systemctl restart agent2-server.service || true
  fi
}

health_server(){
  local port="${1:-53123}"
  echo "[INFO] Verificando servidor en puerto $port…"
  for i in {1..10}; do
    if ss -ltnp 2>/dev/null | grep -q ":$port"; then
      local out; out="$(curl -sS "http://127.0.0.1:${port}/health" || true)"
      echo "[OK] /health => $out"; return 0
    fi; sleep 1
  done
  echo "[WARN] El puerto $port no está en escucha."
  journalctl -u agent2-server.service -n 60 --no-pager || true
  return 1
}

smoketest(){
  local port="${1:-53123}" agent="$2"
  echo "[INFO] E2E test con agente '$agent'…"
  local resp cmd_id http
  resp="$(curl -sS -X POST "http://127.0.0.1:${port}/issue" \
    -H 'Content-Type: application/json' \
    -d "{\"agent_id\":\"$agent\",\"op\":\"shell\",\"args\":{\"cmd\":\"uname -a && id\",\"timeout\":60}}")" || true
  cmd_id="$(python3 - <<'PY' <<<"$resp"
import sys,json; 
try: print(json.load(sys.stdin).get("cmd_id",""))
except: print("")
PY
)"
  [ -z "$cmd_id" ] && { echo "[WARN] No se obtuvo cmd_id (resp=$resp)"; return 1; }
  echo "[INFO] cmd_id=$cmd_id"
  for i in {1..30}; do
    http=$(curl -sS -o /tmp/_agent2_res.json -w "%{http_code}" "http://127.0.0.1:${port}/result/${agent}/${cmd_id}" || true)
    [ "$http" = "200" ] && { echo "[OK] Resultado:"; cat /tmp/_agent2_res.json; echo; return 0; }
    sleep 1
  done
  echo "[WARN] Sin resultado a tiempo."; return 1
}

uninstall_all(){
  echo "[INFO] Desinstalando servidor y agente…"
  systemctl stop agent2.service 2>/dev/null || true
  systemctl stop agent2-server.service 2>/dev/null || true
  systemctl disable agent2.service 2>/dev/null || true
  systemctl disable agent2-server.service 2>/dev/null || true
  rm -f /etc/systemd/system/agent2.service /etc/systemd/system/agent2-server.service
  systemctl daemon-reload
  rm -rf /opt/agent2 /var/lib/agent2 /opt/agent2-server /var/lib/agent2-server
  echo "[DONE] Eliminado."
}

### MAIN ###
must_root
hr
echo "¿Qué quieres hacer?"
echo "  1) Instalar SOLO SERVIDOR"
echo "  2) Instalar SOLO AGENTE"
echo "  3) Instalar SERVIDOR + AGENTE LOCAL (todo en este host)"
echo "  4) Desinstalar TODO (server + agent)"
CHOICE="$(ask 'Selecciona 1/2/3/4' '3')"
hr

case "$CHOICE" in
  1)
    SRV_HOST="$(ask 'SERVER_HOST (0.0.0.0 recomendado)' '0.0.0.0')"
    SRV_PORT="$(ask 'SERVER_PORT' '53123')"
    CORS="$(ask 'CORS_ORIGINS (* para todos)' '*')"
    seedA="$(ask 'Sembrar AGENT_ID (opcional)' '')"
    seedT=""
    if [ -n "$seedA" ]; then
      seedT="$(ask 'Token para ese AGENT_ID' '')"
      [ -z "$seedT" ] && { echo "ERROR: Debes dar TOKEN para $seedA"; exit 1; }
    fi
    install_server "$SRV_HOST" "$SRV_PORT" "$CORS" "$seedA" "$seedT"
    fix_bind_if_needed
    health_server "$SRV_PORT"
    ;;

  2)
    AGID="$(ask 'AGENT_ID' 'lxc-gpt-01')"
    SRV_URL="$(ask 'SERVER_URL (ws://host:port/ws)' 'ws://127.0.0.1:53123/ws')"
    TOK="$(ask 'TOKEN (debe existir en el servidor)' '')"
    [ -z "$TOK" ] && { echo "ERROR: TOKEN requerido."; exit 1; }
    WDIR="$(ask 'WORKDIR' '/root')"
    install_agent "$AGID" "$SRV_URL" "$TOK" "$WDIR"
    echo "[INFO] Agente instalado. Revisa: systemctl status agent2.service"
    ;;

  3)
    SRV_HOST="$(ask 'SERVER_HOST (0.0.0.0 recomendado)' '0.0.0.0')"
    SRV_PORT="$(ask 'SERVER_PORT' '53123')"
    CORS="$(ask 'CORS_ORIGINS (* para todos)' '*')"
    AGID="$(ask 'AGENT_ID local' 'lxc-gpt-LOCAL')"
    # Generar token
    TOK="$(openssl rand -hex 24)"
    echo "[INFO] TOKEN generado para $AGID: $TOK"
    install_server "$SRV_HOST" "$SRV_PORT" "$CORS" "$AGID" "$TOK"
    fix_bind_if_needed
    health_server "$SRV_PORT" || true
    install_agent "$AGID" "ws://127.0.0.1:${SRV_PORT}/ws" "$TOK" "/root"
    echo "[INFO] Esperando conexión del agente…"
    for i in {1..10}; do
      curl -sS "http://127.0.0.1:${SRV_PORT}/agents" | grep -q "$AGID" && { echo "[OK] Agente conectado."; break; }
      sleep 1
    done
    smoketest "$SRV_PORT" "$AGID" || true
    ;;

  4)
    if yesno "¿Seguro que quieres desinstalar por completo?" "n"; then
      uninstall_all
    else
      echo "Cancelado."
    fi
    ;;

  *) echo "Opción inválida."; exit 1;;
esac

echo "[FIN] Operación completada."
