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
LIVERY_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")
LIVERY_LIMIT = 16
LIVERY_LABEL_LIMIT = 48
RESOURCE_RE = re.compile(r"\b(?:preload|load)\s*\(\s*[\"']res://([^\"']+)[\"']\s*\)")
TEXT_SUFFIXES = {".cfg", ".gd", ".godot", ".import", ".json", ".md", ".svg", ".tres", ".tscn", ".txt"}
ADAPTERS = {"euler_hinges", "axis_hinges", "imported_glb"}
CONTROL_ROLES = {"aileron_left", "aileron_right", "elevator", "rudder", "flap_left", "flap_right", "elevon_left", "elevon_right"}
GEAR_ROLES = {"left", "right", "tail", "steering", "nose"}
# X8-02: a family declares the four conventional roles or exactly both elevons (model_manifest.gd); flaps stay optional.
REQUIRED_CONTROL_ROLES = {"aileron_left", "aileron_right", "elevator", "rudder"}
ELEVON_ROLES = {"elevon_left", "elevon_right"}
SHARED_IMPORTED_BUILDER = "res://aircraft/imported_model.gd"
CONSTRUCTION_ROLES = {"left", "right", "tail", "steering", "nose"}
MECHANISM_KEYS = ("canopy", "tailhook", "cowl_flaps")  # imported_model_contract.gd MECHANISM_KEYS
# F4U-02: a sampled retraction rig steers either a nose wheel (tricycle) or a tail wheel (taildragger).
RETRACT_ROLE_SETS = ({"left", "right", "nose", "steering"}, {"left", "right", "tail", "steering"})
CONSTRUCTION_AXES = {"+X", "-X", "+Y", "-Y", "+Z", "-Z"}


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


def _check_keys(value: Any, required: set[str], label: str, optional: set[str] | None = None) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ModelManifestError(f"{label} must be an object")
    optional = optional or set()
    missing = required - value.keys()
    unknown = value.keys() - required - optional
    if missing:
        raise ModelManifestError(f"{label} is missing fields: {', '.join(sorted(missing))}")
    if unknown:
        raise ModelManifestError(f"{label} has unknown fields: {', '.join(sorted(unknown))}")
    return value


def _safe_node_name(value: Any, label: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"[A-Za-z0-9_]+", value) is None:
        raise ModelManifestError(f"{label} must be a safe node name")
    return value


def _construction_ref(source: dict[str, Any], reference: Any, expected_node: Any, label: str) -> dict[str, Any]:
    if not isinstance(reference, str) or not reference or re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*", reference) is None:
        raise ModelManifestError(f"{label} must be a dotted source reference")
    value = _resolve(source, reference, label)
    if not isinstance(value, dict):
        raise ModelManifestError(f"{label} must resolve to an object")
    if value.get("node") != expected_node:
        raise ModelManifestError(f"{label} node {expected_node!r} does not match source node {value.get('node')!r}")
    return value


