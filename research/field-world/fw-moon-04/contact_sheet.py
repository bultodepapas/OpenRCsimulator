#!/usr/bin/env python3
"""FW-MOON-04 visual check: render the generated moon textures offline as a north-up contact sheet.

Orthographic sphere seen from sub-observer longitude 0, latitude 0, north up, so lunar east (Mare Crisium) is on the
right as seen from Earth. Albedo = moon_albedo_2k.jpg (sRGB decoded to linear, box-filtered to 1024x512); normal =
moon_normal_1k.png decoded n = 2 * rgb - 1 in the local (east, north, up) frame. Brightness is lunar-Lambert
(McEwen 1991): r = A * [2 L mu0 / (mu0 + mu) + (1 - L) mu0], L(a) = 1 - 0.019 a + 2.42e-4 a^2 - 1.46e-6 a^3
(a in degrees), clamped >= 0. Each panel is exposed so that its 99.5th percentile is 0.95, then sRGB encoded: this is
a placement and relief check, not a photometric one (photometry is FW-MOON-05).

  "$(app/tests/visual-env.sh)" research/field-world/fw-moon-04/contact_sheet.py [out.png]

Also prints numeric checks: albedo statistics and the sign of the normal-map slopes inside two craters.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
TEX = ROOT / "app" / "assets" / "sky" / "moon"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs" / "research" / "field-world" / "FW-MOON-04" / "contact-sheet.png"
DISC = 256
SS = 2  # supersampling per axis
LABEL_H = 18
FEATURES = {  # name: (lat, east lon), approximate centres from the IAU Gazetteer of Planetary Nomenclature
    "Imbrium": (32.8, -15.6),
    "Serenitatis": (28.0, 17.5),
    "Crisium": (17.0, 59.1),
    "Copernicus": (9.6, -20.1),
    "Tycho": (-43.3, -11.2),
    "Grimaldi": (-5.2, -68.6),
}


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1.0 / 2.4) - 0.055)


def load_textures():
    albedo = np.asarray(Image.open(TEX / "moon_albedo_2k.jpg").convert("RGB")).astype(np.float64) / 255.0
    albedo_lin = srgb_to_linear(albedo)
    albedo_lin = albedo_lin.reshape(512, 2, 1024, 2, 3).mean(axis=(1, 3))
    normal = np.asarray(Image.open(TEX / "moon_normal_1k.png").convert("RGB")).astype(np.float64) / 255.0 * 2.0 - 1.0
    return albedo, albedo_lin, normal


def sample(tex, lon_deg, lat_deg):
    """Bilinear equirectangular lookup, u = (lon + 180) / 360, v = (90 - lat) / 180, longitude wraps."""
    h, w = tex.shape[:2]
    x = (lon_deg + 180.0) / 360.0 * w - 0.5
    y = (90.0 - lat_deg) / 180.0 * h - 0.5
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    x1 = (x0 + 1) % w
    x0 = x0 % w
    y1 = np.clip(y0 + 1, 0, h - 1)
    y0 = np.clip(y0, 0, h - 1)
    top = tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx
    bottom = tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx
    return top * (1 - fy) + bottom * fy


def lunar_lambert_l(alpha_deg):
    a = alpha_deg
    return max(0.0, 1.0 - 0.019 * a + 2.42e-4 * a * a - 1.46e-6 * a ** 3)


def render(albedo_lin, normal, sun_lon_deg, flat_albedo=False, use_normals=True):
    n = DISC * SS
    c = (np.arange(n) + 0.5) / n * 2.0 - 1.0
    sx, sy = np.meshgrid(c, -c)  # screen x right (lunar east), y up (north)
    inside = sx * sx + sy * sy < 1.0
    sz = np.sqrt(np.clip(1.0 - sx * sx - sy * sy, 0.0, 1.0))
    # Moon-fixed: X toward the observer (lon 0, lat 0), Y = lon 90 E (screen right), Z = north (screen up).
    px, py, pz = sz, sx, sy
    lon = np.degrees(np.arctan2(py, px))
    lat = np.degrees(np.arcsin(np.clip(pz, -1.0, 1.0)))
    lam, phi = np.radians(lon), np.radians(lat)
    east = np.stack([-np.sin(lam), np.cos(lam), np.zeros_like(lam)], -1)
    north = np.stack([-np.sin(phi) * np.cos(lam), -np.sin(phi) * np.sin(lam), np.cos(phi)], -1)
    up = np.stack([px, py, pz], -1)
    if use_normals:
        t = sample(normal, lon, lat)
        nrm = t[..., 0:1] * east + t[..., 1:2] * north + t[..., 2:3] * up
        nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    else:
        nrm = up
    s = math.radians(sun_lon_deg)
    sun = np.array([math.cos(s), math.sin(s), 0.0])
    view = np.array([1.0, 0.0, 0.0])
    mu0 = np.clip(nrm @ sun, 0.0, None) * (up @ sun > -0.02)  # relief cannot light the geometric night side
    mu = np.clip(nrm @ view, 1e-4, None)
    alpha = abs(sun_lon_deg)
    L = lunar_lambert_l(alpha)
    r = 2.0 * L * mu0 / (mu0 + mu) + (1.0 - L) * mu0
    a = np.full(lon.shape + (3,), 0.12) if flat_albedo else sample(albedo_lin, lon, lat)
    rgb = a * r[..., None] * inside[..., None]
    rgb = rgb.reshape(DISC, SS, DISC, SS, 3).mean(axis=(1, 3))
    lit = rgb[rgb.max(axis=-1) > 0]
    scale = 0.95 / max(np.percentile(lit.max(axis=-1), 99.5), 1e-9) if lit.size else 1.0
    return (linear_to_srgb(rgb * scale) * 255.0 + 0.5).astype(np.uint8)


def to_screen(lat, lon):
    la, lo = math.radians(lat), math.radians(lon)
    x, y, z = math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)
    return (y + 1.0) * 0.5 * DISC, (1.0 - z) * 0.5 * DISC, x > 0


def crater_sign_check(normal):
    """Mean east component on the west and east inner walls, and north component on the north/south walls."""
    h, w = normal.shape[:2]
    out = []
    for name, (lat, lon, radius_km) in {"Tycho": (-43.3, -11.2, 42.5), "Copernicus": (9.6, -20.1, 46.5)}.items():
        dlon = math.degrees(radius_km / (1737.4 * math.cos(math.radians(lat))))
        dlat = math.degrees(radius_km / 1737.4)
        def at(la, lo):
            return normal[int((90.0 - la) / 180.0 * h), int((lo + 180.0) / 360.0 * w)]
        west = np.mean([at(lat, lon - f * dlon)[0] for f in (0.4, 0.55, 0.7)])
        east = np.mean([at(lat, lon + f * dlon)[0] for f in (0.4, 0.55, 0.7)])
        north = np.mean([at(lat + f * dlat, lon)[1] for f in (0.4, 0.55, 0.7)])
        south = np.mean([at(lat - f * dlat, lon)[1] for f in (0.4, 0.55, 0.7)])
        out.append(f"{name}: n_east west wall {west:+.3f}, east wall {east:+.3f}; n_north north wall {north:+.3f}, south wall {south:+.3f}")
    return out


def main():
    albedo, albedo_lin, normal = load_textures()
    mean = albedo.reshape(-1, 3).mean(axis=0)
    print(f"albedo sRGB mean R {mean[0]:.4f} G {mean[1]:.4f} B {mean[2]:.4f} all {mean.mean():.4f}; "
          f"linear mean {srgb_to_linear(albedo).mean():.4f}")
    for line in crater_sign_check(normal):
        print(line)
    panels = [
        ("waxing crescent, a=120", render(albedo_lin, normal, 120.0)),
        ("first quarter, a=90", render(albedo_lin, normal, 90.0)),
        ("waxing gibbous, a=45", render(albedo_lin, normal, 45.0)),
        ("full, a=0", render(albedo_lin, normal, 0.0)),
        ("relief only, sun at 75 E", render(albedo_lin, normal, 75.0, flat_albedo=True)),
        ("albedo, no relief + features", render(albedo_lin, normal, 0.0, use_normals=False)),
    ]
    cols, rows = 3, 2
    sheet = Image.new("RGB", (cols * DISC, rows * (DISC + LABEL_H)), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for k, (label, img) in enumerate(panels):
        ox, oy = (k % cols) * DISC, (k // cols) * (DISC + LABEL_H)
        sheet.paste(Image.fromarray(img), (ox, oy + LABEL_H))
        draw.text((ox + 4, oy + 3), label, fill=(220, 220, 220), font=font)
    # 255 image colours plus one reserved marker colour, so the labels survive the palette reduction.
    sheet = sheet.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = sheet.getpalette()[: 255 * 3] + [255, 90, 30]
    sheet.putpalette(palette)
    draw = ImageDraw.Draw(sheet)
    ox, oy = 2 * DISC, DISC + 2 * LABEL_H
    for name, (lat, lon) in FEATURES.items():
        x, y, visible = to_screen(lat, lon)
        if visible:
            draw.ellipse((ox + x - 4, oy + y - 4, ox + x + 4, oy + y + 4), outline=255)
            tx = ox + x + 6 if x < 0.7 * DISC else ox + x - 6 - draw.textlength(name, font=font)
            draw.text((tx, oy + y - 6), name, fill=255, font=font)
    sheet.save(OUT, optimize=True)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
