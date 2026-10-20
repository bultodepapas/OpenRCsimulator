#!/usr/bin/env python3
"""Small, ID-gated openrc-aircraft v1 -> v2 structural migration.

This migrates the eight configurations that already exist in app/data/aircraft.
It is not a general authoring defaulting engine. Unknown IDs and contradictory
legacy fields fail closed so new configurations cannot inherit a guessed setup.
Physics derivation scripts call upgrade() on their newly assembled data before
writing. legacy_input() is the compatibility view used by old derivation and
mutation tools when they need v1 layout.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
FORMAT_V1 = "openrc-aircraft v1"
FORMAT_V2 = "openrc-aircraft v2"
CONVENTION_ID = "openrc-le-frd-v1"
LEGACY_ROTATION = (
    "clockwise seen from behind (standard tractor): the reaction torque rolls the airplane left"
)
ROTATION_V2 = "clockwise_from_rear"


def _capabilities(gear: str, layout: str, energy: str) -> dict[str, str]:
    return {
        "controls": "conventional",
        "gear": gear,
        "propulsion_layout": layout,
        "energy": energy,
        "damage": "terminal_hull",
        "flaps": "not_simulated",
    }


# A v2 source that declares simulated flaps carries at least these fields.
FLAPS_REQUIRED = frozenset({
    "max_angle_deg", "takeoff_angle_deg", "inner_span_m", "outer_span_m", "hinge_fraction",
    "extension_time", "retraction_time", "max_speed_mps", "elevator_mix_per_flap_fraction",
    "effective_angle_limit_deg", "profile_drag_coefficient", "aerodynamic_gain",
})


# These policies apply only to existing, reviewed configurations. The names
# deliberately describe simulated configuration, not all physical hardware.
POLICIES: dict[str, dict[str, Any]] = {
    "jensen-das-ugly-stik-60": {
        "kind": "glow_prop", "planform": "rectangular", "gear": "fixed_tricycle",
        "layout": "single_tractor", "energy": "prescribed_fuel", "start_if_missing": 15.0,
        "rotation": LEGACY_ROTATION, "gear_contacts": 3,
    },
    "gp-extra-300s-60": {
        "kind": "glow_prop", "planform": "tapered", "gear": "fixed_taildragger",
        "layout": "single_tractor", "energy": "finite_glow_fuel", "rotation": LEGACY_ROTATION,
        "gear_contacts": 3,
    },
    "p51d-mustang-120": {
        "kind": "glow_prop", "planform": "tapered", "gear": "locked_down_taildragger",
        "layout": "single_tractor", "energy": "finite_liquid_fuel", "rotation": LEGACY_ROTATION,
        "gear_contacts": 3,
    },
    "sebart-avanti-s-a200-p100rx": {
        "kind": "turbine", "planform": "tapered", "gear": "locked_up",
        "layout": "single_centerline_jet", "energy": "finite_liquid_fuel", "start_if_missing": None,
        "gear_contacts": 0,
    },
    "synthetic_stik_electric_4s": {
        "kind": "electric_prop", "planform": "rectangular", "gear": "fixed_tricycle",
        "layout": "single_tractor", "energy": "fixed_voltage", "start_if_missing": 15.0,
        "battery_shape": "fixed_voltage", "gear_contacts": 3,
    },
    "synthetic_stik_electric_6s": {
        "kind": "electric_prop", "planform": "rectangular", "gear": "fixed_tricycle",
        "layout": "single_tractor", "energy": "fixed_voltage", "start_if_missing": 15.0,
        "battery_shape": "fixed_voltage", "gear_contacts": 3,
    },
    "synthetic_stik_electric_4s_battery": {
        "kind": "electric_prop", "planform": "rectangular", "gear": "fixed_tricycle",
        "layout": "single_tractor", "energy": "ocv_resistance", "start_if_missing": 15.0,
        "battery_shape": "ocv_resistance", "gear_contacts": 3,
    },
    "synthetic_stik_electric_6s_battery": {
        "kind": "electric_prop", "planform": "rectangular", "gear": "fixed_tricycle",
        "layout": "single_tractor", "energy": "ocv_resistance", "start_if_missing": 15.0,
        "battery_shape": "ocv_resistance", "gear_contacts": 3,
    },
}

KNOWN_FILES = (
    "jensen_ugly_stik_60.json",
    "gp_extra_300s_60.json",
    "p51d_mustang_120.json",
    "sebart_avanti_s_a200.json",
    "synthetic_stik_electric_4s.json",
    "synthetic_stik_electric_6s.json",
    "synthetic_stik_electric_4s_battery.json",
    "synthetic_stik_electric_6s_battery.json",
)


def _default_quantity(value: Any, unit: str, note: str) -> dict[str, Any]:
    return {
        "value": value,
        "unit": unit,
        "kind": "derived",
        "source": f"AS-02 compatibility default: {note}",
    }


def _require_dict(parent: dict[str, Any], key: str, path: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected object")
    return value


def _assert_planform_and_propulsion(
    data: dict[str, Any], policy: dict[str, Any], *, legacy_defaults: bool = False,
) -> None:
    reference = _require_dict(data, "reference", "reference")
    if reference.get("planform") != policy["planform"]:
        raise ValueError(
            f"{data.get('id')}: reference.planform is {reference.get('planform')!r}; "
            f"expected existing-model policy {policy['planform']!r}"
        )
    propulsion = _require_dict(data, "propulsion", "propulsion")
    actual_kind = propulsion.get("kind")
    if not (legacy_defaults and actual_kind is None and policy["kind"] == "glow_prop") \
            and actual_kind != policy["kind"]:
        raise ValueError(
            f"{data.get('id')}: propulsion.kind is {actual_kind!r}; "
            f"expected existing-model policy {policy['kind']!r}"
        )

    if policy.get("rotation"):
        propeller = _require_dict(propulsion, "propeller", "propulsion.propeller")
        expected_rotation = policy["rotation"] if legacy_defaults else ROTATION_V2
        if propeller.get("rotation") != expected_rotation:
            raise ValueError(f"{data.get('id')}: unrecognized tractor rotation {propeller.get('rotation')!r}")
    elif isinstance(propulsion.get("propeller"), dict) and "rotation" in propulsion["propeller"]:
        raise ValueError(f"{data.get('id')}: electric/jet rotation is defined by the convention, not a free field")

    battery_shape = policy.get("battery_shape")
    if battery_shape:
        battery = _require_dict(propulsion, "battery", "propulsion.battery")
        if battery_shape == "fixed_voltage":
            if "voltage_v" not in battery or "ocv_points" in battery:
                raise ValueError(f"{data.get('id')}: battery does not match fixed_voltage policy")
        elif "ocv_points" not in battery or "voltage_v" in battery:
            raise ValueError(f"{data.get('id')}: battery does not match ocv_resistance policy")


def _numeric_leaves(value: Any, path: str = "") -> dict[str, int | float]:
    result: dict[str, int | float] = {}
    if isinstance(value, bool):
        return result
    if isinstance(value, (int, float)):
        result[path or "/"] = value
    elif isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}/{key}"
            result.update(_numeric_leaves(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            result.update(_numeric_leaves(child, f"{path}/{index}"))
    return result


def numeric_parity(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    """Assert every original numeric leaf is identical after its permitted path move."""
    old = _numeric_leaves(before)
    new = _numeric_leaves(after)
    moved = 0
    differences = []
    preserved_values = []
    expected_targets = set()
    for path, value in old.items():
        target = path.replace("/aero/coefficients/CLadot/", "/aero/reference_coefficients/CLadot/")
        if target != path:
            moved += 1
        expected_targets.add(target)
        if target not in new:
            differences.append({"path": path, "expected_path": target, "before": value, "after": None})
        elif new[target] != value:
            differences.append({"path": path, "expected_path": target, "before": value, "after": new[target]})
        else:
            preserved_values.append({"before_path": path, "after_path": target, "before": value, "after": new[target]})
    if differences:
        raise ValueError(f"numeric parity failed: {differences[:5]}")
    return {
        "source_numeric_leaves": len(old),
        "preserved_numeric_leaves": len(old),
        "relocated_cladot_numeric_leaves": moved,
        "added_numeric_leaves": len(set(new) - expected_targets),
        "preserved_values": preserved_values,
        "added_values": [
            {"path": path, "value": new[path]}
            for path in sorted(set(new) - expected_targets)
        ],
        "numeric_differences": 0,
    }


def _check_v2(data: dict[str, Any], policy: dict[str, Any]) -> None:
    if data.get("convention_id") != CONVENTION_ID:
        raise ValueError(f"{data.get('id')}: v2 convention_id must be {CONVENTION_ID!r}")
    expected_capabilities = _capabilities(policy["gear"], policy["layout"], policy["energy"])
    # AV-09 is an explicit v2 extension. It must survive an idempotent v2 check;
    # the v1 migration policy above remains the historical zero-contact jet.
    if data.get("id") == "sebart-avanti-s-a200-p100rx" and data.get("capabilities", {}).get("gear") == "retractable_tricycle":
        gear = _require_dict(data, "landing_gear", "landing_gear")
        retraction = _require_dict(gear, "retraction", "landing_gear.retraction")
        if set(retraction) != {"extension_time", "retraction_time", "drag_area", "drag_center"}:
            raise ValueError("AV-09 requires its complete retraction module")
        contacts = gear.get("contacts", [])
        if not isinstance(contacts, list) or len(contacts) != 3 or any(not isinstance(c, dict) or not isinstance(c.get("retraction_path"), dict) for c in contacts):
            raise ValueError("AV-09 requires three declared retraction contact paths")
        expected_capabilities["gear"] = "retractable_tricycle"
    # AV-09 extended the Avanti and the P-51 flap probe extended the P-51 with a
    # complete flap module. Historical v1 migration still defaults to
    # not_simulated; this exception only keeps a reviewed v2 source with explicit
    # flap data idempotent. The module may carry further reviewed fields (the
    # P-51 adds lift_reference_offset_m and stall_shift_fraction); the schema
    # owns the allowed keys, this check owns completeness.
    if data.get("capabilities", {}).get("flaps") == "simulated":
        flaps = _require_dict(data, "flaps", "flaps")
        if not FLAPS_REQUIRED <= set(flaps):
            raise ValueError(f"{data.get('id')}: a simulated flaps capability requires the complete flaps module")
        expected_capabilities["flaps"] = "simulated"
    elif "flaps" in data:
        raise ValueError(f"{data.get('id')}: flaps data requires the simulated capability")
    if data.get("id") == "p51d-mustang-120" and data.get("capabilities", {}).get("gear") == "retractable_taildragger":
        gear = _require_dict(data, "landing_gear", "landing_gear")
        retraction = _require_dict(gear, "retraction", "landing_gear.retraction")
        if set(retraction) != {"extension_time", "retraction_time", "drag_area", "drag_center"}:
            raise ValueError("P51-11b requires its complete retraction module")
        contacts = gear.get("contacts", [])
        if not isinstance(contacts, list) or len(contacts) != 3 or any(not isinstance(c, dict) or not isinstance(c.get("retraction_path"), dict) for c in contacts):
            raise ValueError("P51-11b requires three declared retraction contact paths")
        expected_capabilities["gear"] = "retractable_taildragger"
    if data.get("capabilities") != expected_capabilities:
        raise ValueError(f"{data.get('id')}: v2 capabilities do not match its explicit existing-model policy")
    if data.get("format") != FORMAT_V2:
        raise ValueError(f"{data.get('id')}: expected {FORMAT_V2!r}")
    _assert_planform_and_propulsion(data, policy)
    aero = _require_dict(data, "aero", "aero")
    if "CLadot" in _require_dict(aero, "coefficients", "aero.coefficients"):
        raise ValueError(f"{data.get('id')}: inert CLadot must live under aero.reference_coefficients")
    reference_coefficients = _require_dict(aero, "reference_coefficients", "aero.reference_coefficients")
    if "CLadot" not in reference_coefficients:
        raise ValueError(f"{data.get('id')}: missing inert aero.reference_coefficients.CLadot")
    if "level_speed" not in _require_dict(data, "start", "start"):
        raise ValueError(f"{data.get('id')}: missing explicit start.level_speed")


def upgrade(raw: dict[str, Any]) -> dict[str, Any]:
    """Return a v2 copy of one of the eight reviewed configurations.

    Repeated calls on an already migrated file return an equal, independent
    copy. Unknown IDs, versions and policy conflicts raise ValueError.
    """
    if not isinstance(raw, dict):
        raise ValueError("aircraft root must be an object")
    aircraft_id = raw.get("id")
    policy = POLICIES.get(aircraft_id)
    if policy is None:
        raise ValueError(f"no AS-02 migration policy for existing aircraft id {aircraft_id!r}")
    data = deepcopy(raw)
    source_format = data.get("format")
    if source_format == FORMAT_V2:
        _check_v2(data, policy)
        return data
    if source_format != FORMAT_V1:
        raise ValueError(f"{aircraft_id}: expected {FORMAT_V1!r}, got {source_format!r}")

    # Validate model-specific, pre-existing evidence before assigning any
    # policy defaults. The policy selects only the already reviewed ID.
    _assert_planform_and_propulsion(data, policy, legacy_defaults=True)
    before = deepcopy(data)
    data["format"] = FORMAT_V2
    data["convention_id"] = CONVENTION_ID
    data["capabilities"] = _capabilities(policy["gear"], policy["layout"], policy["energy"])

    propulsion = data["propulsion"]
    if "kind" not in propulsion:
        propulsion["kind"] = policy["kind"]
    if policy.get("rotation"):
        propulsion["propeller"]["rotation"] = ROTATION_V2

    if policy.get("start_if_missing") is not None:
        start = data.setdefault("start", {})
        if not isinstance(start, dict):
            raise ValueError(f"{aircraft_id}: start must be an object")
        if "level_speed" not in start:
            start["level_speed"] = _default_quantity(
                policy["start_if_missing"], "m/s",
                "preserves the v1 loader's 15 m/s default for this existing Stik-derived configuration",
            )
    elif "level_speed" not in data.get("start", {}):
        raise ValueError(f"{aircraft_id}: start.level_speed is missing and no policy default is approved")

    for index, item in enumerate(data.get("inventory", [])):
        if not isinstance(item, dict):
            raise ValueError(f"{aircraft_id}: inventory[{index}] must be an object")
        if "size" not in item:
            item["size"] = _default_quantity(
                [0, 0, 0], "m", "explicit point-mass dimensions preserve the v1 omitted-size inertia behavior",
            )

    gear = data.get("landing_gear")
    contacts = [] if gear is None else gear.get("contacts", [])
    if not isinstance(contacts, list) or len(contacts) != policy["gear_contacts"]:
        raise ValueError(f"{aircraft_id}: contact count conflicts with the existing-model gear policy")
    for index, contact in enumerate(contacts):
        if not isinstance(contact, dict):
            raise ValueError(f"{aircraft_id}: landing_gear.contacts[{index}] must be an object")
        if "max_steering" not in contact or contact["max_steering"] is None:
            contact["max_steering"] = _default_quantity(
                0, "deg", "explicit zero preserves the v1 omitted-steering behavior for this contact",
            )

    aero = _require_dict(data, "aero", "aero")
    coefficients = _require_dict(aero, "coefficients", "aero.coefficients")
    if "CLadot" in coefficients:
        reference = aero.setdefault("reference_coefficients", {})
        if not isinstance(reference, dict):
            raise ValueError(f"{aircraft_id}: aero.reference_coefficients must be an object")
        if "CLadot" in reference and reference["CLadot"] != coefficients["CLadot"]:
            raise ValueError(f"{aircraft_id}: conflicting CLadot at active and reference paths")
        reference["CLadot"] = coefficients.pop("CLadot")
    else:
        raise ValueError(f"{aircraft_id}: expected the existing inert aero.coefficients.CLadot quantity")

    numeric_parity(before, data)
    _check_v2(data, policy)
    return data


def legacy_input(raw: dict[str, Any]) -> dict[str, Any]:
    """Return a v1-layout copy for existing historical derivation/test tools.

    This removes v2-only root declarations and reverses the inert CLadot path
    move. An empty-tank v2 balance is rebased to its full inventory state because
    v1 has no fuel-state selector. Other numeric quantities are retained.
    """
    if not isinstance(raw, dict):
        raise ValueError("aircraft root must be an object")
    data = deepcopy(raw)
    source_format = data.get("format")
    if source_format == FORMAT_V1:
        return data
    if source_format != FORMAT_V2:
        raise ValueError(f"legacy_input: expected v1 or v2, got {source_format!r}")
    data["format"] = FORMAT_V1
    data.pop("convention_id", None)
    data.pop("capabilities", None)
    data.pop("flaps", None)
    # Authored physical identities are a v2-only module. Keep this compatibility
    # view in the historical v1 shape; callers retain the original v2 object.
    data.pop("physical_identity_version", None)
    data.pop("crash_hull_ids", None)
    inventory = data.get("inventory")
    if isinstance(inventory, list):
        for item in inventory:
            if isinstance(item, dict):
                item.pop("id", None)
    landing_gear = data.get("landing_gear")
    if isinstance(landing_gear, dict):
        contacts = landing_gear.get("contacts")
        if isinstance(contacts, list):
            for contact in contacts:
                if isinstance(contact, dict):
                    contact.pop("id", None)
    propulsion = data.get("propulsion")
    if isinstance(propulsion, dict):
        propulsion.pop("id", None)
    controls = data.get("controls")
    if isinstance(controls, dict):
        controls.pop("surface_ids", None)
    balance = data.get("balance")
    inventory = data.get("inventory")
    if (isinstance(balance, dict) and balance.get("fuel_state") == "empty_tanks"
            and isinstance(inventory, list) and inventory):
        def finite_number(value: Any) -> bool:
            if type(value) not in (int, float):
                return False
            try:
                return math.isfinite(float(value))
            except (OverflowError, ValueError):
                return False

        masses = []
        positions = []
        for item in inventory:
            if not isinstance(item, dict):
                masses = []
                break
            mass = item.get("mass", {}).get("value") if isinstance(item.get("mass"), dict) else None
            position = item.get("position", {}).get("value") if isinstance(item.get("position"), dict) else None
            if (not finite_number(mass) or float(mass) <= 0.0
                    or not isinstance(position, list) or len(position) != 3
                    or any(not finite_number(value) for value in position)):
                masses = []
                break
            masses.append(float(mass))
            positions.append([float(value) for value in position])
        plan_cg = balance.get("plan_cg")
        evidence_kinds = ("manual", "measured", "borrowed", "estimated", "derived")
        original_cg = plan_cg.get("value") if isinstance(plan_cg, dict) else None
        valid_original_cg = (
            isinstance(original_cg, list) and len(original_cg) == 3
            and all(finite_number(value) and -2.0 <= float(value) <= 2.0
                    for value in original_cg)
        )
        original_source = plan_cg.get("source") if isinstance(plan_cg, dict) else None
        valid_original_source = (
            isinstance(original_source, str)
            and any(ord(character) == 0 or ord(character) > 32 for character in original_source)
        )
        try:
            total_mass = math.fsum(masses) if masses else 0.0
            if (isinstance(plan_cg, dict) and valid_original_cg
                    and plan_cg.get("kind") in evidence_kinds
                    and valid_original_source
                    and total_mass > 0.0 and math.isfinite(total_mass)):
                moments = [math.fsum(mass * position[axis]
                                     for mass, position in zip(masses, positions))
                           for axis in range(3)]
                if all(math.isfinite(moment) for moment in moments):
                    plan_cg["value"] = [moment / total_mass for moment in moments]
                    plan_cg["kind"] = "derived"
                    plan_cg["source"] = "v1 compatibility projection: full inventory CG"
        except OverflowError:
            # Leave invalid/extreme source values untouched for the owning
            # schema and runtime validators to diagnose.
            pass
    aero = data.get("aero")
    if isinstance(aero, dict):
        reference = aero.get("reference_coefficients")
        coefficients = aero.setdefault("coefficients", {})
        if not isinstance(coefficients, dict):
            raise ValueError("legacy_input: aero.coefficients must be an object")
        if isinstance(reference, dict) and "CLadot" in reference:
            if "CLadot" in coefficients and coefficients["CLadot"] != reference["CLadot"]:
                raise ValueError("legacy_input: conflicting CLadot at active and reference paths")
            coefficients["CLadot"] = reference.pop("CLadot")
        if isinstance(reference, dict) and not reference:
            aero.pop("reference_coefficients", None)
    propulsion = data.get("propulsion")
    if isinstance(propulsion, dict) and isinstance(propulsion.get("propeller"), dict):
        if propulsion["propeller"].get("rotation") == ROTATION_V2:
            propulsion["propeller"]["rotation"] = LEGACY_ROTATION
    return data


def _validate_v2_source(raw: dict[str, Any], path: Path) -> dict[str, Any]:
    """Require an already-v2, canonical input for --check-known."""
    if raw.get("format") != FORMAT_V2:
        raise ValueError(f"{path}: source format is {raw.get('format')!r}; expected {FORMAT_V2!r}")
    upgraded = upgrade(raw)
    if upgraded != raw:
        raise ValueError(f"{path}: v2 source is not canonical; upgrade would change its structure")
    return upgraded


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-known", action="store_true", help="upgrade the eight existing aircraft JSONs in place")
    parser.add_argument("--check-known", action="store_true", help="require the eight existing JSONs to be valid v2")
    parser.add_argument("--input-dir", type=Path, default=ROOT / "app/data/aircraft", help="source directory for the known filenames")
    parser.add_argument("--output-dir", type=Path, help="stage --write-known results outside app/data/aircraft")
    args = parser.parse_args()
    if args.write_known == args.check_known:
        parser.error("choose exactly one of --write-known or --check-known")
    if args.check_known and args.output_dir is not None:
        parser.error("--output-dir is only valid with --write-known")
    written = []
    for name in KNOWN_FILES:
        path = args.input_dir / name
        raw = json.loads(path.read_text(encoding="utf-8"))
        if args.check_known:
            try:
                data = _validate_v2_source(raw, path)
            except ValueError as exc:
                raise SystemExit(str(exc)) from exc
        else:
            data = upgrade(raw)
            text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
            target = path if args.output_dir is None else args.output_dir / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or target.read_text(encoding="utf-8") != text:
                target.write_text(text, encoding="utf-8", newline="\n")
        policy = POLICIES[data["id"]]
        if args.write_known:
            target = path if args.output_dir is None else args.output_dir / path.name
            written.append(target.relative_to(ROOT).as_posix() if target.is_relative_to(ROOT) else str(target))
        source_name = path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path)
        print(f"{source_name}: {data['id']} v2, {policy['kind']}, {policy['energy']}")
    if args.write_known:
        print("upgraded/verified " + str(len(written)) + " known configurations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
