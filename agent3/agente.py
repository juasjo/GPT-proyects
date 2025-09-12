import os
from dotenv import load_dotenv

# Cargar variables de entorno desde .env
load_dotenv()

AGENT3_TOKEN = os.getenv("AGENT3_TOKEN")

if not AGENT3_TOKEN:
    raise RuntimeError("Falta AGENT3_TOKEN en las variables de entorno")

print("Token cargado correctamente desde .env (no se muestra por seguridad).")