def _validate_construction(construction: Any, bindings: dict[str, Any], label: str) -> None:
    construction = _check_keys(
        construction,
        {"version", "hinge_axis", "rotor", "gear", "material_grow"},
        f"{label}.construction",
        {"retraction", "folds", "mechanisms"},
    )
    if "mechanisms" in construction:
        # F4U-21: auxiliary mechanisms the flight scene drives by key, at most one of each.
        mechanisms = construction["mechanisms"]
        if not isinstance(mechanisms, list) or not 1 <= len(mechanisms) <= len(MECHANISM_KEYS):
            raise ModelManifestError(f"{label}.construction.mechanisms must be an array of one to three known mechanisms")
        seen: set[str] = set()
        for index, mechanism in enumerate(mechanisms):
            mechanism = _check_keys(mechanism, {"key", "geometry_ref"}, f"{label}.construction.mechanisms[{index}]")
            if mechanism["key"] not in MECHANISM_KEYS or mechanism["key"] in seen:
                raise ModelManifestError(f"{label}.construction.mechanisms[{index}].key must be a unique one of {', '.join(MECHANISM_KEYS)}")
            seen.add(mechanism["key"])
            if not isinstance(mechanism["geometry_ref"], str) or re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*", mechanism["geometry_ref"]) is None:
                raise ModelManifestError(f"{label}.construction.mechanisms[{index}].geometry_ref must be a dotted source reference")
    if "folds" in construction:
        # F4U-17: one or two in-place fold groups, each a unique key and a dotted geometry reference.
        folds = construction["folds"]
        if not isinstance(folds, list) or not 1 <= len(folds) <= 2:
            raise ModelManifestError(f"{label}.construction.folds must be an array of one or two fold groups")
        keys: set[str] = set()
        for index, fold in enumerate(folds):
            fold = _check_keys(fold, {"key", "geometry_ref"}, f"{label}.construction.folds[{index}]")
            _safe_node_name(fold["key"], f"{label}.construction.folds[{index}].key")
            if fold["key"] in keys:
                raise ModelManifestError(f"{label}.construction.folds[{index}].key repeats {fold['key']}")
            keys.add(fold["key"])
            if not isinstance(fold["geometry_ref"], str) or re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*", fold["geometry_ref"]) is None:
                raise ModelManifestError(f"{label}.construction.folds[{index}].geometry_ref must be a dotted source reference")
    if type(construction["version"]) is not int or construction["version"] != 1:
        raise ModelManifestError(f"{label}.construction.version must be integer 1")
    if construction["hinge_axis"] != "+X":
        raise ModelManifestError(f"{label}.construction.hinge_axis must be +X")

    if bindings["rotor"]["present"]:
        rotor = _check_keys(construction["rotor"], {"frame_node", "geometry_ref", "axis"}, f"{label}.construction.rotor")
        _safe_node_name(rotor["frame_node"], f"{label}.construction.rotor.frame_node")
        if not isinstance(rotor["geometry_ref"], str) or re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*", rotor["geometry_ref"]) is None:
            raise ModelManifestError(f"{label}.construction.rotor.geometry_ref must be a dotted source reference")
        if not isinstance(rotor["axis"], str) or rotor["axis"] not in CONSTRUCTION_AXES:
            raise ModelManifestError(f"{label}.construction.rotor.axis must be a signed X, Y or Z axis")
    else:
        _check_keys(construction["rotor"], set(), f"{label}.construction.rotor")
        rotor = {}

    expected_roles = set(bindings["gear"]["keys"])
    if "retraction" in construction:
        retract = _check_keys(construction["retraction"], {"geometry_ref"}, f"{label}.construction.retraction")
        if not isinstance(retract["geometry_ref"], str) or re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*", retract["geometry_ref"]) is None:
            raise ModelManifestError(f"{label}.construction.retraction needs a dotted source reference")
        if expected_roles not in RETRACT_ROLE_SETS or construction["gear"] != []:
            raise ModelManifestError(f"{label}.construction.retraction needs left/right/steering plus a nose or tail wheel and no static wrappers")
        expected_roles = set()
    if not isinstance(construction["gear"], list):
        raise ModelManifestError(f"{label}.construction.gear must be an array")
    seen_roles: set[str] = set()
    used_names: dict[str, str] = {"propeller": "generated propeller", "propeller_mount": "generated propeller mount"}

    def claim_name(value: Any, item_label: str) -> None:
        name = _safe_node_name(value, item_label)
        if name in used_names:
            raise ModelManifestError(f"{item_label} node name {name!r} collides with {used_names[name]}")
        used_names[name] = item_label

    for role, control in bindings["controls"].items():
        for hinge in control["hinges"]:
            if hinge["source"] != "geometry_articulation":
                raise ModelManifestError(f"{label}.bindings.controls.{role}.{hinge['key']} must source its hinge from geometry_articulation")
            claim_name(hinge["node"], f"{label}.bindings.controls.{role}.{hinge['key']}.node")
    if bindings["rotor"]["node"] != "propeller":
        claim_name(bindings["rotor"]["node"], f"{label}.bindings.rotor.node")
    if bindings["rotor"]["spin_node"]:
        claim_name(bindings["rotor"]["spin_node"], f"{label}.bindings.rotor.spin_node")
    if bindings["rotor"]["present"]:
        claim_name(rotor["frame_node"], f"{label}.construction.rotor.frame_node")

    for index, entry in enumerate(construction["gear"]):
        item_label = f"{label}.construction.gear[{index}]"
        entry = _check_keys(entry, {"role", "node", "geometry_ref", "wrapper"}, item_label)
        role = entry["role"]
        if not isinstance(role, str) or role not in CONSTRUCTION_ROLES:
            raise ModelManifestError(f"{item_label}.role is unsupported")
        if role in seen_roles:
            raise ModelManifestError(f"{item_label}.role duplicates a gear role")
        seen_roles.add(role)
        if role not in expected_roles:
            raise ModelManifestError(f"{item_label}.role is not declared by bindings.gear.keys")
        claim_name(entry["node"], f"{item_label}.node")
        wrapper_name = _safe_node_name(entry["wrapper"], f"{item_label}.wrapper")
        claim_name(wrapper_name, f"{item_label}.wrapper")
        claim_name(wrapper_name + "_mount", f"{item_label}.wrapper_mount")
        if not isinstance(entry["geometry_ref"], str) or re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*", entry["geometry_ref"]) is None:
            raise ModelManifestError(f"{item_label}.geometry_ref must be a dotted source reference")
    if seen_roles != expected_roles:
        missing = ", ".join(sorted(expected_roles - seen_roles))
        raise ModelManifestError(f"{label}.construction.gear must declare each bindings.gear.keys role once; missing {missing}")

    if not isinstance(construction["material_grow"], list):
        raise ModelManifestError(f"{label}.construction.material_grow must be an array")
    seen_material_pairs: set[tuple[str, str]] = set()
    for index, entry in enumerate(construction["material_grow"]):
        item_label = f"{label}.construction.material_grow[{index}]"
        entry = _check_keys(entry, {"node", "materials", "amount_m"}, item_label)
        node = _safe_node_name(entry["node"], f"{item_label}.node")
        materials = entry["materials"]
        if not isinstance(materials, list) or not materials:
            raise ModelManifestError(f"{item_label}.materials must be a non-empty array")
        if any(not isinstance(material, str) or not material.strip() for material in materials):
            raise ModelManifestError(f"{item_label}.materials entries must be non-empty strings")
        if len(set(materials)) != len(materials):
            raise ModelManifestError(f"{item_label}.materials repeats a material name")
        for material in materials:
            pair = (node, material)
            if pair in seen_material_pairs:
                raise ModelManifestError(f"{item_label} repeats node/material pair {pair!r}")
            seen_material_pairs.add(pair)
        amount = entry["amount_m"]
        if isinstance(amount, bool) or not isinstance(amount, (int, float)) or not math.isfinite(float(amount)) or not 0.0 < float(amount) <= 0.01:
            raise ModelManifestError(f"{item_label}.amount_m must be finite and greater than 0 and at most 0.01 m")


