# 🤖 Agent3 - Sistema de Ejecución Remota Segura

## 📌 Introducción
Agent3 es un **servidor ligero en Flask** que permite la **ejecución remota de comandos** en un servidor Linux, diseñado para integrarse con modelos de IA (como GPT) de forma segura y controlada.

## 🏗️ Arquitectura
El sistema sigue un esquema **cliente-servidor**:

```
Cliente (GPT) ⇄ API REST (Agent3) ⇄ Servidor Linux
```

### Componentes principales
- **Agente Flask (`agente.py`)** → expone una API REST para recibir y procesar solicitudes.
- **Sesiones (`/sessions/`)** → almacenamiento temporal de resultados grandes o procesos que exceden el límite.
- **Autenticación** → cada petición requiere un token de seguridad (`X-Auth-Token`).

## ⚙️ Endpoints principales

### 1. `POST /` → ejecutar operación

La API acepta JSON con los siguientes campos:

- `op: "shell"` → ejecuta un comando en el sistema.
- `op: "read_session"` → lee un resultado almacenado previamente.
- `op: "close_session"` → elimina una sesión temporal.

Ejemplo de request para ejecutar un comando:
```json
{
  "op": "shell",
  "args": { "cmd": "ls -l /" }
}
```

### 2. Límites de seguridad
- **Máx. tiempo de ejecución:** 45 segundos.
- **Máx. tamaño de salida:** 90 KB (lo que exceda se guarda en sesiones).

## 🔒 Seguridad
- Autenticación mediante **token secreto** en la cabecera HTTP (`X-Auth-Token`).
- Restricción de recursos para evitar abusos o bloqueos del sistema.
- Manejo de sesiones para grandes volúmenes de datos.

## 🚀 Uso
1. Clonar el repositorio:
```bash
git clone https://github.com/juasjo/agent3.git
```

2. Instalar dependencias:
```bash
pip install flask
```

3. Ejecutar el agente:
```bash
python3 agente.py
```

El servicio quedará expuesto en `http://localhost:5000/` (puerto configurable).

## 📂 Estructura del proyecto
```
agent3/
 ├── agente.py     # Script principal del agente
 ├── README.md     # Documentación del proyecto
 └── sessions/     # Carpeta para almacenar sesiones temporales
```

---
✍️ Proyecto mantenido por [@juasjo](https://github.com/juasjo).

## 🛡️ Monitoreo y Mantenimiento

### Logrotate
Para evitar que los archivos de log crezcan indefinidamente, se configuró un archivo en `/etc/logrotate.d/agent3`:
```conf
/root/projects/agent3/agent3.out /root/projects/agent3/agent3.err {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
```
Esto rota los logs diariamente, guarda 7 copias comprimidas y evita problemas de espacio.

### Watchdog (Autoreinicio)
Se creó el script `watchdog_agent3.sh` en la carpeta del proyecto:
```bash
#!/bin/bash
LOGFILE="/root/projects/agent3/watchdog.log"

if ! systemctl is-active --quiet agent3; then
    echo "$(date) - Agent3 not running. Restarting..." >> $LOGFILE
    systemctl restart agent3
else
    echo "$(date) - Agent3 running OK" >> $LOGFILE
fi
```
- El script corre cada 5 minutos mediante **cron**.
- Si el servicio está caído, lo reinicia automáticamente y deja registro en `watchdog.log`.

### Comandos útiles
- Ver estado del servicio:
  ```bash
  systemctl status agent3
  ```
- Reiniciar manualmente:
  ```bash
  systemctl restart agent3
  ```
- Ver últimos logs del watchdog:
  ```bash
  tail -n 20 /root/projects/agent3/watchdog.log
  ```

Con estas configuraciones, Agent3 se mantiene estable y con autorecuperación en caso de fallo.
