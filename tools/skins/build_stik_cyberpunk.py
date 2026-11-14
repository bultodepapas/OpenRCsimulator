"""Build NEON RONIN, a render-only Ugly Stik paint on its unchanged covering atlas.

Uses the existing CC0 ambientCG carbon and SIL OFL Noto font (see shared/LICENSES.txt
and assets/fonts/OFL-NotoSansCJK.txt). Artwork and fictional markings are authored
here. Run with the pinned visual venv; --check compares all three outputs exactly.
"""
from __future__ import annotations

import argparse
import io
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
OUT = APP / "assets/vehicle-paints/ugly-stik"
FONT = APP / "assets/fonts/NotoSansCJKjp-Regular.otf"
SIZE = 2048
S = SIZE / 1024
INK = "#181f30"
PANEL = "#293447"
EDGE = "#46566a"
CYAN = "#16e5f4"
PINK = "#ff268c"
ACID = "#eaff38"
WHITE = "#e4edf2"


class Atlas:
    def __init__(self):
        # Reuse the actual licensed weave rather than manufacturing a substitute.
        carbon = Image.open(APP / "assets/vehicle-paints/shared/carbon_twill_albedo.jpg").convert("RGB")
        carbon = ImageOps.colorize(ImageOps.grayscale(carbon), "#141b29", "#344151")
        carbon = carbon.resize((128, 128), Image.Resampling.LANCZOS)
        self.color = Image.new("RGB", (SIZE, SIZE), INK)
        for y in range(0, SIZE, 128):
            for x in range(0, SIZE, 128):
                self.color.paste(carbon, (x, y))
        self.emission = Image.new("RGB", (SIZE, SIZE), "black")
        self.roughness = Image.new("L", (SIZE, SIZE), 122)

    def polygon(self, points, color, rough=75, glow=False):
        points = [(round(x * S), round(y * S)) for x, y in points]
        ImageDraw.Draw(self.color).polygon(points, fill=color)
        ImageDraw.Draw(self.roughness).polygon(points, fill=rough)
        ImageDraw.Draw(self.emission).polygon(points, fill=color if glow else "black")

    def rect(self, box, color, rough=75, glow=False):
        x0, y0, x1, y1 = box
        self.polygon([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], color, rough, glow)

    def line(self, points, color, width=1, glow=False, rough=95):
        points = [(round(x * S), round(y * S)) for x, y in points]
        for image, fill in [(self.color, color), (self.emission, color if glow else "black"), (self.roughness, rough)]:
            ImageDraw.Draw(image).line(points, fill=fill, width=max(1, round(width * S)), joint="curve")

    def text(self, text, box, color=WHITE, rotate=False):
        x0, y0, x1, y1 = box
        width, height = round((x1 - x0) * S), round((y1 - y0) * S)
        font = ImageFont.truetype(str(FONT), max(12, height * 2))
        bbox = font.getbbox(text, stroke_width=0)
        mask = Image.new("L", (bbox[2] - bbox[0] + 2, bbox[3] - bbox[1] + 2))
        ImageDraw.Draw(mask).text((1 - bbox[0], 1 - bbox[1]), text, font=font, fill=255)
        mask = mask.resize((width, height), Image.Resampling.LANCZOS)
        if rotate:
            mask = mask.rotate(180)
        at = (round(x0 * S), round(y0 * S))
        self.color.paste(color, at, mask)
        self.roughness.paste(90, at, mask)
        self.emission.paste("black", at, mask)

    def panel(self, box, accent=CYAN):
        x0, y0, x1, y1 = box
        c = min(10, (y1 - y0) / 5)
        outline = [(x0 + c, y0), (x1, y0), (x1, y1 - c), (x1 - c, y1), (x0, y1), (x0, y0 + c), (x0 + c, y0)]
        self.line(outline, EDGE, 0.8)
        self.line([(x0 + c, y0 + 2), (x0 + c + 22, y0 + 2)], accent, 1.2)
        for x, y in [(x0 + 5, y1 - 5), (x1 - 5, y0 + 5)]:
            self.rect((x - 1.5, y - 1.5, x + 1.5, y + 1.5), WHITE, 135)
            self.line([(x - 1, y), (x + 1, y)], INK, 0.5)

    def circuits(self, box, accent, seed):
        x0, y0, x1, y1 = box
        rng = random.Random(seed)
        for i in range(10):
            y = y0 + (y1 - y0) * (i + 1) / 12
            x = x0 + rng.uniform(0, 12)
            end = x1 - rng.uniform(0, 18)
            bend = x + (end - x) * rng.uniform(0.3, 0.7)
            rise = rng.choice([-1, 1]) * min(9, (y1 - y0) / 15)
            self.line([(x, y), (bend, y), (bend + abs(rise), y + rise), (end, y + rise)], accent, 0.65, i % 4 == 0)
            self.rect((end - 1.4, y + rise - 1.4, end + 1.4, y + rise + 1.4), accent, 90, i % 4 == 0)

    def barcode(self, x, y, width, height, seed=77):
        rng = random.Random(seed)
        cursor = x
        while cursor < x + width:
            w = rng.choice([0.7, 1.2, 2.2])
            self.rect((cursor, y, min(cursor + w, x + width), y + height), WHITE, 110)
            cursor += w + rng.choice([1, 2, 3])