def validate_registry(registry: Any) -> list[dict[str, str]]:
    """Validate the authoring registry and its stable role vocabulary."""
    errors: list[dict[str, str]] = []
    try:
        _check_keys(registry, {"schema", "version", "families"}, "registry")
        if registry["schema"] != "openrc-aircraft-model-bindings" or type(registry["version"]) is not int or registry["version"] not in {1, 2}:
            raise ModelManifestError("registry schema/version is unsupported")
        registry_version = registry["version"]
        if not isinstance(registry["families"], list) or not registry["families"]:
            raise ModelManifestError("registry families must be a non-empty array")
        families: set[str] = set()
        builders: set[str] = set()
        for index, family in enumerate(registry["families"]):
            label = f"families[{index}]"
            _check_keys(family, {"family_id", "builder", "geometry", "asset", "bindings", "authoring_sources"}, label, {"construction"})
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
            if script != SHARED_IMPORTED_BUILDER:
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
                _check_keys(asset, {"kind", "path", "identity_path"}, f"{label}.asset", {"liveries_path"})
                if not _safe_resource_path(asset["path"], f"{label}.asset.path").startswith("res://assets/aircraft/"):
                    raise ModelManifestError(f"{label}.asset.path must be an aircraft asset")
                if not asset["path"].endswith(".glb") or builder["adapter"] != "imported_glb":
                    raise ModelManifestError(f"{label} imported_glb must bind an imported GLB adapter")
                # F4U-16: selectable liveries of one airframe, a dotted geometry reference; version 2 scenes only.
                if "liveries_path" in asset:
                    if not isinstance(asset["liveries_path"], str) or re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*", asset["liveries_path"]) is None:
                        raise ModelManifestError(f"{label}.asset.liveries_path must be a dotted source reference")
                    if "construction" not in family:
                        raise ModelManifestError(f"{label}.asset.liveries_path requires a version 2 imported construction")

            bindings = _check_keys(family["bindings"], {"controls", "rotor", "gear", "crash"}, f"{label}.bindings")
            controls = bindings["controls"]
            if not isinstance(controls, dict) or not controls or set(controls) - CONTROL_ROLES:
                raise ModelManifestError(f"{label}.bindings.controls has an unsupported or empty role set")
            if ELEVON_ROLES & set(controls):
                if not ELEVON_ROLES <= set(controls) or REQUIRED_CONTROL_ROLES & set(controls):
                    raise ModelManifestError(f"{label}.bindings.controls must declare both {', '.join(sorted(ELEVON_ROLES))} "
                                             f"and none of {', '.join(sorted(REQUIRED_CONTROL_ROLES))}")
            elif not REQUIRED_CONTROL_ROLES <= set(controls):
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

            has_construction = "construction" in family
            if has_construction:
                if registry_version != 2:
                    raise ModelManifestError(f"{label}.construction requires source registry version 2")
                if script != SHARED_IMPORTED_BUILDER or builder["adapter"] != "imported_glb" or asset["kind"] != "imported_glb":
                    raise ModelManifestError(f"{label}.construction requires the shared imported_glb builder and an imported asset")
                if crash["provider"] == "generated_triangle_map":
                    raise ModelManifestError(f"{label}.construction does not support generated_triangle_map crash metadata")
                _validate_construction(family["construction"], bindings, label)
            elif script == SHARED_IMPORTED_BUILDER:
                raise ModelManifestError(f"{label} shared imported builder requires a construction object")

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
    if not isinstance(travel, list) or len(travel) != 2:
        raise ModelManifestError(f"{label} has no valid rest-to-travel range")
    travel_low = _number(travel[0], f"{label}.range_deg[0]")
    travel_high = _number(travel[1], f"{label}.range_deg[1]")
    if travel_low >= travel_high:
        raise ModelManifestError(f"{label} rest-to-travel range must be increasing")
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


