#!/usr/bin/env python3
"""Create a disposable Home/Fly loading profile snapshot from the frozen control tree."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


SPAN_META_KEY = "openrc_loading_profile_spans"
HELPER_NAME = "phase2_loading_profile.gd"


@dataclass(frozen=True)
class FunctionSpec:
    path: str
    header: str
    name: str
    args: str
    result_type: str | None
    span_name: str
    static: bool = False


FUNCTIONS = (
    FunctionSpec("main.gd", "func _ready() -> void:", "_ready", "", None, "main._ready"),
    FunctionSpec("main.gd", "func _build_world() -> bool:", "_build_world", "", "bool", "main._build_world"),
    FunctionSpec(
        "ui/home_scene.gd",
        "func _init(aircraft := AirplaneBuilder.STIK_ID, field_path: String = FieldLoader.DEFAULT_PATH, selected_lighting: Dictionary = {}, selected_night_options: Dictionary = {}, selected_sky: Dictionary = {}, landscape_id: String = Landscapes.DEFAULT_ID) -> void:",
        "_init",
        "aircraft, field_path, selected_lighting, selected_night_options, selected_sky, landscape_id",
        None,
        "home_scene._init",
    ),
    FunctionSpec("ui/home_scene.gd", "func show_aircraft(id: String) -> bool:", "show_aircraft", "id", "bool", "home_scene.show_aircraft"),
    FunctionSpec(
        "render/world/world.gd",
        "static func build(parent: Node, field: Dictionary, build_field := Callable(), conditions: Dictionary = {}, lighting: Dictionary = {}, night_options: Dictionary = {}) -> Dictionary:",
        "build",
        "parent, field, build_field, conditions, lighting, night_options",
        "Dictionary",
        "world.build",
        static=True,
    ),
    FunctionSpec(
        "render/airplane.gd",
        "static func build(id := STIK_ID, propeller_diameter_m := NAN, expected_presentation: Dictionary = {}) -> Dictionary:",
        "build",
        "id, propeller_diameter_m, expected_presentation",
        "Dictionary",
        "airplane_builder.build",
        static=True,
    ),
    FunctionSpec("physics/aircraft_data.gd", "static func load_file(path: String) -> Dictionary:", "load_file", "path", "Dictionary", "aircraft_data.load_file", static=True),
    FunctionSpec("data/field_loader.gd", "static func load_from(path: String = DEFAULT_PATH) -> Dictionary:", "load_from", "path", "Dictionary", "field_loader.load_from", static=True),
    FunctionSpec(
        "sim/flight_session.gd",
        "func setup(path := Scenarios.AIRCRAFT, expected_id: String = \"\", frozen_data: Dictionary = {}) -> void:",
        "setup",
        "path, expected_id, frozen_data",
        None,
        "flight_session.setup",
    ),
    FunctionSpec(
        "sim/flight_session.gd",
        "func set_field(field: Dictionary, table_path := GroundSurfaces.DEFAULT_PATH) -> bool:",
        "set_field",
        "field, table_path",
        "bool",
        "flight_session.set_field",
    ),
    FunctionSpec(
        "sim/flight_session.gd",
        "func set_collision_world(world: Dictionary) -> bool:",
        "set_collision_world",
        "world",
        "bool",
        "flight_session.set_collision_world",
    ),
    FunctionSpec(
        "sim/flight_session.gd",
        "func reset(preserve_radio_readiness := false) -> void:",
        "reset",
        "preserve_radio_readiness",
        None,
        "flight_session.reset",
    ),
    FunctionSpec(
        "render/shadow.gd",
        "static func bind_model(shadow: MeshInstance3D, model: Node3D, shape: Dictionary = {}) -> void:",
        "bind_model",
        "shadow, model, shape",
        None,
        "shadow.bind_model",
        static=True,
    ),
    FunctionSpec(
        "render/aircraft_customization.gd",
        "static func describe(aircraft_id: String) -> Dictionary:",
        "describe",
        "aircraft_id",
        "Dictionary",
        "aircraft_customization.describe",
        static=True,
    ),
)

# This file is pinned by presentation-source validation. Observe its callers;
# never weaken the source guard to accommodate an attribution wrapper.
FUNCTIONS = tuple(spec for spec in FUNCTIONS if spec.path != "render/aircraft_customization.gd")


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8", newline="") as stream:
        return stream.read()


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        stream.write(value)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def line_ending(text: str) -> str:
    for index, char in enumerate(text):
        if char == "\n":
            return "\r\n" if index > 0 and text[index - 1] == "\r" else "\n"
    return "\n"


def make_wrapper(spec: FunctionSpec, newline: str) -> str:
    impl_name = f"_phase2_impl_{spec.name}"
    signature = spec.header.removesuffix(":")
    marker = f"func {spec.name}("
    if marker not in signature:
        raise ValueError(f"Expected a single-line function header for {spec.span_name}: {spec.header}")
    wrapper_signature = signature + ":"
    started = "\tvar phase2_start_usec: int = Time.get_ticks_usec()"
    invoke = f"\t{impl_name}({spec.args})" if not spec.result_type else f"\tvar phase2_result: {spec.result_type} = {impl_name}({spec.args})"
    record = f'\tPhase2LoadingProfile.record("{spec.span_name}", phase2_start_usec, Time.get_ticks_usec())'
    lines = [wrapper_signature, started, invoke, record]
    if spec.result_type:
        lines.append("\treturn phase2_result")
    return newline.join(lines) + newline


def transform_function(text: str, spec: FunctionSpec) -> str:
    newline = line_ending(text)
    original_lines = text.splitlines(keepends=True)
    matches = [i for i, line in enumerate(original_lines) if line.rstrip("\r\n") == spec.header]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one source signature for {spec.span_name}: found {len(matches)}")

    index = matches[0]
    original = original_lines[index]
    if f"_phase2_impl_{spec.name}" in text:
        raise ValueError(f"Scratch wrapper marker already exists in {spec.path}: {spec.name}")
    impl_header = spec.header.replace(f"func {spec.name}(", f"func _phase2_impl_{spec.name}(", 1)
    if impl_header == spec.header:
        raise ValueError(f"Could not rename function header: {spec.header}")
    original_lines[index] = impl_header + ("\r\n" if original.endswith("\r\n") else "\n" if original.endswith("\n") else "")
    original_lines.insert(index, make_wrapper(spec, newline))
    return "".join(original_lines)


def add_helper_preload(text: str, source_path: str) -> str:
    if "const Phase2LoadingProfile" in text:
        raise ValueError(f"Scratch helper name already exists in {source_path}")
    newline = line_ending(text)
    lines = text.splitlines(keepends=True)
    extends = [i for i, line in enumerate(lines) if line.startswith("extends ")]
    if len(extends) != 1:
        raise ValueError(f"Expected one top-level extends line in {source_path}")
    index = extends[0]
    lines.insert(index + 1, f'const Phase2LoadingProfile = preload("res://{HELPER_NAME}"){newline}')
    return "".join(lines)


HELPER_SOURCE = '''extends RefCounted

const META_KEY: StringName = &"openrc_loading_profile_spans"
const MAX_SPANS: int = 512


static func record(name: String, start_usec: int, end_usec: int) -> void:
\tvar spans: Array = Engine.get_meta(META_KEY, [])
\tif spans.size() >= MAX_SPANS:
\t\treturn
\tspans.append({"name": name, "start_usec": start_usec, "end_usec": end_usec})
\tEngine.set_meta(META_KEY, spans)
'''


def patch_probe(source: str) -> str:
    newline = line_ending(source)
    reset_anchor = "\tvar before_load := Time.get_ticks_usec()"
    report_anchor = "\treport.complete = report.shutdown.audio_released and report.shutdown.settings_removed"
    if source.count(reset_anchor) != 1:
        raise ValueError("loading_probe.gd timing reset anchor changed")
    if source.count(report_anchor) != 1:
        raise ValueError("loading_probe.gd report anchor changed")
    source = source.replace(reset_anchor, f'\tEngine.set_meta("{SPAN_META_KEY}", []){newline}{reset_anchor}', 1)
    source = source.replace(
        report_anchor,
        f'{report_anchor}{newline}\treport["construction_spans"] = Engine.get_meta("{SPAN_META_KEY}", [])',
        1,
    )
    return source


def ensure_inside(child: Path, parent: Path) -> None:
    try:
        child.resolve().relative_to(parent.resolve())
    except ValueError as exc:
        raise ValueError(f"Output must stay within scratch directory: {child}") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="new profile directory (defaults to ./profile)")
    args = parser.parse_args()

    scratch = Path(__file__).resolve().parent
    repo = scratch.parents[1]
    control_app = scratch / "control" / "app"
    output_root = (args.output if args.output else scratch / "profile").resolve()
    ensure_inside(output_root, scratch)
    profile_app = output_root / "app"
    if not (repo / "app" / "project.godot").is_file():
        raise FileNotFoundError(f"Repository root not found from instrumenter: {repo}")
    if not control_app.is_dir():
        raise FileNotFoundError(f"Frozen control snapshot is missing: {control_app}")
    if output_root.exists():
        raise FileExistsError(f"Refusing to replace an existing profile snapshot: {output_root}")

    # Preflight all requested signatures before making the large disposable copy.
    originals: dict[str, str] = {}
    for spec in FUNCTIONS:
        path = control_app / spec.path
        if spec.path not in originals:
            originals[spec.path] = read_text(path)
        if sum(line.rstrip("\r\n") == spec.header for line in originals[spec.path].splitlines(keepends=True)) != 1:
            raise ValueError(f"Control snapshot signature mismatch: {spec.path}: {spec.header}")
    probe_source = read_text(repo / "research" / "performance" / "loading_probe.gd")
    patched_probe = patch_probe(probe_source)

    # Disk-bounded scratch-only clone. Detach every edited file below before writing;
    # native runs do not import or edit the shared immutable resource files.
    shutil.copytree(control_app, profile_app, symlinks=True, copy_function=os.link)
    for sibling in ("assets", "tools"):
        shutil.copytree(control_app.parent / sibling, output_root / sibling, copy_function=os.link)
    provenance = output_root / "provenance"
    original_root = provenance / "originals"
    changed: dict[str, tuple[bytes, bytes]] = {}

    for relative, text in originals.items():
        source_path = control_app / relative
        original_bytes = source_path.read_bytes()
        target_path = profile_app / relative
        transformed = text
        for spec in (entry for entry in FUNCTIONS if entry.path == relative):
            transformed = transform_function(transformed, spec)
        transformed = add_helper_preload(transformed, relative)
        transformed_bytes = transformed.encode("utf-8")
        (original_root / "control" / "app" / relative).parent.mkdir(parents=True, exist_ok=True)
        (original_root / "control" / "app" / relative).write_bytes(original_bytes)
        target_path.unlink()
        target_path.write_bytes(transformed_bytes)
        changed[f"app/{relative}"] = (original_bytes, transformed_bytes)

    helper_path = profile_app / HELPER_NAME
    helper_path.write_text(HELPER_SOURCE, encoding="utf-8", newline="")
    changed[f"app/{HELPER_NAME}"] = (b"", helper_path.read_bytes())

    control_project = (control_app / "project.godot").read_bytes()
    repo_project_path = repo / "app" / "project.godot"
    repo_project = repo_project_path.read_bytes()
    (original_root / "control" / "app" / "project.godot").write_bytes(control_project)
    (original_root / "repo" / "app" / "project.godot").parent.mkdir(parents=True, exist_ok=True)
    (original_root / "repo" / "app" / "project.godot").write_bytes(repo_project)
    project_path = profile_app / "project.godot"
    project_path.unlink()
    project_path.write_bytes(repo_project)
    changed["app/project.godot"] = (control_project, repo_project)

    (original_root / "repo" / "research" / "performance").mkdir(parents=True, exist_ok=True)
    (original_root / "repo" / "research" / "performance" / "loading_probe.gd").write_bytes(probe_source.encode("utf-8"))
    profiled_probe = output_root / "profiled_loading_probe.gd"
    write_text(profiled_probe, patched_probe)
    changed["profiled_loading_probe.gd"] = (probe_source.encode("utf-8"), patched_probe.encode("utf-8"))

    diff_parts: list[str] = []
    for relative, (before, after) in sorted(changed.items()):
        before_text = before.decode("utf-8").splitlines(keepends=True) if before else []
        after_text = after.decode("utf-8").splitlines(keepends=True) if after else []
        diff_parts.extend(
            difflib.unified_diff(
                before_text,
                after_text,
                fromfile=f"control/{relative}",
                tofile=f"profile/{relative}",
            )
        )
    write_text(provenance / "loading-profile.patch", "".join(diff_parts))

    hashes = {}
    for relative, (before, after) in sorted(changed.items()):
        hashes[relative] = {
            "control_sha256": sha256(before),
            "profile_sha256": sha256(after),
            "control_bytes": len(before),
            "profile_bytes": len(after),
        }
    manifest = {
        "format": "openrc-loading-profile-snapshot v1",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "control_app": str(control_app),
        "profile_app": str(profile_app),
        "profiled_probe": str(profiled_probe),
        "span_meta_key": SPAN_META_KEY,
        "span_limit": 512,
        "functions": [spec.__dict__ for spec in FUNCTIONS],
        "hashes": hashes,
        "note": "Function bodies and call order are preserved; each selected call is timed by a wrapper that records after return.",
    }
    provenance.mkdir(parents=True, exist_ok=True)
    (provenance / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Created disposable loading profile at {output_root}")
    print(f"Profile project: {profile_app}")
    print(f"Profile probe: {profiled_probe}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
