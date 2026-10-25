"""Project labelled 3D model points (mm) into a photo with its solved camera and draw them (visual measuring aid).
python3 project_pts.py VIEW OUT.png x0 y0 x1 y1 SCALE 'label:x,y,z' ...   (box in photo pixels)
Also importable: proj(view, P) -> (u, v)."""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def cam(view):
    return json.load(open(f"/home/claude/engine/cams/cam_{view}.json"))


def proj(view, P, c=None):
    c = c or cam(view)
    R, C = np.array(c["R"]), np.array(c["C"])
    X = R @ (np.asarray(P, float) - C)
    return c["f"] * X[0] / X[2] + c["pp"][0], c["f"] * X[1] / X[2] + c["pp"][1]


def ray_plane(view, u, v, n, d, c=None):
    """3D point (mm) where the ray of pixel (u, v) meets the plane n.P = d."""
    c = c or cam(view)
    R, C = np.array(c["R"]), np.array(c["C"])
    dv = R.T @ np.array([(u - c["pp"][0]) / c["f"], (v - c["pp"][1]) / c["f"], 1.0])
    n = np.asarray(n, float)
    t = (d - n @ C) / (n @ dv)
    return C + t * dv


if __name__ == "__main__":
    V, OUT = sys.argv[1], sys.argv[2]
    x0, y0, x1, y1 = map(int, sys.argv[3:7])
    S = float(sys.argv[7])
    c = cam(V)
    im = Image.open(c["image"]).convert("RGB").crop((x0, y0, x1, y1))
    im = im.resize((int(im.width * S), int(im.height * S)), Image.LANCZOS)
    dr = ImageDraw.Draw(im)
    try:
        F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13)
    except Exception:
        F = ImageFont.load_default()
    for spec in sys.argv[8:]:
        lab, xyz = spec.split(":")
        P = [float(t) for t in xyz.split(",")]
        u, v = proj(V, P, c)
        X, Y = (u - x0) * S, (v - y0) * S
        dr.line((X - 6, Y, X + 6, Y), fill=(255, 0, 180), width=2)
        dr.line((X, Y - 6, X, Y + 6), fill=(255, 0, 180), width=2)
        dr.text((X + 5, Y + 3), lab, fill=(255, 0, 180), font=F, stroke_width=2, stroke_fill=(255, 255, 255))
    im.save(OUT)
