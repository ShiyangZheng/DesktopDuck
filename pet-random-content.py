#!/usr/bin/env python3
"""
pet-random-content.py — 单击鸭子时生成随机有趣内容
调用 MiniMax API，每次随机选一个主题生成 1-3 句内容。
"""

import json, os, sys, subprocess, urllib.request, random
from pathlib import Path

CONFIG_FILE = Path.home() / '.workbuddy' / 'duck-config.json'
PET_THINK = Path(__file__).parent / 'pet-think.py'

TOPICS = [
    "给诗扬一个关于心理语言学或眼动研究的冷知识，让他学到新东西。1-3句中英文都行，有趣不枯燥。",
    "作为一只鸭子桌面助手，给诗扬一个今天的研究小建议——关于他的习语习得或计算建模。实用具体。",
    "用一个幽默的方式提醒诗扬注意工作健康：站起来走走、喝水、远眺。要有趣，1-2句。",
    "分享一个有趣的中文习语或英文idiom，解释它的含义。像语言学研究生之间聊天。",
    "给诗扬一个摄影小技巧，构图或光线方面的。他喜欢摄影。1-2句。",
    "一句有哲理的鼓励，适合博士生。不要太鸡汤，像朋友间随口一句。",
    "假装你是诗扬的学术伙伴，提一个研究上可以探索的新方向或方法。有创意但实际。",
    "用鸭子的口吻分享一个关于诺丁汉或英国的趣事。1-2句，轻松有趣。",
    "给诗扬推荐一个今天可以听的播客主题或音乐风格。他做播客的，给出制作灵感。",
    "调侃一下诗扬今天的工作状态（你通过截图看到的），给一个搞笑的观察。",
    "一个关于R语言或数据科学的小技巧，适用于他的数据分析工作。简短实用。",
    "假装你看到诗扬的桌面上有什么，做一个搞笑的评论。要真诚但不冒犯。",
]

def main():
    cfg = {'api_key': None, 'url': 'https://api.minimax.io/v1/chat/completions', 'model': 'MiniMax-M2.7'}
    if CONFIG_FILE.exists():
        try:
            d = json.loads(CONFIG_FILE.read_text())
            cfg['api_key'] = d.get('minimax_api_key') or d.get('openai_api_key')
        except Exception:
            pass
    if not cfg['api_key']:
        print('No API key', file=sys.stderr)
        return

    topic = random.choice(TOPICS)
    payload = json.dumps({
        'model': cfg['model'],
        'messages': [{
            'role': 'system',
            'content': '你是诗扬桌面上的鸭子助手鸭鸭。回答自然、有趣、个人化，像研究生室友聊天。永远不说"作为一只鸭子"或"作为AI"之类的话。1-3句。'
        }, {
            'role': 'user',
            'content': topic
        }],
        'max_tokens': 300,
        'temperature': 0.9
    }).encode()

    req = urllib.request.Request(
        cfg['url'],
        data=payload,
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {cfg["api_key"]}'}
    )

    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read())
            content = data['choices'][0]['message']['content'].strip()
            # Strip MiniMax think tags
            if '</think>' in content:
                parts = content.split('</think>', 1)
                content = parts[1].strip() if len(parts) > 1 else content
            if not content:
                content = '嘎？脑子卡了一下...再来试试？🦆'
            # Push to duck
            subprocess.run(['python3', str(PET_THINK), 'found', content],
                           capture_output=True, timeout=5)
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)


if __name__ == '__main__':
    main()
