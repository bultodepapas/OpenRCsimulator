#!/usr/bin/env python3
"""Generate the separate, manifest-pinned aircraft customization slot registry."""

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
SOURCE_PATH = Path("assets/aircraft/customization-bindings.json")
MODEL_SOURCE_PATH = Path("assets/aircraft/model-bindings.json")
MODEL_OUTPUT_DIR = Path("app/data/aircraft_models")
OUTPUT_PATH = Path("app/data/aircraft_customization.json")
SOURCE_FORMAT = "openrc-aircraft-customization-source"
COMPANION_FORMAT = "openrc-aircraft-customization-bindings"
REGISTRY_FORMAT = "openrc-aircraft-customization-registry"
PRESENTATION_ENGINE_VERSION = "4.8.0"
LEGACY_PRESENTATION_SOURCE_PATHS = (
    "res://render/aircraft_customization.gd",
    "res://render/presentation_sources.gd",
    "res://render/smoke/exhaust.gd",
    "res://render/smoke/process.gdshader",
    "res://render/smoke/profile_process.gdshader",
    "res://render/smoke/profile_smoke.gd",
    "res://render/smoke/profile_smoke_schedule.gd",
)
PRESENTATION_SOURCE_PATHS_V2 = LEGACY_PRESENTATION_SOURCE_PATHS + (
    "res://render/smoke/smoke_system.gd",
    "res://render/smoke/stock_profile.gd",
    "res://workshop/presentation.gd",
)
PRESENTATION_SOURCE_PATHS_V3 = (
    "res://audio/mechanical_profile.gd",
    "res://render/aircraft_customization.gd",
    "res://render/lighting/aircraft_lighting_rig_3d.gd",
    "res://render/lighting/lighting_patterns.gd",
    "res://render/lighting/lighting_profile.gd",
    "res://render/lighting/lighting_vfx.gd",
    "res://render/lighting/rgb_lamp.gdshader",
    "res://render/lighting/rgb_strip.gdshader",
    "res://render/presentation_sources.gd",
    "res://render/smoke/exhaust.gd",
    "res://render/smoke/process.gdshader",
    "res://render/smoke/profile_process.gdshader",
    "res://render/smoke/profile_smoke.gd",
    "res://render/smoke/profile_smoke_schedule.gd",
    "res://render/smoke/smoke_system.gd",
    "res://render/smoke/stock_profile.gd",
    "res://render/world/aircraft_light_state.gd",
    "res://render/world/aircraft_lights.gd",
    "res://render/world/engine_srgb.gdshaderinc",
    "res://render/world/exposure.gd",
    "res://render/world/led_strip.gdshader",
    "res://render/world/light_sprite.gdshader",
    "res://workshop/presentation.gd",
)
PRESENTATION_SOURCE_PATHS = PRESENTATION_SOURCE_PATHS_V3
EMISSIONS_PRESETS = {"glow_two_stroke", "glow_four_stroke", "glow_installation", "gasoline_two_stroke", "turbine_show", "independent_show"}
SLOT_ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,79}$")
FAMILY_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
LABEL_RE = re.compile(r"^[ -~]{1,32}$")
NODE_PATH_RE = re.compile(r"^[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*$")
PARAM_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,63}$")
PAINT_KINDS = {"standard_albedo", "shader_color"}
SMOKE_ROLES = {"wing_tip_left", "wing_tip_right", "tail", "tailpipe", "exhaust"}
SOURCE_ANCHOR_REFS = {"exhausts[0]"}
PHYSICAL_ID_REFS = {"propulsion.id"}
PHYSICAL_KIND_REFS = {"propulsion.kind"}
SOURCE_KINDS = {"glow_prop"}
MARKING_TEXT_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -ÁÉÍÓÚÜÑáéíóúüñ")
MARKING_WIDTH_BOUNDS_M = (0.01, 1.0)
MARKING_HEIGHT_BOUNDS_M = (0.01, 0.3)
LIGHT_ANCHOR_IDS = {
    "nav_left", "nav_right", "nav_tail", "strobe_left", "strobe_right", "strobe_dorsal",
    "strobe_ventral", "landing", "landing_right",
}
LIGHT_STRIP_IDS = {"strip_left", "strip_right", "strip_top_left", "strip_top_right", "strip_belly"}
LIGHT_NODE_PATH_MAX_CHARS = 160
LIGHT_ANCHOR_LIMIT = 9
LIGHT_STRIP_LIMIT = 5
LIGHT_STRIP_POINT_LIMIT = 32
LIGHT_STRIP_WIDTH_BOUNDS_M = (0.001, 0.05)


