"""TRA-09: animated titles in the simulator's crystal-green interface style.

Palette from app/ui/ui_theme.gd: FOCUS #66FF16, GLASS_EMISSION #3DFF0A, CRYSTAL #C4FFB3,
PRIMARY_TEXT #E4FFDA, PANEL #111111. Each cue renders one RGBA PNG per shot frame; frames after
the entrance are identical and hard-linked, so only the moving frames cost rendering time.
"""
from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
FONT = HERE / "assets/fonts/BarlowCondensed-SemiBold.ttf"
REGULAR = HERE / "assets/fonts/BarlowCondensed-Regular.ttf"
W, H, FPS = 1920, 1080, 60
FOCUS = (102, 255, 22)
EMISSION = (61, 255, 10)
CRYSTAL = (196, 255, 179)
PRIMARY_TEXT = (228, 255, 218)
SCRIM = (4, 12, 6)
ENTRANCE_S = 1.2
EXIT_S = 0.35


def _font(size, regular=False):
    return ImageFont.truetype(str(REGULAR if regular else FONT), size)


def _ease_out(p, power=4.0):
    p = min(1.0, max(0.0, p))
    return 1.0 - (1.0 - p) ** power


def _text_layer(text, face, fill, stroke=1):
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    box = probe.textbbox((0, 0), text, font=face, stroke_width=stroke)
    pad = 40
    layer = Image.new("RGBA", (box[2] - box[0] + 2 * pad, box[3] - box[1] + 2 * pad))
    ImageDraw.Draw(layer).text((pad - box[0], pad - box[1]), text, font=face, fill=fill + (255,),
                               stroke_width=stroke, stroke_fill=(3, 9, 5, 90))
    return layer, (box[0] - pad, box[1] - pad)


def _glow(layer, radius, color):
    alpha = layer.getchannel("A").filter(ImageFilter.GaussianBlur(radius))
    halo = Image.new("RGBA", layer.size, color + (0,))
    halo.putalpha(alpha)
    return halo


def _scale_alpha(image, factor):
    if factor >= 0.999:
        return image
    out = image.copy()
    out.putalpha(out.getchannel("A").point(lambda a: int(a * max(0.0, factor))))
    return out


