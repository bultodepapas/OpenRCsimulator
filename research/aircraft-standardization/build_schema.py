#!/usr/bin/env python3
"""Generate the strict v2 offline schema from the reviewed v1 numeric schema."""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path



def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def merge_required(node: dict, names):
    required = list(node.get("required", []))
    for name in names:
        if name not in required:
            required.append(name)
    node["required"] = required


def at_pointer(root: dict, pointer: str):
    node = root
    for segment in pointer.strip("/").split("/") if pointer != "/" else []:
        node = node[segment]
    return node


def prune_null_anyof(node):
    if isinstance(node, dict):
        for key in list(node):
            value = node[key]
            if key == "anyOf" and isinstance(value, list):
                retained = [branch for branch in value if not (isinstance(branch, dict) and branch.get("type") == "null")]
                if len(retained) != len(value):
                    siblings = {k: v for k, v in node.items() if k != "anyOf"}
                    node.clear()
                    if len(retained) == 1:
                        node.update(retained[0])
                        node.update(siblings)
                    else:
                        node.update(siblings)
                        node["anyOf"] = retained
                    prune_null_anyof(node)
                    return
            prune_null_anyof(node[key])
    elif isinstance(node, list):
        for item in node:
            prune_null_anyof(item)


def close_objects(node, path=""):
    if isinstance(node, dict):
        for key, value in list(node.items()):
            child_path = f"{path}/{key}"
            close_objects(value, child_path)
        if node.get("type") == "object":
            if path in ("/properties/propulsion", "/$defs/slipstream"):
                node.pop("additionalProperties", None)
                node["unevaluatedProperties"] = False
            elif path == "/$defs/slipstreamPieceCore":
                # The legacy and smooth piece wrappers add mutually exclusive
                # fields through allOf and close the final composed instance.
                pass
            else:
                node["additionalProperties"] = False
    elif isinstance(node, list):
        for i, value in enumerate(node):
            close_objects(value, f"{path}/{i}")


def add_text_field(properties: dict, name: str, nonempty=False):
    schema = {"type": "string"}
    if nonempty:
        schema.update({"minLength": 1, "pattern": r"[^\u0001-\u0020]"})
    properties[name] = schema


def branch_condition(path: list[str], value):
    node = {}
    current = node
    for segment in path[:-1]:
        current[segment] = {"properties": {}}
        current = current[segment]["properties"]
    current[path[-1]] = {"const": value}
    return {"properties": node}


def capability_schema(spec: dict):
    props = {}
    for name, values in spec["capabilities"].items():
        props[name] = {"type": "string", "enum": values}
    return {
        "type": "object",
        # X8-04: optional capability fields keep the historical law when absent.
        "required": [name for name in spec["capabilities"] if name not in spec.get("optional_capabilities", [])],
        "properties": props,
        "additionalProperties": False,
    }


def add_physical_identity(schema: dict):
    """Optional complete v1 identities; numerical v2 shapes remain unchanged."""
    identifier = {"type": "string", "minLength": 1, "maxLength": 80,
                  "pattern": r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$",
                  "not": {"pattern": r"\s"}}
    props = schema["properties"]
    props["physical_identity_version"] = {"type": "integer", "const": 1}
    props["crash_hull_ids"] = {"type": "array", "minItems": 4, "uniqueItems": True,
                               "items": copy.deepcopy(identifier)}
    props["inventory"]["items"]["properties"]["id"] = copy.deepcopy(identifier)
    props["landing_gear"]["properties"]["contacts"]["items"]["properties"]["id"] = copy.deepcopy(identifier)
    for branch in ("glowPropulsion", "turbinePropulsion", "electricPropulsion"):
        schema["$defs"][branch]["properties"]["id"] = copy.deepcopy(identifier)
    props["propulsion"]["properties"]["id"] = copy.deepcopy(identifier)
    # X8-03: the conventional four or the two elevons; the capability rules in add_v2_overlay select which.
    roles = ["aileron_left", "aileron_right", "elevator", "rudder", "elevon_left", "elevon_right"]
    props["controls"]["properties"]["surface_ids"] = {
        "type": "object", "minProperties": 2, "additionalProperties": False,
        "properties": {key: copy.deepcopy(identifier) for key in roles}}
    required = {
        "inventory": {"items": {"required": ["id"]}},
        "landing_gear": {"properties": {"contacts": {"items": {"required": ["id"]}}}},
        "propulsion": {"required": ["id"]}, "controls": {"required": ["surface_ids"]}}
    absent = {
        "landing_gear": {"properties": {"contacts": {"items": {"not": {"required": ["id"]}}}}},
        "propulsion": {"not": {"required": ["id"]}},
        "controls": {"not": {"required": ["surface_ids"]}}}
    schema.setdefault("allOf", []).append({
        "if": {"required": ["physical_identity_version"]},
        "then": {"required": ["crash_hull_ids"], "properties": required},
        "else": {"not": {"required": ["crash_hull_ids"]}, "properties": absent}})
    # Historical v2 files may need inventory IDs for fuel tanks or a battery
    # mount without carrying the complete physical-identity module. JSON Schema
    # cannot verify those cross-property references; AircraftData validates the
    # referenced subset for syntax, uniqueness and resolution.
    reference_capable = {"anyOf": [
        {"required": ["physical_identity_version"]},
        {"required": ["fuel_system"]},
        {"required": ["propulsion"], "properties": {"propulsion": {
            "required": ["battery"], "properties": {"battery": {
                "required": ["mount_inventory_id"]}}}}},
    ]}
    schema["allOf"].append({
        "if": {"not": reference_capable},
        "then": {"properties": {"inventory": {"items": {"not": {"required": ["id"]}}}}},
    })
    schema["$comment"] += (
        " PhysicalIdentity additionally enforces hull-point count alignment and global ID uniqueness "
        "across inventory, supports, hull probes, propulsion and surfaces; the offline companion is "
        "research/aircraft-standardization/physical_identity.py.")


