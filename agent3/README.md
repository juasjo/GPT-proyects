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
