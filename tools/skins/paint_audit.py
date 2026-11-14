"""Quantitative skin audit: texel density, stretch and texel conflicts for painted materials.

    .tools/visual-venv/Scripts/python.exe tools/skins/paint_audit.py <model.glb> <material>[,<material>...] <width>x<height>
    ... app/assets/aircraft/avanti-s-a200/avanti_s.glb paint_wing 2048x2048

Texel density (px/mm) says how small lettering and decals can be: aim for letters >= 20 px tall.
Conflicts count texels shared by surface points that disagree (upper vs lower face, or very different
positions): designs that depend on that signal will show artefacts there.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_vehicle_paints as paints  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("glb", type=Path)
    parser.add_argument("materials")
    parser.add_argument("size", help="atlas size, e.g. 2048x2048 (the size you will bake, not the stock image)")
    args = parser.parse_args()
    width, height = (int(v) for v in args.size.lower().split("x"))
    materials = tuple(args.materials.split(","))
    density, area, stretch = [], [], []
    grid = (512, 512)
    count = np.zeros(grid)
    up_sum = np.zeros(grid)
    z_min = np.full(grid, np.inf)
    z_max = np.full(grid, -np.inf)
    for _name, pos, nrm, uv, tris in paints.scene_primitives(args.glb, materials):
        p = pos[tris]
        t = uv[tris] * np.array([width, height])
        world = 0.5 * np.linalg.norm(np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0]), axis=1) * 1e6
        e1, e2 = t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]
        tex = 0.5 * np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0])
        ok = world > 1e-3
        density.append(np.sqrt(tex[ok] / world[ok]))
        area.append(world[ok])
        w1 = np.linalg.norm(p[:, 1] - p[:, 0], axis=1)[ok] * 1000
        w2 = np.linalg.norm(p[:, 2] - p[:, 0], axis=1)[ok] * 1000
        r1 = np.linalg.norm(e1, axis=1)[ok] / np.maximum(w1, 1e-6)
        r2 = np.linalg.norm(e2, axis=1)[ok] / np.maximum(w2, 1e-6)
        stretch.append(np.maximum(r1, r2) / np.maximum(np.minimum(r1, r2), 1e-6))
        centre = uv[tris].mean(1)
        u = ((centre[:, 0] % 1.0) * grid[1]).astype(int) % grid[1]
        v = ((centre[:, 1] % 1.0) * grid[0]).astype(int) % grid[0]
        up = (nrm[tris].mean(1)[:, 1] >= 0).astype(float)
        np.add.at(count, (v, u), 1)
        np.add.at(up_sum, (v, u), up)
        np.minimum.at(z_min, (v, u), p.mean(1)[:, 2])
        np.maximum.at(z_max, (v, u), p.mean(1)[:, 2])
    d = np.concatenate(density)
    a = np.concatenate(area)
    s = np.concatenate(stretch)
    order = np.argsort(d)
    cum = np.cumsum(a[order]) / a.sum()
    pct = lambda q: d[order][min(np.searchsorted(cum, q), len(order) - 1)]  # noqa: E731
    covered = count > 0
    mixed_faces = covered & (up_sum > 0) & (up_sum < count)
    far_apart = covered & (z_max - z_min > 0.05)
    print(f"{','.join(materials)} at {width}x{height}: surface {a.sum() / 1e6:.3f} m2")
    print(f"  texel density px/mm (area-weighted) p10 {pct(0.1):.2f} p50 {pct(0.5):.2f} p90 {pct(0.9):.2f}"
          f" | area under 0.5 px/mm {a[d < 0.5].sum() / a.sum() * 100:.1f}%")
    print(f"  stretch > 3:1 on {a[s > 3].sum() / a.sum() * 100:.1f}% of the area")
    print(f"  texels shared by up- and down-facing faces {mixed_faces.sum() / covered.sum() * 100:.1f}%,"
          f" by points > 5 cm apart along z {far_apart.sum() / covered.sum() * 100:.1f}%")
    print(f"  smallest legible letter height at p10 density: {20 / max(pct(0.1), 1e-6):.0f} mm")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
