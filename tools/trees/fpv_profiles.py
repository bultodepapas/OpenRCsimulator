"""Bake FPV trunk sections and leaf-area density from the shipped trees. Run with --check to verify."""
from __future__ import annotations

import argparse
import base64
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/landscape/vegetation"))
from convert_forest_shrub import accessor_values  # noqa: E402
from convert_landscapelab_trees import _identity_node  # noqa: E402

OUTPUT = ROOT / "app/data/fpv_tree_profiles.json"
SPECIES = {"maple_tree", "landscapelab_quercus", "landscapelab_quercus2", "landscapelab_fagus", "landscapelab_pine"}
GRID = 24
# Up to six bark tubes per tree, three large sections on each. Radius and all lengths use tree heights.
MAX_LIMBS = 6
MIN_LIMB_RADIUS = 0.001


def model(path):
    data = path.read_bytes()
    if path.suffix == ".glb":
        end = 20 + struct.unpack_from("<I", data, 12)[0]
        return json.loads(data[20:end]), data[end + 8:]
    doc = json.loads(data)
    return doc, (path.parent / doc["buffers"][0]["uri"]).read_bytes()


def alpha_pixels(path, doc, binary, material):
    texture = material["pbrMetallicRoughness"]["baseColorTexture"]
    assert not texture.get("extensions") and texture.get("texCoord", 0) == 0
    ref = doc["images"][doc["textures"][texture["index"]]["source"]]
    if "uri" in ref:
        data = (path.parent / ref["uri"]).read_bytes()
    else:
        view = doc["bufferViews"][ref["bufferView"]]
        start = view.get("byteOffset", 0)
        data = binary[start:start + view["byteLength"]]
    with Image.open(io.BytesIO(data)) as image:
        return np.array(image.convert("RGBA").getchannel("A"))


def leaf_grid(triangles, uv, alpha, cutoff, lo, high):
    """Area-weighted samples of opaque leaf texels, resolved in local 3D cells."""
    grid = np.zeros((GRID, GRID, GRID), dtype=float)
    for triangle, tri_uv in zip(triangles, uv, strict=True):
        a, b, c = triangle
        area = 0.5 * np.linalg.norm(np.cross(b-a, c-a))
        if area == 0:
            continue
        count = max(8, int(np.ceil(area * (GRID * 8) ** 2)))
        # Equal-area, repeatable samples in the triangle; high UV transparency leaves actual holes.
        i = np.arange(count) + 0.5
        u = np.sqrt(i / count)
        v = (i * 0.6180339887498949) % 1.0
        weights = np.column_stack((1-u, u*(1-v), u*v))
        tex = (weights @ tri_uv) % 1.0
        keep = alpha[(tex[:, 1] * alpha.shape[0]).astype(int), (tex[:, 0] * alpha.shape[1]).astype(int)] >= cutoff * 255
        coords = (weights[keep] @ triangle - lo) / (high-lo)
        x, y, z = np.clip((coords * GRID).astype(int), 0, GRID-1).T
        np.add.at(grid, (y, z, x), area / count)
    # Density is normalized one-sided leaf area per typical cell cross-section.
    cell_area = (np.prod(high - lo) ** (2/3)) / GRID**2
    return np.rint(255 * np.minimum(1.0, grid / cell_area)).astype(np.uint8)


def stem_rings(triangles, y, minimum_radius=0.002):
    """Join bark-plane intersection segments into cross sections, including separate limbs."""
    edges = {}
    cut = triangles[(triangles[:, :, 1].min(axis=1) < y) & (triangles[:, :, 1].max(axis=1) > y)]
    for tri in cut:
        points = []
        for i, a in enumerate(tri):
            b = tri[(i+1) % 3]
            if (a[1] < y) == (b[1] < y):
                continue
            p = a + (y-a[1]) / (b[1]-a[1]) * (b-a)
            points.append(tuple(np.round(p[[0, 2]], 7)))
        if len(points) == 2 and points[0] != points[1]:
            a, b = points
            edges.setdefault(a, set()).add(b)
            edges.setdefault(b, set()).add(a)
    seen = set()
    rings = []
    for first in edges:
        if first in seen:
            continue
        stack, group = [first], []
        while stack:
            key = stack.pop()
            if key in seen:
                continue
            seen.add(key)
            group.append(key)
            stack.extend(edges[key])
        if len(group) < 3 or any(len(edges[p]) != 2 for p in group):
            continue
        # Use only a point inside a closed bark cross section, including concave limb outlines.
        points = np.array(group)
        center = (points.min(axis=0) + points.max(axis=0)) / 2
        distances = []
        crossings = 0
        for p in group:
            for q in edges[p]:
                if q <= p:
                    continue
                a, b = np.array(p), np.array(q)
                d = b-a
                offset = center-a
                distances.append(np.linalg.norm(offset-np.clip(offset @ d / (d @ d), 0, 1)*d))
                if (a[1] > center[1]) != (b[1] > center[1]) and a[0] + (center[1]-a[1])*d[0]/d[1] > center[0]:
                    crossings += 1
        radius = min(distances)
        if crossings % 2 and radius >= minimum_radius:
            rings.append((center, radius))
    return rings


