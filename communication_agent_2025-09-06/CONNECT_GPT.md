# 🔗 Conectar un GPT a Agent2

Este tutorial explica cómo integrar un modelo GPT con **Agent2** para ejecutar comandos remotos a través del bridge y el servidor de agentes.

---

## 1. 📌 Requisitos previos
- Servidor con **Agent2** instalado (cliente, servidor y bridge).
- Un **BOT GPT** o asistente con acceso al plugin `gpt_juasjo_com__jit_plugin`.
- Variables de entorno configuradas:
  - `AGENT_ID`
  - `TOKEN`
  - `SERVER_HOST`, `SERVER_PORT`
  - `BRIDGE_HOST`, `BRIDGE_PORT`

---

## 2. 🏗️ Arquitectura
```
GPT ↔ Bridge (HTTP) ↔ Servidor (WebSocket) ↔ Agente(s)
```

- El **GPT** envía peticiones HTTP al **Bridge**.
- El **Bridge** reenvía comandos al **Servidor**.
- El **Servidor** comunica las órdenes al **Agente** correspondiente.
- El **Agente** ejecuta y devuelve resultados.

---

## 3. ⚙️ Instalación rápida
### Servidor
```bash
cd /root/instaladores/agent2_server
./install_agent2_server.sh
```

### Cliente
```bash
cd /root/instaladores/agent2
./install_agent2.sh
```

### Bridge
```bash
cd /root/instaladores
./install_agent2_bridge.sh
```

### Autoinstalador
```bash
cd /root/instaladores
./agent2_autoinstall.sh
```

---

## 4. 🔑 Configuración de `.env`
Ejemplo para un **agente** en `/opt/agent2/.env`:
```
AGENT_ID=Lxc-gpt-LOCAL
TOKEN=secreto123
SERVER_URL=ws://127.0.0.1:53123/ws
```

Ejemplo para el **servidor** en `/opt/agent2-server/.env`:
```
SERVER_HOST=0.0.0.0
SERVER_PORT=53123
CORS_ORIGINS=["*"]
```

Ejemplo para el **bridge** en `/opt/agent2-bridge/.env`:
```
BRIDGE_HOST=0.0.0.0
BRIDGE_PORT=53124
SERVER_HOST=127.0.0.1
SERVER_PORT=53123
DEFAULT_AGENT_ID=Lxc-gpt-LOCAL
TIMEOUT_SECONDS=60
```

---

## 5. 🩺 Probar salud del sistema
```bash
curl http://127.0.0.1:53124/health
```
Debe devolver un JSON con el estado del bridge y del servidor.

---

## 6. 🤖 Primer comando desde GPT
Ejemplo de uso desde GPT (plugin `gpt_juasjo_com__jit_plugin`):
```json
{
  "op": "shell",
  "args": { "cmd": "ls -la" }
}
```

Respuesta típica:
```json
{
  "state": "ok",
  "exit_code": 0,
  "stdout": "total 12...",
  "stderr": ""
}
```

---

## 7. 🔄 Flujo de datos
1. GPT envía petición al **bridge**.
2. El **bridge** reenvía al **servidor**.
3. El **servidor** entrega el comando al **agente**.
4. El **agente** ejecuta localmente y responde.
5. El resultado fluye de vuelta a GPT.

---

## 8. ⚠️ Errores comunes
- `agent not found` → el agente no está registrado en el servidor.
- `timeout` → el agente no respondió a tiempo.
- `invalid token` → el token no coincide con el configurado en el servidor.
- `connection refused` → el bridge o servidor no está en ejecución.

---

## 9. 💡 Buenas prácticas
- Usar **tokens únicos** por agente.
- Mantener los servicios bajo `systemd` para reinicios automáticos.
- Añadir TLS (reverse proxy con Nginx o Caddy) si se expone el bridge públicamente.
- Monitorear logs con `journalctl` o integrarlos con un sistema de alertas.

---

✅ Con esto, tu GPT quedará conectado al ecosistema **Agent2** y podrás ejecutar comandos remotos de forma segura y controlada.