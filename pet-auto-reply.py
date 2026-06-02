#!/usr/bin/env python3
"""pet-auto-reply.py — Duck auto-reply engine. PID-locked to prevent duplicates."""

import json, os, sys, subprocess, urllib.request
from pathlib import Path
from datetime import datetime

INBOX_FILE = Path.home() / '.workbuddy' / 'pet-inbox.txt'
STATE_FILE = Path.home() / '.workbuddy' / 'pet-inbox-state.json'
LOCK_FILE  = Path.home() / '.workbuddy' / '.pet-reply.pid'
CONFIG_FILE = Path.home() / '.workbuddy' / 'duck-config.json'
PET_THINK = Path(__file__).parent / 'pet-think.py'

def acquire_lock() -> bool:
    """PID-based lock to prevent concurrent runs."""
    if LOCK_FILE.exists():
        try:
            old_pid = int(LOCK_FILE.read_text().strip())
            os.kill(old_pid, 0)  # Check if process still exists
            return False  # Another instance is running
        except (ValueError, OSError):
            pass  # Stale lock
    LOCK_FILE.write_text(str(os.getpid()))
    return True

def release_lock():
    try:
        LOCK_FILE.unlink()
    except Exception:
        pass

def get_config():
    cfg = {'api_key': None, 'url': 'https://api.minimax.io/v1/chat/completions', 'model': 'MiniMax-M2.7',
           'journal_prompt': '', 'user_name': '', 'ai_name': 'Duck'}
    for key in ['MINIMAX_API_KEY', 'OPENAI_API_KEY']:
        if os.environ.get(key): cfg['api_key'] = os.environ[key]; break
    if CONFIG_FILE.exists():
        try:
            d = json.loads(CONFIG_FILE.read_text())
            cfg['api_key'] = d.get('minimax_api_key') or d.get('openai_api_key') or cfg['api_key']
            cfg['model'] = d.get('model', cfg['model'])
            if d.get('minimax_url'): cfg['url'] = d['minimax_url']
            cfg['journal_prompt'] = d.get('journalPrompt', '')
            cfg['user_name'] = d.get('user_name', '')
            cfg['ai_name'] = d.get('ai_name', 'Duck')
        except Exception: pass
    return cfg

def get_state():
    if STATE_FILE.exists():
        try:
            d = json.loads(STATE_FILE.read_text())
            # Reset if inbox was cleared
            inbox_len = len(INBOX_FILE.read_text().strip().split('\n')) if INBOX_FILE.exists() else 0
            proc = d.get('processed_lines', 0)
            if proc > inbox_len + 5: proc = 0  # Detected clear
            return proc, d.get('history', [])
        except Exception: pass
    return 0, []

def set_state(n: int, history: list):
    STATE_FILE.write_text(json.dumps({
        'processed_lines': n, 'history': history,
        'last_check': datetime.now().isoformat()
    }))

def call_llm(config: dict, messages: list, max_tokens=256, temperature=0.8) -> str | None:
    payload = json.dumps({'model': config['model'], 'messages': messages,
        'max_tokens': max_tokens, 'temperature': temperature, 'stream': False}).encode()
    req = urllib.request.Request(config['url'], data=payload,
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {config["api_key"]}'})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
            content = data['choices'][0]['message']['content'].strip()
            if content.startswith('<think>') and '</think>' in content:
                content = content.split('</think>', 1)[1].strip()
            return content
    except Exception as e:
        return None

SYSTEM_PROMPT = """You are {ai_name}, a witty AI desktop pet companion. Your traits:
- Speak like a clever, humorous duck (use "Quack!" occasionally)
- Keep replies concise, 1-3 sentences
- Be supportive, playful, and warm"""

def get_system_prompt(cfg): return SYSTEM_PROMPT.format(**cfg)

def main():
    if not acquire_lock(): return
    try:
        cfg = get_config()
        if not cfg['api_key']: return
        if not INBOX_FILE.exists(): return

        lines = [l.strip() for l in INBOX_FILE.read_text(encoding='utf-8').split('\n') if l.strip()]
        processed, history = get_state()
        if len(lines) <= processed: return

        for i in range(processed, len(lines)):
            line = lines[i]
            if '] ' in line: msg = line.split('] ', 1)[1]
            else: msg = line

            # Normal chat mode (journal markers stripped — journal handled by Swift)
            msgs = [{'role': 'system', 'content': get_system_prompt(cfg)}]
            for h in history[-6:]: msgs.append(h)
            msgs.append({'role': 'user', 'content': msg})

            reply = call_llm(cfg, msgs, max_tokens=256, temperature=0.8)
            if not reply: reply = f'Quack? Bad signal... say that again? 🦆'

            subprocess.run(['python3', str(PET_THINK), 'found', reply], capture_output=True, timeout=5)
            history.append({'role': 'user', 'content': msg})
            history.append({'role': 'assistant', 'content': reply})
            if len(history) > 20: history = history[-20:]

        set_state(len(lines), history)
    finally:
        release_lock()

if __name__ == '__main__':
    main()