def stem_sections(wood):
    """Follow the largest connected stem upwards, fitting vertical capsules inside its sampled bark."""
    sections = []
    last_center = None
    last_radius = 0.0
    for bottom in np.arange(0, 0.95, 0.05):
        sample_y = bottom + 0.025
        rings = stem_rings(wood, sample_y)
        if last_center is not None:
            rings = [(p, r) for p, r in rings if np.linalg.norm(p-last_center) < last_radius + r]
        if not rings:
            break
        center, radius = max(rings, key=lambda ring: ring[1])
        last_center, last_radius = center, radius
        # Adjacent nearly concentric bands of similar calibre share a capsule.
        if sections:
            x, z, _, _, old_r = sections[-1]
            if np.linalg.norm(center-[x,z]) + abs(old_r-radius) <= 0.30*old_r:
                sections[-1][3] = bottom+0.05
                sections[-1][4] = min(old_r, radius)
                continue
        sections.append([*center, bottom, bottom+0.05, radius])
    if not sections:
        raise ValueError("no grounded stem could be fitted")
    return np.round(sections, 7).tolist()


def limb_meshes(wood):
    """Bark on the five shipped assets consists of separate triangle tubes. Weld their UV seams."""
    vertices, ids = np.unique(np.round(wood.reshape(-1, 3), 7), axis=0, return_inverse=True)
    ids = ids.reshape(-1, 3)
    parents = list(range(len(vertices)))

    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for a, b, c in ids:
        parents[root(b)] = root(a)
        parents[root(c)] = root(a)
    labels = np.array([root(i) for i in ids[:, 0]])
    meshes = [wood[labels == i] for i in np.unique(labels)]
    limbs = [mesh for mesh in meshes if mesh[:, :, 1].min() > 0.02]
    # Surface area favors substantial long branches. Select the best fits after checking their interior.
    return sorted(limbs, key=lambda t: np.linalg.norm(np.cross(t[:, 1]-t[:, 0], t[:, 2]-t[:, 0]), axis=1).sum(),
                  reverse=True)[:MAX_LIMBS * 3]


def interior_radius(triangles, start, end, nominal):
    """Lower bound on distance of the complete line segment to this tube's triangles."""
    # Distance to a triangle is 1-Lipschitz along a line. Subtract half the sample spacing
    # from the measured clearance. This also detects a chord cutting across a curved limb.
    length = np.linalg.norm(end-start)
    intervals = max(1, int(np.ceil(length / (0.4 * nominal))))
    samples = np.linspace(start, end, intervals+1)[:, None, :]
    a, b, c = triangles.transpose(1, 0, 2)
    n = np.cross(b-a, c-a)
    norm = np.linalg.norm(n, axis=1)
    good = norm > 1.e-14
    if not good.any():
        return 0
    a, b, c, n = a[good], b[good], c[good], n[good] / norm[good, None]
    inside = np.ones((len(samples), len(a)), dtype=bool)
    distances = np.full(inside.shape, np.inf)
    for p, q in ((a,b), (b,c), (c,a)):
        edge = q-p
        offset = samples-p
        inside &= (np.cross(edge, offset) * n).sum(axis=2) >= 0
        t = np.clip((offset*edge).sum(axis=2) / (edge*edge).sum(axis=1), 0, 1)
        distances = np.minimum(distances, np.linalg.norm(offset - t[:,:,None] * edge, axis=2))
    plane = np.abs(((samples-a)*n).sum(axis=2))
    return max(0, np.where(inside, plane, distances).min() - length/(2*intervals) - 1.e-6)


