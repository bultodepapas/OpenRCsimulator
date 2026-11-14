"""US-V21: BLACKBIRD, charcoal thermal panels with sparse red safety markings.

SR-71/A-12-inspired RC tribute, not a reconstruction. Reuses the SILVER ACE
atlas/normal authoring utilities, shared CC0 brushing and bundled OFL fonts.
No emission, logos or geometry changes. --check verifies all four maps and mean.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json

import numpy as np
from PIL import Image, ImageStat

from build_stik_silver_ace import APP, ROOT, OUT, SIZE, S, SOURCES, MetalAtlas

CHARCOAL = [(27, 29, 33), (31, 33, 36), (34, 36, 40), (25, 27, 30),
            (37, 38, 41), (30, 31, 33), (32, 35, 39), (28, 30, 34)]
FINISH = [0.57, 0.66, 0.53, 0.72, 0.61, 0.64, 0.50, 0.69]
RED = "#8d2e30"
GHOST = "#4c5056"
SEAM = "#15181c"


class BlackbirdAtlas(MetalAtlas):
    def __init__(self):
        super().__init__()
        self.albedo.paste(CHARCOAL[0], (0, 0, SIZE, SIZE))
        self.rough.paste(160, (0, 0, SIZE, SIZE))
        self.metal.paste(0, (0, 0, SIZE, SIZE))

    def panel(self, box, number, horizontal=True, rivets=True):
        # Reuse the same flush-rivet and joint recipe, but give the black thermal
        # coating its own reflectance and roughness instead of darkening metal.
        super().panel(box, number, horizontal, rivets)
        x0, y0, x1, y1 = [round(v * S) for v in box]
        # ImageDraw panel borders include the far edge; include it here too so
        # inherited silver strokes cannot bleed through filtering/mipmaps.
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1 + 1, SIZE), min(y1 + 1, SIZE)
        tile = np.asarray(self.albedo.crop((x0, y0, x1, y1)), dtype=np.float32)
        local = tile.mean(axis=-1)
        variation = np.clip((local - np.median(local)) * 0.075, -4.0, 1.5)
        colour = np.asarray(CHARCOAL[number % 8], dtype=np.float32)
        rgb = np.clip(colour + variation[..., None], 18, 48).astype(np.uint8)
        self.albedo.paste(Image.fromarray(rgb), (x0, y0))
        rough = np.clip(FINISH[number % 8] + variation * 0.008, 0.45, 0.76)
        self.rough.paste(Image.fromarray((rough * 255).astype(np.uint8)), (x0, y0))
        self.metal.paste(0, (x0, y0, x1, y1))

    def thermal_joint(self, points):
        self.line(points, "#31343a", 0.65, 0.56, 0.0)
        self.relief_line(points, -0.24, 0.65)

    def ghost_text(self, text, box, rotate=False):
        self.text(text, box, GHOST, rotate, stencil=False)


def build():
    for item in json.loads((SOURCES / "sources.json").read_text()):
        if hashlib.sha256((SOURCES / item["file"]).read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Authoring source changed: " + item["file"])
    a = BlackbirdAtlas()
    # Long, quiet panels with angular thermal joints; no bright insignia.
    a.grid([0, 154, 324, 512, 700, 870, 1024], [14, 84, 161, 252], 0)
    for mirror in (False, True):
        fold = lambda pts: [(1024 - x if mirror else x, y) for x, y in pts]
        a.thermal_joint(fold([(20, 40), (154, 40), (200, 84), (324, 84), (367, 124), (464, 124)]))
        a.line(fold([(446, 61), (446, 190), (423, 211)]), RED, 1.0, 0.61, 0.0)
        a.line(fold([(451, 61), (451, 190), (428, 211)]), "#57282c", 0.5, 0.64, 0.0)
        # Wing faces share mirrored UVs: use marks that survive reflection,
        # keeping all lettering on the separately unwrapped fuselage flanks.
        for offset in (0, 7, 14):
            a.line(fold([(419 + offset, 216), (424 + offset, 224)]), RED, 0.9, 0.61, 0.0)
    a.grid([4, 112, 252, 426, 610, 800, 1020], [278, 332, 385, 415, 468, 522], 3)
    # Mirror the complete label positions around the belly centre, so both
    # separately unwrapped flanks read in the same vertical order.
    for reverse in (False, True):
        def box(x0, y0, x1, y1):
            return (x0, 800 - y1, x1, 800 - y0) if reverse else (x0, y0, x1, y1)
        a.ghost_text("BLACKBIRD", box(123, 326, 390, 340), reverse)
        a.ghost_text("BB-071", box(123, 350, 261, 362), reverse)
        a.text("DANGER", box(310, 350, 401, 360), RED, reverse, stencil=False)
        a.thermal_joint([(590, 284 if not reverse else 516), (590, 356 if not reverse else 444),
                         (658, 386 if not reverse else 414), (919, 386 if not reverse else 414)])
    # Overlapping stock dorsal, fin and stabiliser-underneath regions retain a
    # consistent palette; no new UV mapping or extra draw calls are introduced.
    a.grid([540, 652, 796, 910, 1018], [540, 642, 763, 892, 1014], 1)
    a.grid([16, 170, 330, 496], [528, 683, 833, 992], 2)
    # A mirror-symmetric chevron is legible on both shared fin faces.
    a.line([(206, 704), (266, 685), (326, 704)], RED, 2.0, 0.62, 0.0)
    a.line([(216, 714), (266, 698), (316, 714)], "#542a2d", 0.8, 0.65, 0.0)
    a.thermal_joint([(76, 939), (181, 888), (286, 888), (417, 942)])
    layout = json.loads((ROOT / "assets/aircraft/ugly-stik-60/appearance.json").read_text())
    under = layout["stab_unwrap"]
    xs, ys = under["x_px"], under["y_px"]
    a.height[round((ys[0] - 2) * S):round((ys[1] + 2) * S) + 1,
             round((xs[0] - 2) * S):round((xs[1] + 2) * S) + 1] = 0
    a.grid([xs[0] - 2, 654, 768, 882, xs[1] + 2], [ys[0] - 2, 586, ys[1] + 2], 4)
    a.line([(695, 562), (724, 562), (740, 578)], RED, 1.0, 0.61, 0.0)
    a.line([(841, 562), (812, 562), (796, 578)], RED, 1.0, 0.61, 0.0)
    h = layout["hatch"]
    x0, x1 = h["x_px"]
    y0, y1 = h["y_px"]
    a.height[round((y0 - 2) * S):round((y1 + 2) * S) + 1,
             round((x0 - 2) * S):round((x1 + 2) * S) + 1] = 0
    a.paint((x0 - 2, y0 - 2, x1 + 2, y1 + 2), "#1a1c20", 0.70)
    a.thermal_joint([(x0 + 8, y0 + 8), (x1 - 8, y0 + 8), (x1 - 8, y1 - 8), (x0 + 8, y1 - 8), (x0 + 8, y0 + 8)])
    a.line([(934, 684), (990, 684)], RED, 1.2, 0.62, 0.0)
    a.ghost_text("071", (938, 893, 988, 915))
    # Sparse scuffs reveal dulled titanium, mostly around access joints. Keep
    # them dark enough to read as a used black coating rather than silver paint.
    for _ in range(165):
        x = float(a.rng.uniform(45, 990))
        y = float(a.rng.choice([a.rng.uniform(191, 239), a.rng.uniform(390, 411)]))
        a.line([(x, y), (x + a.rng.uniform(0.8, 3.3), y + 0.2)], "#40434a", 0.45, 0.51, 0.75)
    a.paint((470, 0, 550, 14), CHARCOAL[1], 0.62, 0.0)
    a.height[:round(14 * S) + 1, round(470 * S):round(550 * S) + 1] = 0
    a.paint((28, 540, 54, 565), CHARCOAL[1], 0.62, 0.0)
    return a.maps()


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
        path = OUT / f"blackbird_{kind}.png"
        if args.check:
            if not path.exists() or path.read_bytes() != data: stale.append(str(path.relative_to(ROOT)))
        else:
            path.write_bytes(data)
            print(f"{path.relative_to(ROOT)}: {len(data):,} bytes")
    mean = ImageStat.Stat(maps["roughness"]).mean[0] / 255.0
    pixels = np.asarray(maps["albedo"])
    red_fraction = float(np.mean((pixels[..., 0] > pixels[..., 1] * 1.5) & (pixels[..., 0] > 70)))
    print(f"roughness mean: {mean:.16f}; red coverage: {red_fraction:.4%}")
    if args.check:
        registry = json.loads((APP / "data/vehicle_paints.json").read_text())
        recorded = registry["detail_map_means"].get("res://assets/vehicle-paints/ugly-stik/blackbird_roughness.png", -1)
        if abs(recorded - mean) > 1e-12: stale.append("vehicle_paints.json roughness mean")
    if red_fraction > 0.012: stale.append("red coverage exceeds the sparse-accent budget")
    if stale: raise SystemExit("Stale BLACKBIRD output: " + ", ".join(stale))
    print("BLACKBIRD: four maps verified" if args.check else "BLACKBIRD: four maps built")


if __name__ == "__main__":
    main()
