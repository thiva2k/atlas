#!/usr/bin/env bash
# Regenerates the Atlas boot splash assets: the ASCII "ATLAS" masthead, baked
# as 5 letter PNGs plus a cursor and progress-bar sprite (2026-07-16 B&W
# word-only identity — see docs/superpowers/specs/2026-07-16-atlas-bw-identity-design.md).
#
# Why per-glyph baking instead of a single rendered string: Plymouth's script
# API has no live text primitive suited to a hero visual (Image.Text exists
# but is a fixed system font, used only for the LUKS prompt below) and its
# runtime scaler smears any non-integer resize. So every glyph is rasterized
# offline on an exact 24x48px cell grid — one Unicode codepoint per cell,
# centered, never resized at runtime — then cropped into 5 letter sprites at
# the exact pixel positions atlas.script places them at. What you see in the
# generated PNGs is exactly what boots, pixel for pixel.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT="assets"
mkdir -p "$OUT"
TMP="$(mktemp -d)" || exit 1; trap 'rm -rf "$TMP"' EXIT

rm -f "$OUT"/bg.png "$OUT"/hero.png "$OUT"/node-core.png "$OUT"/node-bloom.png "$OUT"/scanbar.png

JBM="$(fc-list | awk -F: '/JetBrainsMonoNerdFontMono-Regular\.ttf/{print $1; exit}')" || true
[ -n "${JBM:-}" ] || JBM="$HOME/.local/share/fonts/atlas/JetBrainsMonoNerdFont/JetBrainsMonoNerdFontMono-Regular.ttf"
[ -f "$JBM" ] || { echo "JetBrainsMono Nerd Font Mono not found" >&2; exit 1; }

python3 - "$JBM" "$OUT" <<'PYEOF'
import sys
from PIL import Image, ImageDraw, ImageFont

font_path, out_dir = sys.argv[1], sys.argv[2]

ROWS = [
    " █████╗ ████████╗██╗      █████╗ ███████╗",
    "██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝",
    "███████║   ██║   ██║     ███████║███████╗",
    "██╔══██║   ██║   ██║     ██╔══██║╚════██║",
    "██║  ██║   ██║   ███████╗██║  ██║███████║",
    "╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝",
]
assert all(len(r) == 41 for r in ROWS), "masthead must be 41 columns"

CELL_W, CELL_H = 24, 48
BLOCK = "█"  # █
BLOCK_COLOR = (0xF2, 0xF2, 0xF2, 255)
SHADOW_COLOR = (0x5A, 0x5A, 0x5A, 255)

# Calibrate font size so the block glyph's own bbox is close to the cell.
def bbox_wh(font):
    b = font.getbbox(BLOCK)
    return b[2] - b[0], b[3] - b[1]

size = 40
font = ImageFont.truetype(font_path, size)
w, h = bbox_wh(font)
if w > 0:
    size = max(8, round(size * (CELL_W / w)))
    font = ImageFont.truetype(font_path, size)

canvas = Image.new("RGBA", (CELL_W * 41, CELL_H * len(ROWS)), (0, 0, 0, 0))
draw = ImageDraw.Draw(canvas)

for row_i, row in enumerate(ROWS):
    for col_i, ch in enumerate(row):
        if ch == " ":
            continue
        color = BLOCK_COLOR if ch == BLOCK else SHADOW_COLOR
        cx = col_i * CELL_W + CELL_W / 2
        cy = row_i * CELL_H + CELL_H / 2
        draw.text((cx, cy), ch, font=font, fill=color, anchor="mm")

# Letter crops: (name, col_start, col_end) — verified against ROWS above.
letters = [("A1", 0, 8), ("T", 8, 17), ("L", 17, 25), ("A2", 25, 33), ("S", 33, 41)]
for name, c0, c1 in letters:
    crop = canvas.crop((c0 * CELL_W, 0, c1 * CELL_W, CELL_H * len(ROWS)))
    crop.save(f"{out_dir}/letter-{name}.png")

# Cursor: one solid cell block, same tone as the glyph blocks.
cursor = Image.new("RGBA", (CELL_W, CELL_H), BLOCK_COLOR)
cursor.save(f"{out_dir}/cursor.png")

# Progress track (full width, thin) and a 1x1 fill tile Plymouth scales via
# Image.Scale — safe because a solid color cannot smear under bilinear resize.
track = Image.new("RGBA", (CELL_W * 41, 2), (0x23, 0x23, 0x23, 255))
track.save(f"{out_dir}/progress-track.png")
fill = Image.new("RGBA", (2, 2), (0xE8, 0xE8, 0xE8, 255))
fill.save(f"{out_dir}/progress-fill.png")

print("baked:", ", ".join(f"letter-{n}.png" for n, *_ in letters), "cursor.png progress-track.png progress-fill.png")
PYEOF

echo "generated in $OUT:"
identify -format '  %f %wx%h\n' "$OUT"/letter-*.png "$OUT"/cursor.png "$OUT"/progress-track.png "$OUT"/progress-fill.png
