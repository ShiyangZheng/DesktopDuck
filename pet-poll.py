#!/usr/bin/env python3
"""pet-poll — poll for permission response from duck pet.
Usage: python3 pet-poll.py [action_id] [timeout_seconds]

Returns JSON to stdout: {"response": "allow"|"deny"|"timeout"|null}
Exit code 0 = response received, 1 = still waiting, 2 = timed out
"""

import json, sys, time
from pathlib import Path

RESPONSE_FILE = Path.home() / '.workbuddy' / 'pet-response.json'
action_id = sys.argv[1] if len(sys.argv) > 1 else None
timeout = int(sys.argv[2]) if len(sys.argv) > 2 else 30

start = time.time()
while time.time() - start < timeout:
    if RESPONSE_FILE.exists():
        try:
            data = json.loads(RESPONSE_FILE.read_text())
            if action_id is None or data.get('action_id') == action_id:
                resp = data.get('response', 'null')
                print(json.dumps(data))
                # Clear the response file
                RESPONSE_FILE.write_text('{}')
                sys.exit(0 if resp == 'allow' else 1)
        except Exception:
            pass
    time.sleep(0.5)

print('{"response": "timeout"}')
sys.exit(2)
