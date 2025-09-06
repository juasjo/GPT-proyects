#!/usr/bin/env python3
import sys
import os
from datetime import datetime

BASE_DIR = os.path.dirname(__file__)
API_LOG = os.path.join(BASE_DIR, 'api_actions.log')

def log_action(action: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"root@gpt: {action} ({timestamp})\n"
    with open(API_LOG, 'a') as f:
        f.write(line)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: api_logger.py <action>")
        sys.exit(1)
    action = sys.argv[1]
    log_action(action)