def limb_sections(wood):
    """Select substantial off-axis bark tubes and fit up to three straight inner capsules each."""
    selected = []
    for mesh in limb_meshes(wood):
        vertices = np.unique(mesh.reshape(-1, 3), axis=0)
        # The farthest vertex pair gives a reusable transverse slicing direction.
        delta = vertices[:, None] - vertices
        a, b = np.unravel_index((delta*delta).sum(axis=2).argmax(), delta.shape[:2])
        axis = vertices[b]-vertices[a]
        axis /= np.linalg.norm(axis)
        # Walk outwards from the stem. Pine limbs can descend while broadleaf limbs usually rise.
        if np.linalg.norm(vertices[a][[0,2]]) > np.linalg.norm(vertices[b][[0,2]]):
            axis = -axis
        u = np.cross(axis, np.eye(3)[np.abs(axis).argmin()])
        u /= np.linalg.norm(u)
        basis = np.array([u, axis, np.cross(u,axis)])
        local = mesh @ basis.T
        low, high = local[:, :, 1].min(), local[:, :, 1].max()
        cuts = []
        for fraction in (0.07, 0.23, 0.43, 0.65):
            y = low + (high-low)*fraction
            rings = stem_rings(local, y, MIN_LIMB_RADIUS)
            if not rings:
                break
            center, r = max(rings, key=lambda item: item[1])
            cuts.append((np.array([center[0], y, center[1]]) @ basis, r))
        pieces = []
        for (start, r0), (end, r1) in zip(cuts, cuts[1:]):
            radius = interior_radius(mesh, start, end, min(r0,r1))
            if radius >= MIN_LIMB_RADIUS:
                pieces.append([*start, *end, radius])
        if pieces:
            volume = sum(row[6]**2 * np.linalg.norm(np.array(row[:3]) - row[3:6]) for row in pieces)
            selected.append((volume, pieces))
    selected.sort(key=lambda entry: entry[0], reverse=True)
    return [np.round(row, 7).tolist() for _, pieces in selected[:MAX_LIMBS] for row in pieces]


def profile(asset):
    path = ROOT / "app" / asset["scene"].removeprefix("res://")
    doc, binary = model(path)
    _identity_node(doc)
    bounds = asset["source_bounds_m"]
    lo = np.array(bounds["min"]) / bounds["height"]
    high = np.array(bounds["max"]) / bounds["height"]
    origin_y = lo[1]
    lo[1], high[1] = 0, 1
    modes = [doc["materials"][p["material"]].get("alphaMode", "OPAQUE") for p in doc["meshes"][0]["primitives"]]
    if sorted(modes) != ["MASK", "OPAQUE"]:
        raise ValueError(f"{path.name}: expected one opaque bark and one alpha-masked leaf primitive, found {modes}")
    for prim in doc["meshes"][0]["primitives"]:
        def attribute(name):
            return np.array(accessor_values(doc, binary, prim["attributes"][name]))
        pos = attribute("POSITION") / bounds["height"]
        pos[:, 1] -= origin_y
        ids = np.array(accessor_values(doc, binary, prim["indices"])).reshape(-1, 3)
        material = doc["materials"][prim["material"]]
        if material.get("alphaMode", "OPAQUE") == "OPAQUE":
            wood = pos[ids]
        else:
            assert material["alphaMode"] == "MASK"
            alpha = alpha_pixels(path, doc, binary, material)
            leaves = leaf_grid(pos[ids], attribute("TEXCOORD_0")[ids], alpha, material.get("alphaCutoff", 0.5), lo, high)
    return {"license": asset["source_id"], "bounds": np.round([lo, high], 8).tolist(),
            "stem": stem_sections(wood), "limbs": limb_sections(wood),
            "leaf_area": base64.b64encode(leaves.tobytes()).decode("ascii")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    catalog = json.loads((ROOT / "app/assets/landscape/vegetation/catalog.json").read_bytes())
    profiles = {a["id"]: profile(a) for a in catalog["assets"] if a["id"] in SPECIES}
    assert profiles.keys() == SPECIES
    payload = {"generated_by": "tools/trees/fpv_profiles.py", "grid": GRID,
               "notices": {"landscapelab_tree_2026": "CC BY-SA 4.0, res://assets/landscape/vegetation/LICENSE_LANDSCAPELAB.txt",
                           "lolipop_maple_2026": "CC BY 4.0, res://assets/landscape/vegetation/LICENSE_MAPLE.txt"},
               "profiles": profiles}
    encoded = (json.dumps(payload, indent=2) + "\n").encode()
    if args.check:
        if OUTPUT.read_bytes().replace(b"\r\n", b"\n") != encoded:
            raise SystemExit(f"{OUTPUT.name}: stale tree profiles")
    else:
        OUTPUT.write_bytes(encoded)
    for key, data in profiles.items():
        print(f"{key}: {len(data['stem'])} stem sections to {data['stem'][-1][3]:.2f} height, "
              f"{len(data['limbs'])} lateral wood capsules")


if __name__ == "__main__":
    main()
