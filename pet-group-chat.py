#!/usr/bin/env python3
"""pet-group-chat.py — Group chat engine for dual-pet conversations.

Receives conversation context via CLI or stdin JSON, returns next action.

CLI Usage:
  pet-group-chat.py                                    # Read JSON from stdin, output next action
  pet-group-chat.py --summarize                        # Summarize completed conversation

Input JSON (stdin):
{
  "pets": [
    {"name": "Duck", "personality": "cheerful and energetic", "thinking": "optimistic"},
    {"name": "Capybara", "personality": "calm and wise", "thinking": "analytical"}
  ],
  "history": [
    {"from": "user", "to": null, "content": "Let's discuss AI"},
    {"from": "Duck", "to": "user", "content": "Great topic!"}
  ],
  "last_message": {"from": "user", "to": null, "content": "What do you think?"}
}

Output JSON:
{
  "action": "reply" | "wait" | "done",
  "from": "Duck" | "Capybara" | null,
  "to": "user" | "Duck" | "Capybara" | null,
  "content": "...",
  "summary": "..."  // only when action == "done"
}
"""

import json, sys, os, urllib.request
from pathlib import Path

CONFIG_FILE = Path.home() / '.workbuddy' / 'duck-config.json'


def load_config():
    cfg = {'api_key': None, 'url': 'https://api.minimax.io/v1/chat/completions',
           'model': 'MiniMax-M2.7', 'use_local': False, 'local_port': 8090}
    if CONFIG_FILE.exists():
        try:
            d = json.loads(CONFIG_FILE.read_text())
            cfg['api_key'] = d.get('minimax_api_key') or d.get('llmApiKey') or d.get('openai_api_key')
            cfg['model'] = d.get('llmModel') or d.get('model', cfg['model'])
            if d.get('llmUrl'): cfg['url'] = d['llmUrl']
            cfg['local_port'] = d.get('localServerPort', 8090)
            # If a local LLM is configured, check if it's running
            if d.get('llmProvider') == 'local' or d.get('localModelName'):
                cfg['use_local'] = _check_local_server(cfg['local_port'])
        except Exception: pass
    return cfg


def _check_local_server(port=8090):
    """Quick check if local llama-server is healthy."""
    try:
        req = urllib.request.Request(f'http://127.0.0.1:{port}/health', method='GET')
        with urllib.request.urlopen(req, timeout=3) as resp:
            return resp.status == 200
    except Exception:
        return False


def call_local_llm(config, messages, max_tokens=400, temperature=0.7):
    """Call local llama-server via OpenAI-compatible API."""
    url = f'http://127.0.0.1:{config["local_port"]}/v1/chat/completions'
    payload = json.dumps({
        'messages': messages,
        'max_tokens': max_tokens,
        'temperature': temperature,
        'stream': False,
    }).encode()
    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())
        content = data['choices'][0]['message']['content'].strip()
        if content.startswith('<think>') and '</think>' in content:
            content = content.split('</think>', 1)[1].strip()
        return content


