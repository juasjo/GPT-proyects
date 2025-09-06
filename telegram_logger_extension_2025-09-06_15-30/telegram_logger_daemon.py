#!/usr/bin/env python3
import os
import time
import requests
import hashlib
import queue
import threading
import json
import html
from datetime import datetime

BASE_DIR = os.path.dirname(__file__)
COMMANDS_LOG = os.path.join(BASE_DIR, 'commands.log')
API_LOG = os.path.join(BASE_DIR, 'api_actions.log')
DEBUG_LOG = os.path.join(BASE_DIR, 'logs', 'debug.log')
LONG_OUTPUT_DIR = os.path.join(BASE_DIR, 'logs', 'long_outputs')

BOT_TOKEN = os.environ.get('BOT_TOKEN')
CHAT_ID = os.environ.get('CHAT_ID')

sent_cmd_hashes = set()
sent_api_hashes = set()
cmd_queue = queue.Queue()
api_queue = queue.Queue()

MIN_DELAY = 1
MAX_DELAY = 3
current_delay = 2
last_success = time.time()

def debug_write(msg: str):
    os.makedirs(os.path.dirname(DEBUG_LOG), exist_ok=True)
    with open(DEBUG_LOG, 'a') as f:
        f.write(msg + "\n")

def save_long_output(content: str, prefix: str) -> str:
    os.makedirs(LONG_OUTPUT_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = os.path.join(LONG_OUTPUT_DIR, f"{prefix}_{timestamp}.log")
    with open(path, 'w') as f:
        f.write(content)
    return path

def prepare_message(msg: str, is_api: bool) -> str:
    safe = html.escape(msg.strip())
    if len(safe) > 1000:
        preview = safe[:1000] + "\n--- OUTPUT TRUNCATED ---"
        filepath = save_long_output(safe, "api" if is_api else "cmd")
        if is_api:
            formatted = f"🤖 <b>[AGENT API]</b>\n<pre><a href=\"tg://user?id=0\">{preview}</a></pre>\nFull output saved: {filepath}"
        else:
            formatted = f"💻 <b>[CMD]</b>\n<pre><code>{preview}</code></pre>\nFull output saved: {filepath}"
        return formatted
    else:
        if is_api:
            return f"🤖 <b>[AGENT API]</b>\n<pre><a href=\"tg://user?id=0\">{safe}</a></pre>"
        else:
            return f"💻 <b>[CMD]</b>\n<pre><code>{safe}</code></pre>"

def send_to_telegram(msg: str, is_api: bool):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = {"chat_id": CHAT_ID, "text": msg, "parse_mode": "HTML"}
    return requests.post(url, data=data, timeout=10)

def worker_loop(q, is_api: bool):
    global current_delay, last_success
    while True:
        msg = q.get()
        if msg is None:
            break
        formatted = prepare_message(msg, is_api)
        debug_write(f"[{'API' if is_api else 'CMD'} POP] {msg}")
        try:
            r = send_to_telegram(formatted, is_api)
            if r.status_code == 429:
                try:
                    retry_after = json.loads(r.text).get("parameters", {}).get("retry_after", 5)
                except Exception:
                    retry_after = 5
                debug_write(f"[{'API' if is_api else 'CMD'}] Rate limited. Sleeping {retry_after}s")
                time.sleep(retry_after)
                q.put(msg)
                current_delay = min(MAX_DELAY, current_delay + 1)
            elif r.status_code != 200:
                debug_write(f"[{'API' if is_api else 'CMD'}] Error {r.status_code}: {r.text}")
            else:
                debug_write(f"[{'API' if is_api else 'CMD'} SENT] {msg}")
                last_success = time.time()
                if time.time() - last_success > 60:
                    current_delay = max(MIN_DELAY, current_delay - 1)
            time.sleep(current_delay)
        except Exception as e:
            debug_write(f"Error sending {'API' if is_api else 'CMD'}: {e}")
            time.sleep(2)
        finally:
            q.task_done()

def format_cmd(line: str) -> str:
    return f"root@gpt: {line.strip()}"

def format_api(line: str) -> str:
    return f"root@gpt: {line.strip()}"

def read_all_lines(file_path: str):
    try:
        with open(file_path, 'r') as f:
            return f.readlines()
    except FileNotFoundError:
        return []

def process_lines_every_cycle(file_path, formatter, is_api=False):
    lines = read_all_lines(file_path)
    for line in lines:
        clean = line.strip()
        if not clean:
            continue
        h = hashlib.sha256((clean + ("API" if is_api else "CMD")).encode()).hexdigest()
        if is_api:
            if h not in sent_api_hashes:
                sent_api_hashes.add(h)
                debug_write(f"[API DETECTED] {clean}")
                api_queue.put(formatter(clean))
        else:
            if h not in sent_cmd_hashes:
                sent_cmd_hashes.add(h)
                debug_write(f"[CMD DETECTED] {clean}")
                cmd_queue.put(formatter(clean))

def main():
    debug_write("Daemon started (recovered)...")
    threading.Thread(target=worker_loop, args=(cmd_queue, False), daemon=True).start()
    threading.Thread(target=worker_loop, args=(api_queue, True), daemon=True).start()
    while True:
        process_lines_every_cycle(COMMANDS_LOG, format_cmd, is_api=False)
        process_lines_every_cycle(API_LOG, format_api, is_api=True)
        time.sleep(2)

if __name__ == "__main__":
    main()