def build():
    a = Atlas()
    # Original stock UVs: wing spans U, chord is V=16..240. Both faces share
    # this region; the belly and stabiliser underside supply the orientation key.
    for right in (False, True):
        accent = PINK if right else CYAN
        mirror = lambda pts: [(1024 - x if right else x, y) for x, y in pts]
        a.polygon(mirror([(0, 0), (440, 0), (388, 39), (92, 92), (0, 92)]), accent, 52)
        a.polygon(mirror([(0, 150), (60, 150), (144, 240), (0, 260)]), accent, 65)
        a.line(mirror([(0, 101), (98, 101), (395, 48), (442, 8)]), WHITE, 2)
        a.line(mirror([(80, 222), (370, 222), (420, 187), (478, 187)]), accent, 2, True)
        x0, x1 = (560, 906) if right else (118, 464)
        a.panel((x0, 76, x1, 192), accent)
        a.text("RONIN" if right else "NEON", (x0 + 14, 95, x1 - 16, 136))
        a.text("夜間飛行 / 77" if right else "電脳 / FLIGHT DIVISION", (x0 + 16, 149, x1 - 23, 161), accent)
        a.text("EXPERIMENTAL  /  UGLY STIK 60", (x0 + 16, 174, x1 - 35, 180))
        a.circuits((x0 + 32, 30, x1 - 14, 64), accent, 78 if right else 77)
        # Acid tip signature, separated by the dark expansion seam.
        tx = 956 if right else 8
        a.rect((tx, 18, tx + 60, 71), ACID, 80)
        a.text("77", (tx + 7, 26, tx + 53, 54), INK)
        for k in range(5):
            x = (920 + k * 15) if right else (32 + k * 15)
            a.line([(x, 190), (x + 17, 211)], ACID, 4)
        a.barcode(x0 + 24, 202, 90, 9, 8 if right else 7)
    a.rect((486, 0, 538, 265), INK, 145)
    a.line([(497, 18), (497, 237)], CYAN, 2, True)
    a.line([(527, 18), (527, 237)], PINK, 2, True)
    for y in range(34, 239, 23):
        a.line([(505, y + 6), (512, y), (519, y + 6)], ACID, 2)

    layout = json.loads((ROOT / "assets/aircraft/ugly-stik-60/appearance.json").read_text())
    f = layout["fuselage_unwrap"]
    x0, x1 = f["x_px"]
    y0, y1 = f["y_px"]
    # Fuselage: layered carbon armour, two readable flank panels, acid belly keel.
    a.rect((x0, y0, x1, y1), INK, 138)
    for rotate in (False, True):
        top = 286 if not rotate else 414
        accent = CYAN if not rotate else PINK
        a.polygon([(10, top), (310, top), (388, top + 21), (1008, top + 21), (1008, top + 34), (368, top + 34), (292, top + 13), (10, top + 13)], accent, 58)
        a.line([(18, top + 17), (285, top + 17), (363, top + 38), (1005, top + 38)], WHITE, 1.2)
        a.panel((82, top + 43, 558, top + 78), accent)
        a.text("NEON RONIN", (106, top + 48, 450, top + 68), WHITE, rotate)
        a.text("77", (472, top + 47, 541, top + 70), ACID, rotate)
        a.circuits((590, top + 42, 960, top + 77), accent, 5 if rotate else 4)
        a.text("CAUTION // AUTONOMOUS COURIER", (593, top + 81, 899, top + 87), WHITE, rotate)
        a.barcode(36, top + 45, 32, 21, 9)
    a.rect((8, 388, 1016, 412), ACID, 92)
    for x in range(80, 1000, 88):
        a.polygon([(x, 388), (x - 16, 400), (x, 412), (x + 12, 412), (x - 4, 400), (x + 12, 388)], INK, 140)

    # The stock dorsal region overlaps the underside and hatch rectangles. Their
    # stripes and access markings also wrap onto the fuselage top; no UVs move.
    a.panel((542, 542, 1010, 1010), CYAN)
    for x in (560, 990):
        a.line([(x, 550), (x, 1008)], CYAN if x == 560 else PINK, 5, True)
    a.circuits((615, 672, 858, 982), "#586479", 18)
    # Fin. Large unit number and the split diagonal are readable at oblique angles.
    a.polygon([(16, 528), (496, 528), (496, 992), (16, 992)], INK, 130)
    a.polygon([(16, 528), (177, 528), (350, 992), (268, 992)], PINK, 62)
    a.line([(190, 528), (362, 992)], ACID, 4)
    a.panel((205, 692, 447, 878), CYAN)
    a.text("77", (227, 728, 417, 827))
    a.text("RONIN / 電脳", (218, 850, 428, 863), CYAN)
    a.circuits((49, 831, 195, 945), CYAN, 30)

    s = layout["stab_unwrap"]
    sx0, sx1 = s["x_px"]
    sy0, sy1 = s["y_px"]
    a.rect((sx0 - 2, sy0 - 2, sx1 + 2, sy1 + 2), ACID, 90)
    for x in range(sx0 - 80, sx1 + 40, 54):
        a.polygon([(x, sy0), (x + 25, sy0), (x + 105, sy1), (x + 80, sy1)], INK, 135)
    a.rect((690, 552, 846, 612), INK, 120)
    a.text("77", (704, 560, 831, 594), CYAN)
    a.text("UNDERSIDE", (705, 600, 830, 608))

    h = layout["hatch"]
    hx0, hx1 = h["x_px"]
    hy0, hy1 = h["y_px"]
    a.rect((hx0 - 2, hy0 - 2, hx1 + 2, hy1 + 2), PANEL, 115)
    a.panel((hx0 + 4, hy0 + 4, hx1 - 4, hy1 - 4), CYAN)
    for y in range(675, 855, 11):
        a.rect((930, y, 997, y + 4), INK, 160)
        a.line([(932, y), (980, y)], CYAN, 0.7, y % 3 == 0)
    a.text("77", (931, 875, 996, 913), ACID)
    a.text("ACCESS", (931, 930, 996, 940))
    a.text("電脳", (936, 949, 991, 971), CYAN)
    # Constant-UV patches used by the stock tail top/end caps and fin edges.
    a.rect((470, 0, 550, 14), PINK, 60)
    a.rect((28, 540, 54, 565), CYAN, 65)
    return {"albedo": a.color, "emission": a.emission, "roughness": a.roughness}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for kind, image in build().items():
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        data = buffer.getvalue()
        path = OUT / f"neon_ronin_{kind}.png"
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                stale.append(str(path.relative_to(ROOT)))
        else:
            OUT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            print(f"{path.relative_to(ROOT)}: {len(data):,} bytes")
    if stale:
        raise SystemExit("Stale paint: " + ", ".join(stale))
    print("NEON RONIN: 3 maps verified" if args.check else "NEON RONIN: 3 maps built")


if __name__ == "__main__":
    main()