def _liveries(root: Path, source: dict[str, Any], reference: str, asset: dict[str, Any], label: str) -> list[dict[str, str]]:
    """F4U-16: selectable paint schemes of one airframe, each its own GLB with the default's import settings. The
    first is the default and must be the manifest asset. Every GLB and import sidecar is pinned by SHA-256."""
    records = _resolve(source, reference, label)
    if not isinstance(records, list) or not 2 <= len(records) <= LIVERY_LIMIT:
        raise ModelManifestError(f"{label} must list 2 to {LIVERY_LIMIT} liveries")
    liveries = []
    for index, record in enumerate(records):
        item = f"{label}[{index}]"
        record = _check_keys(record, {"id", "label", "path", "glb_sha256"}, item)
        if not isinstance(record["id"], str) or LIVERY_RE.fullmatch(record["id"]) is None or record["id"] in {r["id"] for r in liveries}:
            raise ModelManifestError(f"{item}.id must be a unique lowercase identifier")
        text = record["label"]
        if not isinstance(text, str) or not text.strip() or len(text) > LIVERY_LABEL_LIMIT or any(ord(c) < 32 for c in text):
            raise ModelManifestError(f"{item}.label must be 1 to {LIVERY_LABEL_LIMIT} printable characters")
        path = _safe_resource_path(record["path"], f"{item}.path")
        if not path.startswith("res://assets/aircraft/") or not path.endswith(".glb") or path in {r["path"] for r in liveries}:
            raise ModelManifestError(f"{item}.path must be a unique aircraft GLB")
        glb, sidecar = _resource_file(root, path), _resource_file(root, path + ".import")
        if not glb.is_file() or not sidecar.is_file():
            raise ModelManifestError(f"{item} GLB or its import sidecar is missing")
        digest = _hash(glb.read_bytes())
        if digest != record["glb_sha256"]:
            raise ModelManifestError(f"{item} geometry's livery hash is stale")
        if index == 0 and (path != asset["path"] or digest != asset["sha256"]):
            raise ModelManifestError(f"{label}[0] must be the default imported asset")
        liveries.append({"id": record["id"], "label": text, "path": path, "sha256": digest,
                         "import_sha256": _hash(_normal_bytes(sidecar, "lf_text"))})
    return liveries


