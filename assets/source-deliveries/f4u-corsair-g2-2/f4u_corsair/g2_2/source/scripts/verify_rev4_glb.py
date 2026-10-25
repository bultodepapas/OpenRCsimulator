#!/usr/bin/env python3
"""Revision 4 GLB + sidecar contract verifier (stdlib only).

Place this script beside preflight_glb.py. Run with Python 3.10+:
  python verify_rev4_glb.py --glb export/aircraft.glb --metadata metadata.json --report checks/rev4_glb.json

The bundled strict preflight owns glTF geometry, required pivots/helpers/tags, outward winding,
stowed-gear clearance, span and forbidden-extension checks. This wrapper adds the revision-4
budgets, exact sidecar consistency, Naval 308 default, and the two approved retraction-link nodes.
It is read-only and exits nonzero on any failed check.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import preflight_glb


MAX_BYTES = 30_000_000
TARGET_TRIANGLES = (300_000, 350_000)
MAX_TRIANGLES = 450_000
MAX_SURFACES = 70
MAX_MATERIALS = 16
LINKS = {
    "gear_retraction_link_left": ("gear_fold_left", "gear"),
    "gear_retraction_link_right": ("gear_fold_right", "gear"),
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def gltf_parent_map(gltf: dict) -> tuple[dict[str, dict], dict[str, str | None]]:
    nodes = gltf.get("nodes", [])
    by_name = {str(node.get("name", "")): node for node in nodes}
    parents: dict[int, int] = {}
    for parent_index, node in enumerate(nodes):
        for child in node.get("children", []):
            parents[int(child)] = parent_index
    names = [str(node.get("name", "")) for node in nodes]
    parent_by_name = {
        name: names[parents[i]] if i in parents else None
        for i, name in enumerate(names)
    }
    return by_name, parent_by_name


def run(glb_path: Path, metadata_path: Path, native_source_path: Path) -> dict:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    preflight = preflight_glb.inspect(glb_path, "f4u-g2")
    gltf, _binary = preflight_glb.read_glb(glb_path)
    by_name, parents = gltf_parent_map(gltf)
    counts = preflight["counts"]
    mesh_rows = {row["node"]: row for row in preflight["meshes"]}
    sidecar_mesh_rows = {row["node"]: row for row in metadata.get("meshes", [])}
    sidecar_nodes = metadata.get("nodes", {})
    byte_count = glb_path.stat().st_size
    digest = sha256(glb_path)

    checks: list[dict] = []

    def check(name: str, ok: bool, detail: object = "") -> None:
        checks.append({"name": name, "ok": bool(ok), "detail": detail})

    check("strict GLB preflight", preflight["ok"], preflight["failures"])
    check("triangle target 300k–350k", TARGET_TRIANGLES[0] <= counts["triangles"] <= TARGET_TRIANGLES[1], counts["triangles"])
    check("hard triangle ceiling 450k", counts["triangles"] <= MAX_TRIANGLES, counts["triangles"])
    check("surface ceiling 70", counts["surfaces"] <= MAX_SURFACES, counts["surfaces"])
    check("material ceiling 16", counts["materials"] <= MAX_MATERIALS, counts["materials"])
    check("GLB size ceiling 30 MB", byte_count <= MAX_BYTES, byte_count)
    check("GLB SHA-256 matches metadata", digest == metadata.get("glb_sha256"), digest)
    check("GLB byte length matches metadata", byte_count == metadata.get("glb_bytes"), byte_count)
    source_hash = sha256(native_source_path) if native_source_path.is_file() else None
    check("native source SHA-256 matches metadata", source_hash is not None and
          source_hash == metadata.get("source_blend_sha256"),
          {"source": str(native_source_path), "actual": source_hash,
           "metadata": metadata.get("source_blend_sha256")})
    check("sidecar triangle count matches imported GLB", counts["triangles"] == metadata.get("triangle_count"),
          {"glb": counts["triangles"], "metadata": metadata.get("triangle_count")})
    check("sidecar surface count matches imported GLB", counts["surfaces"] == metadata.get("surface_count"),
          {"glb": counts["surfaces"], "metadata": metadata.get("surface_count")})
    check("sidecar material count matches imported GLB", counts["materials"] == metadata.get("material_count"),
          {"glb": counts["materials"], "metadata": metadata.get("material_count")})
    check("sidecar mesh-node count matches imported GLB", counts["mesh_nodes"] == len(sidecar_mesh_rows),
          {"glb": counts["mesh_nodes"], "metadata": len(sidecar_mesh_rows)})

    per_mesh_errors = []
    if set(mesh_rows) != set(sidecar_mesh_rows):
        per_mesh_errors.append({"glb_only": sorted(set(mesh_rows) - set(sidecar_mesh_rows)),
                                "metadata_only": sorted(set(sidecar_mesh_rows) - set(mesh_rows))})
    for name in sorted(set(mesh_rows) & set(sidecar_mesh_rows)):
        actual, declared = mesh_rows[name], sidecar_mesh_rows[name]
        for key in ("triangles", "surfaces", "section"):
            if actual.get(key) != declared.get(key):
                per_mesh_errors.append({"node": name, "field": key,
                                        "glb": actual.get(key), "metadata": declared.get(key)})
    check("per-mesh counts and section tags match metadata", not per_mesh_errors, per_mesh_errors[:30])

    liveries = metadata.get("liveries", [])
    is_naval_default = bool(liveries) and liveries[0].get("id") == "midnight" and \
        liveries[0].get("name") == "Naval 308" and bool(liveries[0].get("default"))
    check("Naval 308 is the first/default livery", metadata.get("default_livery") == "midnight" and is_naval_default,
          {"default_livery": metadata.get("default_livery"), "first": liveries[0] if liveries else None})
    gear = metadata.get("gear", {})
    check("GearRetract has 101 samples and exports frame 100",
          gear.get("action") == "GearRetract" and gear.get("samples") == 101 and
          metadata.get("runtime_export_frame") == 100,
          {"action": gear.get("action"), "samples": gear.get("samples"),
           "runtime_export_frame": metadata.get("runtime_export_frame")})

    link_errors = []
    for name, (expected_parent, expected_section) in LINKS.items():
        node = by_name.get(name)
        if node is None:
            link_errors.append({"node": name, "error": "missing from GLB"})
            continue
        extras = node.get("extras") or {}
        if parents.get(name) != expected_parent:
            link_errors.append({"node": name, "parent": parents.get(name), "expected_parent": expected_parent})
        if extras.get("openrc_section") != expected_section:
            link_errors.append({"node": name, "section": extras.get("openrc_section"), "expected": expected_section})
        record = sidecar_nodes.get(name, {})
        if record.get("parent") != expected_parent or record.get("section") != expected_section:
            link_errors.append({"node": name, "metadata": record})
    check("two retraction links are gear meshes below existing fold carriers", not link_errors, link_errors)

    return {
        "audit": "F4U g2.0 Revision 4 GLB and sidecar contract",
        "read_only": True,
        "glb": str(glb_path.resolve()),
        "metadata": str(metadata_path.resolve()),
        "native_source": str(native_source_path.resolve()) if native_source_path.exists() else str(native_source_path),
        "glb_sha256": digest,
        "counts": counts,
        "bytes": byte_count,
        "outward_share": preflight.get("outward_share", {}),
        "gear_and_airframe_bounds": preflight.get("bounds_m", {}),
        "checks_passed": sum(1 for row in checks if row["ok"]),
        "checks_total": len(checks),
        "ok": all(row["ok"] for row in checks),
        "checks": checks,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--native-source", type=Path,
                        help="defaults to metadata's sibling source/aircraft_game.blend")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        native_source = args.native_source or args.metadata.parent / "source" / "aircraft_game.blend"
        report = run(args.glb, args.metadata, native_source)
    except (OSError, ValueError, KeyError, IndexError, TypeError) as exc:
        print(f"FAIL verifier could not complete: {exc}", file=sys.stderr)
        return 2
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for row in report["checks"]:
        print(("PASS " if row["ok"] else "FAIL ") + row["name"] +
              ("" if row["detail"] in ("", [], {}) else f" :: {json.dumps(row['detail'], ensure_ascii=False)}"))
    print(f"Revision 4 GLB verifier: {report['checks_passed']}/{report['checks_total']} checks; "
          f"{report['counts']['triangles']} triangles, {report['counts']['surfaces']} surfaces, "
          f"{report['counts']['materials']} materials, {report['bytes']} bytes")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
