"""Reproduce the D1 reading of the Jensen Das Ugly Stik plan (Outerzone oz1253): CG, nose length, chord.

The plan is full size (page 3476.88 pt = 48.29 in wide), so a 100 dpi render gives 100 px per inch.
Needs the local, gitignored plan copy and poppler + Pillow. It writes zoomed crops with pixel rulers
to an output folder for visual reading; it does not copy plan imagery into the repository.

Readings taken 2026-10-05 from these crops (side.png pixel x, origin = page left edge):
  firewall F1 front face 114, wing leading edge 808, CG arrow apex 1284, wing trailing edge 2015 (±3 px).
  chord 12.07 in (title block: 720 sq in / 60 in = 12.00 in, a 0.6 % scale check)
  firewall -> LE 6.94 in; CG 4.76 in aft of LE = 39.4 % chord.
Usage: python3 research/d1/jensen_plan_cg.py OUTPUT_DIR
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
PLAN = ROOT / 'references/ugly-stik/downloads/jensen/Das_Ugly_Stik_Jensen_oz1253.pdf'
READINGS_PX = {'firewall': 114, 'leading_edge': 808, 'cg_arrow': 1284, 'trailing_edge': 2015}
CROPS = {'firewall': (40, 100, 240, 300), 'leading_edge': (700, 40, 900, 240),
         'cg_arrow': (1180, 150, 1400, 290), 'trailing_edge': (1900, 40, 2100, 240)}


def main(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    side = out / 'side'
    subprocess.run(['pdftoppm', '-r', '100', '-x', '0', '-y', '2250', '-W', '2300', '-H', '700',
                    '-png', '-singlefile', str(PLAN), str(side)], check=True)
    im = Image.open(f'{side}.png').convert('RGB')
    for name, (x0, y0, x1, y1) in CROPS.items():
        tile = im.crop((x0, y0, x1, y1)).resize(((x1 - x0) * 3, (y1 - y0) * 3), Image.NEAREST)
        draw = ImageDraw.Draw(tile)
        for x in range(x0 - x0 % 10 + 10, x1, 10):
            draw.line([((x - x0) * 3, 0), ((x - x0) * 3, 30 if x % 50 == 0 else 12)], fill=(255, 0, 0))
            if x % 50 == 0:
                draw.text(((x - x0) * 3 + 2, 30), str(x), fill=(255, 0, 0))
        mark = (READINGS_PX[name] - x0) * 3
        draw.line([(mark, 0), (mark, tile.height)], fill=(0, 128, 255))
        tile.save(out / f'{name}.png')
    r = READINGS_PX
    chord = (r['trailing_edge'] - r['leading_edge']) / 100
    print(f"chord {chord:.2f} in; firewall->LE {(r['leading_edge'] - r['firewall']) / 100:.2f} in; "
          f"CG {(r['cg_arrow'] - r['leading_edge']) / 100:.2f} in aft of LE = "
          f"{(r['cg_arrow'] - r['leading_edge']) / (r['trailing_edge'] - r['leading_edge']) * 100:.1f} % chord")
    print(f'crops with readings (blue lines) in {out}')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
