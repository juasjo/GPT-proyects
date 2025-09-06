# 📡 Telegram Logger Extension

## 📌 Descripción
Este proyecto implementa un **sistema de logging hacia Telegram** para registrar tanto comandos ejecutados (CMD) como acciones de API (API) desde el servidor.

Incluye:
- Envío en tiempo real de mensajes a un chat de Telegram.
- Diferenciación clara entre **CMD** (verde) y **API** (azul).
- Manejo de *rate limits* con backoff automático.
- Truncado de salidas largas, guardando los detalles en ficheros locales.
- Sistema de **heartbeat automático** que confirma cada hora que el servicio sigue activo.

---

## ⚙️ Componentes

### 1. `telegram_logger_daemon.py`
- Daemon principal que supervisa:
  - `commands.log` → registros de comandos.
  - `api_actions.log` → registros de acciones API.
- Envía cada entrada a Telegram con formato diferenciado.
- Aplica control de flujo y backoff en caso de saturación (`429 Too Many Requests`).

### 2. `api_logger.py`
- Script auxiliar para registrar acciones API en `api_actions.log`.
- Uso:
  ```bash
  python3 api_logger.py "list_dir /etc"
  ```

### 3. Servicios systemd
- `telegram_logger.service` → daemon principal.
- `telegram_logger_heartbeat.service` → servicio one-shot para enviar heartbeat.
- `telegram_logger_heartbeat.timer` → ejecuta el heartbeat cada hora.

---

## 🎨 Formato en Telegram

- **Comandos (CMD)** → 💻 verde:
  ```
  💻 [CMD]
  root@gpt: uptime
  ```

- **Acciones API** → 🤖 azul:
  ```
  🤖 [AGENT API]
  root@gpt: list_dir /etc
  ```

- Los mensajes largos se truncan a 1000 caracteres y se guardan en `logs/long_outputs/`.

---

## 🕒 Heartbeat
Cada hora se envía automáticamente:
- 💻 `[CMD] root@gpt: HEARTBEAT CMD ...`
- 🤖 `[AGENT API] root@gpt: HEARTBEAT API ...`

Esto confirma que el servicio está activo. Si dejas de ver estos mensajes, el daemon puede haberse detenido.

---

## 📂 Estructura del proyecto
```
/root/projects/telegram_logger_extension_2025-09-06_15-30/
├── telegram_logger_daemon.py        # daemon principal
├── api_logger.py                    # script para registrar acciones API
├── README.md                        # documentación
├── commands.log                     # log de comandos (ignorado en Git)
├── api_actions.log                  # log de API (ignorado en Git)
├── logs/                            # debug y salidas largas (ignorado en Git)
└── systemd/
    ├── telegram_logger.service
    ├── telegram_logger_heartbeat.service
    └── telegram_logger_heartbeat.timer
```

---

## 🔑 Configuración
1. Crear archivo `/root/.telegram_env` con:
   ```
   BOT_TOKEN=1234567890:AAH-xxxxxxxxxxxxxxxxxxxxx
   CHAT_ID=-1001234567890
   ```

2. Habilitar servicios:
   ```bash
   systemctl daemon-reload
   systemctl enable --now telegram_logger.service
   systemctl enable --now telegram_logger_heartbeat.timer
   ```

---

## ▶️ Uso
- Iniciar daemon:
  ```bash
  systemctl start telegram_logger
  ```
- Ver estado:
  ```bash
  systemctl status telegram_logger
  ```
- Consultar logs de debug:
  ```bash
  tail -f /root/projects/telegram_logger_extension_2025-09-06_15-30/logs/debug.log
  ```

---

## ✅ Estado final
- CMD → funcionando, llegan a Telegram en verde.
- API → funcionando, llegan a Telegram en azul.
- Heartbeat → activo cada hora.
- Sistema robusto y estable, listo para producción.