def call_llm(config, messages, max_tokens=400):
    if config.get('use_local'):
        return call_local_llm(config, messages, max_tokens)
    payload = json.dumps({
        'model': config['model'], 'messages': messages,
        'max_tokens': max_tokens, 'temperature': 0.7, 'stream': False
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


def decide_next_action(cfg, pets, history, last_message, round_count=1):
    """Determine what should happen next in the group conversation.
    
    For cloud LLMs: full prompt-based decision making.
    For local LLMs: code determines routing (who speaks to whom), LLM only generates content.
    """
    pet_names = [p['name'] for p in pets]
    pet_descriptions = '\n'.join(
        f"- {p['name']}: {p.get('personality', 'friendly')}, thinks in a {p.get('thinking', 'balanced')} way"
        for p in pets
    )

    # Format conversation for context
    conv_lines = []
    for msg in history:
        sender = msg.get('from', 'unknown')
        recipient = msg.get('to', '')
        content = msg.get('content', '')
        if recipient:
            conv_lines.append(f"{sender} → {recipient}: {content}")
        else:
            conv_lines.append(f"{sender}: {content}")

    conv_text = '\n'.join(conv_lines[-30:])

    # Count pet-to-pet messages since the LAST user message
    pet_to_pet_this_round = 0
    for msg in reversed(history):
        sender = msg.get('from', '')
        recipient = msg.get('to', '')
        if sender == 'user':
            break
        if sender in pet_names and recipient in pet_names:
            pet_to_pet_this_round += 1

    last_sender = last_message.get('from', 'unknown')
    last_content = last_message.get('content', '')

    # ─── ROUTING LOGIC ───────────────────────────────────
    # Determine WHO should speak and TO WHOM (code-enforced for reliability)
    route_from = None
    route_to = None
    route_action = 'reply'

    if last_sender == 'user':
        route_from = pet_names[0]
        route_to = pet_names[1]
    elif last_sender in pet_names:
        last_to = last_message.get('to', '')
        if last_to in pet_names:
            # Pet addressed another pet → the addressed pet replies
            route_from = last_to
            route_to = pet_names[1] if last_to == pet_names[0] else pet_names[0]
            if pet_to_pet_this_round >= 2 and pet_to_pet_this_round < 3:
                route_to = 'user'
            elif pet_to_pet_this_round >= 3:
                route_to = 'user'
        elif last_to == 'user':
            route_action = 'wait'
        else:
            route_action = 'wait'
    else:
        route_action = 'wait'

    is_local = cfg.get('use_local', False)

    # ─── CONTENT GENERATION ──────────────────────────────
    if route_action == 'wait':
        return {'action': 'wait', 'from': None, 'to': None, 'content': ''}

    if is_local:
        # Code routes the flow, LLM only generates the reply content
        content = _generate_pet_reply_local(cfg, pet_names, pet_descriptions, conv_text, last_content,
                                             pet_to_pet_this_round, route_from, route_to)
        return {'action': 'reply', 'from': route_from, 'to': route_to, 'content': content}
    else:
        # Cloud LLM does full decision-making via prompt
        result = _decide_via_prompt(cfg, pet_names, pet_descriptions, conv_text, 
                                     last_sender, last_content, pet_to_pet_this_round, round_count)
        return result


def _generate_pet_reply_local(cfg, pet_names, pet_descriptions, conv_text, last_content,
                                pet_to_pet_count, who, to_whom):
    """Generate a pet's reply using local LLM. Routing is already determined."""
    if to_whom == 'user':
        direction = f"Now it's time to wrap up the discussion. Reply to the user ({pet_names[0] if who == pet_names[0] else pet_names[1]}'s perspective), summarizing the discussion and inviting their input."
    else:
        direction = f"Reply to {to_whom} with your thoughts. Engage deeply — ask {to_whom} for their perspective."

    system_prompt = f"""You are {who}, a {pet_descriptions.split(who + ': ', 1)[-1].split('\n')[0] if who in pet_descriptions else 'friendly AI pet'}.

Context:
{conv_text}

{direction}

Write 1-2 sentences as {who}. Be playful, concise, and stay in character. Output ONLY the reply text, no JSON, no labels."""

    try:
        return call_llm(cfg, [
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': 'Write your reply.'}
        ], max_tokens=200)
    except Exception as e:
        return f"[{who} is thinking... {str(e)[:50]}]"


def _decide_via_prompt(cfg, pet_names, pet_descriptions, conv_text, 
                        last_sender, last_content, pet_to_pet_this_round, round_count):
    """Full decision-making via cloud LLM prompt."""
    system_prompt = f"""You are a group chat coordinator managing a lively conversation between two AI pets and a user. The user speaks occasionally, and when they do, the pets should have a REAL multi-turn discussion among themselves about the user's message.

Pets in this conversation:
{pet_descriptions}

Current conversation:
{conv_text if conv_text else '[No previous messages]'}

The last message was from "{last_sender}": "{last_content}"

ROUND INFO: This is round {round_count}. So far in THIS specific round, {pet_to_pet_this_round} pet-to-pet messages have been exchanged since the user last spoke.

CRITICAL RULE: Every time the user speaks, a NEW round begins. The pets MUST discuss the user's point with each other (pet-to-pet) for 2-4 exchanges BEFORE either pet addresses the user.

DECISION TREE (follow strictly):
1. If the LAST message was from the USER:
   → {pet_names[0]} replies. They ALWAYS address {pet_names[1]} (NOT the user).
   → Share thoughts on the user's point and ask for the other pet's perspective.
   
2. If the LAST message was from a pet TO another pet:
   → The addressed pet MUST reply.
   → If pet-to-pet count < 3: reply to the OTHER pet (continue discussion).
   → If pet-to-pet count >= 3: reply to the USER (wrap up the discussion).
   
3. If a pet addressed the USER → Signal WAIT.

4. Signal DONE only when user says goodbye.

Respond in JSON format only:
{{"action": "reply"|"wait"|"done", "from": "pet_name", "to": "other_pet_name"|"user", "content": "response message"}}"""

    try:
        response = call_llm(cfg, [
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': 'What should happen next? Reply with JSON only.'}
        ], max_tokens=500)

        response = response.strip()
        if response.startswith('```'):
            response = response.split('\n', 1)[1].rsplit('\n```', 1)[0] if '```' in response[3:] else response[3:]
            response = response.replace('```', '').strip()
        return json.loads(response)
    except json.JSONDecodeError as e:
        return {'action': 'wait', 'from': None, 'to': None, 'content': '', 'error': f'JSON parse: {str(e)[:100]}'}
    except Exception as e:
        return {'action': 'wait', 'from': None, 'to': None, 'content': '', 'error': str(e)[:100]}


def summarize_conversation(cfg, pets, history):
    """Summarize the completed conversation and extract insights about the user."""
    pet_names = ', '.join(p['name'] for p in pets)

    conv_lines = []
    for msg in history:
        sender = msg.get('from', 'unknown')
        recipient = msg.get('to', '')
        content = msg.get('content', '')
        if recipient:
            conv_lines.append(f"{sender}→{recipient}: {content}")
        else:
            conv_lines.append(f"{sender}: {content}")

    conv_text = '\n'.join(conv_lines)

    prompt = f"""You are a conversation summarizer. Below is a group chat transcript between a user and two AI pets ({pet_names}).

Conversation:
{conv_text[-5000:]}

Write a concise summary (2-3 paragraphs) covering:
1. Main topics discussed
2. Key insights or decisions
3. The user's opinions, preferences, or personality traits revealed
4. Any notable interactions between the pets

Format as plain text, no markdown headers."""

    try:
        return call_llm(cfg, [{'role': 'user', 'content': prompt}], max_tokens=600)
    except Exception as e:
        return f"Summary unavailable: {e}"


def main():
    cfg = load_config()
    if not cfg['api_key'] and not cfg.get('use_local'):
        print(json.dumps({'error': 'No API key configured and local LLM is not running'}))
        sys.exit(1)

    data = json.loads(sys.stdin.read()) if not sys.stdin.isatty() else {}

    # --summarize mode: just summarize existing history
    if '--summarize' in sys.argv:
        pets = data.get('pets', [])
        history = data.get('history', [])
        summary = summarize_conversation(cfg, pets, history)
        print(json.dumps({'action': 'done', 'summary': summary}))
        return

    # Normal mode: determine next action
    pets = data.get('pets', [
        {'name': 'Duck', 'personality': 'cheerful and energetic', 'thinking': 'optimistic'},
        {'name': 'Capybara', 'personality': 'calm and wise', 'thinking': 'analytical'}
    ])
    history = data.get('history', [])
    last_message = data.get('last_message', {})
    round_count = data.get('round_count', 1)

    if not last_message:
        print(json.dumps({'error': 'No last_message provided'}))
        sys.exit(1)

    result = decide_next_action(cfg, pets, history, last_message, round_count)

    # If conversation is done, also generate summary
    if result.get('action') == 'done':
        summary = summarize_conversation(cfg, pets, history)
        result['summary'] = summary
    elif result.get('action') == 'reply':
        # Ensure the response fits within max length
        if result.get('content') and len(result['content']) > 500:
            result['content'] = result['content'][:497] + '...'

    print(json.dumps(result))


if __name__ == '__main__':
    main()
