#!/usr/bin/env bash
# Bakes the Atlas Hyprland B&W images (Fable spec 2026-07-16):
#   atlas-lock-bg.png  — 1920x1080 #070707, two-tone ATLAS masthead top-centre
#                        (white blocks #f2f2f2 + grey shadow #5a5a5a). hyprlock
#                        draws the live clock/date/password over it.
#   atlas-wall-bw.png  — 1920x1080 #070707, the same masthead ENGRAVED
#                        bottom-right in near-black (#161616 / #0f0f0f) — visible
#                        only on an empty workspace, invisible behind windows.
#
# Same per-glyph two-tone bake as the Plymouth/SDDM masthead: each Unicode cell
# rendered centred on an exact pixel grid so the block art stays crisp and the
# two tones register perfectly. Output goes to the deploy dir the configs point
# at: ~/.local/share/backgrounds/atlas/ (does NOT touch the old blue canvases).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

OUT="${ATLAS_WALL_OUT:-$HOME/.local/share/backgrounds/atlas}"
mkdir -p "$OUT"

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
assert all(len(r) == 41 for r in ROWS)
BLOCK = "█"
W, H = 1920, 1080
BG = (7, 7, 7, 255)

def font_for_cell(cw):
    # JBM advance ~= 0.6 * pixelsize; calibrate so glyph advance == cell width.
    size = max(6, round(cw / 0.6))
    f = ImageFont.truetype(font_path, size)
    adv = f.getlength(BLOCK)
    if adv > 0:
        size = max(6, round(size * (cw / adv)))
        f = ImageFont.truetype(font_path, size)
    return f

def render_masthead(cell_w, cell_h, block_rgb, shadow_rgb):
    """Return an RGBA image of the two-tone masthead on a cell_w x cell_h grid."""
    font = font_for_cell(cell_w)
    img = Image.new("RGBA", (cell_w * 41, cell_h * len(ROWS)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r, row in enumerate(ROWS):
        for c, ch in enumerate(row):
            if ch == " ":
                continue
            color = block_rgb if ch == BLOCK else shadow_rgb
            d.text((c * cell_w + cell_w / 2, r * cell_h + cell_h / 2), ch,
                   font=font, fill=color, anchor="mm")
    return img

# ---- 1. lock background: masthead top-centre, full white/grey ---------------
lock = Image.new("RGBA", (W, H), BG)
mh = render_masthead(16, 32, (242, 242, 242, 255), (90, 90, 90, 255))
lx = (W - mh.width) // 2
ly = 140
lock.alpha_composite(mh, (lx, ly))
lock.convert("RGB").save(f"{out_dir}/atlas-lock-bg.png")

# ---- 2. desktop wallpaper: masthead engraved bottom-right -------------------
wall = Image.new("RGBA", (W, H), BG)
eng = render_masthead(10, 20, (22, 22, 22, 255), (15, 15, 15, 255))
inset = 48
wx = W - eng.width - inset
wy = H - eng.height - inset
wall.alpha_composite(eng, (wx, wy))
wall.convert("RGB").save(f"{out_dir}/atlas-wall-bw.png")

print(f"lock-bg: masthead {mh.width}x{mh.height} at ({lx},{ly})")
print(f"wallpaper: engrave {eng.width}x{eng.height} at ({wx},{wy})")
PYEOF

echo "generated in $OUT:"
identify -format '  %f %wx%h\n' "$OUT"/atlas-lock-bg.png "$OUT"/atlas-wall-bw.png
