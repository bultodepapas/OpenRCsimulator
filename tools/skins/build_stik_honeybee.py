"""US-V22: HONEYBEE, honey-yellow film, charcoal bands and a licensed bee emblem.

Two baked maps use the unchanged Stik atlas and its original film normals.
Reuses the NEON RONIN drawing utilities, ambientCG CC0 carbon and OFL Noto font.
Bee source and attribution: sources/honeybee/. Run --check with the visual venv.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageOps, ImageStat

from build_stik_cyberpunk import APP, ROOT, OUT, SIZE, S, Atlas

SOURCES = ROOT / "tools/skins/sources/honeybee"
HONEY = "#ffc844"
GOLD = "#edaa2d"
INK = "#25272b"
IVORY = "#fff0c7"


class BeeAtlas(Atlas):
    def __init__(self):
        super().__init__()
        self.rect((0, 0, 1024, 1024), HONEY, 92)

    def bee(self, box):
        x0, y0, x1, y1 = box
        original = Image.open(SOURCES / "bee.png").convert("RGBA")
        mask = ImageChops.multiply(ImageOps.invert(original.convert("L")), original.getchannel("A"))
        width, height = round((x1 - x0) * S), round((y1 - y0) * S)
        mask = ImageOps.contain(mask, (width, height), Image.Resampling.LANCZOS)
        # Finish.uv("fin") has unequal U/V texels per metre. Compensate here
        # so the source bee keeps its proportions on the aircraft, not just PNG.
        fin_u_density = 448 / 0.31
        fin_v_density = 432 / 0.215
        mask = mask.resize((round(mask.width * fin_u_density / fin_v_density), mask.height), Image.Resampling.LANCZOS)
        at = (round(x0 * S) + (width - mask.width) // 2,
              round(y0 * S) + (height - mask.height) // 2)
        self.color.paste(INK, at, mask)
        self.roughness.paste(135, at, mask)

    def hexagons(self, box, radius=13):
        # A low-contrast comb in the varnish, clipped to the region. No new
        # height map: this covering intentionally keeps the stock film structure.
        overlay = Image.new("RGBA", (SIZE, SIZE))
        draw = ImageDraw.Draw(overlay)
        x0, y0, x1, y1 = box
        step_y = math.sqrt(3) * radius
        column = 0
        for x in np.arange(x0 - radius, x1 + radius, 1.5 * radius):
            offset = step_y / 2 if column % 2 else 0
            for y in np.arange(y0 - step_y, y1 + step_y, step_y):
                points = [(round((x + radius * math.cos(i * math.pi / 3)) * S),
                           round((y + offset + radius * math.sin(i * math.pi / 3)) * S)) for i in range(6)]
                draw.line(points + [points[0]], fill=(164, 99, 18, 44), width=max(1, round(0.7 * S)))
            column += 1
        clip = Image.new("L", (SIZE, SIZE))
        ImageDraw.Draw(clip).rectangle(tuple(round(v * S) for v in box), fill=255)
        overlay.putalpha(Image.fromarray(np.minimum(np.asarray(overlay.getchannel("A")), np.asarray(clip))))
        self.color = Image.alpha_composite(self.color.convert("RGBA"), overlay).convert("RGB")
        self.roughness.paste(118, (0, 0), overlay.getchannel("A"))

    def carbon_bands(self):
        # Existing licensed twill is visible only in the dark bands. It remains
        # subtle and achromatic; it does not introduce the earlier neon palette.
        tile = Image.open(APP / "assets/vehicle-paints/shared/carbon_twill_albedo.jpg").convert("L")
        tile = ImageOps.colorize(tile, "#202226", "#33353a").resize((128, 128), Image.Resampling.LANCZOS)
        weave = Image.new("RGB", (SIZE, SIZE))
        for y in range(0, SIZE, 128):
            for x in range(0, SIZE, 128):
                weave.paste(tile, (x, y))
        rgb = np.asarray(self.color)
        mask = Image.fromarray(((rgb[..., 0] < 70) & (rgb[..., 1] < 75)).astype(np.uint8) * 255)
        self.color.paste(weave, (0, 0), mask)


def build():
    manifest = json.loads((SOURCES / "sources.json").read_text(encoding="utf-8"))
    for item in manifest if isinstance(manifest, list) else manifest["sources"]:
        if hashlib.sha256((SOURCES / item["file"]).read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Authoring source changed: " + item["file"])
    a = BeeAtlas()
    a.hexagons((0, 14, 1024, 252), 14)
    # Paired black abdomen bands, reflected in span. The upper/lower wing UVs
    # are shared, so there are no letters or numbers anywhere in this region.
    a.rect((0, 14, 1024, 29), "#ffdb72", 80)
    for right in (False, True):
        fold = lambda points: [(1024 - x if right else x, y) for x, y in points]
        a.polygon(fold([(0, 14), (73, 14), (142, 252), (0, 252)]), INK, 153)
        a.polygon(fold([(174, 14), (249, 14), (316, 252), (241, 252)]), INK, 153)
        a.line(fold([(256, 16), (322, 246)]), IVORY, 1.3, rough=100)
        a.line(fold([(94, 211), (187, 211)]), GOLD, 2, rough=115)
    a.rect((472, 14, 552, 252), INK, 153)
    a.line([(512, 36), (512, 227)], GOLD, 1.2, rough=110)

    # Nose-to-tail bands wrap the complete fuselage arc like a bee's abdomen.
    a.rect((4, 278, 1020, 522), HONEY, 89)
    a.hexagons((4, 278, 1020, 522), 13)
    for start, stop in [(438, 516), (586, 664), (734, 812), (882, 960)]:
        a.rect((start, 278, stop, 522), INK, 151)
        a.rect((stop + 3, 278, stop + 5, 522), IVORY, 99)
    for reverse in (False, True):
        def box(x0, y0, x1, y1):
            return (x0, 800 - y1, x1, 800 - y0) if reverse else (x0, y0, x1, y1)
        a.text("HONEYBEE / 07", box(104, 329, 400, 345), INK, reverse)
        a.line([(115, 353 if not reverse else 447), (369, 353 if not reverse else 447)], INK, 0.9, rough=120)
    a.rect((8, 387, 1016, 413), INK, 151)

    # Fin: a bee silhouette remains recognizable on the shared mirrored faces.
    a.rect((16, 528, 496, 992), HONEY, 92)
    a.hexagons((16, 528, 496, 992), 17)
    a.rect((16, 528, 496, 632), INK, 150)
    a.rect((16, 916, 496, 992), INK, 150)
    # Keep the complete insect on the fixed fin, before the relieved hinge at
    # x=318.14. The source outline leaves ample clearance from the curved edge.
    a.bee((110, 700, 300, 890))

    # Dorsal, hatch and stabilizer underside deliberately share a coherent
    # palette. No independent lettering is promised on overlapping UV regions.
    a.rect((540, 540, 1018, 1014), HONEY, 92)
    a.hexagons((540, 540, 1018, 1014), 18)
    layout = json.loads((ROOT / "assets/aircraft/ugly-stik-60/appearance.json").read_text())
    under = layout["stab_unwrap"]
    x0, x1 = under["x_px"]
    y0, y1 = under["y_px"]
    a.rect((x0 - 2, y0 - 2, x1 + 2, y1 + 2), HONEY, 92)
    for start, stop in [(x0 - 2, x0 + 51), (739, 797), (x1 - 51, x1 + 2)]:
        a.rect((start, y0 - 2, stop, y1 + 2), INK, 151)
    hatch = layout["hatch"]
    x0, x1 = hatch["x_px"]
    y0, y1 = hatch["y_px"]
    a.rect((x0 - 2, y0 - 2, x1 + 2, y1 + 2), INK, 151)
    for y in (y0 + 29, y0 + 91, y0 + 153, y0 + 215, y0 + 277):
        a.polygon([(x0 + 9, y), (x1 - 9, y), (x1 - 9, y + 27), (x0 + 9, y + 48)], HONEY, 89)
    a.carbon_bands()
    # Constant stock UVs cannot carry separate art: warm tail tops, dark edges.
    a.rect((470, 0, 550, 14), HONEY, 89)
    a.rect((28, 540, 54, 565), INK, 151)
    return {"albedo": a.color, "roughness": a.roughness}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    maps = build()
    stale = []
    for kind, image in maps.items():
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        data = buffer.getvalue()
        path = OUT / f"honeybee_{kind}.png"
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
        recorded = registry["detail_map_means"].get("res://assets/vehicle-paints/ugly-stik/honeybee_roughness.png", -1)
        if abs(recorded - mean) > 1e-12:
            stale.append("vehicle_paints.json roughness mean")
    if stale:
        raise SystemExit("Stale HONEYBEE output: " + ", ".join(stale))
    print("HONEYBEE: two maps verified" if args.check else "HONEYBEE: two maps built")


if __name__ == "__main__":
    main()