class CustomizationError(ValueError):
    """Raised when authored customization slots cannot safely be generated."""


def _normalize_numbers(value: Any) -> Any:
    if isinstance(value, bool) or value is None or isinstance(value, (str, int)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise CustomizationError("canonical data must contain only finite numbers")
        if value.is_integer():
            return int(value)
        return value
    if isinstance(value, list):
        return [_normalize_numbers(item) for item in value]
    if isinstance(value, dict):
        return {str(key): _normalize_numbers(item) for key, item in value.items()}
    raise CustomizationError(f"unsupported canonical value type: {type(value).__name__}")


def canonical_bytes(value: Any) -> bytes:
    """Canonical JSON shared with the Godot runtime and presentation profile."""
    normalized = _normalize_numbers(value)
    return json.dumps(normalized, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def _closed(value: Any, required: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise CustomizationError(f"{label} must be an object")
    if value.keys() != required:
        missing = sorted(required - value.keys())
        extra = sorted(value.keys() - required)
        raise CustomizationError(f"{label} keys mismatch (missing={missing}, unknown={extra})")
    return value


def _text(value: Any, pattern: re.Pattern[str], label: str) -> str:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise CustomizationError(f"{label} is malformed")
    return value


def _vector(value: Any, label: str, *, unit: bool = False) -> list[float | int]:
    if not isinstance(value, list) or len(value) != 3:
        raise CustomizationError(f"{label} must be a three-number array")
    numbers: list[float | int] = []
    for part in value:
        if isinstance(part, bool) or not isinstance(part, (int, float)):
            raise CustomizationError(f"{label} must contain finite numbers")
        try:
            number = float(part)
        except OverflowError as exc:
            raise CustomizationError(f"{label} must contain finite numbers") from exc
        if not math.isfinite(number):
            raise CustomizationError(f"{label} must contain finite numbers")
        if abs(number) > 5.0:
            raise CustomizationError(f"{label} exceeds the five-metre source-space bound")
        numbers.append(part)
    if unit and not 0.999 <= sum(float(part) ** 2 for part in numbers) ** 0.5 <= 1.001:
        raise CustomizationError(f"{label} must be a unit direction")
    return numbers


def empty_lighting_layout() -> dict[str, Any]:
    """Return the canonical no-authored-light layout used by historical sources."""
    return {"version": 1, "anchors": [], "strips": []}


def _lighting_node_path(value: Any, label: str) -> str:
    if value == ".":
        return value
    path = _text(value, NODE_PATH_RE, label)
    if len(path) > LIGHT_NODE_PATH_MAX_CHARS:
        raise CustomizationError(f"{label} exceeds {LIGHT_NODE_PATH_MAX_CHARS} characters")
    return path


def validate_lighting_layout(layout: Any, label: str) -> dict[str, Any]:
    _closed(layout, {"version", "anchors", "strips"}, label)
    version = layout["version"]
    if isinstance(version, bool) or not isinstance(version, (int, float)):
        raise CustomizationError(f"{label}.version is unsupported")
    try:
        numeric_version = float(version)
    except OverflowError as exc:
        raise CustomizationError(f"{label}.version is unsupported") from exc
    if not math.isfinite(numeric_version) or numeric_version != 1.0:
        raise CustomizationError(f"{label}.version is unsupported")
    anchors, strips = layout["anchors"], layout["strips"]
    if not isinstance(anchors, list) or len(anchors) > LIGHT_ANCHOR_LIMIT:
        raise CustomizationError(f"{label}.anchors must be an array of at most {LIGHT_ANCHOR_LIMIT} entries")
    if not isinstance(strips, list) or len(strips) > LIGHT_STRIP_LIMIT:
        raise CustomizationError(f"{label}.strips must be an array of at most {LIGHT_STRIP_LIMIT} entries")

    validated_anchors: list[dict[str, Any]] = []
    anchor_ids: set[str] = set()
    for index, anchor in enumerate(anchors):
        anchor_label = f"{label}.anchors[{index}]"
        _closed(anchor, {"id", "node_path", "position_m", "gear_gated"}, anchor_label)
        anchor_id = anchor["id"]
        if not isinstance(anchor_id, str) or anchor_id not in LIGHT_ANCHOR_IDS:
            raise CustomizationError(f"{anchor_label}.id is unsupported")
        if anchor_id in anchor_ids:
            raise CustomizationError(f"{anchor_label}.id is duplicated")
        anchor_ids.add(anchor_id)
        node_path = _lighting_node_path(anchor["node_path"], f"{anchor_label}.node_path")
        position = _vector(anchor["position_m"], f"{anchor_label}.position_m")
        gear_gated = anchor["gear_gated"]
        if type(gear_gated) is not bool:
            raise CustomizationError(f"{anchor_label}.gear_gated must be a boolean")
        if gear_gated and anchor_id not in {"landing", "landing_right"}:
            raise CustomizationError(f"{anchor_label}.gear_gated is only supported for landing anchors")
        validated_anchors.append({
            "id": anchor_id,
            "node_path": node_path,
            "position_m": position,
            "gear_gated": gear_gated,
        })

    validated_strips: list[dict[str, Any]] = []
    strip_ids: set[str] = set()
    for index, strip in enumerate(strips):
        strip_label = f"{label}.strips[{index}]"
        _closed(strip, {"id", "node_path", "points_m", "face", "width_m"}, strip_label)
        strip_id = strip["id"]
        if not isinstance(strip_id, str) or strip_id not in LIGHT_STRIP_IDS:
            raise CustomizationError(f"{strip_label}.id is unsupported")
        if strip_id in strip_ids:
            raise CustomizationError(f"{strip_label}.id is duplicated")
        strip_ids.add(strip_id)
        node_path = _lighting_node_path(strip["node_path"], f"{strip_label}.node_path")
        points_value = strip["points_m"]
        if not isinstance(points_value, list) or not 2 <= len(points_value) <= LIGHT_STRIP_POINT_LIMIT:
            raise CustomizationError(f"{strip_label}.points_m must contain 2 to {LIGHT_STRIP_POINT_LIMIT} points")
        points = [_vector(point, f"{strip_label}.points_m[{point_index}]") for point_index, point in enumerate(points_value)]
        face = _vector(strip["face"], f"{strip_label}.face", unit=True)
        width = strip["width_m"]
        if isinstance(width, bool) or not isinstance(width, (int, float)):
            raise CustomizationError(f"{strip_label}.width_m must be in [{LIGHT_STRIP_WIDTH_BOUNDS_M[0]}, {LIGHT_STRIP_WIDTH_BOUNDS_M[1]}] m")
        try:
            numeric_width = float(width)
        except OverflowError as exc:
            raise CustomizationError(f"{strip_label}.width_m must be in [{LIGHT_STRIP_WIDTH_BOUNDS_M[0]}, {LIGHT_STRIP_WIDTH_BOUNDS_M[1]}] m") from exc
        if not math.isfinite(numeric_width) or not LIGHT_STRIP_WIDTH_BOUNDS_M[0] <= numeric_width <= LIGHT_STRIP_WIDTH_BOUNDS_M[1]:
            raise CustomizationError(f"{strip_label}.width_m must be in [{LIGHT_STRIP_WIDTH_BOUNDS_M[0]}, {LIGHT_STRIP_WIDTH_BOUNDS_M[1]}] m")
        face_vector = [float(part) for part in face]
        for point_index, (start, end) in enumerate(zip(points, points[1:])):
            segment = [float(b) - float(a) for a, b in zip(start, end)]
            segment_length = math.sqrt(sum(part * part for part in segment))
            if segment_length < 1e-5:
                raise CustomizationError(f"{strip_label}.points_m[{point_index}:{point_index + 2}] are too close")
            cross = [
                segment[1] * face_vector[2] - segment[2] * face_vector[1],
                segment[2] * face_vector[0] - segment[0] * face_vector[2],
                segment[0] * face_vector[1] - segment[1] * face_vector[0],
            ]
            cross_ratio = math.sqrt(sum(part * part for part in cross)) / segment_length
            if cross_ratio < 0.01:
                raise CustomizationError(f"{strip_label}.points_m segment {point_index} is degenerate against face")
        validated_strips.append({
            "id": strip_id,
            "node_path": node_path,
            "points_m": points,
            "face": face,
            "width_m": width,
        })

    return {
        "version": 1,
        "anchors": sorted(validated_anchors, key=lambda value: value["id"]),
        "strips": sorted(validated_strips, key=lambda value: value["id"]),
    }


def validate_source(source: Any, expected_families: set[str]) -> dict[str, dict[str, Any]]:
    _closed(source, {"format", "version", "families"}, "source")
    if source["format"] != SOURCE_FORMAT or type(source["version"]) is not int or source["version"] not in (1, 2, 3):
        raise CustomizationError("source format/version is unsupported")
    if not isinstance(source["families"], list):
        raise CustomizationError("source.families must be an array")
    families: dict[str, dict[str, Any]] = {}
    for index, family in enumerate(source["families"]):
        label = f"source.families[{index}]"
        family_keys = {"visual_family", "paint_slots", "marking_slots", "smoke_slots"}
        if source["version"] == 3:
            family_keys.add("lighting_layout")
        _closed(family, family_keys, label)
        family_id = _text(family["visual_family"], FAMILY_RE, f"{label}.visual_family")
        if family_id in families:
            raise CustomizationError(f"duplicate visual family {family_id!r}")
        if any(not isinstance(family[key], list) for key in ("paint_slots", "marking_slots", "smoke_slots")):
            raise CustomizationError(f"{label} slot groups must be arrays")

        paint_slots: list[dict[str, Any]] = []
        paint_ids: set[str] = set()
        seen_targets: set[tuple[str, int]] = set()
        for slot_index, slot in enumerate(family["paint_slots"]):
            slot_label = f"{label}.paint_slots[{slot_index}]"
            _closed(slot, {"id", "label", "targets"}, slot_label)
            slot_id = _text(slot["id"], SLOT_ID_RE, f"{slot_label}.id")
            _text(slot["label"], LABEL_RE, f"{slot_label}.label")
            if slot_id in paint_ids:
                raise CustomizationError(f"{slot_label}.id is duplicated")
            paint_ids.add(slot_id)
            if not isinstance(slot["targets"], list) or not slot["targets"]:
                raise CustomizationError(f"{slot_label}.targets must be a non-empty array")
            targets = []
            for target_index, target in enumerate(slot["targets"]):
                target_label = f"{slot_label}.targets[{target_index}]"
                if not isinstance(target, dict):
                    raise CustomizationError(f"{target_label} must be an object")
                kind = target.get("kind")
                expected = {"node_path", "surface", "kind"} | ({"parameter"} if kind == "shader_color" else set())
                _closed(target, expected, target_label)
                node_path = _text(target["node_path"], NODE_PATH_RE, f"{target_label}.node_path")
                if type(target["surface"]) is not int or target["surface"] < 0 or target["surface"] > 64:
                    raise CustomizationError(f"{target_label}.surface must be an integer in [0, 64]")
                if kind not in PAINT_KINDS:
                    raise CustomizationError(f"{target_label}.kind is unsupported")
                if kind == "shader_color":
                    _text(target["parameter"], PARAM_RE, f"{target_label}.parameter")
                target_key = (node_path, target["surface"])
                if target_key in seen_targets:
                    raise CustomizationError(f"{target_label} duplicates a paint target")
                seen_targets.add(target_key)
                targets.append(dict(target))
            paint_slots.append({"id": slot_id, "label": slot["label"], "targets": targets})

        marking_slots: list[dict[str, Any]] = []
        marking_ids: set[str] = set()
        for slot_index, slot in enumerate(family["marking_slots"]):
            slot_label = f"{label}.marking_slots[{slot_index}]"
            _closed(slot, {"id", "label", "max_chars", "targets"}, slot_label)
            slot_id = _text(slot["id"], SLOT_ID_RE, f"{slot_label}.id")
            _text(slot["label"], LABEL_RE, f"{slot_label}.label")
            if slot_id in marking_ids:
                raise CustomizationError(f"{slot_label}.id is duplicated")
            marking_ids.add(slot_id)
            if type(slot["max_chars"]) is not int or not 1 <= slot["max_chars"] <= 12:
                raise CustomizationError(f"{slot_label}.max_chars must be an integer in [1, 12]")
            if not isinstance(slot["targets"], list) or not 1 <= len(slot["targets"]) <= 2:
                raise CustomizationError(f"{slot_label}.targets must contain one or two authored mounts")
            targets = []
            seen_mounts: set[tuple[Any, ...]] = set()
            for target_index, target in enumerate(slot["targets"]):
                target_label = f"{slot_label}.targets[{target_index}]"
                _closed(target, {"node_path", "position_m", "direction", "up", "width_m", "height_m"}, target_label)
                node_path = _text(target["node_path"], NODE_PATH_RE, f"{target_label}.node_path")
                position = _vector(target["position_m"], f"{target_label}.position_m")
                direction = _vector(target["direction"], f"{target_label}.direction", unit=True)
                up = _vector(target["up"], f"{target_label}.up", unit=True)
                if abs(sum(float(a) * float(b) for a, b in zip(direction, up))) > 0.001:
                    raise CustomizationError(f"{target_label}.up must be perpendicular to direction")
                for dimension, bounds in (("width_m", MARKING_WIDTH_BOUNDS_M), ("height_m", MARKING_HEIGHT_BOUNDS_M)):
                    value = target[dimension]
                    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)) or not bounds[0] <= float(value) <= bounds[1]:
                        raise CustomizationError(f"{target_label}.{dimension} must be in [{bounds[0]}, {bounds[1]}] m")
                mount_key = (node_path, *(round(float(part), 9) for part in position))
                if mount_key in seen_mounts:
                    raise CustomizationError(f"{target_label} duplicates a marking mount")
                seen_mounts.add(mount_key)
                targets.append({
                    "node_path": node_path,
                    "position_m": position,
                    "direction": direction,
                    "up": up,
                    "width_m": target["width_m"],
                    "height_m": target["height_m"],
                })
            marking_slots.append({"id": slot_id, "label": slot["label"], "max_chars": slot["max_chars"], "targets": targets})

        smoke_slots: list[dict[str, Any]] = []
        smoke_ids: set[str] = set()
        smoke_roles: set[str] = set()
        if len(family["smoke_slots"]) > 8:
            raise CustomizationError(f"{label} supports at most eight authored smoke outlets")
        for slot_index, slot in enumerate(family["smoke_slots"]):
            slot_label = f"{label}.smoke_slots[{slot_index}]"
            if not isinstance(slot, dict):
                raise CustomizationError(f"{slot_label} must be an object")
            kind = slot.get("kind")
            common = {"id", "label", "kind", "pair", "role"}
            if source["version"] in {2, 3}:
                common |= {"radius_m", "emissions_preset", "activation_policy", "provenance"}
                if kind == "source" or "anchor_id" in slot:
                    required = common | {"source_id", "source_kind", "anchor_id"}
                elif kind == "show":
                    required = common | {"node_path", "position_m", "direction"}
                    if slot.get("activation_policy") == "source_and_request":
                        required |= {"source_id", "source_kind"}
                else:
                    raise CustomizationError(f"{slot_label}.kind must be show or source")
                _closed(slot, required, slot_label)
                validate_smoke_v3(slot, slot_label)
                slot_id = slot["id"]
                if slot_id in smoke_ids:
                    raise CustomizationError(f"{slot_label}.id is duplicated")
                if slot["role"] in {"wing_tip_left", "wing_tip_right", "tail", "tailpipe"} and slot["role"] in smoke_roles:
                    raise CustomizationError(f"{slot_label}.role is duplicated")
                smoke_ids.add(slot_id)
                smoke_roles.add(slot["role"])
                smoke_slots.append(dict(slot))
                continue
            if kind == "show":
                required = common | {"node_path", "position_m", "direction"}
            elif kind == "source":
                required = common | {"source_kind", "source_anchor_ref", "physical_source_ref", "physical_source_kind_ref"}
            else:
                raise CustomizationError(f"{slot_label}.kind must be show or source")
            _closed(slot, required, slot_label)
            slot_id = _text(slot["id"], SLOT_ID_RE, f"{slot_label}.id")
            _text(slot["label"], LABEL_RE, f"{slot_label}.label")
            role = slot["role"]
            if role not in SMOKE_ROLES:
                raise CustomizationError(f"{slot_label}.role is unsupported")
            if slot_id in smoke_ids:
                raise CustomizationError(f"{slot_label}.id is duplicated")
            if role in smoke_roles:
                raise CustomizationError(f"{slot_label}.role is duplicated")
            smoke_ids.add(slot_id)
            smoke_roles.add(role)
            if not isinstance(slot["pair"], str) or len(slot["pair"]) > 80:
                raise CustomizationError(f"{slot_label}.pair must be a bounded string")
            if kind == "show":
                if role == "exhaust":
                    raise CustomizationError(f"{slot_label} cannot route an exhaust role through a show mount")
                node_path = slot["node_path"]
                if node_path != ".":
                    _text(node_path, NODE_PATH_RE, f"{slot_label}.node_path")
                _vector(slot["position_m"], f"{slot_label}.position_m")
                _vector(slot["direction"], f"{slot_label}.direction", unit=True)
                if role in {"wing_tip_left", "wing_tip_right"} and slot["pair"] != "wing_tips":
                    raise CustomizationError(f"{slot_label} must declare pair wing_tips")
                if role in {"tail", "tailpipe"} and slot["pair"]:
                    raise CustomizationError(f"{slot_label} tail/tailpipe endpoint must have an empty pair")
            else:
                if role != "exhaust" or slot["pair"]:
                    raise CustomizationError(f"{slot_label} source endpoint must be an unpaired exhaust")
                if slot["source_kind"] not in SOURCE_KINDS:
                    raise CustomizationError(f"{slot_label}.source_kind is unsupported")
                if slot["source_anchor_ref"] not in SOURCE_ANCHOR_REFS:
                    raise CustomizationError(f"{slot_label}.source_anchor_ref is unsupported")
                if slot["physical_source_ref"] not in PHYSICAL_ID_REFS or slot["physical_source_kind_ref"] not in PHYSICAL_KIND_REFS:
                    raise CustomizationError(f"{slot_label} physical source selectors are unsupported")
            smoke_slots.append(dict(slot))

        paired_roles = {role for role in smoke_roles if role in {"wing_tip_left", "wing_tip_right"}}
        if source["version"] == 1 and paired_roles != {"wing_tip_left", "wing_tip_right"}:
            raise CustomizationError(f"{label} requires an explicit left/right show endpoint pair")
        if source["version"] == 1 and "tail" not in smoke_roles:
            raise CustomizationError(f"{label} requires an explicit tail show endpoint")
        families[family_id] = {
            "paint_slots": sorted(paint_slots, key=lambda value: value["id"]),
            "marking_slots": sorted(marking_slots, key=lambda value: value["id"]),
            "smoke_slots": sorted(smoke_slots, key=lambda value: value["id"]),
            "lighting_layout": validate_lighting_layout(family["lighting_layout"], f"{label}.lighting_layout")
            if source["version"] == 3 else empty_lighting_layout(),
        }
    if set(families) != expected_families:
        missing = sorted(expected_families - set(families))
        extra = sorted(set(families) - expected_families)
        raise CustomizationError(f"customization family coverage mismatch (missing={missing}, unknown={extra})")
    return families


def validate_smoke_v3(slot: dict[str, Any], label: str) -> None:
    for key, pattern in (("id", SLOT_ID_RE), ("label", LABEL_RE)):
        _text(slot[key], pattern, f"{label}.{key}")
    kind, role, policy = slot["kind"], slot["role"], slot["activation_policy"]
    if role not in SMOKE_ROLES or not isinstance(slot["pair"], str):
        raise CustomizationError(f"{label} has an invalid role or pair")
    if slot["pair"] and SLOT_ID_RE.fullmatch(slot["pair"]) is None:
        raise CustomizationError(f"{label}.pair is malformed")
    if slot["emissions_preset"] not in EMISSIONS_PRESETS or slot["provenance"] not in {"estimated", "authored", "measured"}:
        raise CustomizationError(f"{label} has unsupported preset or provenance")
    radius = slot["radius_m"]
    if isinstance(radius, bool) or not isinstance(radius, (int, float)) or not math.isfinite(radius) or not 0.0001 <= radius <= 0.1:
        raise CustomizationError(f"{label}.radius_m must be in [0.0001, 0.1]")
    if kind == "source" and (role != "exhaust" or slot["pair"] or policy != "source_running"):
        raise CustomizationError(f"{label} source must be an unpaired exhaust with source_running policy")
    if kind == "show" and policy not in {"independent_request", "source_and_request"}:
        raise CustomizationError(f"{label} has unsupported show activation policy")
    if kind == "show" and role == "exhaust" and "anchor_id" not in slot:
        raise CustomizationError(f"{label} exhaust show outlet requires its physical source anchor")
    if "source_id" in slot:
        if not isinstance(slot["source_id"], str) or (slot["source_id"] != "$propulsion" and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", slot["source_id"]) is None):
            raise CustomizationError(f"{label}.source_id is malformed")
        if slot["source_kind"] not in {"glow_prop", "electric_prop", "turbine"}:
            raise CustomizationError(f"{label}.source_kind is unsupported")
    if "anchor_id" in slot:
        _text(slot["anchor_id"], SLOT_ID_RE, f"{label}.anchor_id")
        if kind == "show" and policy != "source_and_request":
            raise CustomizationError(f"{label} source anchor requires source_and_request")
    else:
        if slot["node_path"] != ".":
            _text(slot["node_path"], NODE_PATH_RE, f"{label}.node_path")
        _vector(slot["position_m"], f"{label}.position_m")
        _vector(slot["direction"], f"{label}.direction", unit=True)
    if role in {"wing_tip_left", "wing_tip_right"} and (kind != "show" or slot["pair"] != "wing_tips"):
        raise CustomizationError(f"{label} requires a paired show wingtip")
    if role in {"tail", "tailpipe", "exhaust"} and slot["pair"]:
        raise CustomizationError(f"{label} tail/exhaust endpoint must be unpaired")


def presentation_sources(root: Path) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for resource_path in PRESENTATION_SOURCE_PATHS:
        if not resource_path.startswith("res://"):
            raise CustomizationError(f"presentation source path must be a resource path: {resource_path}")
        source_path = root / "app" / resource_path.removeprefix("res://")
        try:
            text = source_path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise CustomizationError(f"presentation source is missing or unreadable: {resource_path}") from exc
        normalized_text = text.replace("\r\n", "\n").replace("\r", "\n")
        records.append({
            "path": resource_path,
            "sha256": hashlib.sha256(normalized_text.encode("utf-8")).hexdigest(),
        })
    return records


def build_companion(family_id: str, manifest_sha256: str, slots: dict[str, Any], sources: list[dict[str, str]]) -> dict[str, Any]:
    companion: dict[str, Any] = {
        "format": COMPANION_FORMAT,
        "version": 4,
        "source_proof_version": 3,
        "visual_family": family_id,
        "model_manifest_sha256": manifest_sha256,
        "paint_slots": slots["paint_slots"],
        "marking_slots": slots["marking_slots"],
        "smoke_slots": slots["smoke_slots"],
        "lighting_layout": slots["lighting_layout"],
        "presentation_engine_version": PRESENTATION_ENGINE_VERSION,
        "presentation_sources": sources,
    }
    companion["slots_sha256"] = hashlib.sha256(canonical_bytes(companion)).hexdigest()
    return companion


def generate(root: Path, check: bool) -> int:
    try:
        source = json.loads((root / SOURCE_PATH).read_text(encoding="utf-8"))
        model_source = json.loads((root / MODEL_SOURCE_PATH).read_text(encoding="utf-8"))
        model_families = model_source.get("families") if isinstance(model_source, dict) else None
        if not isinstance(model_families, list):
            raise CustomizationError("model source registry families must be an array")
        expected_ids = {str(item.get("family_id", "")) for item in model_families if isinstance(item, dict)}
        if len(expected_ids) != len(model_families) or not all(FAMILY_RE.fullmatch(item) for item in expected_ids):
            raise CustomizationError("model source registry contains missing or duplicate family IDs")
        slots_by_family = validate_source(source, expected_ids)
        source_records = presentation_sources(root)
        companions = []
        for family_id in sorted(expected_ids):
            manifest_path = root / MODEL_OUTPUT_DIR / f"{family_id}.json"
            manifest_bytes = manifest_path.read_bytes()
            manifest = json.loads(manifest_bytes.decode("utf-8"))
            if manifest.get("family_id") != family_id:
                raise CustomizationError(f"generated model manifest family mismatch for {family_id}")
            companions.append(build_companion(family_id, hashlib.sha256(manifest_bytes).hexdigest(), slots_by_family[family_id], source_records))
        output = {"format": REGISTRY_FORMAT, "version": 1, "families": companions}
        rendered = json.dumps(output, ensure_ascii=False, indent=2) + "\n"
    except (OSError, UnicodeError, json.JSONDecodeError, CustomizationError) as exc:
        print(f"aircraft customization generation failed: {exc}", file=sys.stderr)
        return 1

    path = root / OUTPUT_PATH
    expected_bytes = rendered.encode("utf-8")
    if check:
        if not path.is_file() or path.read_bytes() != expected_bytes:
            print(f"stale generated customization registry: {OUTPUT_PATH}", file=sys.stderr)
            print("run: python research/aircraft-standardization/build_customization.py", file=sys.stderr)
            return 1
        print(f"customization bindings current ({len(companions)} visual families)")
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.is_file() or path.read_bytes() != expected_bytes:
        path.write_bytes(expected_bytes)
    print(f"generated customization bindings ({len(companions)} visual families)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated registry is stale")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    return generate(args.root.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
