#!/usr/bin/env python3
"""Negative smoke tests for the co-located preflight_glb.py (stdlib only).

Run: python test_rev4_glb_negative_cases.py --glb export/aircraft.glb --report checks/rev4_negative_cases.json
Fixtures are mutated copies in a temporary directory; the supplied GLB is read-only.
"""
from __future__ import annotations

import argparse
import json
import struct
import tempfile
from pathlib import Path

import preflight_glb


JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def write_glb(path: Path, gltf: dict, binary: bytes | bytearray) -> None:
    json_bytes = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    bin_bytes = bytes(binary)
    bin_bytes += b"\x00" * ((-len(bin_bytes)) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    with path.open("wb") as stream:
        stream.write(struct.pack("<4sII", b"glTF", 2, total))
        stream.write(struct.pack("<II", len(json_bytes), JSON_CHUNK))
        stream.write(json_bytes)
        stream.write(struct.pack("<II", len(bin_bytes), BIN_CHUNK))
        stream.write(bin_bytes)


def clone_input(path: Path) -> tuple[dict, bytearray]:
    gltf, binary = preflight_glb.read_glb(path)
    return gltf, bytearray(binary)


def reverse_fuselage_winding(gltf: dict, binary: bytearray) -> None:
    nodes = gltf.get("nodes", [])
    node = next((n for n in nodes if n.get("name") == "fuselage_core"), None)
    if node is None or "mesh" not in node:
        raise RuntimeError("fuselage_core mesh is missing")
    mesh = gltf["meshes"][node["mesh"]]
    seen_accessors: set[int] = set()
    for primitive in mesh.get("primitives", []):
        if "indices" not in primitive:
            raise RuntimeError("fuselage_core primitive has no index accessor to reverse")
        accessor_index = int(primitive["indices"])
        if accessor_index in seen_accessors:
            continue
        seen_accessors.add(accessor_index)
        accessor = gltf["accessors"][accessor_index]
        if accessor.get("type") != "SCALAR":
            raise RuntimeError("fuselage index accessor is not SCALAR")
        component_type = int(accessor["componentType"])
        fmt, width = preflight_glb.COMPONENTS[component_type]
        if fmt not in ("B", "H", "I"):
            raise RuntimeError(f"unsupported index component format {fmt}")
        view = gltf["bufferViews"][accessor["bufferView"]]
        stride = int(view.get("byteStride", width))
        base = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
        count = int(accessor["count"])
        if count % 3:
            raise RuntimeError(f"fuselage index count {count} is not divisible by three")
        for i in range(0, count, 3):
            b_offset = base + (i + 1) * stride
            c_offset = base + (i + 2) * stride
            b_value = struct.unpack_from("<" + fmt, binary, b_offset)[0]
            c_value = struct.unpack_from("<" + fmt, binary, c_offset)[0]
            struct.pack_into("<" + fmt, binary, b_offset, c_value)
            struct.pack_into("<" + fmt, binary, c_offset, b_value)
    if not seen_accessors:
        raise RuntimeError("no fuselage index accessor was reversed")


def make_case(base_gltf: dict, base_binary: bytearray, case: str) -> tuple[dict, bytearray, str]:
    gltf = json.loads(json.dumps(base_gltf))
    binary = bytearray(base_binary)
    if case == "missing_hinge":
        node = next((n for n in gltf["nodes"] if n.get("name") == "aileron_left_hinge"), None)
        if node is None:
            raise RuntimeError("required hinge was absent from the baseline fixture")
        node["name"] = "test_missing_aileron_left_hinge"
        return gltf, binary, "missing pivot pair aileron_left_hinge -> aileron_left"
    if case == "missing_mesh_tag":
        node = next((n for n in gltf["nodes"] if n.get("name") == "gear_retraction_link_left"), None)
        if node is None:
            raise RuntimeError("expected Revision 4 retraction-link node was absent")
        extras = node.get("extras") or {}
        extras.pop("openrc_section", None)
        node["extras"] = extras
        return gltf, binary, "has no openrc_section"
    if case == "inverted_fuselage":
        reverse_fuselage_winding(gltf, binary)
        return gltf, binary, "fuselage_core is inside out"
    raise ValueError(case)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    original_gltf, original_binary = clone_input(args.glb)
    rows = []
    with tempfile.TemporaryDirectory(prefix="f4u_rev4_negative_") as temp:
        root = Path(temp)
        for case in ("missing_hinge", "missing_mesh_tag", "inverted_fuselage"):
            gltf, binary, expected = make_case(original_gltf, original_binary, case)
            fixture = root / f"{case}.glb"
            write_glb(fixture, gltf, binary)
            result = preflight_glb.inspect(fixture, "f4u-g2")
            matching = [failure for failure in result["failures"] if expected in failure]
            rows.append({"case": case, "rejected": not result["ok"],
                         "expected_failure_seen": bool(matching), "matching_failures": matching,
                         "all_failures": result["failures"]})
    report = {"audit": "F4U Revision 4 preflight negative cases", "read_only_input": str(args.glb.resolve()),
              "cases": rows, "passed": all(r["rejected"] and r["expected_failure_seen"] for r in rows)}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(("PASS " if row["rejected"] and row["expected_failure_seen"] else "FAIL ") +
              f"{row['case']}: rejected={row['rejected']}; expected failure seen={row['expected_failure_seen']}")
    print(f"Negative preflight tests: {sum(r['rejected'] and r['expected_failure_seen'] for r in rows)}/{len(rows)} passed")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
