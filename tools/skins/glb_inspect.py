"""Inspect a GLB before painting it: materials, textures, nodes, scene-space bounds and UV traps.

    .tools/visual-venv/Scripts/python.exe tools/skins/glb_inspect.py app/assets/aircraft/avanti-s-a200/avanti_s.glb
    ... --material paint_wing        # only primitives using this material

Flags what broke earlier skins: UVs outside 0..1 (the texture repeats), left/right parts sharing one
UV region (mirrored: no lettering there), one image shared by several materials (their UVs may overlap),
and emission textures that would keep glowing the old design.
"""
from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_vehicle_paints as paints  # noqa: E402  (reuses its GLB reader and scene walk)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("glb", type=Path)
    parser.add_argument("--material", default="", help="limit the primitive report to one material")
    args = parser.parse_args()
    doc, _accessor = paints.read_glb(args.glb)
    materials = doc.get("materials", [])
    images_by_material = defaultdict(list)
    print(f"== materials ({len(materials)})")
    for m in materials:
        pbr = m.get("pbrMetallicRoughness", {})
        textures = [k for k in ("baseColorTexture", "metallicRoughnessTexture") if k in pbr]
        textures += [k for k in ("normalTexture", "emissiveTexture", "occlusionTexture") if k in m]
        for key in textures:
            ref = pbr.get(key, m.get(key))
            images_by_material[doc["textures"][ref["index"]]["source"]].append(m["name"])
        colour = [round(c, 3) for c in pbr.get("baseColorFactor", [1, 1, 1, 1])]
        print(f"  {m['name']:26s} base {colour} metal {pbr.get('metallicFactor', 1)} rough {pbr.get('roughnessFactor', 1)}"
              f" textures {textures} alpha {m.get('alphaMode', 'OPAQUE')} ext {list(m.get('extensions', {}))}")
        if "emissiveTexture" in m:
            print(f"    ! emission texture (factor {m.get('emissiveFactor')}): a new design needs its own emission map")
    for image, users in images_by_material.items():
        unique = sorted(set(users))
        if len(unique) > 1:
            print(f"  ! image {image} ({doc['images'][image].get('name')}) is shared by {unique}: check their UVs overlap")
    names = sorted({m["name"] for m in materials})
    wanted = [args.material] if args.material else names
    print("== primitives (scene space: node transforms applied)")
    by_material = defaultdict(list)
    for name, pos, nrm, uv, tris in paints.scene_primitives(args.glb, wanted):
        by_material[name].append((pos, uv))
        lo, hi = uv.min(0), uv.max(0)
        wrap = " WRAPS (UV outside 0..1)" if (lo < -0.001).any() or (hi > 1.001).any() else ""
        print(f"  {name:26s} verts {len(pos):6d} x {pos[:, 0].min():+.3f}..{pos[:, 0].max():+.3f}"
              f" y {pos[:, 1].min():+.3f}..{pos[:, 1].max():+.3f} z {pos[:, 2].min():+.3f}..{pos[:, 2].max():+.3f}"
              f" uv {lo.round(3)}..{hi.round(3)}{wrap}")
    for name, parts in by_material.items():
        left = [uv for pos, uv in parts if pos[:, 0].mean() < -0.02]
        right = [uv for pos, uv in parts if pos[:, 0].mean() > 0.02]
        for a in left:
            for b in right:
                if np.allclose(a.min(0), b.min(0), atol=0.01) and np.allclose(a.max(0), b.max(0), atol=0.01):
                    print(f"  ! {name}: left and right parts share one UV region (mirrored): keep text and"
                          " asymmetric marks off it")
                    break
    node_names = [n.get("name", "") for n in doc.get("nodes", []) if "mesh" in n]
    print(f"== mesh nodes ({len(node_names)}): {', '.join(node_names[:60])}{' ...' if len(node_names) > 60 else ''}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
