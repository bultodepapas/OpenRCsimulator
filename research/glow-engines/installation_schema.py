"""Generate and check the versioned JSON Schema for glow installation v1."""
from __future__ import annotations

import argparse
import copy
import json
import math
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "app" / "data" / "schema" / "glow-installation-v1.schema.json"
GLOW_DATA_DIRECTORY = ROOT / "app" / "data" / "glow"
INSTALLATION_FILES = sorted([*GLOW_DATA_DIRECTORY.glob("stik_*.json"), *GLOW_DATA_DIRECTORY.glob("extra_*.json")])
KINDS = ["manual", "measured", "borrowed", "estimated", "derived"]


def quantity(unit: str, *, minimum: float | None = None, exclusive_minimum: float | None = None,
             maximum: float | None = None, exclusive_maximum: float | None = None) -> dict[str, Any]:
    value: dict[str, Any] = {"type": "number"}
    if minimum is not None:
        value["minimum"] = minimum
    if exclusive_minimum is not None:
        value["exclusiveMinimum"] = exclusive_minimum
    if maximum is not None:
        value["maximum"] = maximum
    if exclusive_maximum is not None:
        value["exclusiveMaximum"] = exclusive_maximum
    return {
        "type": "object",
        "required": ["value", "unit", "kind", "source"],
        "additionalProperties": False,
        "properties": {
            "value": value,
            "unit": {"const": unit},
            "kind": {"enum": KINDS},
            "source": {"type": "string", "minLength": 1, "pattern": "\\S"},
        },
    }


def vector_quantity(unit: str, length: int = 3) -> dict[str, Any]:
    schema = quantity(unit)
    schema["properties"]["value"] = {"type": "array", "minItems": length, "maxItems": length, "items": {"type": "number"}}
    return schema


def object_schema(properties: dict[str, Any]) -> dict[str, Any]:
    return {
        "type": "object",
        "required": list(properties),
        "additionalProperties": False,
        "properties": properties,
    }


def schema_document() -> dict[str, Any]:
    settings = {
        "idle_admission": quantity("1", exclusive_minimum=0.0, exclusive_maximum=1.0),
        "servo_time_constant_s": quantity("s", minimum=0.02, maximum=5.0),
        "air_time_constant_s": quantity("s", minimum=0.02, maximum=5.0),
        "fuel_transport_time_constant_s": quantity("s", minimum=0.02, maximum=5.0),
        "stall_rpm": quantity("rpm", exclusive_minimum=0.0),
        "minimum_start_rpm": quantity("rpm", exclusive_minimum=0.0),
        "starter_prime_kg": quantity("kg", minimum=0.0, maximum=0.001),
        "temperature_firing_min_k": quantity("K", minimum=200.0, maximum=1000.0),
        "temperature_firing_full_k": quantity("K", minimum=200.0, maximum=1000.0),
        "temperature_firing_hot_full_k": quantity("K", minimum=200.0, maximum=1000.0),
        "temperature_firing_hot_zero_k": quantity("K", minimum=200.0, maximum=1000.0),
        "lean_misfire_zero_ratio": quantity("1", minimum=0.0, maximum=1.0),
        "lean_misfire_start_ratio": quantity("1", exclusive_minimum=0.0, exclusive_maximum=1.0),
        "rich_misfire_start_ratio": quantity("1", exclusive_minimum=1.0, exclusive_maximum=4.0),
        "rich_misfire_zero_ratio": quantity("1", exclusive_minimum=1.0, maximum=4.0),
        "thermal": object_schema({
            "heat_capacity_j_k": quantity("J/K", exclusive_minimum=0.0, maximum=10000.0),
            "head_heat_fraction": quantity("1", minimum=0.0, maximum=1.0),
            "cooling_base_w_k": quantity("W/K", minimum=0.0, maximum=1000.0),
            "cooling_airflow_w_s_m_k": quantity("W/(K m/s)", minimum=0.0, maximum=1000.0),
            "premix_evaporation_j_kg": quantity("J/kg", minimum=0.0, maximum=10000000.0),
            "evaporation_head_fraction": quantity("1", minimum=0.0, maximum=1.0),
        }),
    }
    propeller = {
        "max_rpm": quantity("rpm", exclusive_minimum=0.0),
        "diameter_m": quantity("m", minimum=0.05, maximum=2.0),
        "pitch_m": quantity("m", exclusive_minimum=0.0, maximum=2.0),
        "chord_m": quantity("m", exclusive_minimum=0.0),
        "blades": quantity("1", minimum=2.0, maximum=2.0),
        "lift_slope": quantity("1/rad", exclusive_minimum=0.0, maximum=20.0),
        "cd0": quantity("1", exclusive_minimum=0.0, maximum=2.0),
        "induced_drag": quantity("1", exclusive_minimum=0.0, maximum=10.0),
    }
    # NITRO-05: optional fuel feed (spray-bar position in the inventory frame, driving pressures).
    fuel_feed = {
        "carburetor_position": vector_quantity("m"),
        "idle_drive_pressure_pa": quantity("Pa", exclusive_minimum=0.0, maximum=100000.0),
        "wot_drive_pressure_pa": quantity("Pa", exclusive_minimum=0.0, maximum=100000.0),
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "urn:openrc:glow-installation:v1",
        "title": "OpenRC glow installation v1",
        "description": (
            "Closed structural schema for the optional finite-tank glow installation. "
            "Cross-field temperature/mixture ordering, profile-family matching, tank membership, "
            "aircraft propeller agreement and dry-carrier inertia remain runtime semantic checks."
        ),
        "type": "object",
        "required": ["format", "family", "profile", "fuel_inventory", "settings", "initial_temperature_k", "propeller"],
        "additionalProperties": False,
        "properties": {
            "format": {"const": "openrc-glow-installation v1"},
            "family": {"enum": ["glow_2t", "glow_4t"]},
            "profile": {
                "type": "string",
                "pattern": "^res://data/glow/[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]+)*\\.json$",
            },
            "fuel_inventory": {"type": "string", "minLength": 1, "pattern": "\\S"},
            "settings": object_schema(settings),
            "initial_temperature_k": quantity("K", minimum=200.0, maximum=600.0),
            "propeller": object_schema(propeller),
            "fuel_feed": object_schema(fuel_feed),
        },
    }