def _validate_retraction_rig(rig: Any, gear_keys: set[str]) -> None:
    """Sampled retraction rig rules shared with app/aircraft/retractable_model.gd."""
    wheels = set(rig.get("wheels", {})) if isinstance(rig, dict) else set()
    if not isinstance(rig, dict) or rig.get("version") != 1 or wheels | {"steering"} not in RETRACT_ROLE_SETS:
        raise ModelManifestError("Retractable model needs version 1, left/right wheels and one nose or tail wheel")
    if wheels | {"steering"} != gear_keys:
        raise ModelManifestError("Retractable model wheels must match the family's gear bindings")
    samples = rig.get("retraction", {}).get("samples", [])
    if not 2 <= len(samples) <= 513:
        raise ModelManifestError("Retractable model requires 2..513 sampled poses")
    names = set(samples[0]["nodes"])
    helpers = set()
    for index, sample in enumerate(samples):
        if abs(sample["extension"] - index / (len(samples) - 1)) > 1e-8 or set(sample["nodes"]) != names:
            raise ModelManifestError("Retractable model samples must share a uniform grid and node set")
        for name, pose in sample["nodes"].items():
            values = pose.get("translation", []) + pose.get("rotation_wxyz", [])
            if len(pose.get("translation", [])) != 3 or len(pose.get("rotation_wxyz", [])) != 4 or any(type(v) not in (int, float) or not math.isfinite(v) for v in values) or abs(sum(v*v for v in pose["rotation_wxyz"]) - 1) > 1e-5 or name not in rig.get("bindings", {}):
                raise ModelManifestError("Retractable model has an invalid pose or missing rest binding")
    for role, wheel in rig["wheels"].items():
        for key in ("spin_node", "compression_node") + (("steer_node",) if role in ("nose", "tail") else ()):
            name = wheel.get(key)
            # F4U-05: an oleo slider may be a sampled carrier; spin and steering helpers may not.
            if name not in rig["bindings"] or (name in names and key != "compression_node") or name in helpers:
                raise ModelManifestError("Retractable model has an invalid or reused wheel helper")
            helpers.add(name)
        for key in ("center_model", "contact_model"):
            path = wheel.get(key, [])
            if len(path) != len(samples) or any(len(p) != 3 or any(type(v) not in (int, float) or not math.isfinite(v) for v in p) for p in path):
                raise ModelManifestError("Retractable wheel paths must match the sample grid")


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

    construction = family.get("construction")
    if construction is not None:
        if "retraction" in construction:
            rig = _resolve(geometry, construction["retraction"]["geometry_ref"], f"{family['family_id']}.retraction")
            _validate_retraction_rig(rig, set(family["bindings"]["gear"]["keys"]))
        if rotor_cfg["present"]:
            thrust_frame = _construction_ref(
                geometry,
                construction["rotor"]["geometry_ref"],
                construction["rotor"]["frame_node"],
                f"{family['family_id']}.construction.rotor",
            )
            if thrust_frame.get("spin_node") != rotor_cfg["spin_node"]:
                raise ModelManifestError(f"{family['family_id']} construction rotor spin node does not match its thrust frame")
        for index, gear in enumerate(construction["gear"]):
            _construction_ref(
                geometry,
                gear["geometry_ref"],
                gear["node"],
                f"{family['family_id']}.construction.gear[{index}]",
            )

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
    manifest = {
        "schema": "openrc-aircraft-model",
        "version": 2 if construction is not None else 1,
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
    if construction is not None:
        manifest["construction"] = construction
    if "liveries_path" in asset_cfg:
        manifest["liveries"] = _liveries(root, geometry, asset_cfg["liveries_path"], asset, f"{family['family_id']}.liveries")
    return manifest


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
        if not path.is_file() or path.read_bytes() != rendered.encode("utf-8"):
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
