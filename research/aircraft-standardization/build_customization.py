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
SLOT_ID_RE = re.compile(r"^[a-z][a-z0-9_]{0,79}$")
FAMILY_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
LABEL_RE = re.compile(r"^[ -~]{1,32}$")
NODE_PATH_RE = re.compile(r"^[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*$")
PARAM_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,63}$")
PAINT_KINDS = {"standard_albedo", "shader_color"}
SMOKE_ROLES = {"wing_tip_left", "wing_tip_right", "tail", "exhaust"}
SOURCE_ANCHOR_REFS = {"exhausts[0]"}
PHYSICAL_ID_REFS = {"propulsion.id"}
PHYSICAL_KIND_REFS = {"propulsion.kind"}
SOURCE_KINDS = {"glow_prop"}


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
        if isinstance(part, bool) or not isinstance(part, (int, float)) or not math.isfinite(float(part)):
            raise CustomizationError(f"{label} must contain finite numbers")
        if abs(float(part)) > 5.0:
            raise CustomizationError(f"{label} exceeds the five-metre source-space bound")
        numbers.append(part)
    if unit and not 0.999 <= sum(float(part) ** 2 for part in numbers) ** 0.5 <= 1.001:
        raise CustomizationError(f"{label} must be a unit direction")
    return numbers


def validate_source(source: Any, expected_families: set[str]) -> dict[str, dict[str, Any]]:
    _closed(source, {"format", "version", "families"}, "source")
    if source["format"] != SOURCE_FORMAT or type(source["version"]) is not int or source["version"] != 1:
        raise CustomizationError("source format/version is unsupported")
    if not isinstance(source["families"], list):
        raise CustomizationError("source.families must be an array")
    families: dict[str, dict[str, Any]] = {}
    for index, family in enumerate(source["families"]):
        label = f"source.families[{index}]"
        _closed(family, {"visual_family", "paint_slots", "marking_slots", "smoke_slots"}, label)
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

        if family["marking_slots"]:
            raise CustomizationError(f"{label}.marking_slots must stay empty until bounded marking targets are implemented")

        smoke_slots: list[dict[str, Any]] = []
        smoke_ids: set[str] = set()
        smoke_roles: set[str] = set()
        for slot_index, slot in enumerate(family["smoke_slots"]):
            slot_label = f"{label}.smoke_slots[{slot_index}]"
            if not isinstance(slot, dict):
                raise CustomizationError(f"{slot_label} must be an object")
            kind = slot.get("kind")
            common = {"id", "label", "kind", "pair", "role"}
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
                if role == "tail" and slot["pair"]:
                    raise CustomizationError(f"{slot_label} tail endpoint must have an empty pair")
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
        if paired_roles != {"wing_tip_left", "wing_tip_right"}:
            raise CustomizationError(f"{label} requires an explicit left/right show endpoint pair")
        if "tail" not in smoke_roles:
            raise CustomizationError(f"{label} requires an explicit tail show endpoint")
        families[family_id] = {
            "paint_slots": sorted(paint_slots, key=lambda value: value["id"]),
            "marking_slots": [],
            "smoke_slots": sorted(smoke_slots, key=lambda value: value["id"]),
        }
    if set(families) != expected_families:
        missing = sorted(expected_families - set(families))
        extra = sorted(set(families) - expected_families)
        raise CustomizationError(f"customization family coverage mismatch (missing={missing}, unknown={extra})")
    return families


def build_companion(family_id: str, manifest_sha256: str, slots: dict[str, Any]) -> dict[str, Any]:
    companion: dict[str, Any] = {
        "format": COMPANION_FORMAT,
        "version": 1,
        "visual_family": family_id,
        "model_manifest_sha256": manifest_sha256,
        "paint_slots": slots["paint_slots"],
        "marking_slots": slots["marking_slots"],
        "smoke_slots": slots["smoke_slots"],
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
        companions = []
        for family_id in sorted(expected_ids):
            manifest_path = root / MODEL_OUTPUT_DIR / f"{family_id}.json"
            manifest_bytes = manifest_path.read_bytes()
            manifest = json.loads(manifest_bytes.decode("utf-8"))
            if manifest.get("family_id") != family_id:
                raise CustomizationError(f"generated model manifest family mismatch for {family_id}")
            companions.append(build_companion(family_id, hashlib.sha256(manifest_bytes).hexdigest(), slots_by_family[family_id]))
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