def validate_instance(value: Any, schema: dict[str, Any], location: str = "$", errors: list[str] | None = None) -> list[str]:
    """Validate the keyword subset emitted above, using only the Python standard library."""
    if errors is None:
        errors = []
    expected = schema.get("type")
    type_ok = {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value)),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
    }
    if expected in type_ok and not type_ok[expected]:
        errors.append(f"{location}: expected {expected}")
        return errors
    if "const" in schema and value != schema["const"]:
        errors.append(f"{location}: expected constant {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{location}: value is outside the declared enum")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{location}: missing required property {key!r}")
        props = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for key in value.keys() - props.keys():
                errors.append(f"{location}: additional property {key!r} is not allowed")
        for key, child in props.items():
            if key in value:
                validate_instance(value[key], child, f"{location}.{key}", errors)
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{location}: array is too short")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{location}: array is too long")
        if "items" in schema:
            for index, item in enumerate(value):
                validate_instance(item, schema["items"], f"{location}[{index}]", errors)
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{location}: string is too short")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            errors.append(f"{location}: string does not match the declared pattern")
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value)):
        for key, predicate in (
            ("minimum", lambda x, bound: x < bound),
            ("exclusiveMinimum", lambda x, bound: x <= bound),
            ("maximum", lambda x, bound: x > bound),
            ("exclusiveMaximum", lambda x, bound: x >= bound),
        ):
            if key in schema and predicate(float(value), float(schema[key])):
                errors.append(f"{location}: number violates {key} {schema[key]}")
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="write the canonical JSON Schema")
    mode.add_argument("--check", action="store_true", help="check schema freshness and bundled installs")
    args = parser.parse_args()
    rendered = json.dumps(schema_document(), indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if args.write:
        SCHEMA_PATH.parent.mkdir(parents=True, exist_ok=True)
        SCHEMA_PATH.write_text(rendered, encoding="utf-8")
        print("Wrote glow installation v1 JSON Schema")
        return
    if not SCHEMA_PATH.exists() or SCHEMA_PATH.read_text(encoding="utf-8") != rendered:
        raise SystemExit(f"Stale schema: {SCHEMA_PATH.relative_to(ROOT)}")
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    files = sorted(INSTALLATION_FILES)
    if len(files) != 5:
        raise SystemExit(f"Expected five generated installation inputs (55AX, FS-64V, each with an APC 13x6, and the 61FX), found {len(files)}")
    for path in files:
        instance = json.loads(path.read_text(encoding="utf-8"))
        errors = validate_instance(instance, schema)
        if errors:
            raise SystemExit(f"Schema rejected {path.name}: {errors}")
    print(f"Glow installation schema current; {len(files)} bundled installations read and valid")


if __name__ == "__main__":
    main()
