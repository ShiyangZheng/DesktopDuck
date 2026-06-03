#!/usr/bin/env python3
"""pet-generate-character.py — Generate a pixel art spritesheet via AI → auto-convert to per-state animation GIFs.

CLI Mode:
  pet-generate-character.py "cute yellow duck"                   # Generate spritesheet + convert
  pet-generate-character.py "cute yellow duck" --output-dir DIR

HTTP Server Mode:
  pet-generate-character.py --http [--port 8765]                # Start API server
  Then open spritesheet-editor.html in browser

Output JSON (CLI):
  {"success": true, "spritesheet": "/path/to/spritesheet.png",
   "states": {"idle": "/path/to/idle.gif", "walking": "/path/to/walking.gif", ...}}
"""

import json, sys, os, urllib.request, io, argparse, base64, traceback, tempfile
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from PIL import Image

CONFIG_FILE = Path.home() / '.workbuddy' / 'duck-config.json'
DEFAULT_OUTPUT = Path.home() / '.workbuddy' / 'duck-custom'
DEFAULT_PORT = 8765

# State definitions: (name, row_index, default_cols, fps, frame_duration_ms)
# These are defaults; user can override via state_names and cols parameter
DEFAULT_STATES = [
    ("idle",      0, 4, 10, 100),
    ("walking",   1, 4, 10, 100),
    ("thinking",  2, 3, 10, 100),
    ("happy",     3, 2, 10, 100),
    ("sleepy",    4, 2, 10, 100),
    ("surprised", 5, 2, 10, 100),
]

CANVAS_W, CANVAS_H = 80, 80

# MiniMax image-01 supported aspect ratios
ASPECT_RATIOS = ['1:1', '3:2', '2:3', '3:4', '4:3', '4:5', '5:4', '9:16', '16:9', '21:9']


def pick_aspect_ratio(cols, rows):
    """Choose best MiniMax aspect ratio for a cols×rows grid."""
    if rows <= 0 or cols <= 0:
        return '1:1'
    ratio = cols / rows
    # Map ratio ranges to supported aspect ratios
    if ratio > 3.0:        return '21:9'
    elif ratio > 2.0:      return '16:9'
    elif ratio > 1.5:      return '3:2'
    elif ratio > 0.66:     return '1:1'
    elif ratio > 0.55:     return '4:5'
    elif ratio > 0.5:      return '9:16'
    else:                  return '2:3'


