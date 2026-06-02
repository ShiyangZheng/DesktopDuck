#!/usr/bin/env python3
"""pet-generate-character.py — Generate a character image via MiniMax API and create a pet animation.

Usage: pet-generate-character.py "a cute pixel art cat, white background"
  --output-dir DIR   Output directory (default: ~/.workbuddy/duck-custom/)

Outputs idle.gif in the output directory.
Also saves the original generated image as original.png.
"""

import json, sys, os, urllib.request, io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

CONFIG_FILE = Path.home() / '.workbuddy' / 'duck-config.json'
DEFAULT_OUTPUT = Path.home() / '.workbuddy' / 'duck-custom'

# Character dimensions for the pet (matches the GIF sprite size)
SPRITE_W, SPRITE_H = 64, 64
# Pad the canvas for movement
CANVAS_W, CANVAS_H = 80, 80

def load_config():
    cfg = {'api_key': None, 'url': 'https://api.minimax.io/v1/image_generation'}
    if CONFIG_FILE.exists():
        try:
            d = json.loads(CONFIG_FILE.read_text())
            cfg['api_key'] = d.get('minimax_api_key') or d.get('openai_api_key')
        except Exception: pass
    return cfg


def generate_image(config, prompt):
    """Call MiniMax image generation API, return image URL."""
    payload = json.dumps({
        'model': 'image-01',
        'prompt': prompt + ', game sprite asset, simple flat design, white background, chibi style, full body, centered, small character',
        'aspect_ratio': '1:1',
        'n': 1,
        'response_format': 'url'
    }).encode()

    req = urllib.request.Request(config['url'], data=payload, headers={
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {config["api_key"]}'
    })

    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())

    if 'data' in data and 'image_urls' in data['data']:
        return data['data']['image_urls'][0]

    raise RuntimeError(f'Unexpected API response: {json.dumps(data)[:300]}')


def download_image(url):
    """Download image from URL, return PIL Image."""
    with urllib.request.urlopen(url, timeout=30) as resp:
        return Image.open(io.BytesIO(resp.read()))


def resize_to_sprite(img):
    """Resize image to sprite dimensions, preserving aspect ratio."""
    # Convert to RGBA for transparency support
    img = img.convert('RGBA')

    # Fit within sprite bounds while keeping aspect ratio
    img.thumbnail((SPRITE_W, SPRITE_H), Image.LANCZOS)

    # Create a centered canvas
    canvas = Image.new('RGBA', (SPRITE_W, SPRITE_H), (0, 0, 0, 0))
    x = (SPRITE_W - img.width) // 2
    y = (SPRITE_H - img.height) // 2
    canvas.paste(img, (x, y), img)

    return canvas


def create_idle_gif(sprite):
    """Create idle animation: subtle bounce + breathing."""
    frames = []
    offsets = [
        (0, 0),     # normal
        (0, -2),    # up
        (0, 0),     # normal
        (0, 1),     # slight down
    ]
    scales = [1.0, 1.04, 1.0, 0.97]

    for (ox, oy), scale in zip(offsets, scales):
        frame = Image.new('RGBA', (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
        # Scale sprite
        sw = int(SPRITE_W * scale)
        sh = int(SPRITE_H * scale)
        scaled = sprite.resize((sw, sh), Image.LANCZOS)
        # Center on canvas with offset
        x = (CANVAS_W - sw) // 2 + ox
        y = (CANVAS_H - sh) // 2 + oy
        frame.paste(scaled, (x, y), scaled)
        frames.append(frame)

    return frames


def save_gif(frames, path, duration=200):
    """Save frames as animated GIF."""
    # Convert frames to palette mode for smaller GIFs
    paletted = []
    for f in frames:
        # Quantize to reduce colors
        p = f.convert('P', palette=Image.ADAPTIVE, colors=64)
        paletted.append(p)
    paletted[0].save(
        path, save_all=True, append_images=paletted[1:],
        duration=duration, loop=0, disposal=2, optimize=True
    )


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        sys.exit(1)

    prompt = sys.argv[1]
    output_dir = DEFAULT_OUTPUT

    # Parse --output-dir
    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == '--output-dir' and i + 1 < len(args):
            output_dir = Path(args[i + 1])
            i += 2
        else:
            i += 1

    output_dir.mkdir(parents=True, exist_ok=True)
    original_path = output_dir / 'original.png'
    idle_path = output_dir / 'idle.gif'

    cfg = load_config()
    if not cfg['api_key']:
        print(json.dumps({'error': 'No API key configured'}))
        sys.exit(1)

    try:
        # 1. Generate image
        print('Generating character image...', file=sys.stderr)
        image_url = generate_image(cfg, prompt)
        print(f'Image URL received', file=sys.stderr)

        # 2. Download
        print('Downloading...', file=sys.stderr)
        img = download_image(image_url)

        # Save original
        img.save(original_path)
        print(f'Original saved: {original_path}', file=sys.stderr)

        # 3. Resize to sprite
        sprite = resize_to_sprite(img)

        # 4. Create animated GIF
        print('Creating animation...', file=sys.stderr)
        idle_frames = create_idle_gif(sprite)
        save_gif(idle_frames, idle_path, duration=200)

        print(json.dumps({
            'success': True,
            'original': str(original_path),
            'idle': str(idle_path)
        }))

    except Exception as e:
        print(json.dumps({'error': str(e)}))
        sys.exit(1)


if __name__ == '__main__':
    main()
