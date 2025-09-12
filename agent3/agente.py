import os
import uuid
import subprocess
import json
from flask import Flask, request, jsonify
from dotenv import load_dotenv

# ==============================
# CONFIGURACIÓN DE SEGURIDAD
# ==============================
load_dotenv()

MAX_OUTPUT_SIZE = 90 * 1024   # 90 KB
MAX_EXEC_TIME = 45            # 45 segundos
SESSION_DIR = "/root/projects/agent3/sessions"
os.makedirs(SESSION_DIR, exist_ok=True)

# Tokens desde .env
AGENT3_TOKEN = os.getenv("AGENT3_TOKEN")
API_TOKEN = os.getenv("AGENT3_API_TOKEN")

if not AGENT3_TOKEN or not API_TOKEN:
    raise RuntimeError("Faltan tokens en el archivo .env")

app = Flask(__name__)

def check_token(req):
    auth = req.headers.get("X-Auth-Token")
    return auth == API_TOKEN

# ==============================
# RUTA PRINCIPAL
# ==============================
@app.route("/", methods=["POST"])
def run_agent():
    if not check_token(request):
        return jsonify({"error": "Unauthorized"}), 403

    data = request.get_json(force=True)
    op = data.get("op")
    args = data.get("args", {})

    if op == "shell":
        cmd = args.get("cmd")
        if not cmd:
            return jsonify({"error": "Missing cmd"}), 400

        session_id = str(uuid.uuid4())
        session_file = os.path.join(SESSION_DIR, session_id)

        try:
            result = subprocess.run(
                cmd, shell=True, capture_output=True, text=True,
                timeout=MAX_EXEC_TIME
            )
            stdout = result.stdout[-MAX_OUTPUT_SIZE:]
            stderr = result.stderr[-MAX_OUTPUT_SIZE:]
            exit_code = result.returncode
        except subprocess.TimeoutExpired:
            stdout, stderr, exit_code = "", "Timeout", 124

        with open(session_file, "w") as f:
            json.dump({"stdout": stdout, "stderr": stderr, "exit_code": exit_code}, f)

        return jsonify({
            "stdout": stdout,
            "stderr": stderr,
            "exit_code": exit_code,
            "session": session_id,
            "status": "done"
        })

    elif op == "read_session":
        session_id = args.get("session")
        offset = args.get("offset", 0)
        limit = args.get("limit", MAX_OUTPUT_SIZE)
        session_file = os.path.join(SESSION_DIR, session_id)

        if not os.path.exists(session_file):
            return jsonify({"error": "Session not found"}), 404

        with open(session_file, "r") as f:
            data = json.load(f)

        return jsonify({
            "stdout": data["stdout"][offset:offset+limit],
            "stderr": data["stderr"],
            "exit_code": data["exit_code"]
        })

    elif op == "close_session":
        session_id = args.get("session")
        session_file = os.path.join(SESSION_DIR, session_id)

        if os.path.exists(session_file):
            os.remove(session_file)
            return jsonify({"status": "closed"})
        else:
            return jsonify({"error": "Session not found"}), 404

    else:
        return jsonify({"error": "Invalid op"}), 400

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