class CrystalCue:
    """Static layout of one cue; `frame(tau, exit_q)` composes it at cue time tau."""

    def __init__(self, cue, lower=False):
        x, y = cue.get("xy", [96, 88])
        size = cue.get("size", 84)
        self.rows = []
        kicker = cue.get("kicker", "")
        if kicker:
            layer, off = _text_layer(kicker.upper(), _font(26, True), CRYSTAL, 0)
            self.rows.append({"kind": "kicker", "layer": layer, "xy": (x + 54 + off[0], y + 2 + off[1])})
        self.bar = (x, y + 18)
        title_y = y + 42
        lines = cue["headline"]
        assert 1 <= len(lines) <= 2
        for i, line in enumerate(lines):
            last = i == len(lines) - 1
            layer, off = _text_layer(line, _font(size), FOCUS if last else PRIMARY_TEXT)
            row = {"kind": "line", "index": i, "last": last, "layer": layer,
                   "xy": (x + off[0], title_y + i * (size - 2) + off[1])}
            row["glow"] = _glow(layer, 14 if last else 8, EMISSION if last else CRYSTAL)
            row["glow_gain"] = 0.95 if last else 0.25
            self.rows.append(row)
        detail = cue.get("detail", "")
        if detail:
            layer, off = _text_layer(detail, _font(31, True), PRIMARY_TEXT, 0)
            self.rows.append({"kind": "detail", "layer": layer,
                              "xy": (x + 2 + off[0], title_y + len(lines) * (size - 2) + 18 + off[1])})
        self.line_count = len(lines)
        if cue.get("align") == "center":
            left = min(r["xy"][0] + 40 for r in self.rows)
            right = max(r["xy"][0] + r["layer"].width - 40 for r in self.rows)
            dx = int((W - (right - left)) / 2 - left)
            for r in self.rows:
                r["xy"] = (r["xy"][0] + dx, r["xy"][1])
            self.bar = (self.bar[0] + dx, self.bar[1])
        self.credit = None
        if cue.get("credit"):
            layer, off = _text_layer(cue["credit"], _font(24, True), (150, 176, 160), 0)
            self.credit = {"layer": layer, "xy": ((W - layer.width) // 2, 1004 + off[1])}
        boxes = [(r["xy"][0] + 40, r["xy"][1] + 40, r["xy"][0] + r["layer"].width - 40, r["xy"][1] + r["layer"].height - 40)
                 for r in self.rows]
        bottom_limit = H - 64 if lower else 450
        assert all(72 <= b[0] and b[2] <= W - 72 and 60 <= b[1] and b[3] <= bottom_limit for b in boxes), boxes
        self.bounds = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
        self.scrim = None if lower else self._scrim(x)

    def _scrim(self, x):
        left, top, right, bottom = self.bounds
        mask = Image.new("L", (W // 4, H // 4))
        px = mask.load()
        for py in range(min(H // 4, (bottom + 170) // 4)):
            yy = py * 4
            fy = math.exp(-((yy - (top + bottom) / 2) / 210) ** 2) * min(1.0, max(0.0, (bottom + 170 - yy) / 100))
            for qx in range(min(W // 4, (right + 380) // 4)):
                xx = qx * 4
                fx = math.exp(-((xx - (x + right) / 2) / (right - x + 200)) ** 2) * min(1.0, max(0.0, (right + 380 - xx) / 160))
                px[qx, py] = int(130 * fx * fy)
        scrim = Image.new("RGBA", (W, H), SCRIM + (0,))
        scrim.putalpha(mask.resize((W, H), Image.Resampling.BICUBIC))
        return scrim

    def frame(self, tau, exit_q=1.0):
        im = Image.new("RGBA", (W, H))
        if self.scrim is not None:
            im.alpha_composite(_scale_alpha(self.scrim, _ease_out(tau / 0.35, 2.0) * exit_q))
        drift = int(round(-36 * (1.0 - exit_q) ** 2))
        draw = ImageDraw.Draw(im)
        bar_p = _ease_out(tau / 0.28, 3.0)
        if bar_p > 0 and any(r["kind"] == "kicker" for r in self.rows):
            bx, by = self.bar
            length = int(36 * bar_p)
            glow = Image.new("RGBA", (W, H))
            ImageDraw.Draw(glow).rectangle((bx + drift, by - 3, bx + drift + length, by + 3), fill=EMISSION + (int(150 * exit_q),))
            im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(5)))
            draw.rectangle((bx + drift, by - 1, bx + drift + length, by + 2), fill=FOCUS + (int(255 * exit_q),))
        for row in self.rows:
            layer = row["layer"]
            rx, ry = row["xy"]
            rx += drift
            if row["kind"] == "kicker":
                p = _ease_out((tau - 0.05) / 0.35, 3.0)
                lift = 0
            elif row["kind"] == "line":
                start = 0.10 + 0.13 * row["index"]
                p = _ease_out((tau - start) / 0.50, 5.0)
                lift = int(round(24 * (1.0 - p)))
            else:
                p = _ease_out((tau - 0.50) / 0.35, 2.0)
                lift = int(round(10 * (1.0 - p)))
            if p <= 0.0:
                continue
            reveal = layer.width if row["kind"] == "detail" else max(1, int(layer.width * p))
            alpha = (min(1.0, p * 1.8) if row["kind"] != "detail" else p * 0.9) * exit_q
            if row["kind"] == "line":
                land = start + 0.50
                flash = 1.0 + (1.6 if row["last"] else 0.6) * math.exp(-((tau - land) / 0.16) ** 2)
                gain = min(1.0, row["glow_gain"] * flash)
                halo = _scale_alpha(row["glow"].crop((0, 0, reveal, layer.height)), gain * alpha)
                im.alpha_composite(halo, (rx, ry + lift))
                if flash > 1.05:
                    halo2 = _scale_alpha(row["glow"].crop((0, 0, reveal, layer.height)), (flash - 1.0) * 0.6 * alpha)
                    im.alpha_composite(halo2, (rx, ry + lift))
            im.alpha_composite(_scale_alpha(layer.crop((0, 0, reveal, layer.height)), alpha), (rx, ry + lift))
            if row["kind"] in ("line", "kicker") and p < 0.995:
                # Crystal scan edge leading the wipe.
                edge_x = rx + reveal
                edge = Image.new("RGBA", (24, layer.height), (0, 0, 0, 0))
                ImageDraw.Draw(edge).rectangle((10, 34, 13, layer.height - 34), fill=CRYSTAL + (int(230 * (1 - p) ** 0.5 * exit_q),))
                im.alpha_composite(edge.filter(ImageFilter.GaussianBlur(3)), (edge_x - 12, ry + lift))
        if self.credit is not None:
            p = _ease_out((tau - 0.7) / 0.5, 2.0) * exit_q
            if p > 0:
                im.alpha_composite(_scale_alpha(self.credit["layer"], p * 0.85), self.credit["xy"])
        return im


def render_cue(directory, cue, frames, duration, lower=False):
    """Write frames 00000..frames-1 for one cue; return the number of distinct renders."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    layout = CrystalCue(cue, lower)
    start = float(cue.get("start", 0))
    end = float(cue.get("end", duration))
    exits = end <= duration
    blank = directory / "blank.png"
    Image.new("RGBA", (W, H)).save(blank, compress_level=1)
    static = directory / "static.png"
    rendered = 0
    for f in range(frames):
        t = f / FPS
        target = directory / f"{f:05d}.png"
        if target.exists():
            target.unlink()
        tau = t - start
        if t < start or (exits and t >= end):
            os.link(blank, target)
            continue
        exit_q = min(1.0, max(0.0, (end - t) / EXIT_S)) if exits else 1.0
        if tau >= ENTRANCE_S and exit_q >= 1.0:
            if not static.exists():
                layout.frame(ENTRANCE_S + 1.0).save(static, compress_level=1)
                rendered += 1
            os.link(static, target)
            continue
        layout.frame(tau, exit_q).save(target, compress_level=1)
        rendered += 1
    return rendered