def remove_background(img, threshold=30):
    """Remove near-white background from a PIL RGBA image.
    Samples edges to find dominant background color, then makes matching
    pixels (within `threshold` Euclidean distance) transparent.
    Returns new RGBA image.
    """
    img = img.convert('RGBA')
    w, h = img.size
    pixels = img.load()

    # Sample edge pixels to find background color
    edge_pixels = []
    border = max(1, min(w, h) // 40)
    # Top and bottom edges
    for x in range(0, w, 3):
        for y in range(0, min(border, h)):
            r, g, b, a = pixels[x, y]
            if a > 0: edge_pixels.append((r, g, b))
        for y in range(max(0, h - border), h):
            r, g, b, a = pixels[x, y]
            if a > 0: edge_pixels.append((r, g, b))
    # Left and right edges
    for y in range(0, h, 3):
        for x in range(0, min(border, w)):
            r, g, b, a = pixels[x, y]
            if a > 0: edge_pixels.append((r, g, b))
        for x in range(max(0, w - border), w):
            r, g, b, a = pixels[x, y]
            if a > 0: edge_pixels.append((r, g, b))

    if not edge_pixels:
        return img  # already fully transparent?

    # Find most common color among edge samples
    from collections import Counter
    # Quantize to reduce noise
    quantized = [(r // 10 * 10, g // 10 * 10, b // 10 * 10) for r, g, b in edge_pixels]
    most_common = Counter(quantized).most_common(1)[0][0]
    bg_r, bg_g, bg_b = most_common

    # Make matching pixels transparent
    new_data = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a > 0 and abs(r - bg_r) < threshold and abs(g - bg_g) < threshold and abs(b - bg_b) < threshold:
                new_data.append((0, 0, 0, 0))
            else:
                new_data.append((r, g, b, a))

    img2 = Image.new('RGBA', (w, h))
    img2.putdata(new_data)
    return img2


def load_config():
    cfg = {'api_key': None, 'url': 'https://api.minimax.io/v1/image_generation'}
    if CONFIG_FILE.exists():
        try:
            d = json.loads(CONFIG_FILE.read_text())
            cfg['api_key'] = d.get('minimax_api_key') or d.get('openai_api_key')
        except Exception:
            pass
    return cfg


def generate_spritesheet(config, prompt, rows=6, cols=4):
    """Call MiniMax image generation API → return image URL."""
    aspect = pick_aspect_ratio(cols, rows)

    # Build layout description
    if rows == 1:
        layout = f"a single horizontal row of {cols} frames from left to right"
        frame_desc = f"{cols} sequential animation poses in one row"
    elif cols == 1:
        layout = f"a single vertical column of {rows} frames from top to bottom"
        frame_desc = f"{rows} sequential animation poses in one column"
    else:
        layout = f"a {rows}×{cols} grid"
        frame_desc = f"{rows}×{cols} sequential animation frames"

    # Prompt engineered for image models that don't understand "spritesheet"
    total_frames = rows * cols
    spritesheet_prompt = (
        f"{prompt}, pixel art. "
        f"The image is a contact sheet divided by thin lines into exactly {total_frames} equal panels "
        f"arranged in {layout}. "
        f"Every panel shows the SAME {prompt} character — identical design, identical colors, identical outfit. "
        f"Only the pose changes slightly from panel to panel, creating a simple animation sequence. "
        f"Exactly {total_frames} characters total across all panels, no extras, no different characters. "
        f"Solid flat background. "
        f"Clean pixel art game style. No text, no labels, no numbers."
    )

    payload = json.dumps({
        'model': 'image-01',
        'prompt': spritesheet_prompt,
        'aspect_ratio': aspect,
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
    raise RuntimeError(f'Unexpected API response keys: {list(data.keys())}')


def download_image(url):
    """Download image from URL → PIL Image."""
    with urllib.request.urlopen(url, timeout=30) as resp:
        return Image.open(io.BytesIO(resp.read()))


def trim_to_content(frame):
    """Find bounding box of non-transparent pixels and crop, with small padding."""
    frame = frame.convert('RGBA')
    pixels = list(frame.getdata())
    w, h = frame.size
    # Find non-transparent pixel bounds
    x_min, x_max, y_min, y_max = w, 0, h, 0
    found = False
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            if a > 128:
                x_min = min(x_min, x)
                x_max = max(x_max, x)
                y_min = min(y_min, y)
                y_max = max(y_max, y)
                found = True
    if not found:
        return frame, (0, 0)
    # Add 4px padding
    x_min = max(0, x_min - 4)
    x_max = min(w - 1, x_max + 4)
    y_min = max(0, y_min - 4)
    y_max = min(h - 1, y_max + 4)
    content = frame.crop((x_min, y_min, x_max + 1, y_max + 1))
    return content, (content.width, content.height)


def slice_spritesheet(img, rows=6, cols=4, state_names=None):
    """Extract frames from spritesheet by grid layout, auto-trimming content."""
    w, h = img.size
    row_h = h // rows
    col_w = w // cols

    frames_by_state = {}
    for r in range(rows):
        name = state_names[r] if state_names and r < len(state_names) else f"state_{r+1}"
        frames = []
        for c in range(cols):
            x0, y0 = c * col_w, r * row_h
            x1, y1 = x0 + col_w, y0 + row_h
            if x1 <= w and y1 <= h:
                cell = img.crop((x0, y0, x1, y1))
                frame, _ = trim_to_content(cell)
                frames.append(frame)
        if frames:
            frames_by_state[name] = frames
    return frames_by_state


def create_gif(frames, output_path, canvas_w=80, canvas_h=80, duration=100):
    """Create animated GIF from frames, centered on transparent canvas."""
    gif_frames = []
    for frame in frames:
        canvas = Image.new('RGBA', (canvas_w, canvas_h), (0, 0, 0, 0))
        frame_rgba = frame.convert('RGBA')
        fw, fh = frame.size
        scale = min((canvas_w - 10) / fw, (canvas_h - 10) / fh, 1.0)
        nw, nh = int(fw * scale), int(fh * scale)
        resized = frame_rgba.resize((nw, nh), Image.LANCZOS)
        x, y = (canvas_w - nw) // 2, (canvas_h - nh) // 2
        canvas.paste(resized, (x, y), resized)
        gif_frames.append(canvas)
    gif_frames[0].save(
        output_path, save_all=True, append_images=gif_frames[1:],
        duration=duration, loop=0, disposal=2, optimize=True
    )


def process_spritesheet(img, output_dir, rows, cols, canvas_size, frame_delay, state_names=None):
    """Convert a spritesheet PIL Image to per-state GIFs. Returns results dict."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    spritesheet_path = output_dir / 'spritesheet.png'
    img.save(spritesheet_path)

    state_frames = slice_spritesheet(img, rows, cols, state_names)
    results = {'states': {}, 'spritesheet': str(spritesheet_path)}
    for name, frames in state_frames.items():
        gif_path = output_dir / f'{name}.gif'
        create_gif(frames, str(gif_path), canvas_w=canvas_size, canvas_h=canvas_size, duration=frame_delay)
        results['states'][name] = str(gif_path)
    results['success'] = True
    return results


# ─── HTTP Server ────────────────────────────────────────────
class APIHandler(BaseHTTPRequestHandler):
    server_config = None  # Set by run_server

    def log_message(self, fmt, *args): pass  # quiet

    def _send_json(self, data, code=200):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        if self.path == '/api/health':
            self._send_json({'status': 'ok', 'output_dir': str(DEFAULT_OUTPUT)})
        elif self.path == '/' or self.path == '/index.html':
            editor_path = Path(__file__).parent / 'spritesheet-editor.html'
            if editor_path.exists():
                content = editor_path.read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            else:
                self._send_json({'error': 'spritesheet-editor.html not found'}, 404)
        else:
            self._send_json({'error': 'not found'}, 404)

    def do_POST(self):
        content_len = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(content_len)) if content_len else {}

        if self.path == '/api/generate':
            try:
                cfg = load_config()
                if not cfg['api_key']:
                    self._send_json({'error': 'No API key configured'}, 400); return

                prompt = body.get('prompt', 'cute duck')
                rows = int(body.get('rows', 6))
                cols = int(body.get('cols', 4))
                canvas_size = int(body.get('canvas_size', 80))
                frame_delay = int(body.get('frame_delay', 100))
                state_names = body.get('state_names', None)

                image_url = generate_spritesheet(cfg, prompt, rows, cols)
                img = download_image(image_url)
                img = remove_background(img)  # Remove solid bg
                results = process_spritesheet(img, DEFAULT_OUTPUT, rows, cols, canvas_size, frame_delay, state_names)

                # Include spritesheet as data URL for browser display
                buf = io.BytesIO()
                img.save(buf, format='PNG')
                results['spritesheet_data_url'] = 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode()

                self._send_json(results)
            except Exception as e:
                traceback.print_exc()
                self._send_json({'error': str(e)}, 500)

        elif self.path == '/api/convert-local':
            try:
                data_url = body.get('spritesheet_data_url', '')
                rows = int(body.get('rows', 6))
                cols = int(body.get('cols', 4))
                canvas_size = int(body.get('canvas_size', 80))
                frame_delay = int(body.get('frame_delay', 100))
                state_names = body.get('state_names', None)

                # Decode base64 data URL
                if data_url.startswith('data:'):
                    header, encoded = data_url.split(',', 1)
                    img = Image.open(io.BytesIO(base64.b64decode(encoded)))
                elif data_url.startswith('file://'):
                    img = Image.open(data_url[7:])
                else:
                    img = Image.open(data_url)

                results = process_spritesheet(img, DEFAULT_OUTPUT, rows, cols, canvas_size, frame_delay, state_names)
                self._send_json(results)
            except Exception as e:
                traceback.print_exc()
                self._send_json({'error': str(e)}, 500)

        elif self.path == '/api/apply':
            try:
                data_url = body.get('spritesheet_data_url', '')
                rows = int(body.get('rows', 6))
                cols = int(body.get('cols', 4))
                canvas_size = int(body.get('canvas_size', 80))
                frame_delay = int(body.get('frame_delay', 100))
                state_names = body.get('state_names', None)

                # Decode and process
                if data_url.startswith('data:'):
                    header, encoded = data_url.split(',', 1)
                    img = Image.open(io.BytesIO(base64.b64decode(encoded)))
                else:
                    self._send_json({'error': 'Only data:// URLs supported for apply'}, 400); return

                # Convert all states to custom dir
                results = process_spritesheet(img, DEFAULT_OUTPUT, rows, cols, canvas_size, frame_delay, state_names)

                # Copy idle.gif to main pet directory
                idle_path = results['states'].get('idle') or list(results['states'].values())[0]
                if idle_path:
                    idle_dest = Path.home() / '.workbuddy' / 'duck-idle.gif'
                    import shutil
                    shutil.copy(idle_path, idle_dest)

                # Copy all to sprites dir
                sprite_dir = Path.home() / '.workbuddy' / 'duck-sprites'
                sprite_dir.mkdir(parents=True, exist_ok=True)
                for name, path in results['states'].items():
                    import shutil
                    shutil.copy(path, sprite_dir / f'{name}.gif')

                self._send_json({'success': True, 'states': {k: str(v) for k, v in results['states'].items()}})
            except Exception as e:
                traceback.print_exc()
                self._send_json({'error': str(e)}, 500)

        else:
            self._send_json({'error': 'not found'}, 404)


def run_server(port=DEFAULT_PORT):
    cfg = load_config()
    APIHandler.server_config = cfg
    server = HTTPServer(('127.0.0.1', port), APIHandler)
    print(f'🦆 Spritesheet API server running at http://localhost:{port}', file=sys.stderr)
    print(f'   Open http://localhost:{port} in browser', file=sys.stderr)
    print(f'   Output dir: {DEFAULT_OUTPUT}', file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nServer stopped.', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Generate pixel art spritesheet via AI → auto-convert to animation GIFs')
    parser.add_argument('prompt', nargs='?', help='Character description (e.g. "cute yellow duck")')
    parser.add_argument('--output-dir', help=f'Output directory (default: {DEFAULT_OUTPUT})')
    parser.add_argument('--http', action='store_true', help='Start HTTP API server')
    parser.add_argument('--port', type=int, default=DEFAULT_PORT, help=f'Server port (default: {DEFAULT_PORT})')
    parser.add_argument('--rows', type=int, default=6, help='Number of animation rows (default: 6)')
    parser.add_argument('--cols', type=int, default=4, help='Frames per row (default: 4)')
    parser.add_argument('--canvas-size', type=int, default=80, help='Output GIF canvas size (default: 80)')
    parser.add_argument('--frame-delay', type=int, default=100, help='Frame delay in ms (default: 100)')
    args = parser.parse_args()

    # HTTP server mode
    if args.http:
        run_server(args.port)
        return

    # CLI mode
    if not args.prompt:
        parser.print_help()
        sys.exit(1)

    output_dir = Path(args.output_dir) if args.output_dir else DEFAULT_OUTPUT
    output_dir.mkdir(parents=True, exist_ok=True)

    cfg = load_config()
    if not cfg['api_key']:
        print(json.dumps({'error': 'No API key configured in duck-config.json'}))
        sys.exit(1)

    try:
        # 1. Generate spritesheet
        print('Generating spritesheet via AI...', file=sys.stderr)
        image_url = generate_spritesheet(cfg, args.prompt, args.rows, args.cols)

        # 2. Download image
        print('Downloading spritesheet...', file=sys.stderr)
        img = download_image(image_url)

        # 3. Remove background (AI generates solid bg, not transparent)
        print('Removing background...', file=sys.stderr)
        img = remove_background(img)

        # 4. Process
        print('Slicing and creating GIFs...', file=sys.stderr)
        results = process_spritesheet(img, output_dir, args.rows, args.cols,
                                       args.canvas_size, args.frame_delay)
        print(json.dumps(results))
    except Exception as e:
        print(json.dumps({'error': str(e)}))
        sys.exit(1)


if __name__ == '__main__':
    main()
