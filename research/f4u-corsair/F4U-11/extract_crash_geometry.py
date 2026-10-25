"""F4U-11-R1: bounded extra hull probes measured on the frozen, neutral g2.2 mesh.

Run before derive_physics.py; --check refuses stale output. No Blender edits or
runtime mesh queries. Moving gear, propeller and tailhook use their own contracts.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "research/f4u-corsair/F4U-04"))
import preflight_glb as glb

ASSET = ROOT / "assets/aircraft/f4u-corsair-250"
OUTPUT = ASSET / "crash-geometry.json"
# id, mesh, LE support direction, shared impact label, optional model-X half.
PROBES = [
    ("probe_wing_left_tip", "wing_left_fixed", [0, -1, 0], "left_wing_tip", 0),
    ("probe_wing_right_tip", "wing_right_fixed", [0, 1, 0], "right_wing_tip", 0),
    ("probe_gull_left_bottom", "wing_center_fixed", [0, 0, -1], "left_wing_root", -1),
    ("probe_gull_right_bottom", "wing_center_fixed", [0, 0, -1], "right_wing_root", 1),
    ("probe_tail_cone", "fuselage_core", [1, 0, 0], "tail_end", 0),
    ("probe_fuselage_rear_bottom", "fuselage_core", [1, 0, -1], "tail_end", 0),
    ("probe_stabilizer_left_aft", "stabilizer_fixed", [1, -1, 0], "left_stab_tip", -1),
    ("probe_stabilizer_right_aft", "stabilizer_fixed", [1, 1, 0], "right_stab_tip", 1),
    ("probe_fin_aft_upper", "rudder", [1, 0, 1], "fin_top", 0),
]


def derive():
    manifest = json.loads((ASSET / "source-manifest.json").read_text())
    identity = manifest["key_files"]["glb"]
    source = ROOT / manifest["delivery_root"] / identity["path"]
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    assert digest == identity["sha256"], "frozen aircraft differs from its identity"
    gltf, binary = glb.read_glb(source)
    nodes = gltf["nodes"]
    parents = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    matrices, meshes = {}, {}

    def world(index):
        if index not in matrices:
            local = glb.local_matrix(nodes[index])
            matrices[index] = glb.multiply(world(parents[index]), local) if index in parents else local
        return matrices[index]

    records = []
    for probe_id, mesh_name, direction, label, side in PROBES:
        if mesh_name not in meshes:
            found = [i for i, node in enumerate(nodes) if node["name"] == mesh_name]
            assert len(found) == 1, mesh_name
            index = found[0]
            matrix = world(index)
            points = []
            for primitive in gltf["meshes"][nodes[index]["mesh"]]["primitives"]:
                for vertex in glb.accessor_values(gltf, binary, primitive["attributes"]["POSITION"]):
                    point = [sum(matrix[r][c] * vertex[c] for c in range(3)) + matrix[r][3] for r in range(3)]
                    points.append([point[2], point[0], point[1]]) # model -> LE
            meshes[mesh_name] = points
        points = [p for p in meshes[mesh_name] if side == 0 or side * p[1] > 0]
        support = max(points, key=lambda p: sum(p[i] * direction[i] for i in range(3)))
        records.append({"id": probe_id, "mesh": mesh_name, "direction_le": direction,
                        "half": side, "component": label,
                        "position_le": [round(v, 6) for v in support]})
    return {"format": "openrc-f4u-crash-geometry v1", "step": "F4U-11-R1",
            "generator": "research/f4u-corsair/F4U-11/extract_crash_geometry.py",
            "source_glb": str(source.relative_to(ROOT)).replace("\\", "/"),
            "source_sha256": digest, "pose": "neutral controls, wings spread",
            "probes": records}


if __name__ == "__main__":
    text = json.dumps(derive(), indent=2) + "\n"
    if "--check" in sys.argv:
        if not OUTPUT.exists() or OUTPUT.read_text() != text:
            sys.exit("Corsair crash geometry is stale: run extract_crash_geometry.py")
        print("Corsair crash geometry current (9 additional probes)")
    else:
        OUTPUT.write_text(text, encoding="utf-8", newline="\n")
        print("Wrote " + str(OUTPUT.relative_to(ROOT)))
