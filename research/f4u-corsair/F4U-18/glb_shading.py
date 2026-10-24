"""F4U-18: shading-noise audit of named meshes in a GLB, independent of Blender and Godot.

For each mesh: the angle between every stored corner normal and its triangle's geometric normal, and the dihedral
angle between neighbouring triangles (vertices welded by position, 0.01 mm). A smooth skin has small values for both;
dents, creases and noisy custom normals show as a heavy tail. Reports percentiles and the share above 10° and 25°.

    python research/f4u-corsair/F4U-18/glb_shading.py MODEL.glb [mesh ...]
"""
import sys
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glb_orientation import accessor, load, local_matrix


def angles(a, b):
    a = a / np.maximum(np.linalg.norm(a, axis=-1, keepdims=True), 1e-12)
    b = b / np.maximum(np.linalg.norm(b, axis=-1, keepdims=True), 1e-12)
    return np.degrees(np.arccos(np.clip(np.einsum("...i,...i->...", a, b), -1, 1)))


def main():
    gltf, blob = load(sys.argv[1])
    wanted = set(sys.argv[2:])
    worlds = {}
    def walk(index, parent):
        worlds[index] = parent @ local_matrix(gltf["nodes"][index])
        for child in gltf["nodes"][index].get("children", []):
            walk(child, worlds[index])
    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(root, np.eye(4))
    print(f"{'mesh':28} {'tris':>7} {'corner p50':>10} {'p95':>6} {'>10°':>6} {'>25°':>6} {'dihedral p50':>12} {'p95':>6} {'>10°':>6} {'>25°':>6}")
    for index, node in enumerate(gltf["nodes"]):
        if "mesh" not in node or (wanted and node.get("name") not in wanted):
            continue
        w = worlds[index]
        pos_all, nrm_all, tri_all, offset = [], [], [], 0
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            pos = accessor(gltf, blob, prim["attributes"]["POSITION"]) @ w[:3, :3].T + w[:3, 3]
            nrm = accessor(gltf, blob, prim["attributes"]["NORMAL"]) @ np.linalg.inv(w[:3, :3])
            tri = accessor(gltf, blob, prim["indices"]).reshape(-1, 3) + offset
            pos_all.append(pos); nrm_all.append(nrm); tri_all.append(tri); offset += len(pos)
        pos, nrm, tri = np.concatenate(pos_all), np.concatenate(nrm_all), np.concatenate(tri_all)
        p = pos[tri]
        face = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
        keep = np.linalg.norm(face, axis=1) > 1e-12
        tri, face = tri[keep], face[keep]
        corner = angles(nrm[tri], face[:, None, :]).ravel()
        # Weld by position and find triangles sharing an edge.
        key = np.round(pos / 1e-5).astype(np.int64)
        _, weld = np.unique(key, axis=0, return_inverse=True)
        t = weld.ravel()[tri] if weld.ndim > 1 else weld[tri]
        edges = np.concatenate([np.sort(t[:, [0, 1]], axis=1), np.sort(t[:, [1, 2]], axis=1), np.sort(t[:, [2, 0]], axis=1)])
        owner = np.tile(np.arange(len(t)), 3)
        order = np.lexsort((edges[:, 1], edges[:, 0]))
        e, o = edges[order], owner[order]
        same = np.all(e[1:] == e[:-1], axis=1)
        pairs = np.stack([o[:-1][same], o[1:][same]], axis=1)
        dihedral = angles(face[pairs[:, 0]], face[pairs[:, 1]]) if len(pairs) else np.zeros(1)
        def share(x, limit):
            return f"{(x > limit).mean():6.1%}"
        print(f"{node.get('name', index):28} {len(tri):>7} {np.percentile(corner, 50):10.2f} {np.percentile(corner, 95):6.1f} "
              f"{share(corner, 10)} {share(corner, 25)} {np.percentile(dihedral, 50):12.2f} {np.percentile(dihedral, 95):6.1f} "
              f"{share(dihedral, 10)} {share(dihedral, 25)}")


if __name__ == "__main__":
    main()
