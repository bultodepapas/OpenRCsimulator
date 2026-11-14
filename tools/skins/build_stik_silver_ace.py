"""US-V20: SILVER ACE, a fictional USAF/Sabre-inspired natural-metal Stik skin.

Four maps share the unchanged stock atlas. Reuses ambientCG Metal009 roughness,
the public-domain USAF roundel and OFL Black Ops One; see sources/silver-ace/.
Run with the pinned visual venv. --check verifies output bytes and roughness mean.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageStat

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
OUT = APP / "assets/vehicle-paints/ugly-stik"
SOURCES = Path(__file__).parent / "sources/silver-ace"
FONT = SOURCES / "BlackOpsOne-Regular.ttf"
SMALL_FONT = APP / "assets/fonts/NotoSansCJKjp-Regular.otf"
SIZE = 2048
S = SIZE / 1024
YELLOW = "#edbb32"
INK = "#242a2c"
RED = "#a43029"
# Art-directed metal reflectance colours and finish estimates, not measured BRDFs.
ALLOYS = [(216, 221, 225), (197, 205, 212), (229, 230, 225), (186, 195, 204),
          (209, 211, 207), (221, 224, 229), (183, 190, 196), (211, 218, 221)]
FINISHES = [0.20, 0.34, 0.16, 0.43, 0.29, 0.23, 0.51, 0.36]


class MetalAtlas:
    def __init__(self):
        self.albedo = Image.new("RGB", (SIZE, SIZE), ALLOYS[0])
        self.rough = Image.new("L", (SIZE, SIZE), 85)
        self.metal = Image.new("L", (SIZE, SIZE), 255)
        self.height = np.zeros((SIZE, SIZE), dtype=np.float32)
        self.rng = np.random.default_rng(604)
        grain = Image.open(APP / "assets/vehicle-paints/shared/brushed_metal_roughness.jpg").convert("L")
        self.grain = np.asarray(grain.resize((512, 512)), dtype=np.float32) / 255.0
        self.badge = Image.open(SOURCES / "usaf-roundel.png").convert("RGBA")

    def points(self, pts):
        return [(round(x * S), round(y * S)) for x, y in pts]

    def paint(self, box, colour, rough=0.55, metal=0.0):
        coords = tuple(round(v * S) for v in box)
        ImageDraw.Draw(self.albedo).rectangle(coords, fill=colour)
        ImageDraw.Draw(self.rough).rectangle(coords, fill=round(rough * 255))
        ImageDraw.Draw(self.metal).rectangle(coords, fill=round(metal * 255))

    def line(self, pts, colour=INK, width=0.7, rough=0.62, metal=0.3):
        points = self.points(pts)
        for image, value in [(self.albedo, colour), (self.rough, round(rough * 255)),
                             (self.metal, round(metal * 255))]:
            ImageDraw.Draw(image).line(points, fill=value, width=max(1, round(width * S)))

    def polygon(self, pts, colour, rough=0.55, metal=0.0):
        points = self.points(pts)
        for image, value in [(self.albedo, colour), (self.rough, round(rough * 255)),
                             (self.metal, round(metal * 255))]:
            ImageDraw.Draw(image).polygon(points, fill=value)

    def relief_line(self, pts, depth=-0.38, width=0.7):
        mask = Image.new("L", (SIZE, SIZE))
        ImageDraw.Draw(mask).line(self.points(pts), fill=255, width=max(1, round(width * S)))
        self.height += np.asarray(mask, dtype=np.float32) / 255.0 * depth

    def rivet(self, x, y, screw=False):
        cx, cy = round(x * S), round(y * S)
        radius = 2.0 * S if screw else 1.05 * S
        pad = int(np.ceil(radius * 2))
        x0, x1 = max(0, cx - pad), min(SIZE, cx + pad + 1)
        y0, y1 = max(0, cy - pad), min(SIZE, cy + pad + 1)
        xx, yy = np.meshgrid(np.arange(x0, x1) - cx, np.arange(y0, y1) - cy)
        r2 = (xx * xx + yy * yy) / radius ** 2
        # Flush head with a narrow recessed ring; geometry remains untouched.
        relief = 0.20 * np.exp(-r2 * 2.2) - 0.28 * np.exp(-((np.sqrt(r2) - 1.0) / 0.24) ** 2)
        self.height[y0:y1, x0:x1] += relief.astype(np.float32)
        d = ImageDraw.Draw(self.albedo)
        rr = max(1, round(radius * 0.55))
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=(151, 159, 165))
        if screw:
            self.line([(x - 1.0, y), (x + 1.0, y)], "#737a7e", 0.55)

    def panel(self, box, number, horizontal=True, rivets=True):
        x0, y0, x1, y1 = [round(v * S) for v in box]
        x0, y0, x1, y1 = max(0, x0), max(0, y0), min(SIZE, x1), min(SIZE, y1)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        grain = self.grain[(yy if horizontal else xx) % 512, (xx if horizontal else yy) % 512]
        grain = (grain - float(self.grain.mean())) * 4.0
        noise = self.rng.normal(0, 0.5, (y1 - y0, x1 - x0))
        base = np.asarray(ALLOYS[number % len(ALLOYS)], dtype=np.float32)
        rgb = np.clip(base + (grain * 1.3 + noise)[..., None], 0, 255).astype(np.uint8)
        self.albedo.paste(Image.fromarray(rgb), (x0, y0))
        rough = np.clip(FINISHES[number % len(FINISHES)] + grain * 0.035, 0.10, 0.64)
        self.rough.paste(Image.fromarray((rough * 255).astype(np.uint8)), (x0, y0))
        self.metal.paste(255, (x0, y0, x1, y1))
        x0, y0, x1, y1 = [v / S for v in (x0, y0, x1, y1)]
        edge = [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)]
        self.line(edge, "#7b858d", 0.65, 0.65, 0.65)
        self.relief_line(edge)
        if rivets and x1 - x0 > 20 and y1 - y0 > 18:
            for x in np.arange(x0 + 5, x1 - 3, 9):
                self.rivet(x, y0 + 4)
                self.rivet(x, y1 - 4)
            for y in np.arange(y0 + 12, y1 - 7, 9):
                self.rivet(x0 + 4, y)
                self.rivet(x1 - 4, y)

    def grid(self, xs, ys, seed):
        for row in range(len(ys) - 1):
            for col in range(len(xs) - 1):
                self.panel((xs[col], ys[row], xs[col + 1], ys[row + 1]),
                           (seed + col * 3 + row * 5) % 8, (row + col) % 2 == 0)

    def text(self, text, box, colour=INK, rotate=False, stencil=True):
        x0, y0, x1, y1 = box
        width, height = round((x1 - x0) * S), round((y1 - y0) * S)
        font = ImageFont.truetype(str(FONT if stencil else SMALL_FONT), max(12, height * 2))
        b = font.getbbox(text)
        mask = Image.new("L", (b[2] - b[0] + 2, b[3] - b[1] + 2))
        ImageDraw.Draw(mask).text((1 - b[0], 1 - b[1]), text, font=font, fill=255)
        mask = mask.resize((width, height), Image.Resampling.LANCZOS)
        if rotate:
            mask = mask.rotate(180)
        self.sticker(mask, (round(x0 * S), round(y0 * S)), colour)

    def sticker(self, mask, at, colour):
        self.albedo.paste(colour, at, mask)
        self.rough.paste(145, at, mask)
        self.metal.paste(0, at, mask)

    def insignia(self, box, rotate=False):
        x0, y0, x1, y1 = box
        size = (round((x1 - x0) * S), round((y1 - y0) * S))
        badge = self.badge.resize(size, Image.Resampling.LANCZOS)
        if rotate:
            badge = badge.rotate(180)
        self.sticker(badge.getchannel("A"), (round(x0 * S), round(y0 * S)), badge.convert("RGB"))

    def stripe(self, x0, x1, y0, y1):
        self.paint((x0 - 4, y0, x1 + 4, y1), INK, 0.62)
        self.paint((x0, y0, x1, y1), YELLOW, 0.46)
        # Chipped paint exposes real metal in the metalness map as well as albedo.
        for _ in range(60):
            x = float(self.rng.choice([x0, x1])) + float(self.rng.uniform(-1.4, 1.4))
            y = float(self.rng.uniform(y0 + 2, y1 - 2))
            self.line([(x, y), (x + self.rng.uniform(-3, 3), y + self.rng.uniform(0.3, 1.5))],
                      ALLOYS[1], 0.65, 0.36, 1.0)

    def access(self, box, label="ACCESS"):
        x0, y0, x1, y1 = box
        c = 6
        p = [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c),
             (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c), (x0 + c, y0)]
        self.line(p, "#69737c", 0.9)
        self.relief_line(p, -0.55)
        for x, y in [(x0 + 6, y0 + 6), (x1 - 6, y0 + 6), (x0 + 6, y1 - 6), (x1 - 6, y1 - 6)]:
            self.rivet(x, y, True)
        self.text(label, (x0 + 10, y1 - 13, x1 - 10, y1 - 7), stencil=False)

    def weather(self):
        # Localised scuffs, wipe marks and grey oxide, not orange rust on aluminium.
        for _ in range(450):
            x = self.rng.uniform(22, 1000)
            y = self.rng.choice([self.rng.uniform(183, 234), self.rng.uniform(383, 418)])
            self.line([(x, y), (x + self.rng.uniform(1, 7), y + self.rng.uniform(-0.35, 0.35))],
                      "#a1a7a9", 0.45, 0.58, 0.80)
        # Oil wipe streaks aft of the exposed glow engine on the +X flank.
        overlay = Image.new("RGBA", (SIZE, SIZE))
        draw = ImageDraw.Draw(overlay)
        for _ in range(95):
            x, y = self.rng.uniform(25, 240), self.rng.uniform(469, 493)
            length = self.rng.uniform(15, 160)
            draw.line(self.points([(x, y), (x + length, y - self.rng.uniform(0, 8))]),
                      fill=(74, 63, 47, int(self.rng.uniform(8, 28))), width=int(self.rng.integers(1, 4)))
        self.albedo = Image.alpha_composite(self.albedo.convert("RGBA"), overlay).convert("RGB")
        residue = overlay.getchannel("A")
        self.metal.paste(0, (0, 0), residue)
        self.rough.paste(150, (0, 0), residue)

    def maps(self):
        dy, dx = np.gradient(self.height)
        normals = np.stack([-dx, dy, np.ones_like(dx)], axis=-1)
        normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
        normal = Image.fromarray(np.clip((normals * 0.5 + 0.5) * 255 + 0.5, 0, 255).astype(np.uint8))
        return {"albedo": self.albedo, "roughness": self.rough, "metallic": self.metal, "normal": normal}


def build():
    for item in json.loads((SOURCES / "sources.json").read_text()):
        if hashlib.sha256((SOURCES / item["file"]).read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Authoring source changed: " + item["file"])
    a = MetalAtlas()
    a.grid([0, 100, 230, 365, 512, 659, 794, 924, 1024], [14, 55, 118, 182, 252], 0)
    for x in (100, 874):
        a.stripe(x, x + 50, 14, 252)
    for x in (462, 535):
        a.paint((x, 26, x + 27, 243), "#3a3f3f", 0.88)
        for y in range(35, 238, 9):
            a.line([(x + 3, y), (x + 24, y + 4)], "#5b6061", 0.55, 0.91, 0.0)
    a.insignia((253, 84, 425, 175))
    a.text("USAF", (604, 85, 825, 159))
    for x in (174, 590):
        a.text("NO STEP", (x, 213, x + 72, 220), RED, stencil=False)
        a.access((x + 73, 190, x + 137, 231), "INSPECT")
    a.text("FUEL  /  SERVICE", (260, 34, 402, 41), stencil=False)
    a.text("FU-604", (642, 34, 790, 46))
    a.grid([4, 94, 195, 300, 425, 550, 690, 830, 1020], [278, 324, 385, 415, 476, 522], 3)
    a.stripe(610, 668, 278, 522)
    for rotate in (False, True):
        top = 322 if not rotate else 424
        a.text("U.S. AIR FORCE", (111, top, 399, top + 13), rotate=rotate)
        a.text("FU-604", (113, top + 23, 405, top + 54), rotate=rotate)
        a.insignia((442, top + 3, 553, top + 62), rotate)
        a.text("52-0604   /   SILVER ACE", (45, top + 63, 340, top + 69), rotate=rotate, stencil=False)
        a.access((716, top + 48, 812, top + 81), "BATTERY")
        a.polygon([(70, top + 6), (80, top + 16), (60, top + 16)], RED)
    # Dorsal, underside and hatch overlap in this stock atlas. Keep their palette
    # coherent: these service marks also wrap onto the fuselage top.
    a.grid([540, 620, 742, 882, 1018], [540, 640, 752, 876, 1014], 2)
    a.grid([16, 154, 310, 496], [528, 665, 820, 992], 4)
    a.paint((16, 528, 496, 616), YELLOW, 0.49)
    a.paint((16, 616, 496, 624), INK, 0.59)
    # Mirror-symmetric national insignia avoids a backwards tail serial.
    a.insignia((208, 737, 442, 861))
    a.access((100, 871, 239, 953), "RUDDER SERVICE")
    layout = json.loads((ROOT / "assets/aircraft/ugly-stik-60/appearance.json").read_text())
    under = layout["stab_unwrap"]
    xs, ys = under["x_px"], under["y_px"]
    a.grid([xs[0] - 2, 650, 768, 886, xs[1] + 2], [ys[0] - 2, 585, ys[1] + 2], 1)
    a.stripe(572, 601, ys[0], ys[1])
    a.stripe(935, 964, ys[0], ys[1])
    a.text("NO STEP", (692, 550, 840, 561), RED, stencil=False)
    h = layout["hatch"]
    x0, x1 = h["x_px"]
    y0, y1 = h["y_px"]
    a.paint((x0 - 2, y0 - 2, x1 + 2, y1 + 2), "#303a35", 0.83)
    a.access((x0 + 5, y0 + 5, x1 - 5, y1 - 5), "DANGER")
    a.text("604", (932, 877, 996, 916), "#d8d5bc")
    a.polygon([(953, 726), (981, 777), (925, 777)], YELLOW, 0.58)
    a.text("!", (948, 743, 959, 767), INK)
    a.weather()
    # Stab top and fin edges sample constant UV points. These must stay plain metal.
    a.paint((470, 0, 550, 14), ALLOYS[0], 0.22, 1.0)
    a.height[:round(14 * S) + 1, round(470 * S):round(550 * S) + 1] = 0
    a.paint((28, 540, 54, 565), ALLOYS[0], 0.25, 1.0)
    return a.maps()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    maps = build()
    stale = []
    for name, image in maps.items():
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        data = buffer.getvalue()
        path = OUT / f"silver_ace_{name}.png"
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                stale.append(str(path.relative_to(ROOT)))
        else:
            OUT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            print(f"{path.relative_to(ROOT)}: {len(data):,} bytes")
    mean = ImageStat.Stat(maps["roughness"]).mean[0] / 255.0
    print(f"roughness mean: {mean:.16f}")
    if args.check:
        registry = json.loads((APP / "data/vehicle_paints.json").read_text(encoding="utf-8"))
        recorded = registry["detail_map_means"].get("res://assets/vehicle-paints/ugly-stik/silver_ace_roughness.png", -1)
        if abs(recorded - mean) > 1e-12:
            stale.append("vehicle_paints.json roughness mean")
    if stale:
        raise SystemExit("Stale SILVER ACE output: " + ", ".join(stale))
    print("SILVER ACE: four maps verified" if args.check else "SILVER ACE: four maps built")


if __name__ == "__main__":
    main()
