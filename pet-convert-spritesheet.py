#!/usr/bin/env python3
"""pet-convert-spritesheet.py — Convert a PNG spritesheet into per-state animation GIFs.

Usage:
  pet-convert-spritesheet.py <spritesheet.png> [options]

Options:
  --rows N           Number of animation rows (default: 6)
  --cols N           Frames per row (default: 4)
  --row-splits S     Comma-separated row boundary fractions 0..1 (e.g. "0,0.33,0.66,1")
  --col-splits S     Comma-separated col boundary fractions 0..1
  --canvas-size N    Output GIF canvas in pixels (default: 80)
  --frame-delay N    Frame delay in milliseconds (default: 100)
  --names ...        Comma-separated state names (default: idle,walking,...)
  --output-dir D     Output directory (default: same as spritesheet)
"""

import json, sys, argparse, os
from pathlib import Path
from PIL import Image

DEFAULT_NAMES = "Row 1, Row 2, Row 3, Row 4, Row 5, Row 6, Row 7, Row 8, Row 9, Row 10"


def trim_to_content(frame):
    """Find bounding box of non-transparent pixels and crop, with small padding."""
    frame = frame.convert('RGBA')
    pixels = list(frame.getdata())
    w, h = frame.size
    x_min, x_max, y_min, y_max = w, 0, h, 0
    found = False
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            if a > 128:
                x_min = min(x_min, x); x_max = max(x_max, x)
                y_min = min(y_min, y); y_max = max(y_max, y)
                found = True
    if not found:
        return frame
    x_min = max(0, x_min - 4)
    x_max = min(w - 1, x_max + 4)
    y_min = max(0, y_min - 4)
    y_max = min(h - 1, y_max + 4)
    return frame.crop((x_min, y_min, x_max + 1, y_max + 1))



def convert_spritesheet(sheet_path, rows, cols, canvas_size, frame_delay, names, output_dir, row_splits=None, col_splits=None):
    img = Image.open(sheet_path).convert('RGBA')
    w, h = img.size
    csz = canvas_size
    delay = frame_delay

    # Compute row/col boundaries (fraction 0..1 of image dimension, 0=top/left)
    if row_splits is not None and len(row_splits) == rows + 1:
        row_fracs = row_splits
    else:
        row_fracs = [i / rows for i in range(rows + 1)]
    if col_splits is not None and len(col_splits) == cols + 1:
        col_fracs = col_splits
    else:
        col_fracs = [i / cols for i in range(cols + 1)]

    state_names = [n.strip() for n in names.split(',') if n.strip()]
    results = {'states': {}}

    for r in range(rows):
        name = state_names[r] if r < len(state_names) else f'state_{r+1}'
        frames = []
        for c in range(cols):
            y0 = int(row_fracs[r] * h)
            y1 = int(row_fracs[r + 1] * h)
            x0 = int(col_fracs[c] * w)
            x1 = int(col_fracs[c + 1] * w)
            if x1 <= x0 or y1 <= y0:
                continue
            frame = img.crop((x0, y0, x1, y1))
            frame = trim_to_content(frame)  # Remove transparent padding
            fw, fh = frame.size
            canvas = Image.new('RGBA', (csz, csz), (0, 0, 0, 0))
            scale = min((csz - 10) / max(fw, fh), 1.0)
            nw, nh = int(fw * scale), int(fh * scale)
            fr = frame.resize((nw, nh), Image.LANCZOS)
            canvas.paste(fr, ((csz - nw) // 2, (csz - nh) // 2), fr)
            frames.append(canvas)

        if frames:
            gif_path = os.path.join(output_dir, f'{name}.gif')
            frames[0].save(gif_path, save_all=True, append_images=frames[1:],
                           duration=delay, loop=0, disposal=2, optimize=True)
            results['states'][name] = gif_path

    results['success'] = True
    return results


def main():
    parser = argparse.ArgumentParser(description='Convert spritesheet PNG to per-state GIFs')
    parser.add_argument('spritesheet', help='Path to spritesheet PNG')
    parser.add_argument('--rows', type=int, default=6)
    parser.add_argument('--cols', type=int, default=4)
    parser.add_argument('--canvas-size', type=int, default=80)
    parser.add_argument('--frame-delay', type=int, default=100)
    parser.add_argument('--names', default=DEFAULT_NAMES)
    parser.add_argument('--output-dir', default=None)
    parser.add_argument('--row-splits', default=None, help='Comma-separated row boundary fractions 0..1')
    parser.add_argument('--col-splits', default=None, help='Comma-separated col boundary fractions 0..1')
    args = parser.parse_args()

    sheet_path = args.spritesheet
    if not os.path.exists(sheet_path):
        print(json.dumps({'error': f'File not found: {sheet_path}'}))
        sys.exit(1)

    output_dir = args.output_dir or os.path.dirname(sheet_path) or '.'
    os.makedirs(output_dir, exist_ok=True)

    # Parse custom splits
    row_splits = None
    col_splits = None
    if args.row_splits:
        row_splits = [float(v.strip()) for v in args.row_splits.split(',')]
    if args.col_splits:
        col_splits = [float(v.strip()) for v in args.col_splits.split(',')]

    try:
        results = convert_spritesheet(
            sheet_path, args.rows, args.cols,
            args.canvas_size, args.frame_delay, args.names, output_dir,
            row_splits=row_splits, col_splits=col_splits
        )
        print(json.dumps(results))
    except Exception as e:
        print(json.dumps({'error': str(e)}))
        sys.exit(1)


if __name__ == '__main__':
    main()
