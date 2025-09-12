# GPT-proyects

Este repositorio contiene el **Agente3**, un servicio basado en Flask que permite ejecutar comandos en el servidor de forma controlada.

## 🚀 Instalación

1. Clonar el repositorio:
   ```bash
   git clone https://github.com/juasjo/GPT-proyects.git
   cd GPT-proyects/agent3
   ```

2. Crear y configurar el archivo `.env` a partir del ejemplo:
   ```bash
   cp .env.example .env
   ```

   Editar `.env` y rellenar:
   ```env
   AGENT3_TOKEN=tu_token_principal
   AGENT3_API_TOKEN=tu_token_api
   ```

3. Instalar dependencias:
   ```bash
   pip install -r requirements.txt
   ```

## ▶️ Ejecución

Para lanzar el servidor:
```bash
python agente.py
```

Por defecto escucha en `http://0.0.0.0:5000`.

## 📌 Endpoints disponibles

### 1. `/` → Ejecutar comando
- **Método:** POST
- **Headers:** `X-Auth-Token: <AGENT3_API_TOKEN>`
- **Body (JSON):**
  ```json
  { "op": "shell", "args": { "cmd": "ls -l" } }
  ```

### 2. `/` → Leer sesión
```json
{ "op": "read_session", "args": { "session": "<id>", "offset": 0, "limit": 90000 } }
```

### 3. `/` → Cerrar sesión
```json
{ "op": "close_session", "args": { "session": "<id>" } }
```

## 🛡️ Seguridad
- El servicio **requiere autenticación por token** (`X-Auth-Token`).
- Los secretos nunca deben subirse a GitHub.
- `.env` está en `.gitignore`.

