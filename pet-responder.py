#!/usr/bin/env python3
"""
pet-responder.py — 监控鸭子的收件箱并自动回复
定时检查 ~/.workbuddy/pet-inbox.txt 的新消息，推送确认气泡。
"""

import json, os, sys, subprocess, time
from pathlib import Path
from datetime import datetime

INBOX_FILE = Path.home() / '.workbuddy' / 'pet-inbox.txt'
STATE_FILE = Path.home() / '.workbuddy' / 'pet-inbox-state.json'
PET_THINK = Path(__file__).parent / 'pet-think.py'


def get_state() -> int:
    """返回已处理的行数"""
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text()).get('processed_lines', 0)
        except Exception:
            pass
    return 0


def set_state(n: int):
    STATE_FILE.write_text(json.dumps({'processed_lines': n}))


def main():
    if not INBOX_FILE.exists():
        return

    lines = INBOX_FILE.read_text(encoding='utf-8').strip().split('\n')
    processed = get_state()

    if len(lines) <= processed:
        return  # nothing new

    # Process new messages
    for i in range(processed, len(lines)):
        line = lines[i].strip()
        if not line:
            continue
        # Extract message text (after timestamp)
        # Format: "[2026-06-02 07:30:00] hello world"
        if '] ' in line:
            msg = line.split('] ', 1)[1]
        else:
            msg = line

        # Push acknowledgement bubble to duck
        subprocess.run([
            'python3', str(PET_THINK), 'found',
            f'收到：{msg[:30]}{"..." if len(msg) > 30 else ""}'
        ], capture_output=True, timeout=5)

    set_state(len(lines))


if __name__ == '__main__':
    main()
