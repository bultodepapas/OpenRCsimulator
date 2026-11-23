#!/usr/bin/env python3
"""Extract and time the pinned Nitro numeric sampler; no app or FPS benchmark."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import struct
import subprocess
import sys

SOURCE = "7940a4081e10994f34c858c4acac3d7a1a271464"
ENGINE_SHA256 = "34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564"
MODEL = "app/vehicles/ground/monster_car_2_model.gd"
MANIFEST = "app/assets/vehicles/monster-car-2/visual_rig.json"
BINARY = "app/assets/vehicles/monster-car-2/visual_rig.bin"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def block(source: str, start: str) -> str:
    lines = source.splitlines(keepends=True)
    first = next(i for i, line in enumerate(lines) if line.startswith(start))
    last = first + 1
    while last < len(lines) and (lines[last].startswith(("\t", "\n", "\r")) or not lines[last].strip()):
        last += 1
    return "".join(lines[first:last]).rstrip() + "\n"


def build_fixture(root: Path, fixture: Path) -> dict:
    files = {name: subprocess.check_output(["git", "-C", str(root), "show", f"{SOURCE}:{name}"])
             for name in (MODEL, MANIFEST, BINARY)}
    manifest = json.loads(files[MANIFEST])
    if digest(files[BINARY]) != manifest["binary_sha256"]:
        raise ValueError("real rig bytes do not match their pinned manifest")
    source = files[MODEL].decode()
    starts = ("class TrackSampler extends RefCounted:", "static func _compile_track(",
              "static func _sample_compiled_track(", "static func _transform_from_floats(")
    blocks = [block(source, start) for start in starts]
    original = blocks[2]
    packed = original.replace("_sample_compiled_track(", "_sample_packed(", 1).replace(
        "_transform_from_floats(sampler.values)", "_transform_from_packed(sampler.values)")
    packed_helper = blocks[3].replace("_transform_from_floats(values: Array)",
                                     "_transform_from_packed(values: PackedFloat32Array)")
    shared = original.replace("_sample_compiled_track(", "_sample_shared(", 1).replace(
        "inputs: Dictionary", "group_ids: PackedInt32Array, lows: PackedInt32Array, highs: PackedInt32Array, fractions: PackedFloat64Array")
    begin = shared.index("\tfor axis_index in axis_count:")
    end = shared.index("\tfor mask in (1 << axis_count):")
    shared = shared[:begin] + shared[end:]
    shared = shared.replace("\t\t\tvar choose_upper", "\t\t\tvar group_id := group_ids[axis_index]\n\t\t\tvar choose_upper")
    for old, new in (("sampler.high_indices[axis_index]", "highs[group_id]"),
                     ("sampler.low_indices[axis_index]", "lows[group_id]"),
                     ("sampler.fractions[axis_index]", "fractions[group_id]")):
        shared = shared.replace(old, new)
    combined = shared.replace("_sample_shared(", "_sample_combined(", 1).replace(
        "_transform_from_floats(sampler.values)", "_transform_from_packed(sampler.values)")
    derived = "extends RefCounted\n\n" + "\n".join(blocks + [packed, packed_helper, shared, combined])
    (fixture / "sampler.gd").write_text(derived)
    (fixture / "rig.json").write_bytes(files[MANIFEST])
    (fixture / "rig.bin").write_bytes(files[BINARY])

    tracks = manifest["tracks"]
    names = [name for name in tracks if not name.startswith("@wheel_")]
    names += [manifest["bindings"]["wheel_groups"][corner]["pivot_track"] for corner in ("FL", "FR", "RL", "RR")]
    groups, group_keys, ids = [], [], {}
    for name in names:
        ids[name] = []
        for axis, values in zip(tracks[name]["axes"], tracks[name]["ranges"], strict=True):
            low, _, step, count = values
            key = (axis, struct.pack("!d", low), struct.pack("!d", step), int(count))
            if key not in group_keys:
                group_keys.append(key)
                groups.append({"name": axis, "low": low, "step": step, "count": int(count)})
            ids[name].append(group_keys.index(key))
    if len(names) != 209 or len(set(names)) != 209 or len(groups) != 5:
        raise ValueError("unexpected pinned rig inventory")
    neutral = {g["name"]: 0.0 for g in groups}
    cases = [{"name": "neutral", "inputs": neutral}]
    for mask in range(32):
        cases.append({"name": f"boundary_{mask}", "inputs": {
            g["name"]: g["low"] + (g["count"] - 1) * g["step"] * ((mask >> i) & 1)
            for i, g in enumerate(groups)}})
    for g in groups:
        for label, position in (("below", -4), ("first_knot", 1), ("interior_knot", (g["count"] - 1) // 2),
                                ("fractional", (g["count"] - 1) * 0.371), ("above", g["count"] + 3)):
            cases.append({"name": g["name"] + "_" + label,
                          "inputs": {**neutral, g["name"]: g["low"] + position * g["step"]}})
    seed = 0x37C0FFEE
    for index in range(128):
        inputs = {}
        for g in groups:
            seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
            inputs[g["name"]] = g["low"] + (g["count"] - 1) * g["step"] * (0.001 + 0.998 * seed / 4294967296.0)
        cases.append({"name": f"seeded_{index}", "inputs": inputs})
    spec = {"names": names, "groups": groups, "ids": ids, "cases": cases,
            "workloads": [{"name": "neutral", "cases": [0]},
                          {"name": "fractional_interior", "cases": [58]},
                          {"name": "varying_interiors", "cases": list(range(58, 76))}]}
    spec_bytes = (json.dumps(spec, indent=2) + "\n").encode()
    (fixture / "inputs.json").write_bytes(spec_bytes)
    return {"source": SOURCE, "inputs": [{"path": name, "bytes": len(data), "sha256": digest(data)} for name, data in files.items()],
            "extracted_blocks": [{"declaration": start, "sha256": digest(data.encode())} for start, data in zip(starts, blocks, strict=True)],
            "derived_sampler_sha256": digest(derived.encode()), "case_spec_sha256": digest(spec_bytes),
            "tracks": len(names), "axis_preparations": sum(len(v) for v in ids.values()), "groups": len(groups),
            "cases": len(cases), "variant_scope": "valid compiled pinned metadata only; malformed/mutated metadata is not qualified"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    sys.path.insert(0, str(root))
    from tools.testqueue.common import enabled, inherited
    if enabled() and not inherited("performance"):
        parser.error("component timings require an exclusive admitted performance attempt on an enrolled host")
    if os.environ.get("OPENRC_TESTPOOL_CONFIG") and not inherited("performance"):
        parser.error("use an admitted performance attempt; this reproducer does not submit to a pool")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        parser.error("--out must be new or empty")
    engine = args.godot.resolve()
    if digest(engine.read_bytes()) != ENGINE_SHA256:
        parser.error("expected the pinned official Linux x86_64 Godot 4.8-beta2 binary")
    fixture = out / "fixture"
    fixture.mkdir()
    manifest = build_fixture(root, fixture)
    probe = Path(__file__).with_name("rig_sampler_probe.gd")
    (fixture / probe.name).write_bytes(probe.read_bytes())
    config = 'config_version=5\n[application]\nconfig/name="Detached numeric rig audit"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
    (fixture / "project.godot").write_text(config)
    runner = root / "tools/godot/run_checked.py"
    env = os.environ.copy()
    for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        private = out / key.lower()
        private.mkdir()
        env[key] = str(private)
    manifest.update({"engine_sha256": ENGINE_SHA256, "probe_sha256": digest(probe.read_bytes()),
                     "reproducer_sha256": digest(Path(__file__).read_bytes()), "runner_sha256": digest(runner.read_bytes()),
                     "config_sha256": digest(config.encode()),
                     "host": {"system": platform.system(), "release": platform.release(), "machine": platform.machine(), "logical_cpu_count": os.cpu_count()},
                     "scope": "unrendered numeric component with real rig bytes and synthetic finite controls; not native vehicle, full draw, full visual parity, GPU, or FPS evidence",
                     "admission": {"queue_enabled": enabled(), "inherited_performance": inherited("performance"),
                                   "pool_configured": bool(os.environ.get("OPENRC_TESTPOOL_CONFIG"))}})
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    checks = []
    for label, tail, marker in (("rig-sampler-import", ["--editor", "--import"], None),
                                ("rig-sampler-component", ["--script", "res://" + probe.name], "RIG_SAMPLER_AUDIT_COMPLETE")):
        command = [sys.executable, str(runner), "--out-dir", str(out / "checks"), "--label", label,
                   "--timeout", "60", "--warnings-as-errors"]
        if marker:
            command += ["--require-text", marker]
        command += ["--", str(engine), "--headless", "--path", str(fixture), "--audio-driver", "Dummy", *tail]
        run = subprocess.run(command, cwd=root, env=env, check=False)
        checks.append({"label": label, "exit_code": run.returncode})
        if run.returncode:
            break
    result_path = fixture / "rig-sampler-results.json"
    result = json.loads(result_path.read_text()) if result_path.is_file() else {}
    stable = (digest(engine.read_bytes()) == ENGINE_SHA256
              and digest(probe.read_bytes()) == manifest["probe_sha256"]
              and digest((fixture / probe.name).read_bytes()) == manifest["probe_sha256"]
              and digest(runner.read_bytes()) == manifest["runner_sha256"]
              and digest(Path(__file__).read_bytes()) == manifest["reproducer_sha256"]
              and digest((fixture / "sampler.gd").read_bytes()) == manifest["derived_sampler_sha256"]
              and digest((fixture / "inputs.json").read_bytes()) == manifest["case_spec_sha256"]
              and digest((fixture / "rig.json").read_bytes()) == manifest["inputs"][1]["sha256"]
              and digest((fixture / "rig.bin").read_bytes()) == manifest["inputs"][2]["sha256"]
              and digest((fixture / "project.godot").read_bytes()) == manifest["config_sha256"])
    result_ok = (result.get("complete") is True and result.get("failures") == 0
                 and result.get("track_cases") == 209 * 186 and len(result.get("rows", [])) == 144
                 and result.get("engine_version") == "4.8.beta2.official.cafc17a19"
                 and all(row["batches"] == 18 and row["duration_usec"] > 0 for row in result["rows"]))
    if result_ok:
        for workload in ("neutral", "fractional_interior", "varying_interiors"):
            rows = [row for row in result["rows"] if row["workload"] == workload]
            result_ok = result_ok and len(rows) == 48 and len({row["checksum"] for row in rows}) == 1
    summary = {"checks": checks, "inputs_stable": stable, "result_ok": result_ok,
               "result_sha256": digest(result_path.read_bytes()) if result_path.is_file() else None,
               "ok": len(checks) == 2 and all(row["exit_code"] == 0 for row in checks) and stable and result_ok}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
