#!/usr/bin/env python3
"""pet-think — write thoughts to the duck pet.
Usage:
  pet-think.py <type> <text>              # normal thought
  pet-think.py permission <text> [id]     # permission request (auto-generates id if omitted)
"""

import json, sys, os, uuid
from pathlib import Path
from datetime import datetime

THOUGHTS_FILE = Path.home() / '.workbuddy' / 'pet-thoughts.json'
RESPONSE_FILE = Path.home() / '.workbuddy' / 'pet-response.json'

if len(sys.argv) < 2:
    print("Usage: pet-think.py <type> <text>")
    print("  type: thinking | analyzing | searching | found | writing | working | done | permission")
    print("  permission: pet-think.py permission '需要访问文件' [action_id]")
    sys.exit(1)

thought_type = sys.argv[1]

if thought_type == 'permission':
    # permission: pet-think.py permission "text" [action_id]
    text = sys.argv[2] if len(sys.argv) > 2 else '需要授权继续操作'
    action_id = sys.argv[3] if len(sys.argv) > 3 else str(uuid.uuid4())[:8]
else:
    text = ' '.join(sys.argv[2:]) if len(sys.argv) > 2 else '...'
    action_id = None
now = datetime.now().strftime('%H:%M:%S')

THOUGHTS_FILE.parent.mkdir(parents=True, exist_ok=True)

thoughts = []
if THOUGHTS_FILE.exists():
    try:
        thoughts = json.loads(THOUGHTS_FILE.read_text())
    except json.JSONDecodeError:
        pass

entry = {'time': now, 'type': thought_type, 'text': text}
if thought_type == 'permission':
    entry['action_id'] = action_id
    print(f"🔐 Permission [{action_id}]: {text}")
    print(f"   Response → {RESPONSE_FILE}")

thoughts.append(entry)
if len(thoughts) > 50:
    thoughts = thoughts[-50:]

THOUGHTS_FILE.write_text(json.dumps(thoughts, ensure_ascii=False, indent=2))
if thought_type != 'permission':
    print(f"✅ [{thought_type}] {text}")
