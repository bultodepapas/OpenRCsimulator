"""F4U-18: face orientation of every mesh in a GLB, read independently of Blender and Godot.

For each mesh node, in model space: the area share of triangles whose winding normal points away from the mesh's
own centroid ("outward"), the share whose stored vertex normals agree with the winding, and, for the fuselage, the
share pointing away from the thrust axis (glTF model frame: +X right, +Y up, nose -Z, thrust axis on Z).
A closed outer skin is expected near 1.0 outward; a value well below 0.5 means the shell is inside out.

    python research/f4u-corsair/F4U-18/glb_orientation.py MODEL.glb [--json OUT.json]
"""
import json, struct, sys
import numpy as np

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
DTYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}


def load(path):
    raw = open(path, "rb").read()
    length = struct.unpack_from("<I", raw, 12)[0]
    gltf = json.loads(raw[20:20 + length])
    offset = 20 + length
    bin_length = struct.unpack_from("<I", raw, offset)[0]
    return gltf, raw[offset + 8:offset + 8 + bin_length]


def accessor(gltf, blob, index):
    a = gltf["accessors"][index]
    view = gltf["bufferViews"][a["bufferView"]]
    count, width = a["count"], COMPONENTS[a["type"]]
    dtype = np.dtype(DTYPES[a["componentType"]])
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", 0) or width * dtype.itemsize
    rows = np.ndarray((count, width), dtype=dtype, buffer=blob, offset=start, strides=(stride, dtype.itemsize))
    return np.array(rows, dtype=np.float64 if dtype == np.float32 else np.int64)


def local_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    t = np.array(node.get("translation", [0, 0, 0]))
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * np.array(node.get("scale", [1, 1, 1]))
    m[:3, 3] = t
    return m


def main():
    gltf, blob = load(sys.argv[1])
    worlds = {}
    def walk(index, parent):
        world = parent @ local_matrix(gltf["nodes"][index])
        worlds[index] = world
        for child in gltf["nodes"][index].get("children", []):
            walk(child, world)
    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(root, np.eye(4))
    rows = []
    for index, node in enumerate(gltf["nodes"]):
        if "mesh" not in node:
            continue
        world = worlds[index]
        normal_matrix = np.linalg.inv(world[:3, :3]).T
        tris, normals = [], []
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            pos = accessor(gltf, blob, prim["attributes"]["POSITION"])
            nrm = accessor(gltf, blob, prim["attributes"]["NORMAL"])
            idx = accessor(gltf, blob, prim["indices"]).reshape(-1, 3)
            pos = pos @ world[:3, :3].T + world[:3, 3]
            nrm = nrm @ normal_matrix.T
            tris.append(pos[idx])
            normals.append(nrm[idx].mean(axis=1))
        t = np.concatenate(tris)
        vn = np.concatenate(normals)
        cross = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
        area = 0.5 * np.linalg.norm(cross, axis=1)
        centre = t.mean(axis=1)
        centroid = (centre * area[:, None]).sum(axis=0) / area.sum()
        outward = (np.einsum("ij,ij->i", cross, centre - centroid) > 0)
        agree = (np.einsum("ij,ij->i", cross, vn) > 0)
        radial = centre.copy()
        radial[:, 2] = 0.0
        axis_out = (np.einsum("ij,ij->i", cross, radial) > 0)
        rows.append({"node": node.get("name", str(index)), "triangles": int(len(t)),
                     "outward_share": round(float(area[outward].sum() / area.sum()), 3),
                     "normals_agree_share": round(float(area[agree].sum() / area.sum()), 3),
                     "away_from_thrust_axis_share": round(float(area[axis_out].sum() / area.sum()), 3)})
    rows.sort(key=lambda r: r["outward_share"])
    for r in rows:
        print(f"{r['outward_share']:6.3f} {r['away_from_thrust_axis_share']:6.3f} {r['normals_agree_share']:6.3f} "
              f"{r['triangles']:>8}  {r['node']}")
    if "--json" in sys.argv:
        with open(sys.argv[sys.argv.index("--json") + 1], "w", encoding="utf-8") as f:
            json.dump({"file": sys.argv[1], "meshes": rows}, f, indent=1)


if __name__ == "__main__":
    main()
