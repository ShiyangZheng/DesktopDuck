#!/usr/bin/env python3
"""pet-journal-summary.py — Generate iterative document from journal sessions.

Concept: Each journal template is an evolving document, not a list of entries.
New sessions append to and enrich the existing document via AI summarization.

Usage:
  pet-journal-summary.py <template_name>   # Update document for specific template
  pet-journal-summary.py --all             # Update all documents

Data model (journal.json):
{
  "documents": {
    "Template Name": {
      "template": "Template Name",
      "content": "Iteratively growing markdown document",
      "sessions": [ [transcript_history] ],
      "updated_at": "ISO timestamp",
      "created_at": "ISO timestamp"
    }
  }
}
"""

import json, sys, os, urllib.request
from pathlib import Path
from datetime import datetime

JOURNAL_FILE = Path.home() / '.workbuddy' / 'journal.json'
CONFIG_FILE = Path.home() / '.workbuddy' / 'duck-config.json'


def load_config():
    cfg = {'api_key': None, 'url': 'https://api.minimax.io/v1/chat/completions',
           'model': 'MiniMax-M2.7'}
    for key in ['MINIMAX_API_KEY', 'OPENAI_API_KEY']:
        if os.environ.get(key): cfg['api_key'] = os.environ[key]; break
    if CONFIG_FILE.exists():
        try:
            d = json.loads(CONFIG_FILE.read_text())
            cfg['api_key'] = d.get('minimax_api_key') or d.get('openai_api_key') or cfg['api_key']
            cfg['model'] = d.get('model', cfg['model'])
            if d.get('minimax_url'): cfg['url'] = d['minimax_url']
        except Exception: pass
    return cfg


def load_journal():
    if not JOURNAL_FILE.exists(): return {'documents': {}}
    try: return json.loads(JOURNAL_FILE.read_text())
    except: return {'documents': {}}


def save_journal(data):
    JOURNAL_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2))


def call_llm(config, messages, max_tokens=800):
    payload = json.dumps({
        'model': config['model'], 'messages': messages,
        'max_tokens': max_tokens, 'temperature': 0.5, 'stream': False
    }).encode()
    req = urllib.request.Request(config['url'], data=payload,
        headers={'Content-Type': 'application/json',
                 'Authorization': f'Bearer {config["api_key"]}'})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())
        content = data['choices'][0]['message']['content'].strip()
        if content.startswith('<think>') and '</think>' in content:
            content = content.split('</think>', 1)[1].strip()
        return content


def update_document(cfg, template_name):
    """Iteratively update a journal document by incorporating the latest session."""
    journal = load_journal()
    docs = journal.get('documents', {})
    doc = docs.get(template_name, None)

    if not doc or not doc.get('sessions'):
        return None

    sessions = doc.get('sessions', [])
    # Get the latest session (last one without a processed flag)
    unprocessed = [s for s in sessions if not s.get('processed')]
    if not unprocessed:
        return doc.get('content', '')

    latest = unprocessed[-1]
    transcript = latest.get('transcript', [])
    if not transcript:
        return doc.get('content', '')

    # Format conversation
    lines = []
    for t in transcript[-20:]:  # Last 20 exchanges
        role = t.get('role', '?')
        content = t.get('content', '')
        lines.append(f"[{role}] {content}")
    conv_text = '\n'.join(lines)

    existing_content = doc.get('content', '')

    prompt = f"""You are a journal curator. Below is an existing journal document, followed by a new conversation session on the same topic.

Your task: Update and enrich the document to incorporate the new insights, themes, and decisions from this session.

Rules:
1. Keep the document as a coherent, flowing narrative (not a log)
2. Integrate new insights naturally into the existing structure
3. Preserve all important information from previous iterations
4. Use clear markdown headings and formatting
5. End with a "Latest Reflections" section highlighting what's new

Existing Document:
{existing_content[:4000] if existing_content else '[New document - no existing content]'}

New Conversation:
{conv_text[-4000:]}

Updated Document (in markdown):"""

    try:
        new_content = call_llm(cfg, [{'role': 'user', 'content': prompt}], max_tokens=1200)

        # Mark session as processed
        for s in unprocessed:
            s['processed'] = True

        # Update document
        doc['content'] = new_content
        doc['sessions'] = sessions
        doc['updated_at'] = datetime.now().isoformat()

        if 'documents' not in journal:
            journal['documents'] = {}
        journal['documents'][template_name] = doc
        save_journal(journal)

        return new_content
    except Exception as e:
        print(f"Error updating document: {e}", file=sys.stderr)
        return None


def create_document(template_name, transcript):
    """Create initial document from first session."""
    journal = load_journal()
    now = datetime.now().isoformat()

    doc = {
        'template': template_name,
        'content': '',
        'sessions': [{'time': now, 'transcript': transcript, 'processed': False}],
        'updated_at': now,
        'created_at': now
    }

    if 'documents' not in journal:
        journal['documents'] = {}
    journal['documents'][template_name] = doc
    save_journal(journal)

    return doc


def main():
    cfg = load_config()
    if not cfg['api_key']:
        print("No API key configured", file=sys.stderr)
        return

    target = sys.argv[1] if len(sys.argv) > 1 else '--all'

    journal = load_journal()
    docs = journal.get('documents', {})

    if target == '--all':
        templates = list(docs.keys())
    else:
        templates = [target]

    for tpl in templates:
        if tpl not in docs:
            print(f"⚠️  No document for template: {tpl}", file=sys.stderr)
            continue
        try:
            result = update_document(cfg, tpl)
            if result:
                print(f"✅ Updated: {tpl}")
                print(json.dumps({'template': tpl, 'updated': True, 'preview': result[:200] + '...'}))
            else:
                print(f"⏭️  No new sessions for: {tpl}")
        except Exception as e:
            print(f"❌ Error for {tpl}: {e}", file=sys.stderr)


if __name__ == '__main__':
    main()