def add_v2_overlay(schema: dict, spec: dict):
    schema["title"] = "OpenRC aircraft data v2"
    schema["description"] = "Strict structural and per-field validation for openrc-aircraft v2. Coupled physical validation remains in AircraftData and AircraftContract."
    # Quantity constraints are layered onto this reusable definition at each field.
    # Declare a generic value here so strict closure still composes those sibling constraints.
    schema["$defs"]["evidence"]["properties"]["value"] = {}
    schema["$defs"]["evidence"]["properties"]["unit"]["minLength"] = 1
    schema["$defs"]["electricEvidence"]["properties"]["unit"]["minLength"] = 1
    schema["$comment"] = (
        "Generated by research/aircraft-standardization/build_schema.py from the reviewed v1 numeric constraints and "
        "app/data/schema/aircraft-contract-v2.json. Runtime additionally checks branch/capability relations, positive "
        "inertia references, unique contact names and steering topology. Reference-only quantities have no force effect."
    )
    schema["properties"]["format"] = {"const": spec["format"]}
    root_props = schema["properties"]
    add_text_field(root_props, "id", nonempty=True)
    add_text_field(root_props, "description", nonempty=True)
    frame_fields = {}
    add_text_field(frame_fields, "le_frame", nonempty=True)
    add_text_field(frame_fields, "body", nonempty=True)
    root_props["frames"] = {
        "type": "object",
        "required": ["le_frame", "body"],
        "properties": frame_fields,
        "additionalProperties": False,
    }
    root_props["convention_id"] = {"const": spec["convention_id"]}
    root_props["capabilities"] = capability_schema(spec)
    def flap_quantity(unit, low, high):
        return {"$ref": "#/$defs/evidence", "properties": {
            "value": {"type": "number", "minimum": low, "maximum": high},
            "unit": {"const": unit}}}
    flap_fields = {
        "max_angle_deg": flap_quantity("deg", 5, 60),
        "takeoff_angle_deg": flap_quantity("deg", 0, 60),
        "inner_span_m": flap_quantity("m", 0, 2),
        "outer_span_m": flap_quantity("m", 0, 2),
        "hinge_fraction": flap_quantity("1", 0.5, 0.95),
        "extension_time": flap_quantity("s", 0.25, 30),
        "retraction_time": flap_quantity("s", 0.25, 30),
        "max_speed_mps": flap_quantity("m/s", 5, 100),
        "elevator_mix_per_flap_fraction": flap_quantity("1", 0, 0.5),
        "effective_angle_limit_deg": flap_quantity("deg", 5, 30),
        "profile_drag_coefficient": flap_quantity("1", 0, 1),
        # A generated zero value is used only as a paired software sensitivity control.
        "aerodynamic_gain": flap_quantity("1", 0, 1),
    }
    # P51-11a optional refinements: stall-onset fraction of the camber shift (strip blend only) and the
    # flap-lift reference offset aft of the strip force point. Absent keeps the shared law unchanged.
    flap_optional = {
        "stall_shift_fraction": flap_quantity("1", 0, 1),
        "lift_reference_offset_m": flap_quantity("m", -0.5, 0.5),
    }
    root_props["flaps"] = {
        "type": "object", "required": list(flap_fields),
        "properties": {**flap_fields, **flap_optional}, "additionalProperties": False,
    }
    merge_required(schema, ["id", "frames", "convention_id", "capabilities", "start"])
    schema["additionalProperties"] = False

    reference = root_props["reference"]
    # Tapered chord constraints are declared inside `then`; mirror those
    # properties at the base object so strict closure recognizes them.
    taper_props = reference["allOf"][0]["then"]["properties"]
    for name in ("root_chord", "tip_chord"):
        reference["properties"].setdefault(name, copy.deepcopy(taper_props[name]))
    merge_required(reference, ["planform"])
    # The runtime ignores tapered chords for a rectangular planform. Reject
    # those dead inputs while preserving the v1 tapered-geometry requirement.
    reference["allOf"].append({
        "if": {
            "required": ["planform"],
            "properties": {"planform": {"const": "rectangular"}},
        },
        "then": {
            "not": {
                "anyOf": [
                    {"required": ["root_chord"]},
                    {"required": ["tip_chord"]},
                ]
            }
        },
    })

    controls = root_props["controls"]
    controls["properties"]["keyboard"] = {
        "type": "object", "additionalProperties": False,
        "required": ["pitch_press_time", "pitch_release_time"],
        "properties": {key: {"$ref": "#/$defs/evidence", "properties": {
            "unit": {"const": "s"}, "value": {"type": "number", "minimum": 0.05, "maximum": 5.0}}}
            for key in ["pitch_press_time", "pitch_release_time"]}}
    controls.setdefault("allOf", []).append({"if": {"required": ["keyboard"]}, "then": {"required": ["rates"]}})
    controls["properties"]["gamepad"] = {
        "type": "object", "additionalProperties": False, "required": ["pitch_scale"],
        "properties": {"pitch_scale": {"$ref": "#/$defs/evidence", "properties": {
            "unit": {"const": "1"}, "value": {"type": "number", "minimum": 0.05, "maximum": 1.0}}}}}
    controls["allOf"].append({"if": {"required": ["gamepad"]}, "then": {"required": ["rates"]}})
    for key, unit, low, high in [("yaw_scale", "1", 0.05, 1.0), ("yaw_response_time", "s", 0.02, 0.5)]:
        controls["properties"]["gamepad"]["properties"][key] = {
            "$ref": "#/$defs/evidence", "properties": {
                "unit": {"const": unit}, "value": {"type": "number", "minimum": low, "maximum": high}}}

    aero = root_props["aero"]
    aero_props = aero["properties"]
    add_text_field(aero_props, "source", nonempty=True)
    aero_props["conventions"] = {
        "type": "object",
        "required": ["alpha_beta", "rates", "elevator", "aileron", "rudder", "drag", "axes"],
        "properties": {name: {"type": "string", "minLength": 1, "pattern": r"[^\u0001-\u0020]"} for name in ["alpha_beta", "rates", "elevator", "aileron", "rudder", "drag", "axes"]},
        "additionalProperties": False,
    }
    coefficients = aero_props["coefficients"]
    cl_adot_schema = coefficients["properties"].pop("CLadot")
    coefficients["required"].remove("CLadot")
    aero_props["reference_coefficients"] = {
        "type": "object",
        "required": ["CLadot"],
        "properties": {"CLadot": cl_adot_schema},
        "additionalProperties": False,
    }
    merge_required(aero, ["conventions", "reference_coefficients"])

    # CR-01d: optional semantic name per crash_hull point; the vocabulary lives in the contract's enum paths.
    # The runtime loader also checks that the list matches the number of hull points.
    hull_names = next(rule["values"] for rule in spec["enum_paths"] if rule["path"] == "/crash_hull_components/*")
    root_props["crash_hull_components"] = {
        "type": "array",
        "minItems": 4,
        "items": {"type": "string", "enum": hull_names},
    }

    balance_props = root_props["balance"]["properties"]
    add_text_field(balance_props, "configuration", nonempty=True)
    # FUEL-03: optional balance fuel state and CG range, and liquid-fuel tanks bound to inventory ids.
    # Vocabularies live in the contract; the loader checks registry blends, ids, masses and the dry CG.
    def enum_of(path):
        return next(rule["values"] for rule in spec["enum_paths"] if rule["path"] == path)

    def fuel_quantity(unit, low, high, exclusive_low=False):
        value = {"type": "number", "maximum": high}
        value["exclusiveMinimum" if exclusive_low else "minimum"] = low
        return {"$ref": "#/$defs/evidence", "properties": {"value": value, "unit": {"const": unit}}}
    balance_props["fuel_state"] = {"type": "string", "enum": enum_of("/balance/fuel_state")}
    balance_props["cg_range"] = {
        "type": "object", "required": ["forward", "aft"],
        "properties": {"forward": fuel_quantity("m", -2, 2), "aft": fuel_quantity("m", -2, 2)},
        "additionalProperties": False,
    }
    tank_fields = {name: {"type": "string", "minLength": 1}
                   for name in ["id", "fuel", "liquid_inventory_id", "shell_inventory_id"]}
    tank_fields["capacity"] = fuel_quantity("l", 0, 50, exclusive_low=True)
    tank_fields["unusable"] = fuel_quantity("l", 0, 50)
    # FUEL-03: reserve is optional; the loader supplies a disclosed estimate when absent.
    tank_fields["reserve"] = fuel_quantity("l", 0, 50)
    tank_fields["pickup"] = {"type": "string", "enum": enum_of("/fuel_system/tanks/*/pickup")}
    tank_fields["feed"] = {"type": "string", "enum": enum_of("/fuel_system/tanks/*/feed")}
    tank_fields["pickup_position"] = {
        "$ref": "#/$defs/evidence",
        "properties": {
            "value": {"type": "array", "minItems": 3, "maxItems": 3,
                      "items": {"type": "number", "minimum": -3, "maximum": 3}},
            "unit": {"const": "m"},
        },
    }
    tank_fields["feed_line"] = {
        "type": "object",
        "required": ["id", "liquid_inventory_id", "capacity"],
        "properties": {
            "id": {"type": "string", "minLength": 1},
            "liquid_inventory_id": {"type": "string", "minLength": 1},
            "capacity": fuel_quantity("l", 0, 50, exclusive_low=True),
        },
        "additionalProperties": False,
    }
    root_props["fuel_system"] = {
        "type": "object", "required": ["tanks"],
        "properties": {"tanks": {"type": "array", "minItems": 1, "items": {
            "type": "object", "required": [name for name in tank_fields if name not in ("reserve", "pickup_position", "feed_line")], "properties": tank_fields,
            "additionalProperties": False}}},
        "additionalProperties": False,
    }
    inventory_items = root_props["inventory"]["items"]
    add_text_field(inventory_items["properties"], "name", nonempty=True)
    # CR-22b: optional energy carried by this item (fuel or pack); the vocabulary lives in the contract.
    energy_names = next(rule["values"] for rule in spec["enum_paths"] if rule["path"] == "/inventory/*/energy_source")
    inventory_items["properties"]["energy_source"] = {"type": "string", "enum": energy_names}
    merge_required(inventory_items, ["size"])

    propulsion = root_props["propulsion"]
    propulsion["required"] = ["kind"]
    propulsion["properties"]["kind"] = {"type": "string", "enum": ["glow_prop", "turbine", "electric_prop"]}
    glow = schema["$defs"]["glowPropulsion"]
    glow["properties"]["kind"] = {"const": "glow_prop"}
    merge_required(glow, ["kind"])
    add_text_field(glow["properties"], "description", nonempty=True)
    # FUEL-08: finite liquid consumption is optional on the existing combustion branches.
    # Gasoline's estimate is explicit; a turbine reuses its authored fuel_flow map.
    tank_id = {"type": "string", "minLength": 1}
    schema["$defs"]["liquidFuelConsumption"] = {
        "oneOf": [
            {
                "type": "object",
                "required": ["law", "tank_id", "bsfc", "idle_flow"],
                "properties": {
                    "law": {"const": "gasoline_bsfc_v1"},
                    "tank_id": copy.deepcopy(tank_id),
                    "bsfc": fuel_quantity("kg/kWh", 0.05, 2.0, exclusive_low=True),
                    "idle_flow": fuel_quantity("kg/s", 0.0, 0.01),
                },
                "additionalProperties": False,
            },
            {
                "type": "object",
                "required": ["law", "tank_id"],
                "properties": {
                    "law": {"const": "turbine_map_v1"},
                    "tank_id": copy.deepcopy(tank_id),
                },
                "additionalProperties": False,
            },
        ]
    }
    glow["properties"]["fuel_consumption"] = {"$ref": "#/$defs/liquidFuelConsumption"}
    glow_engine = glow["properties"]["engine"]
    add_text_field(glow_engine["properties"], "name", nonempty=True)
    add_text_field(glow_engine["properties"], "glow_installation", nonempty=True)
    # The base v1 schema required a shaft even for the separate finite glow
    # installation branch. Keep legacy and installation engines shaft-optional;
    # the gasoline BSFC rule below requires it when that law is selected.
    glow_engine["required"] = [field for field in glow_engine.get("required", []) if field != "shaft"]
    glow_engine["allOf"] = [{"not": {"required": ["glow_installation", "shaft"]}}]
    glow_prop = glow["properties"]["propeller"]
    add_text_field(glow_prop["properties"], "name", nonempty=True)
    glow_prop["properties"]["rotation"] = {"const": "clockwise_from_rear"}
    merge_required(glow_prop, ["rotation"])

    turbine = schema["$defs"]["turbinePropulsion"]
    turbine["properties"]["kind"] = {"const": "turbine"}
    merge_required(turbine, ["kind"])
    add_text_field(turbine["properties"], "description", nonempty=True)
    turbine["properties"]["fuel_consumption"] = {"$ref": "#/$defs/liquidFuelConsumption"}
    add_text_field(turbine["properties"]["engine"]["properties"], "name", nonempty=True)
    turbine["properties"]["engine"]["properties"]["spool_integrator"] = {
        "type": "string", "enum": next(rule["values"] for rule in spec["enum_paths"]
                                         if rule["path"] == "/propulsion/engine/spool_integrator")
    }

    electric = schema["$defs"]["electricPropulsion"]
    add_text_field(schema["$defs"]["electricPropeller"]["properties"], "name", nonempty=True)

    # Keep OCV `contains` strict while allowing the full evidence envelope.
    # The legacy selector described only `soc.value` and v2 object closure would
    # otherwise reject its unit/kind/source siblings.
    ocv_contains = schema["$defs"]["electricOcvResistanceBattery"]["properties"]["ocv_points"]["contains"]
    ocv_contains.clear()
    ocv_contains.update({
        "$ref": "#/$defs/electricOcvPoint",
        "properties": {
            "soc": {
                "$ref": "#/$defs/electricEvidence",
                "properties": {"value": {"const": 1.0}},
            }
        },
    })

    # BAT-09: generated packs are referenced by id and SHA-256; the installation and the ESC
    # low-voltage cutoff are aircraft data (docs/research/battery/BAT-04/specification.md §3).
    def evidence(unit, value):
        return {"allOf": [{"$ref": "#/$defs/electricEvidence"}, {"properties": {"value": value, "unit": {"const": unit}}}]}
    def bounded(lo, hi, exclusive_lo=False):
        out = {"type": "number", "maximum": hi}
        out["exclusiveMinimum" if exclusive_lo else "minimum"] = lo
        return out
    schema["$defs"]["electricPackEcmBattery"] = {
        "type": "object",
        "required": ["kind", "pack", "mount_inventory_id", "initial_soc", "auxiliary_current_a",
                     "cooling_airflow_fraction", "weak_cell"],
        "properties": {
            "kind": {"const": "pack_ecm"},
            "pack": {"type": "object", "required": ["id", "sha256"], "properties": {
                "id": {"type": "string", "pattern": "^[a-z0-9][a-z0-9-]{0,95}$"},
                "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}}},
            "mount_inventory_id": {"type": "string", "minLength": 1},
            "initial_soc": evidence("1", bounded(0.0, 1.0, True)),
            "auxiliary_current_a": evidence("A", bounded(0.0, 100.0)),
            "cooling_airflow_fraction": evidence("1", bounded(0.0, 1.0)),
            "weak_cell": {"type": "object", "required": ["capacity_factor", "resistance_factor", "soc_offset"], "properties": {
                "capacity_factor": evidence("1", bounded(0.01, 1.0)),
                "resistance_factor": evidence("1", bounded(1.0, 10.0)),
                "soc_offset": evidence("1", {"type": "number", "minimum": 0.0, "exclusiveMaximum": 0.5})}},
        },
    }
    schema["$defs"]["electricLowVoltageCutoff"] = {
        "type": "object",
        "required": ["mode", "cell_detection", "cutoff_per_cell_v", "soft_limit", "soft_ramp_s", "debounce_s",
                     "recovery", "reset_throttle_max", "voltage_filter_s"],
        "properties": {
            "mode": {"enum": ["soft", "hard", "off"]},
            "cell_detection": {"enum": ["auto", "fixed"]},
            "fixed_cells": evidence("1", {"type": "integer", "minimum": 1, "maximum": 24}),
            "detection_max_cell_v": evidence("V", bounded(0.5, 6.0)),
            "cutoff_per_cell_v": evidence("V", bounded(0.5, 5.0)),
            "soft_limit": evidence("1", {"type": "number", "minimum": 0.0, "exclusiveMaximum": 1.0}),
            "soft_ramp_s": evidence("s", bounded(0.0, 60.0, True)),
            "debounce_s": evidence("s", bounded(0.0, 60.0)),
            "recovery": {"enum": ["throttle_reset", "latched"]},
            "reset_throttle_max": evidence("1", bounded(0.0, 0.2)),
            "voltage_filter_s": evidence("s", bounded(0.02, 10.0)),
        },
        "allOf": [{"if": {"properties": {"cell_detection": {"const": "fixed"}}},
                   "then": {"required": ["fixed_cells"], "not": {"required": ["detection_max_cell_v"]}},
                   "else": {"required": ["detection_max_cell_v"], "not": {"required": ["fixed_cells"]}}}],
    }
    schema["$defs"]["electricEsc"]["properties"]["low_voltage_cutoff"] = {"$ref": "#/$defs/electricLowVoltageCutoff"}
    electric["properties"]["battery"]["oneOf"].append({"$ref": "#/$defs/electricPackEcmBattery"})
    electric["allOf"] = list(electric.get("allOf", [])) + [{
        "if": {"properties": {"battery": {"properties": {"kind": {"const": "pack_ecm"}}}}},
        "then": {"properties": {"esc": {"required": ["low_voltage_cutoff"]}}},
        "else": {"properties": {"esc": {"not": {"required": ["low_voltage_cutoff"]}}}},
    }]

    gear_schema = root_props["landing_gear"]
    # The v1 nullable branch is removed by prune_null_anyof; this explicit
    # description is part of the retained named metadata surface.
    gear_object = next((x for x in gear_schema.get("anyOf", []) if x.get("type") == "object"), gear_schema)
    add_text_field(gear_object.get("properties", {}), "description", nonempty=True)
    contact_items = gear_object["properties"]["contacts"]["items"]
    merge_required(contact_items, ["max_steering"])
    # AV-09 is opt-in; historical fixed gear cannot silently carry an actuator.
    def gear_quantity(unit, value):
        return {"$ref": "#/$defs/evidence", "properties": {"value": value, "unit": {"const": unit}}}
    gear_fields = {
        "extension_time": gear_quantity("s", {"type": "number", "minimum": 0.25, "maximum": 30}),
        "retraction_time": gear_quantity("s", {"type": "number", "minimum": 0.25, "maximum": 30}),
        "drag_area": gear_quantity("m²", {"type": "number", "minimum": 0, "maximum": 1}),
        "drag_center": copy.deepcopy(contact_items["properties"]["position"]),
    }
    gear_object["properties"]["retraction"] = {"type": "object", "required": list(gear_fields), "properties": gear_fields}
    contact_items["properties"]["retraction_path"] = gear_quantity("m", {
        "type": "array", "minItems": 6, "maxItems": 1539,
        "items": {"type": "number", "minimum": -3, "maximum": 3}})

    # X8-03/04/08: elevon throws and rates, the tailless wing stations and the tolerant hull. The conventional
    # rudder, horizontal tail and aileron-effectiveness requirements move to the capability rules below.
    def x8_quantity(unit, value):
        return {"$ref": "#/$defs/evidence", "properties": {"value": value, "unit": {"const": unit}}}
    max_throw = controls["properties"]["max_throw"]
    max_throw["properties"]["elevon"] = x8_quantity("deg", {"type": "number", "minimum": 1.0, "maximum": 60.0})
    max_throw["required"] = ["aileron", "elevator"]
    rates_normal = controls["properties"]["rates"]["properties"]["normal"]
    rates_normal["required"] = ["aileron", "elevator", "aileron_expo", "elevator_expo"]
    surfaces = aero_props["surfaces"]
    surfaces["required"] = [name for name in surfaces["required"] if name not in ("wing_aileron_effectiveness", "horizontal")]
    station_triplet = {"type": "array", "minItems": 3, "maxItems": 3}
    surfaces["properties"]["tailless"] = {
        "type": "object", "required": ["station_x", "elevon_coverage", "elevon_chord_fraction"],
        "properties": {
            "station_x": x8_quantity("m", {**station_triplet, "items": {"type": "number", "minimum": -2.0, "maximum": 2.0}}),
            "elevon_coverage": x8_quantity("1", {**station_triplet, "items": {"type": "number", "minimum": 0.0, "maximum": 1.0}}),
            "elevon_chord_fraction": x8_quantity("1", {"type": "number", "minimum": 0.05, "maximum": 0.6}),
        },
        "additionalProperties": False,
    }
    # The vertical element's rudder effectiveness may be exactly zero only for an elevon (rudderless) aircraft.
    surfaces["properties"]["vertical"]["properties"]["control_effectiveness"]["properties"]["value"]["minimum"] = 0.0
    root_props["crash_tolerance"] = {
        "type": "object", "required": ["terminal_specific_energy", "crash_depth", "presentation_durability"],
        "properties": {
            "terminal_specific_energy": x8_quantity("J/kg", {"type": "number", "minimum": 2.5, "maximum": 50.0}),
            "crash_depth": x8_quantity("m", {"type": "number", "minimum": 0.08, "maximum": 0.3}),
            "presentation_durability": x8_quantity("1", {"type": "number", "minimum": 1.0, "maximum": 10.0}),
        },
        "additionalProperties": False,
    }

    # A zero inertia reference causes the legacy warning normalization to divide
    # by zero. Make every declared axis strictly positive in v2.
    inertia_value = root_props["plausibility"]["properties"]["inertia_reference"]["properties"]["value"]
    # A vector schema can be nested behind $ref + properties, so the direct
    # vector field's `items` is the numeric component schema.
    if isinstance(inertia_value.get("items"), dict):
        inertia_value["items"]["exclusiveMinimum"] = 0.0

    prune_null_anyof(schema)
    # Remove reference-only CLadot from the active map, but retain its exact v1
    # unit/range/evidence contract at aero.reference_coefficients.CLadot.
    # Close composed smooth/legacy slipstream pieces and their parent definition.
    for name in ("slipstreamPieceLegacy", "slipstreamPieceSmooth"):
        wrapper = schema["$defs"][name]
        wrapper.pop("additionalProperties", None)
        wrapper["unevaluatedProperties"] = False
    # `profile` and `chords` are added by those wrappers; the shared core is not
    # closed on its own. Their final composed instance is closed above.
    close_objects(schema)

    # The glow/turbine definitions are the complete top-level propulsion shapes;
    # the outer union uses unevaluatedProperties so cross-branch data is rejected.
    schema["$defs"]["glowPropulsion"]["additionalProperties"] = False
    schema["$defs"]["turbinePropulsion"]["additionalProperties"] = False
    propulsion.pop("additionalProperties", None)
    propulsion["unevaluatedProperties"] = False

    # Wire root-level capability cross-checks into the offline schema. The runtime
    # contract repeats these and adds geometric steering checks.
    rules = []
    turbine_energy = {
        "if": {"properties": {"propulsion": {"required": ["fuel_consumption"]}}},
        "then": {"allOf": [
            {"properties": {"capabilities": {"properties": {"energy": {"const": "finite_liquid_fuel"}}}}},
            {"properties": {"propulsion": {"properties": {"fuel_consumption": {"properties": {"law": {"const": "turbine_map_v1"}}}}}}},
            {"properties": {"propulsion": {"properties": {"engine": {
                "required": ["spool_integrator"], "properties": {"spool_integrator": {"const": "rk4"}},
            }}}}},
        ]},
        "else": {"properties": {"capabilities": {"properties": {"energy": {"const": "prescribed_fuel"}}}}},
    }
    rules.append({"if": branch_condition(["propulsion", "kind"], "turbine"), "then": {"allOf": [
        {"properties": {"capabilities": {"properties": {"propulsion_layout": {"const": "single_centerline_jet"}}}}},
        turbine_energy,
    ]}})
    glow_energy = {
        "if": {"properties": {"propulsion": {"properties": {"engine": {"required": ["glow_installation"]}}}}},
        "then": {"properties": {"capabilities": {"properties": {"energy": {"const": "finite_glow_fuel"}}}}},
        "else": {
            "if": {"properties": {"propulsion": {"required": ["fuel_consumption"]}}},
            "then": {"properties": {"capabilities": {"properties": {"energy": {"const": "finite_liquid_fuel"}}}}},
            "else": {"properties": {"capabilities": {"properties": {"energy": {"const": "prescribed_fuel"}}}}},
        },
    }
    rules.append({"if": branch_condition(["propulsion", "kind"], "glow_prop"), "then": {"allOf": [glow_energy, {"properties": {"capabilities": {"properties": {"propulsion_layout": {"const": "single_tractor"}}}}}]}})
    rules.append({"if": {"properties": {"propulsion": {"required": ["fuel_consumption"], "properties": {
        "kind": {"const": "glow_prop"},
        "fuel_consumption": {"properties": {"law": {"const": "gasoline_bsfc_v1"}}},
    }}}}, "then": {"properties": {"propulsion": {"properties": {"engine": {
        "required": ["shaft"], "not": {"required": ["glow_installation"]},
    }}}}}})
    rules.append({"if": {"properties": {"propulsion": {"required": ["fuel_consumption"], "properties": {
        "kind": {"const": "glow_prop"},
    }}}}, "then": {"properties": {"propulsion": {"properties": {"fuel_consumption": {
        "properties": {"law": {"const": "gasoline_bsfc_v1"}},
    }}}}}})
    rules.append({"if": {"properties": {"propulsion": {"properties": {
        "kind": {"const": "turbine"},
        "fuel_consumption": {"properties": {"law": {"const": "turbine_map_v1"}}},
    }}}}, "then": {"properties": {"fuel_system": {"required": ["tanks"]}}}})
    rules.append({"if": {"properties": {"propulsion": {"required": ["fuel_consumption"]}}},
                  "then": {"required": ["fuel_system"]}})
    for battery_kind, energy in [("fixed_voltage", "fixed_voltage"), ("ocv_resistance", "ocv_resistance"), ("pack_ecm", "pack_ecm")]:
        condition = {"properties": {"propulsion": {"properties": {"kind": {"const": "electric_prop"}, "battery": {"properties": {"kind": {"const": battery_kind}}}}}}}
        rules.append({"if": condition, "then": {"properties": {"capabilities": {"properties": {"propulsion_layout": {"enum": ["single_tractor", "single_pusher"]}, "energy": {"const": energy}}}}}})
    for gear_kind in ["fixed_tricycle", "fixed_taildragger", "locked_down_taildragger", "retractable_tricycle", "retractable_taildragger"]:
        rules.append({"if": {"properties": {"capabilities": {"properties": {"gear": {"const": gear_kind}}}}}, "then": {"required": ["landing_gear"]}})
    rules.append({"if": {"properties": {"capabilities": {"properties": {"gear": {"const": "locked_up"}}}}}, "then": {"not": {"required": ["landing_gear"]}}})
    rules.append({"if": branch_condition(["capabilities", "flaps"], "simulated"),
                  "then": {"required": ["flaps"]},
                  "else": {"not": {"required": ["flaps"]}}})
    retractable_gear = {"properties": {"capabilities": {"properties": {"gear": {"enum": ["retractable_tricycle", "retractable_taildragger"]}}}}}
    rules.append({"if": retractable_gear,
                  "then": {"properties": {"landing_gear": {"required": ["retraction"], "properties": {
                      "contacts": {"items": {"required": ["retraction_path"]}}}}}},
                  "else": {"properties": {"landing_gear": {"not": {"required": ["retraction"]}, "properties": {
                      "contacts": {"items": {"not": {"required": ["retraction_path"]}}}}}}}})
    # X8-03/04/08: elevons replace the conventional surfaces on the tailless law only; the rudderless branch zeroes
    # every rudder term. The runtime contract repeats these relations; AircraftData derives the tailless strips.
    conventional_roles = ["aileron_left", "aileron_right", "elevator", "rudder"]
    zero = {"properties": {"value": {"const": 0}}}
    rules.append({"if": branch_condition(["capabilities", "controls"], "elevon"),
                  "then": {"properties": {
                      "capabilities": {"required": ["airframe_layout"]},
                      "controls": {"properties": {
                          "max_throw": {"required": ["elevon"], "not": {"anyOf": [
                              {"required": ["rudder"]}, {"required": ["aileron_down"]}]}},
                          "rates": {"properties": {"normal": {"not": {"anyOf": [
                              {"required": ["rudder"]}, {"required": ["rudder_expo"]}]}}}},
                          "surface_ids": {"required": ["elevon_left", "elevon_right"],
                                          "not": {"anyOf": [{"required": [role]} for role in conventional_roles]}},
                      }},
                      "aero": {"properties": {
                          "coefficients": {"properties": {name: zero for name in ("CYdr", "Cldr", "Cndr", "CDdr")}},
                          "surfaces": {"properties": {"vertical": {"properties": {"control_effectiveness": zero}}}},
                      }},
                  }},
                  "else": {"properties": {
                      "capabilities": {"not": {"required": ["airframe_layout"]}},
                      "controls": {"properties": {
                          "max_throw": {"required": ["rudder"], "not": {"required": ["elevon"]}},
                          "rates": {"properties": {"normal": {"required": ["rudder", "rudder_expo"]}}},
                          "surface_ids": {"required": conventional_roles, "not": {"anyOf": [
                              {"required": ["elevon_left"]}, {"required": ["elevon_right"]}]}},
                      }},
                      "aero": {"properties": {"surfaces": {"properties": {"vertical": {"properties": {
                          "control_effectiveness": {"properties": {"value": {"minimum": 0.01}}}}}}}}},
                  }}})
    rules.append({"if": {"properties": {"capabilities": {"required": ["airframe_layout"]}}},
                  "then": {"properties": {"aero": {"not": {"required": ["ground_effect"]}, "properties": {"surfaces": {
                      "required": ["tailless"], "not": {"anyOf": [
                          {"required": ["horizontal"]}, {"required": ["wing_aileron_effectiveness"]},
                          {"required": ["wing_section_cm_ac"]}]}}}}}},
                  "else": {"properties": {"aero": {"properties": {"surfaces": {
                      "required": ["horizontal", "wing_aileron_effectiveness"], "not": {"required": ["tailless"]}}}}}}})
    rules.append({"if": branch_condition(["capabilities", "damage"], "tolerant_hull"),
                  "then": {"required": ["crash_tolerance"]},
                  "else": {"not": {"required": ["crash_tolerance"]}}})
    schema["allOf"] = list(schema.get("allOf", [])) + rules
    add_physical_identity(schema)
    return schema


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--contract", type=Path)
    parser.add_argument("--check", action="store_true", help="check generated output freshness without writing")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    source = root / "app/data/schema/openrc-aircraft-v1.schema.json"
    contract_path = args.contract or root / "app/data/schema/aircraft-contract-v2.json"
    output = args.output or root / "app/data/schema/openrc-aircraft-v2.schema.json"
    spec = read_json(contract_path)
    schema = add_v2_overlay(copy.deepcopy(read_json(source)), spec)
    generated = json.dumps(schema, indent=2, ensure_ascii=False) + "\n"
    if args.check:
        if not output.is_file() or output.read_text(encoding="utf-8") != generated:
            print(f"Schema is stale: {output}")
            return 1
        print(f"Schema is current: {output}")
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(generated, encoding="utf-8")
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

