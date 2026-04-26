#!/usr/bin/env python3
"""
rover_darkmode.py — Post-process a Rover-generated SVG into dark mode.

Usage:
    python3 rover_darkmode.py rover.svg rover_dark.svg

Color map (light → dark):
    Background  rgb(255,255,255) → rgb(22,25,33)       dark card (nodes float on canvas)
    Canvas      BACKGROUND_RECT  → rgb(38,42,50)       blue-slate canvas (#262a32)
    Text        rgb(0,0,0)       → rgb(201,209,217)   off-white
    Edges/gray  rgb(211,211,211) → rgb(48,54,61)      dark border gray
    Edge stroke rgb(0,0,0)       → rgb(100,110,120)   readable gray lines
    Blue node   rgb(225,240,255) → rgb(4,21,44)       deep navy fill
    Blue accent rgb(29,122,218)  → rgb(88,166,255)    bright sky blue
    Amber node  rgb(255,247,224) → rgb(30,22,0)       deep amber fill
    Amber accent rgb(255,193,7)  → rgb(255,210,60)    bright amber
    Red node    rgb(255,236,236) → rgb(40,0,12)       deep crimson fill
    Red accent  rgb(220,71,125)  → rgb(255,121,174)   bright pink
"""

import sys
import re

REPLACEMENTS = [
    # Order matters — most specific first, then general

    # ── Canvas background (rover's full-graph background rect) ──────────────
    (r'fill="rgb\(244,236,255\)"',  'fill="rgb(38,42,50)"'),       # rover canvas bg → blue-slate

    # ── Node fill backgrounds (light pastels → deep darks) ──────────────────
    (r'fill="rgb\(255,247,224\)"',  'fill="rgb(30,22,0)"'),        # amber bg
    (r'fill="rgb\(225,240,255\)"',  'fill="rgb(4,21,44)"'),        # blue bg
    (r'fill="rgb\(255,236,236\)"',  'fill="rgb(40,0,12)"'),        # red/pink bg
    (r'fill="rgb\(255,255,255\)"',  'fill="rgb(22,25,33)"'),        # white node fills → dark card

    # ── White strokes (rover uses white as separator/knockout stroke) ────────
    (r'stroke="rgb\(255,255,255\)"','stroke="rgb(38,42,50)"'),     # white strokes → canvas color

    # ── Text / label fills ───────────────────────────────────────────────────
    (r'fill="rgb\(0,0,0\)"',        'fill="rgb(201,209,217)"'),    # black text → light

    # ── Accent colors (keep vibrant, slightly brighten for dark bg) ──────────
    (r'fill="rgb\(29,122,218\)"',   'fill="rgb(88,166,255)"'),     # blue node
    (r'color="rgb\(29,122,218\)"',  'color="rgb(88,166,255)"'),
    (r'stroke="rgb\(29,122,218\)"', 'stroke="rgb(88,166,255)"'),

    (r'color="rgb\(255,193,7\)"',   'color="rgb(255,210,60)"'),    # amber accent
    (r'stroke="rgb\(255,193,7\)"',  'stroke="rgb(255,210,60)"'),

    (r'color="rgb\(220,71,125\)"',  'color="rgb(255,121,174)"'),   # pink accent
    (r'stroke="rgb\(220,71,125\)"', 'stroke="rgb(255,121,174)"'),

    # ── Edge / border colors ─────────────────────────────────────────────────
    (r'stroke="rgb\(0,0,0\)"',      'stroke="rgb(100,110,120)"'),  # black edges → gray
    (r'stroke="rgb\(211,211,211\)"','stroke="rgb(48,54,61)"'),     # light gray borders
    (r'color="rgb\(211,211,211\)"', 'color="rgb(48,54,61)"'),
    (r'color="rgb\(0,0,0\)"',       'color="rgb(201,209,217)"'),

    # ── Gradient stop-colors ─────────────────────────────────────────────────
    (r'stop-color="rgb\(211,211,211\)"', 'stop-color="rgb(48,54,61)"'),
]

BACKGROUND_RECT = (
    '<rect width="100%" height="100%" fill="rgb(38,42,50)"/>'
)


def transform(src: str) -> str:
    # 1. Apply all color substitutions
    for pattern, replacement in REPLACEMENTS:
        src = re.sub(pattern, replacement, src)

    # 2. Inject a background rect immediately after the opening <svg ...> tag
    #    so transparent areas also get the dark background.
    src = re.sub(
        r'(<svg[^>]*>)',
        r'\1' + BACKGROUND_RECT,
        src,
        count=1,
    )

    return src


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.svg> <output.svg>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, 'r', encoding='utf-8') as f:
        content = f.read()

    transformed = transform(content)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(transformed)

    print(f"Dark mode SVG written to: {output_path}")


if __name__ == '__main__':
    main()
