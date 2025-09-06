# 🤖 Agent2 - Sistema de Comunicación Cliente/Servidor/Bridge

## 📌 Introducción
Agent2 es un sistema modular que permite la **comunicación remota entre un servidor y múltiples agentes** mediante WebSockets y HTTP (a través de un bridge). Está diseñado para ser ligero, extensible y fácil de integrar con modelos GPT.

## 🏗️ Arquitectura
- **Agente (Cliente)** → ejecuta comandos recibidos del servidor.
- **Servidor** → coordina múltiples agentes, mantiene tokens y gestiona resultados.
- **Bridge** → expone el servidor a través de HTTP/REST para integraciones externas (ej: GPT).
- **Instalador combinado** → despliega cliente + servidor en un mismo host.

```
GPT ↔ Bridge ↔ Servidor ↔ Agente(s)
```

## ⚙️ Instaladores

### Cliente (`agent2/install_agent2.sh`)
- Instala el agente en `/opt/agent2/`.
- Configura `.env` con `AGENT_ID`, `TOKEN`, `SERVER_URL`.
- Servicio: `agent2.service`.

### Servidor (`agent2_server/install_agent2_server.sh`)
- Instala el servidor en `/opt/agent2-server/`.
- Gestiona múltiples agentes.
- Endpoints: `/health`, `/agents`, `/issue`, `/result/{agent}/{cmd_id}`, `/reload_tokens`.
- Servicio: `agent2-server.service`.

### Bridge (`install_agent2_bridge.sh`)
- Expone FastAPI + Uvicorn en `/opt/agent2-bridge/`.
- Endpoints: `/health`, `/agent/run`, `/result/{agent_id}/{cmd_id}`.
- Servicio: `agent2-bridge.service`.

### Cliente + Servidor (`agent2_both/install_agent2_both.sh`)
- Instala cliente y servidor en un mismo host.
- Servicios: `agent2.service`, `agent2-server.service`.

### Autoinstalador (`agent2_autoinstall.sh`)
- Detecta entorno y despliega automáticamente cliente, servidor o ambos.

---

## 🧪 Tests
- `tests/step1_check_bridge.sh` → valida el estado del bridge.
- `tests/step2_fix_bridge_env.sh` → corrige variables de entorno.

---

## 🛠️ Uso con systemd
```bash
systemctl start agent2
systemctl status agent2
systemctl restart agent2-server
```

Logs:
```bash
journalctl -u agent2 -f
```

---

## 📂 Estructura del proyecto
```
communication_agent_2025-09-06/
├── agent2/
├── agent2_server/
├── agent2_both/
├── tests/
├── install_agent2_bridge.sh
├── agent2_autoinstall.sh
├── README.md
└── CONNECT_GPT.md
```

---

## 🚀 Casos de uso
- **Desarrollo local** → usar `agent2_both` para cliente+servidor en el mismo host.
- **Despliegue remoto** → servidor en un VPS, clientes en múltiples máquinas.
- **Integración GPT** → exponer bridge vía HTTP y conectar un modelo GPT para ejecutar comandos.

---

## 🗺️ Roadmap
- Mejorar seguridad en tokens.
- Añadir logging avanzado con envío a Telegram.
- Integración nativa con Docker.
- Documentación de ejemplos multi-agente.
