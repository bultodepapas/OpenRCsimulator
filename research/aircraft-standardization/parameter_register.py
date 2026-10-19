"""AS-01: enumerate every quantity's structural domain and reviewed consumer.

The schema supplies domains; AIRCRAFT_CONTRACT supplies meanings and coupled
constraints. Fail on an unassigned family so a new module needs review.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "app/data/schema/openrc-aircraft-v2.schema.json"
OUTPUT = ROOT / "docs/research/aircraft-standardization/AS-01/parameters.md"


def consumer(path: str) -> str:
    reference_only = {
        "balance.firewall": "AircraftData._q: reference validation only; no force effect",
        "balance.cg_tolerance": "AircraftData.validate_and_derive: inventory/declared CG acceptance",
        "balance.plan_cg": "AircraftData.validate_and_derive: inventory CG agreement; not an override",
        "plausibility.mass_range": "AircraftData.validate_and_derive: total-mass acceptance",
        "plausibility.inertia_reference": "AircraftData.validate_and_derive: scaled-inertia warning only",
        "aero.reference_coefficients.CLadot": "AircraftData reference validation only; no alpha-dot force consumer",
        "propulsion.engine.peak_power": "AircraftData._propulsion: brochure evidence validation only",
        "propulsion.engine.peak_power_rpm": "AircraftData._propulsion: brochure evidence validation only",
        "propulsion.motor.no_load_context.temperature_c": "AircraftData._electric_propulsion: test context; no thermal law",
        "propulsion.motor.no_load_context.rpm": "AircraftData._electric_propulsion: Kv/test-voltage consistency",
        "propulsion.motor.no_load_context.voltage_v": "AircraftData._electric_propulsion: Kv/test-RPM consistency",
        "propulsion.engine.fuel_flow": "Turbine.fuel_flow / session telemetry; no mass depletion",
    }
    if path in reference_only:
        return reference_only[path]

    if path.startswith("controls.keyboard."):
        return "AircraftData._controls → Commands.keyboard_pitch; keyboard normal-profile virtual stick only, before expo/rates; no aerodynamic or servo change"
    if path.startswith("controls.gamepad."):
        return "AircraftData._controls → FlightSession normal-gamepad sampler/flown_commands; fixed yaw response time and pitch/yaw travel before trim; full/radio bypass"
    if path.startswith("landing_gear.retraction.") or path.endswith(".retraction_path"):
        return "AircraftData._derive_retraction → RetractableGear actuator/contact interpolation/drag; FlightSession accepted gear state"
    if path.startswith("flaps."):
        return "AircraftData._flaps → Flaps.advance normalized actuator / Aero strip incidence, bounded lift, induced and profile drag, thin-airfoil pitch couple, and tail downwash; AV-09 manual-mix and EAS-advisory consumers"
    if path.startswith("balance.cg_range."):
        return "AircraftData._fuel_system: plan-CG acceptance at the declared balance fuel state; no force effect"
    if path.startswith("fuel_system.tanks[]."):
        return "AircraftData._fuel_system: tank capacity/unusable volume → model.fuel_system (registry density, start fill); FUEL-03, consumers from FUEL-05"
    families = [
        ("inventory[].", "AircraftData.inertia_about / mass-CG sum → rigid_body, trim, rotor carrier"),
        ("reference.", "AircraftData reference/strip derivation → Aero.loads, trim, render datum checks"),
        ("start.", "FlightSession._prepare_aircraft → Scenarios.trimmed_level_across_view"),
        ("aero.coefficients.", "Aero._global_loads / local-oracle calibration: normalized force or moment derivative"),
        ("aero.envelope.", "AircraftData._envelope → Aero stall/sideslip blend and local plate loads"),
        ("aero.surfaces.", "AircraftData._surfaces/_induced_map → Aero local wing/tail and downwash"),
        ("aero.wing_polar.", "AircraftData._wing_polar → WingPolar.prepare / Aero local wing"),
        ("aero.ground_effect.", "AircraftData._ground_effect → GroundEffect.factors / Aero strip induced angle, induced drag and tail downwash near the ground"),
        ("controls.", "AircraftData._controls → Commands surface mapping, session servo integration, rendering"),
        ("crash_hull", "AircraftData._hull_body → hull_crossing / ImpactSnapshot / FlightSession crash"),
        ("landing_gear.", "AircraftData._landing_gear → ground_contact, ground_start, session anchors/travel crash"),
        ("propulsion.propeller.slipstream.", "AircraftData._slipstream → Slipstream.loads / SwirlLoads module / session wake state"),
        ("propulsion.engine.shaft.", "AircraftData._shaft → Propulsion shaft torque/RPM balance / session integrator"),
        ("propulsion.propeller.", "AircraftData._propulsion/_electric_propulsion → Propulsion thrust/torque/axis/rotor loads"),
        ("propulsion.motor.", "AircraftData._electric_propulsion → electric_motor/electric_supply shaft and bus law"),
        ("propulsion.battery.weak_cell.", "AircraftData._pack_ecm_battery → PackEcm weakest-cell capacity/resistance/charge offset; exhaustion event state"),
        ("propulsion.battery.", "AircraftData._electric_battery/_pack_ecm_battery → electric_supply or PackEcm, electric_battery_step, reset/trim"),
        ("propulsion.esc.low_voltage_cutoff.", "AircraftData._low_voltage_cutoff → EscSupervisor cell detection and sampled cutoff; PackEcm voltage filter"),
    ]
    for prefix, result in families:
        if path.startswith(prefix):
            return result
    engine_lag = {"max_rpm_static", "idle_rpm", "lag_time_constant"}
    if path.startswith("propulsion.engine."):
        key = path.split(".")[-1]
        return ("AircraftData._propulsion/_turbine → Propulsion target/lag or Turbine spool (branch-specific)"
                if key in engine_lag else
                "AircraftData._turbine → Turbine spool/thrust/ram/rotor load law")
    if path in {"propulsion.thrust_line_offset", "propulsion.intake_offset", "propulsion.thrust_angles"}:
        return "AircraftData._turbine → Turbine force application and rotor axis"
    raise ValueError(f"Unassigned parameter consumer: {path}")


def bound(node) -> str:
    if not isinstance(node, dict):
        return ""
    parts = []
    for key, symbol in [("minimum", "≥"), ("exclusiveMinimum", ">"),
                        ("maximum", "≤"), ("exclusiveMaximum", "<")]:
        if key in node:
            parts.append(f"{symbol}{node[key]:g}")
    if "minItems" in node or "maxItems" in node:
        parts.append(f"length {node.get('minItems', 0)}…{node.get('maxItems', 'unbounded')}")
    if "items" in node and isinstance(node["items"], dict):
        item = bound(node["items"])
        if item:
            parts.append("each(" + item + ")")
    if "prefixItems" in node:
        parts.append("columns(" + "; ".join(bound(x) or "see schema" for x in node["prefixItems"]) + ")")
    for key in ["allOf", "anyOf", "oneOf"]:
        for item in node.get(key, []):
            item_bound = bound(item)
            if item_bound:
                parts.append(item_bound)
    return ", ".join(parts)


def render() -> str:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    fields = {}

    def visit(node, path="", depth=0):
        if not isinstance(node, dict) or depth > 40:
            return
        if "$ref" in node:
            target = schema
            for key in node["$ref"].split("/")[1:]:
                target = target[key]
            visit(target, path, depth + 1)
        props = node.get("properties", {})
        if "value" in props:
            field = fields.setdefault(path, {"unit": set(), "bounds": set()})
            unit = props.get("unit", {}).get("const")
            if unit is not None:
                field["unit"].add(unit)
            limits = bound(props["value"])
            if limits:
                field["bounds"].add(limits)
        for key, value in props.items():
            if key not in {"value", "unit", "kind", "source"}:
                visit(value, path + ("." if path else "") + key, depth + 1)
        if isinstance(node.get("items"), dict):
            visit(node["items"], path + "[]", depth + 1)
        for key in ["allOf", "oneOf", "anyOf"]:
            for child in node.get(key, []):
                visit(child, path, depth + 1)
        for key in ["then", "else"]:
            visit(node.get(key), path, depth + 1)

    visit(schema)
    rows = ["# AS-01 parameter register", "", "**Status: Generated contract reference, 2026-10-11.**",
            "", "Generated by `research/aircraft-standardization/parameter_register.py`; do not hand-edit.",
            "", "Every quantity is listed, including reference-only evidence. Bounds are structural limits;",
            "alternatives belong to different conditional branches. The versioned schema selects the branch.",
            "CG/area/tensor/table/support/timestep/trim constraints remain additional runtime checks.",
            "Meanings, sign conventions, dependencies, default policy and physical justification are in",
            "[AIRCRAFT_CONTRACT](../../../../AIRCRAFT_CONTRACT.md). The [audit](../AS-00/config-audit.md)",
            "explains the original consumers. Metadata/capability enums are specified in the root contract and schema.",
            "", "| Quantity | Unit | Structural domain | Consumer / defined effect |",
            "| --- | --- | --- | --- |"]
    for path, field in sorted(fields.items()):
        unit = " / ".join(sorted(field["unit"])) or "see schema"
        limits = " OR ".join(sorted(field["bounds"])) or "finite; see schema"
        rows.append(f"| `{path}` | {unit} | {limits} | {consumer(path)} |")
    rows.extend(["", f"Total: {len(fields)} distinct quantity paths. Shared paths retain branch-dependent ranges.", ""])
    return "\n".join(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != text:
            raise SystemExit("parameter register is stale")
        print("parameter register is current")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(text, encoding="utf-8")
        print(OUTPUT.relative_to(ROOT))
