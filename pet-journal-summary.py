#!/usr/bin/env python3
"""pet-journal-summary.py — Generate AI summary for a specific journal entry or all pending ones.
Usage: pet-journal-summary.py <timestamp>   OR   pet-journal-summary.py --all
The timestamp identifies which entry in journal.json to update."""

import json, sys, os, urllib.request
from pathlib import Path

JOURNAL_FILE = Path.home() / '.workbuddy' / 'journal.json'
CONFIG_FILE = Path.home() / '.workbuddy' / 'duck-config.json'


def load_config():
    cfg = {'api_key': None, 'url': 'https://api.minimax.io/v1/chat/completions', 'model': 'MiniMax-M2.7'}
    if CONFIG_FILE.exists():
        try:
            d = json.loads(CONFIG_FILE.read_text())
            cfg['api_key'] = d.get('minimax_api_key') or d.get('openai_api_key')
            cfg['model'] = d.get('model', cfg['model'])
            if d.get('minimax_url'): cfg['url'] = d['minimax_url']
        except Exception: pass
    return cfg


def load_entries():
    if not JOURNAL_FILE.exists(): return []
    try: return json.loads(JOURNAL_FILE.read_text())
    except: return []


def save_entries(entries):
    JOURNAL_FILE.write_text(json.dumps(entries, ensure_ascii=False, indent=2))


def call_llm(config, messages, max_tokens=500):
    payload = json.dumps({'model': config['model'], 'messages': messages,
        'max_tokens': max_tokens, 'temperature': 0.5, 'stream': False}).encode()
    req = urllib.request.Request(config['url'], data=payload,
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {config["api_key"]}'})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
        content = data['choices'][0]['message']['content'].strip()
        if content.startswith('<think>') and '</think>' in content:
            content = content.split('</think>', 1)[1].strip()
        return content


def summarize_entry(cfg, entry):
    transcript = entry.get('transcript', [])
    if not transcript: return None
    
    lines = []
    for t in transcript:
        role = t.get('role', '?')
        content = t.get('content', '')
        lines.append(f"[{role}] {content}")
    conv_text = '\n'.join(lines)
    
    template = entry.get('template', 'Journal')
    prompt = f"""You are a journal analyst. Below is a conversation between a user and their {template} journaling companion.
Write a concise summary (2-3 paragraphs) covering:
1) Key themes and emotions expressed
2) Main insights or breakthroughs  
3) Actionable takeaways or growth areas

Conversation:
{conv_text[-3000:]}

Summary:"""
    
    return call_llm(cfg, [{'role': 'user', 'content': prompt}], max_tokens=500)


def main():
    cfg = load_config()
    if not cfg['api_key']:
        print("No API key configured", file=sys.stderr)
        return
    
    entries = load_entries()
    if not entries:
        return
    
    updated = False
    target_ts = None if len(sys.argv) < 2 else sys.argv[1]
    
    for entry in entries:
        ts = entry.get('time', '')
        summary = entry.get('summary', '')
        
        # Skip entries that already have a real summary
        if summary and summary not in ('[Generating summary...]', '', 'Summary pending...'):
            continue
        
        if target_ts and target_ts != '--all' and ts != target_ts:
            continue
        
        try:
            summary = summarize_entry(cfg, entry)
            if summary:
                entry['summary'] = summary
                updated = True
                print(f"✅ Generated summary for {ts}")
            else:
                entry['summary'] = '[Summary generation failed]'
                print(f"❌ Failed to summarize {ts}")
        except Exception as e:
            entry['summary'] = f'[Error: {e}]'
            print(f"❌ Error for {ts}: {e}")
    
    if updated:
        save_entries(entries)
        print("Saved!")


if __name__ == '__main__':
    main()
