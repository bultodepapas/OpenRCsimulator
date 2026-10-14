#!/usr/bin/env python3
"""Generate strict visual model manifests from the existing aircraft sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = Path("assets/aircraft/model-bindings.json")
OUTPUT_DIR = Path("app/data/aircraft_models")
FAMILY_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
RESOURCE_RE = re.compile(r"\b(?:preload|load)\s*\(\s*[\"']res://([^\"']+)[\"']\s*\)")
TEXT_SUFFIXES = {".cfg", ".gd", ".godot", ".import", ".json", ".md", ".svg", ".tres", ".tscn", ".txt"}
ADAPTERS = {"euler_hinges", "axis_hinges", "imported_glb"}
CONTROL_ROLES = {"aileron_left", "aileron_right", "elevator", "rudder", "flap_left", "flap_right"}
GEAR_ROLES = {"left", "right", "tail", "steering", "nose"}
REQUIRED_CONTROL_ROLES = {"aileron_left", "aileron_right", "elevator", "rudder"}


class ModelManifestError(ValueError):
    """Raised when authoring inputs cannot produce a safe manifest."""


def _hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _normal_bytes(path: Path, mode: str) -> bytes:
    raw = path.read_bytes()
    if mode == "raw":
        return raw
    if mode != "lf_text":
        raise ModelManifestError(f"unsupported hash mode {mode!r} for {path}")
    try:
        return raw.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    except UnicodeDecodeError as exc:
        raise ModelManifestError(f"expected UTF-8 text for {path}") from exc


def _safe_repo_path(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        raise ModelManifestError(f"{label} must be a repository-relative POSIX path")
    path = Path(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in value.split("/")):
        raise ModelManifestError(f"{label} is not a safe relative path: {value!r}")
    if not value.startswith("assets/aircraft/"):
        raise ModelManifestError(f"{label} must stay under assets/aircraft/: {value!r}")
    return value


def _safe_resource_path(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.startswith("res://") or "\\" in value:
        raise ModelManifestError(f"{label} must be a res:// path")
    tail = value[6:]
    parts = tail.split("/")
    if not tail or any(part in {"", ".", ".."} for part in parts):
        raise ModelManifestError(f"{label} is not a safe resource path: {value!r}")
    if any(re.fullmatch(r"[A-Za-z0-9_.@+-]+", part) is None for part in parts):
        raise ModelManifestError(f"{label} contains an unsupported resource path character: {value!r}")
    if not (parts[0] == "aircraft" or (parts[0] == "assets" and len(parts) > 2 and parts[1] == "aircraft")
            or (parts[0] == "render" and len(parts) > 2 and parts[1] == "crash")):
        raise ModelManifestError(f"{label} must stay under bundled aircraft, aircraft assets or crash resources: {value!r}")
    return value


def _resource_file(root: Path, resource_path: str) -> Path:
    _safe_resource_path(resource_path, "resource path")
    return root / "app" / resource_path[6:]


def _resolve(data: Any, dotted_path: str, label: str) -> Any:
    current = data
    for token in dotted_path.split("."):
        if not isinstance(current, dict) or token not in current:
            raise ModelManifestError(f"{label} refers to missing source field {dotted_path!r}")
        current = current[token]
    return current


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise ModelManifestError(f"{label} must resolve to a finite number")
    return float(value)


def _selector_value(source: Any, selector: Any, label: str) -> float:
    if not isinstance(selector, dict) or set(selector) - {"path", "value", "scale"}:
        raise ModelManifestError(f"{label} selector must contain only path, value and optional scale")
    if ("path" in selector) == ("value" in selector):
        raise ModelManifestError(f"{label} selector needs exactly one of path or value")
    raw = _resolve(source, selector["path"], label) if "path" in selector else selector["value"]
    scale = _number(selector.get("scale", 1.0), f"{label}.scale")
    return _number(raw, label) * scale


def _check_keys(value: Any, required: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ModelManifestError(f"{label} must be an object")
    missing = required - value.keys()
    unknown = value.keys() - required
    if missing:
        raise ModelManifestError(f"{label} is missing fields: {', '.join(sorted(missing))}")
    if unknown:
        raise ModelManifestError(f"{label} has unknown fields: {', '.join(sorted(unknown))}")
    return value


def validate_registry(registry: Any) -> list[dict[str, str]]:
    """Validate the authoring registry and its stable role vocabulary."""
    errors: list[dict[str, str]] = []
    try:
        _check_keys(registry, {"schema", "version", "families"}, "registry")
        if registry["schema"] != "openrc-aircraft-model-bindings" or type(registry["version"]) is not int or registry["version"] != 1:
            raise ModelManifestError("registry schema/version is unsupported")
        if not isinstance(registry["families"], list) or not registry["families"]:
            raise ModelManifestError("registry families must be a non-empty array")
        families: set[str] = set()
        builders: set[str] = set()
        for index, family in enumerate(registry["families"]):
            label = f"families[{index}]"
            _check_keys(family, {"family_id", "builder", "geometry", "asset", "bindings", "authoring_sources"}, label)
            family_id = family["family_id"]
            if not isinstance(family_id, str) or not FAMILY_RE.fullmatch(family_id):
                raise ModelManifestError(f"{label}.family_id is not a stable slug")
            if family_id in families:
                raise ModelManifestError(f"duplicate family_id {family_id!r}")
            families.add(family_id)

            builder = _check_keys(family["builder"], {"script", "adapter"}, f"{label}.builder")
            script = _safe_resource_path(builder["script"], f"{label}.builder.script")
            if not script.startswith("res://aircraft/") or not script.endswith("_model.gd") or builder["adapter"] not in ADAPTERS:
                raise ModelManifestError(f"{label}.builder must name a supported bundled model builder")
            if script in builders:
                raise ModelManifestError(f"multiple visual families use builder {script!r}")
            builders.add(script)

            geometry = _check_keys(family["geometry"], {"script", "source", "revision_path", "identity_path", "datum"}, f"{label}.geometry")
            geometry_script = _safe_resource_path(geometry["script"], f"{label}.geometry.script")
            if not geometry_script.startswith("res://aircraft/") or not geometry_script.endswith("_geometry.gd"):
                raise ModelManifestError(f"{label}.geometry.script must be a generated geometry script")
            _safe_repo_path(geometry["source"], f"{label}.geometry.source")
            if not isinstance(geometry["revision_path"], str) or not isinstance(geometry["identity_path"], str):
                raise ModelManifestError(f"{label}.geometry identity selectors must be strings")
            datum = _check_keys(geometry["datum"], {"model_z_le", "model_y_thrust"}, f"{label}.geometry.datum")
            if any(not isinstance(v, dict) for v in datum.values()):
                raise ModelManifestError(f"{label}.geometry.datum values must be selectors")

            asset = family["asset"]
            if not isinstance(asset, dict) or asset.get("kind") not in {"procedural", "imported_glb"}:
                raise ModelManifestError(f"{label}.asset.kind is unsupported")
            if asset["kind"] == "procedural":
                _check_keys(asset, {"kind"}, f"{label}.asset")
                if builder["adapter"] == "imported_glb":
                    raise ModelManifestError(f"{label} imported adapter requires an imported GLB asset")
            else:
                _check_keys(asset, {"kind", "path", "identity_path"}, f"{label}.asset")
                if not _safe_resource_path(asset["path"], f"{label}.asset.path").startswith("res://assets/aircraft/"):
                    raise ModelManifestError(f"{label}.asset.path must be an aircraft asset")
                if not asset["path"].endswith(".glb") or builder["adapter"] != "imported_glb":
                    raise ModelManifestError(f"{label} imported_glb must bind an imported GLB adapter")

            bindings = _check_keys(family["bindings"], {"controls", "rotor", "gear", "crash"}, f"{label}.bindings")
            controls = bindings["controls"]
            if not isinstance(controls, dict) or not controls or set(controls) - CONTROL_ROLES:
                raise ModelManifestError(f"{label}.bindings.controls has an unsupported or empty role set")
            if not REQUIRED_CONTROL_ROLES <= set(controls):
                raise ModelManifestError(f"{label}.bindings.controls must declare {', '.join(sorted(REQUIRED_CONTROL_ROLES))}")
            seen_hinges: set[str] = set()
            seen_nodes: set[str] = set()
            for role, control in controls.items():
                control = _check_keys(control, {"visual_only", "hinges"}, f"{label}.bindings.controls.{role}")
                if not isinstance(control["visual_only"], bool):
                    raise ModelManifestError(f"{label}.bindings.controls.{role}.visual_only must be boolean")
                if not isinstance(control["hinges"], list) or not control["hinges"]:
                    raise ModelManifestError(f"{label}.bindings.controls.{role}.hinges must be a non-empty array")
                for index, hinge in enumerate(control["hinges"]):
                    hinge_label = f"{label}.bindings.controls.{role}.hinges[{index}]"
                    hinge = _check_keys(hinge, {"key", "node", "source", "geometry_ref"}, hinge_label)
                    if not all(isinstance(hinge[key], str) for key in ("key", "node", "source", "geometry_ref")):
                        raise ModelManifestError(f"{hinge_label} text fields must be strings")
                    if not re.fullmatch(r"[a-z][a-z0-9_]*", hinge["key"]) or not hinge["node"].endswith("_hinge"):
                        raise ModelManifestError(f"{hinge_label} needs a stable hinge key and public hinge node name")
                    if hinge["key"] in seen_hinges or hinge["node"] in seen_nodes:
                        raise ModelManifestError(f"{hinge_label} duplicates another control hinge binding")
                    seen_hinges.add(hinge["key"])
                    seen_nodes.add(hinge["node"])
                    if hinge["source"] not in {"builder", "geometry_articulation"}:
                        raise ModelManifestError(f"{hinge_label}.source is unsupported")
                    if (hinge["source"] == "geometry_articulation") != bool(hinge["geometry_ref"]):
                        raise ModelManifestError(f"{hinge_label} must pair geometry_articulation with a geometry_ref")

            rotor = _check_keys(bindings["rotor"], {"present", "node", "spin_node", "diameter", "source", "geometry_ref"}, f"{label}.bindings.rotor")
            if not isinstance(rotor["present"], bool) or not all(isinstance(rotor[k], str) for k in ("node", "spin_node", "source", "geometry_ref")):
                raise ModelManifestError(f"{label}.bindings.rotor fields have invalid types")
            if rotor["source"] not in {"builder", "geometry_articulation", "none"}:
                raise ModelManifestError(f"{label}.bindings.rotor.source is unsupported")
            if (rotor["source"] == "geometry_articulation") != bool(rotor["geometry_ref"]):
                raise ModelManifestError(f"{label}.bindings.rotor must pair geometry_articulation with a geometry_ref")
            if not isinstance(rotor["diameter"], dict):
                raise ModelManifestError(f"{label}.bindings.rotor.diameter must be a selector")

            gear = _check_keys(bindings["gear"], {"keys"}, f"{label}.bindings.gear")
            keys = gear["keys"]
            if not isinstance(keys, dict) or set(keys) - GEAR_ROLES or not all(isinstance(v, str) and v for v in keys.values()):
                raise ModelManifestError(f"{label}.bindings.gear.keys contains an invalid role")
            if len(set(keys.values())) != len(keys):
                raise ModelManifestError(f"{label}.bindings.gear.keys maps multiple roles to one builder key")

            crash = _check_keys(bindings["crash"], {"provider", "metadata_script", "asset_node"}, f"{label}.bindings.crash")
            if not all(isinstance(crash[k], str) for k in crash):
                raise ModelManifestError(f"{label}.bindings.crash fields must be strings")
            if crash["provider"] not in {"none", "generated_triangle_map", "gltf_extras"}:
                raise ModelManifestError(f"{label}.bindings.crash.provider is unsupported")
            if crash["provider"] == "generated_triangle_map":
                if not _safe_resource_path(crash["metadata_script"], f"{label}.bindings.crash.metadata_script").startswith("res://aircraft/"):
                    raise ModelManifestError(f"{label}.bindings.crash.metadata_script must be an aircraft handler")
                if not crash["asset_node"]:
                    raise ModelManifestError(f"{label}.bindings.crash.asset_node is required for a section map")
            elif crash["metadata_script"] or crash["asset_node"]:
                raise ModelManifestError(f"{label}.bindings.crash {crash['provider']} provider cannot name separate metadata")
            if crash["provider"] == "gltf_extras" and asset["kind"] != "imported_glb":
                raise ModelManifestError(f"{label}.bindings.crash gltf_extras requires an imported_glb asset")

            sources = family["authoring_sources"]
            if not isinstance(sources, list):
                raise ModelManifestError(f"{label}.authoring_sources must be an array")
            seen_sources = {geometry["source"]}
            for source in sources:
                source = _check_keys(source, {"path", "role"}, f"{label}.authoring_sources[]")
                path = _safe_repo_path(source["path"], f"{label}.authoring_sources[].path")
                if path in seen_sources:
                    raise ModelManifestError(f"{label} repeats authoring source {path!r}")
                seen_sources.add(path)
                if not isinstance(source["role"], str) or not source["role"]:
                    raise ModelManifestError(f"{label}.authoring_sources[].role must be non-empty")
    except (KeyError, TypeError, ModelManifestError) as exc:
        errors.append({"code": "MODEL_SOURCE_INVALID", "path": "$", "message": str(exc)})
    return errors


def _validate_articulation(source: dict[str, Any], ref: str, node_name: str, label: str) -> None:
    articulation = _resolve(source, ref, label)
    if not isinstance(articulation, dict):
        raise ModelManifestError(f"{label} must refer to an articulation object")
    if articulation.get("node") != node_name:
        raise ModelManifestError(f"{label} node {node_name!r} does not match source node {articulation.get('node')!r}")
    if not isinstance(articulation.get("positive"), str) or not articulation["positive"].strip():
        raise ModelManifestError(f"{label} has no declared positive direction")
    travel = articulation.get("range_deg")
    if not isinstance(travel, list) or len(travel) != 2 or not all(math.isfinite(float(x)) for x in travel):
        raise ModelManifestError(f"{label} has no valid rest-to-travel range")
    sign = articulation.get("app_sign")
    if isinstance(sign, bool) or not isinstance(sign, (int, float)) or abs(float(sign)) != 1.0:
        raise ModelManifestError(f"{label} must declare a signed presentation conversion")


def _collect_dependencies(root: Path, family: dict[str, Any], source: dict[str, Any]) -> list[dict[str, str]]:
    builder = family["builder"]["script"]
    geometry_script = family["geometry"]["script"]
    crash_script = family["bindings"]["crash"]["metadata_script"]
    asset_path = family["asset"].get("path", "")
    pending = [builder, geometry_script]
    if crash_script:
        pending.append(crash_script)
    if asset_path:
        pending.append(asset_path)
        sidecar = asset_path + ".import"
        if _resource_file(root, sidecar).is_file():
            pending.append(sidecar)

    visited: set[str] = set()
    while pending:
        resource = _safe_resource_path(pending.pop(), "dependency path")
        if resource in visited:
            continue
        path = _resource_file(root, resource)
        if not path.is_file():
            raise ModelManifestError(f"missing bundled model dependency {resource!r}")
        visited.add(resource)
        if path.suffix == ".gd":
            text = _normal_bytes(path, "lf_text").decode("utf-8")
            for match in RESOURCE_RE.finditer(text):
                pending.append("res://" + match.group(1))

    dependencies = []
    for resource in sorted(visited):
        path = _resource_file(root, resource)
        mode = "lf_text" if path.suffix.lower() in TEXT_SUFFIXES else "raw"
        if resource == builder:
            role = "builder"
        elif resource == geometry_script:
            role = "generated_geometry"
        elif resource == asset_path:
            role = "imported_asset"
        elif resource == crash_script:
            role = "crash_metadata"
        elif path.suffix == ".gd":
            role = "script_dependency"
        else:
            role = "resource_dependency"
        dependencies.append({"path": resource, "sha256": _hash(_normal_bytes(path, mode)), "hash_mode": mode, "role": role})
    return dependencies


def build_manifest(root: Path, registry_path: Path, family: dict[str, Any]) -> dict[str, Any]:
    root = root.resolve()
    registry_path = registry_path.resolve()
    geometry_cfg = family["geometry"]
    source_path = root / geometry_cfg["source"]
    if not source_path.is_file():
        raise ModelManifestError(f"missing source geometry {geometry_cfg['source']!r}")
    try:
        geometry = json.loads(source_path.read_text(encoding="utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ModelManifestError(f"cannot read source geometry {geometry_cfg['source']!r}: {exc}") from exc
    axes = geometry.get("axes", {})
    if geometry.get("units") != "m" or axes != {"nose": "-Z", "right": "+X", "up": "+Y"}:
        raise ModelManifestError(f"{family['family_id']} geometry does not use the accepted metre/+X-right/+Y-up/-Z-nose convention")

    datum_source = geometry_cfg["datum"]
    datum = {key: _selector_value(geometry, selector, f"{family['family_id']}.datum.{key}") for key, selector in datum_source.items()}
    revision = _resolve(geometry, geometry_cfg["revision_path"], f"{family['family_id']}.geometry.revision")
    identity = _resolve(geometry, geometry_cfg["identity_path"], f"{family['family_id']}.asset.identity")
    if not isinstance(revision, str) or not revision or not isinstance(identity, str) or not identity:
        raise ModelManifestError(f"{family['family_id']} geometry revision and identity must be non-empty strings")

    for role, control in family["bindings"]["controls"].items():
        for hinge in control["hinges"]:
            if hinge["source"] == "geometry_articulation":
                _validate_articulation(geometry, hinge["geometry_ref"], hinge["node"], f"{family['family_id']}.controls.{role}.{hinge['key']}")
    rotor_cfg = family["bindings"]["rotor"]
    diameter = _selector_value(geometry, rotor_cfg["diameter"], f"{family['family_id']}.rotor.authored_diameter_m")
    if diameter < 0.0 or (rotor_cfg["present"] and diameter <= 0.0) or (not rotor_cfg["present"] and diameter != 0.0):
        raise ModelManifestError(f"{family['family_id']} rotor diameter does not agree with declared rotor presence")
    if rotor_cfg["source"] == "geometry_articulation":
        articulation = _resolve(geometry, rotor_cfg["geometry_ref"], f"{family['family_id']}.rotor")
        if not isinstance(articulation, dict) or articulation.get("node") != rotor_cfg["spin_node"]:
            raise ModelManifestError(f"{family['family_id']} rotor spin node does not agree with source articulation")
        if not isinstance(articulation.get("positive"), str) or not articulation["positive"].strip():
            raise ModelManifestError(f"{family['family_id']} rotor articulation lacks its declared rotation sense")

    source_registry_rel = registry_path.relative_to(root).as_posix()
    source_record = {
        "path": source_registry_rel,
        "sha256": _hash(_normal_bytes(registry_path, "lf_text")),
        "hash_mode": "lf_text",
    }
    geometry_source = {
        "path": geometry_cfg["source"],
        "sha256": _hash(_normal_bytes(source_path, "lf_text")),
        "hash_mode": "lf_text",
    }
    authoring_sources = [dict(geometry_source, role="geometry")]
    for extra in family["authoring_sources"]:
        path_rel = _safe_repo_path(extra["path"], "authoring source path")
        path = root / path_rel
        if not path.is_file():
            raise ModelManifestError(f"missing authoring source {path_rel!r}")
        authoring_sources.append({
            "path": path_rel,
            "sha256": _hash(_normal_bytes(path, "lf_text")),
            "hash_mode": "lf_text",
            "role": extra["role"],
        })

    asset_cfg = family["asset"]
    if asset_cfg["kind"] == "procedural":
        asset = {"kind": "procedural", "identity": identity, "revision": revision}
    else:
        path = asset_cfg["path"]
        asset_file = _resource_file(root, path)
        if not asset_file.is_file():
            raise ModelManifestError(f"missing imported aircraft asset {path!r}")
        asset_hash = _hash(asset_file.read_bytes())
        declared_hash = _resolve(geometry, "inputs.glb_sha256", f"{family['family_id']}.asset.sha256")
        if declared_hash != asset_hash:
            raise ModelManifestError(f"{family['family_id']} geometry's imported asset hash is stale")
        asset_identity = _resolve(geometry, asset_cfg["identity_path"], f"{family['family_id']}.asset.identity")
        asset = {"kind": "imported_glb", "identity": str(asset_identity), "revision": revision, "path": path, "sha256": asset_hash}

    dependencies = _collect_dependencies(root, family, geometry)
    controls = {}
    for role, control in family["bindings"]["controls"].items():
        controls[role] = {
            "visual_only": control["visual_only"],
            "hinges": [
                {
                    "key": hinge["key"],
                    "node": hinge["node"],
                    "source": hinge["source"],
                    "geometry_ref": hinge["geometry_ref"],
                }
                for hinge in control["hinges"]
            ],
        }
    output_bindings = {
        "controls": controls,
        "rotor": {
            "present": rotor_cfg["present"],
            "node": rotor_cfg["node"],
            "spin_node": rotor_cfg["spin_node"],
            "authored_diameter_m": diameter,
            "source": rotor_cfg["source"],
            "geometry_ref": rotor_cfg["geometry_ref"],
        },
        "gear": family["bindings"]["gear"],
        "crash": family["bindings"]["crash"],
    }
    return {
        "schema": "openrc-aircraft-model",
        "version": 1,
        "family_id": family["family_id"],
        "builder": family["builder"],
        "surface_method": "apply_surfaces",
        "datum": datum,
        "coordinates": {"units": "m", "nose": "-Z", "right": "+X", "up": "+Y"},
        "root_node": "airplane",
        "source_registry": source_record,
        "geometry": {
            "script": geometry_cfg["script"],
            "source": geometry_source,
            "revision": revision,
            "datum_source": datum_source,
        },
        "asset": asset,
        "bindings": output_bindings,
        "authoring_sources": authoring_sources,
        "dependencies": dependencies,
    }


def validate_dependency_hashes(root: Path, manifest: dict[str, Any]) -> list[dict[str, str]]:
    diagnostics: list[dict[str, str]] = []
    dependencies = manifest.get("dependencies")
    if not isinstance(dependencies, list):
        return [{"code": "MODEL_DEPENDENCIES_INVALID", "path": "$.dependencies", "message": "dependencies must be an array"}]
    seen: set[str] = set()
    for index, dependency in enumerate(dependencies):
        path = dependency.get("path", "") if isinstance(dependency, dict) else ""
        label = f"$.dependencies[{index}]"
        try:
            resource = _safe_resource_path(path, f"{label}.path")
            if resource in seen:
                raise ModelManifestError(f"duplicate dependency path {resource!r}")
            seen.add(resource)
            mode = dependency.get("hash_mode")
            expected = dependency.get("sha256")
            if mode not in {"raw", "lf_text"} or not isinstance(expected, str) or not HASH_RE.fullmatch(expected):
                raise ModelManifestError("dependency hash fields are malformed")
            source = _resource_file(root, resource)
            if not source.is_file():
                raise ModelManifestError(f"missing dependency {resource!r}")
            actual = _hash(_normal_bytes(source, mode))
            if actual != expected:
                raise ModelManifestError(f"SHA-256 mismatch for {resource!r}: expected {expected}, got {actual}")
        except (ModelManifestError, OSError) as exc:
            diagnostics.append({"code": "MODEL_DEPENDENCY_INVALID", "path": label, "message": str(exc)})
    return diagnostics


def generate(root: Path, check: bool) -> int:
    registry_path = root / REGISTRY_PATH
    if not registry_path.is_file():
        print(f"missing registry: {REGISTRY_PATH}", file=sys.stderr)
        return 1
    try:
        registry = json.loads(registry_path.read_text(encoding="utf-8"))
        diagnostics = validate_registry(registry)
        if diagnostics:
            raise ModelManifestError(diagnostics[0]["message"])
        manifests = {
            family["family_id"]: build_manifest(root, registry_path, family)
            for family in registry["families"]
        }
    except (UnicodeError, json.JSONDecodeError, ModelManifestError) as exc:
        print(f"model manifest generation failed: {exc}", file=sys.stderr)
        return 1

    output_dir = root / OUTPUT_DIR
    expected_names = {f"{family_id}.json" for family_id in manifests}
    existing_names = {path.name for path in output_dir.glob("*.json")} if output_dir.exists() else set()
    stale_names = existing_names - expected_names
    if stale_names:
        print("unregistered generated manifests: " + ", ".join(sorted(stale_names)), file=sys.stderr)
        return 1

    changed = []
    for family_id, manifest in manifests.items():
        path = output_dir / f"{family_id}.json"
        rendered = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
        if not path.is_file() or path.read_text(encoding="utf-8") != rendered:
            changed.append((path, rendered))
    if check:
        if changed:
            print("stale generated aircraft model manifests:", file=sys.stderr)
            for path, _ in changed:
                print("  " + path.relative_to(root).as_posix(), file=sys.stderr)
            print("run: python research/aircraft-standardization/build_models.py", file=sys.stderr)
            return 1
        print(f"model manifests current ({len(manifests)} visual families)")
        return 0

    output_dir.mkdir(parents=True, exist_ok=True)
    for path, rendered in changed:
        path.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"generated {len(manifests)} aircraft model manifests")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated manifests are stale")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    return generate(args.root.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
