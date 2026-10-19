#!/usr/bin/env python3
"""Compare the reviewed v2 JSON Schema with the public Godot aircraft loader."""

from __future__ import annotations

import argparse
from copy import deepcopy
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[2]
LOADER_PROBE = ROOT / "research" / "aircraft-data" / "schema" / "loader_probe.gd"
LEGACY_V1 = Path(__file__).with_name("fixtures") / "legacy-stik-v1.json"
DEFAULT_GODOT = ROOT / ".tools" / "Godot_v4.7.2-stable_linux.x86_64"
DEFAULT_APP = ROOT / "app"
EXPECTED_FLEET = {
    "jensen_ugly_stik_60",
    "gp_extra_300s_60",
    "p51d_mustang_120",
    "sebart_avanti_s_a200",
    "synthetic_stik_electric_4s",
    "synthetic_stik_electric_6s",
    "synthetic_stik_electric_4s_battery",
    "synthetic_stik_electric_6s_battery",
    "stik_glow_55ax_2t",
    "stik_glow_55ax_2t_apc_13x6",
    "stik_glow_61fx_2t",
    "stik_glow_fs64v_4t",
    "stik_glow_fs64v_4t_apc_13x6",
    "turbo_lumber_evolution",
}
ENGINE_ERROR = re.compile(r"(?:SCRIPT ERROR:|Parse Error:|ERROR:)")
@dataclass
class Case:
    name: str
    data: dict[str, Any]
    schema_ok: bool
    loader_ok: bool
    classification: str


def reject_constant(value: str) -> None:
    raise ValueError(f"non-JSON numeric constant: {value}")


def finite_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"number exceeds finite float64 range: {value}")
    return number


def finite_int(value: str) -> int:
    finite_float(value)
    return int(value)


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant,
                       parse_float=finite_float, parse_int=finite_int)
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected top-level object")
    return value


def at(data: Any, path: tuple[Any, ...]) -> Any:
    value = data
    for part in path:
        value = value[part]
    return value


def remove(data: Any, path: tuple[Any, ...]) -> None:
    at(data, path[:-1]).pop(path[-1])


def without(data: dict[str, Any], path: tuple[Any, ...]) -> dict[str, Any]:
    clone = deepcopy(data)
    remove(clone, path)
    return clone


def schema_validator(data: dict[str, Any], cache: dict[Path, Draft202012Validator],
                     schema_paths: dict[str, Path]) -> Draft202012Validator:
    version = data.get("format")
    schema_path = schema_paths.get(version, schema_paths["openrc-aircraft v2"])
    if schema_path not in cache:
        schema = read_json(schema_path)
        Draft202012Validator.check_schema(schema)
        cache[schema_path] = Draft202012Validator(schema)
    return cache[schema_path]


def build_cases(app: Path) -> list[Case]:
    fleet_dir = app / "data" / "aircraft"
    # The shared directory also holds explicitly tagged rotorcraft with their own schema.
    fleet_paths = {path.stem: path for path in sorted(fleet_dir.glob("*.json"))
                   if read_json(path).get("vehicle") != "rotorcraft"}
    if set(fleet_paths) != EXPECTED_FLEET:
        raise AssertionError(
            "expected the four catalog, four electric, five glow, and Turbo Lumber v2 files; "
            f"missing={sorted(EXPECTED_FLEET - set(fleet_paths))}, "
            f"extra={sorted(set(fleet_paths) - EXPECTED_FLEET)}"
        )
    fleet = {name: read_json(path) for name, path in fleet_paths.items()}
    if any(data.get("format") != "openrc-aircraft v2" for data in fleet.values()):
        raise AssertionError("all fourteen current fixed-wing aircraft data files must be explicitly migrated to v2")
    stik = fleet["jensen_ugly_stik_60"]
    p51 = fleet["p51d_mustang_120"]
    avanti = fleet["sebart_avanti_s_a200"]
    electric = fleet["synthetic_stik_electric_4s"]

    cases: list[Case] = [
        Case(f"fleet-positive:{name}", data, True, True, "positive")
        for name, data in sorted(fleet.items())
    ]

    def add(name: str, source: dict[str, Any], *, schema_ok: bool, loader_ok: bool,
            classification: str = "v2-structural") -> dict[str, Any]:
        data = deepcopy(source)
        cases.append(Case(name, data, schema_ok, loader_ok, classification))
        return data

    # Optional feed-line and pickup data retain stable resource/inventory IDs,
    # authored geometry and source quantities. The line fluid is a second liquid
    # resource, not a dry accessory or a display-name binding.
    feed_line = deepcopy(stik)
    feed_tank = feed_line["fuel_system"]["tanks"][0]
    feed_tank["pickup_position"] = {
        "value": [-0.015, 0.004, 0.008], "unit": "m", "kind": "estimated",
        "source": "synthetic AS-08 pickup-position fixture",
    }
    feed_tank["feed_line"] = {
        "id": "line_main", "liquid_inventory_id": "item_fuel_line",
        "capacity": {"value": 0.005, "unit": "l", "kind": "estimated",
                     "source": "synthetic AS-08 preprimed line fixture"},
    }
    feed_line["inventory"].append({
        "id": "item_fuel_line", "name": "preprimed glow line", "energy_source": "glow_fuel",
        "mass": {"value": 0.002, "unit": "kg", "kind": "estimated",
                 "source": "synthetic AS-08 preprimed line fixture"},
        "position": {"value": [0.07, 0.01, -0.02], "unit": "m", "kind": "estimated",
                     "source": "synthetic AS-08 inventory-frame line placement"},
        "size": {"value": [0.04, 0.02, 0.02], "unit": "m", "kind": "estimated",
                 "source": "synthetic AS-08 line-liquid capacity envelope"},
    })
    cases.append(Case("fuel-feed-line:optional-pickup-and-primed-line", feed_line,
                      True, True, "fuel-feed-line"))
    line_over_capacity = deepcopy(feed_line)
    line_over_capacity["fuel_system"]["tanks"][0]["feed_line"]["capacity"]["value"] = 0.3
    cases.append(Case("fuel-feed-line:capacity-exceeds-main-tank", line_over_capacity,
                      True, False, "coupled-runtime-only"))
    line_family_mismatch = deepcopy(feed_line)
    next(item for item in line_family_mismatch["inventory"] if item["id"] == "item_fuel_line")["energy_source"] = "gasoline"
    cases.append(Case("fuel-feed-line:blend-family-mismatch", line_family_mismatch,
                      True, False, "coupled-runtime-only"))
    line_reuses_tank_fluid = deepcopy(feed_line)
    line_reuses_tank_fluid["fuel_system"]["tanks"][0]["feed_line"]["liquid_inventory_id"] = "item_fuel_main"
    cases.append(Case("fuel-feed-line:reuses-tank-liquid", line_reuses_tank_fluid,
                      True, False, "coupled-runtime-only"))
    pickup_wrong_arity = deepcopy(feed_line)
    pickup_wrong_arity["fuel_system"]["tanks"][0]["pickup_position"]["value"] = [0.0, 0.0]
    cases.append(Case("fuel-feed-line:pickup-wrong-arity", pickup_wrong_arity,
                      False, False, "fuel-feed-line"))
    line_empty_id = deepcopy(feed_line)
    line_empty_id["fuel_system"]["tanks"][0]["feed_line"]["id"] = ""
    cases.append(Case("fuel-feed-line:empty-resource-id", line_empty_id,
                      False, False, "fuel-feed-line"))
    pickup_missing_source = deepcopy(feed_line)
    pickup_missing_source["fuel_system"]["tanks"][0]["pickup_position"].pop("source")
    cases.append(Case("fuel-feed-line:pickup-missing-provenance", pickup_missing_source,
                      False, False, "fuel-feed-line"))
    capacity_missing_source = deepcopy(feed_line)
    capacity_missing_source["fuel_system"]["tanks"][0]["feed_line"]["capacity"].pop("source")
    cases.append(Case("fuel-feed-line:capacity-missing-provenance", capacity_missing_source,
                      False, False, "fuel-feed-line"))
    line_geometry_empty_source = deepcopy(feed_line)
    next(item for item in line_geometry_empty_source["inventory"] if item["id"] == "item_fuel_line")["position"]["source"] = " "
    cases.append(Case("fuel-feed-line:geometry-empty-provenance", line_geometry_empty_source,
                      False, False, "fuel-feed-line"))

    # AS-08: complete optional identities preserve old v2, and fail closed when partial.
    if stik.get("physical_identity_version") != 1:
        raise AssertionError("catalog Stik must carry authored physical identities")
    # Use the identity-free compatible electric branch here: the Stik fixture now
    # has v2 tank references that correctly require the referenced inventory IDs.
    idless = add("identity:legacy-v2", electric, schema_ok=True, loader_ok=True)
    idless.pop("physical_identity_version")
    idless.pop("crash_hull_ids")
    for item in idless["inventory"] + idless["landing_gear"]["contacts"]:
        item.pop("id")
    idless["propulsion"].pop("id")
    idless["controls"].pop("surface_ids")
    for name, path in [
        ("version", ("physical_identity_version",)),
        ("inventory", ("inventory", 0, "id")),
        ("support", ("landing_gear", "contacts", 0, "id")),
        ("hull", ("crash_hull_ids",)),
        ("propulsion", ("propulsion", "id")),
        ("surfaces", ("controls", "surface_ids")),
        ("elevator", ("controls", "surface_ids", "elevator")),
    ]:
        cases.append(Case("identity:missing-" + name, without(stik, path), False, False, "identity"))
    for index, value in enumerate([None, True, False, "1", 0, 2, 1.5]):
        mutant = add(f"identity:version-{index}", stik, schema_ok=False, loader_ok=False)
        mutant["physical_identity_version"] = value
    for index, value in enumerate([None, True, 1, "Wing", "a__b", "a-1", "1_wing", "wing\n", "a" * 81]):
        mutant = add(f"identity:syntax-{index}", stik, schema_ok=False, loader_ok=False)
        mutant["inventory"][0]["id"] = value
    hull_duplicate = add("identity:duplicate-hull", stik, schema_ok=False, loader_ok=False)
    hull_duplicate["crash_hull_ids"][1] = hull_duplicate["crash_hull_ids"][0]
    # JSON Schema cannot express these comparisons of independently nested values.
    duplicate = add("identity:cross-group-duplicate", stik, schema_ok=True, loader_ok=False,
                    classification="coupled-runtime-only")
    duplicate["propulsion"]["id"] = duplicate["inventory"][0]["id"]
    misaligned = add("identity:hull-count", stik, schema_ok=True, loader_ok=False,
                     classification="coupled-runtime-only")
    misaligned["crash_hull_ids"].pop()
    gear_up = add("identity:gear-up", stik, schema_ok=True, loader_ok=True)
    gear_up["id"] = "identity-gear-up-fixture"
    gear_up["capabilities"]["gear"] = "locked_up"
    gear_up.pop("landing_gear")
    for name in ("synthetic_stik_electric_4s", "synthetic_stik_electric_4s_battery"):
        identified = add("identity:" + name, fleet[name], schema_ok=True, loader_ok=True)
        identified["physical_identity_version"] = 1
        identified["propulsion"]["id"] = "propulsion_main"
        identified["controls"]["surface_ids"] = deepcopy(stik["controls"]["surface_ids"])
        identified["crash_hull_ids"] = deepcopy(stik["crash_hull_ids"])
        for i, item in enumerate(identified["inventory"]):
            item["id"] = f"fixture_part_{i}"
        for i, item in enumerate(identified["landing_gear"]["contacts"]):
            item["id"] = f"fixture_support_{i}"

    # Fixed and missing required fields, exact capability branch selectors, and version routing.
    all_zero_steering = add("positive:all-zero-steering", stik, schema_ok=True,
                            loader_ok=True, classification="v2-positive-edge")
    for contact in all_zero_steering["landing_gear"]["contacts"]:
        contact["max_steering"]["value"] = 0.0

    bad_kind = add("reject:unsupported-propulsion-kind", stik, schema_ok=False, loader_ok=False)
    bad_kind["propulsion"]["kind"] = "edf"
    bad_layout = add("reject:unsupported-layout", stik, schema_ok=False, loader_ok=False)
    bad_layout["capabilities"]["propulsion_layout"] = "single_pusher"
    numeric_capability = add("reject:numeric-capability", stik, schema_ok=False, loader_ok=False)
    numeric_capability["capabilities"]["gear"] = 1
    future_version = add("reject:unsupported-version-no-downgrade", stik, schema_ok=False, loader_ok=False)
    future_version["format"] = "openrc-aircraft v3"
    for name, path in [
        ("convention-id", ("convention_id",)),
        ("capabilities", ("capabilities",)),
        ("initial-speed", ("start", "level_speed")),
        ("inventory-size", ("inventory", 0, "size")),
        ("combustion-rotation", ("propulsion", "propeller", "rotation")),
    ]:
        cases.append(Case(f"reject:missing-required-{name}", without(stik, path), False, False, "v2-structural"))

    # Spec string_rules use strip_edges() at runtime; the offline schema must
    # reject the same all-whitespace metadata values.
    whitespace_configuration = add("reject:whitespace-balance-configuration", stik,
                                   schema_ok=False, loader_ok=False)
    whitespace_configuration["balance"]["configuration"] = " \t\r\n"
    whitespace_inventory_name = add("reject:whitespace-inventory-name", stik,
                                    schema_ok=False, loader_ok=False)
    whitespace_inventory_name["inventory"][0]["name"] = " \t\r\n"

    # Optional means absent. Explicit null is not a zero/default/disabled module.
    for name, source, path in [
        ("shaft", p51, ("propulsion", "engine", "shaft")),
        ("slipstream", p51, ("propulsion", "propeller", "slipstream")),
    ]:
        null_module = add(f"reject:null-optional-{name}", source, schema_ok=False, loader_ok=False)
        at(null_module, path[:-1])[path[-1]] = None

    # A known-looking but unsupported coefficient must not be ignored.
    unknown_coefficient = add("reject:unknown-active-coefficient", stik, schema_ok=False, loader_ok=False)
    unknown_coefficient["aero"]["coefficients"]["CL_unregistered"] = deepcopy(
        unknown_coefficient["aero"]["coefficients"]["CLa"]
    )

    # Branch-exclusive fields must be refused instead of being silently ignored.
    turbine_propeller = add("reject:turbine-with-propeller-branch", avanti, schema_ok=False, loader_ok=False)
    turbine_propeller["propulsion"]["propeller"] = deepcopy(stik["propulsion"]["propeller"])
    combustion_motor = add("reject:combustion-with-electric-motor", stik, schema_ok=False, loader_ok=False)
    combustion_motor["propulsion"]["motor"] = deepcopy(electric["propulsion"]["motor"])
    electric_engine = add("reject:electric-with-combustion-engine", electric, schema_ok=False, loader_ok=False)
    electric_engine["propulsion"]["engine"] = deepcopy(stik["propulsion"]["engine"])
    gear_contradiction = add("reject:locked-up-with-contacts", stik, schema_ok=False, loader_ok=False)
    gear_contradiction["capabilities"]["gear"] = "locked_up"
    zero_inertia = add("reject:zero-inertia-reference", stik, schema_ok=False, loader_ok=False)
    zero_inertia["plausibility"]["inertia_reference"]["value"][0] = 0.0

    # Planform branches are explicit: rectangular data has no root/tip chord,
    # while tapered data requires both. The Extra is the positive tapered fixture.
    for chord_name in ("root_chord", "tip_chord"):
        rectangular_chord = add(f"reject:rectangular-with-{chord_name}", stik,
                                schema_ok=False, loader_ok=False)
        rectangular_chord["reference"][chord_name] = {
            "value": 0.3048,
            "unit": "m",
            "kind": "estimated",
            "source": "AS-04 forbidden rectangular branch mutant",
        }
    cases.append(Case("positive:tapered-root-tip", deepcopy(fleet["gp_extra_300s_60"]),
                      True, True, "v2-planform-branch"))
    tapered_missing_chords = add("reject:tapered-missing-root-tip", fleet["gp_extra_300s_60"],
                                 schema_ok=False, loader_ok=False,
                                 classification="v2-planform-branch")
    tapered_missing_chords["reference"].pop("root_chord")
    tapered_missing_chords["reference"].pop("tip_chord")

    # Bounded coverage of all existing P-51 optional propeller feature masks.
    # Force/moment/wake options require the shaft and explicit axis; with none of
    # those three enabled, shaft/axis may independently be absent or present.
    p51_options = {
        "shaft": ("propulsion", "engine", "shaft"),
        "angles": ("propulsion", "propeller", "thrust_angles"),
        "normal_force": ("propulsion", "propeller", "normal_force"),
        "pfactor": ("propulsion", "propeller", "pfactor_moment"),
        "slipstream": ("propulsion", "propeller", "slipstream"),
    }
    for name, path in p51_options.items():
        if not at(p51, path):
            raise AssertionError(f"P-51 must contain its audited optional module for the mask test: {name}")
    # P-51 has negative windmilling Cp coefficients, so its fitted propeller
    # table is valid only with the shaft model active. Hold shaft present while
    # testing the angle/force/moment/wake combinations; separately exercise the
    # no-shaft path with the shipped Stik data, whose Cp table is no-shaft-safe.
    option_names = [name for name in p51_options if name != "shaft"]
    for mask in range(1 << len(option_names)):
        enabled = {name for bit, name in enumerate(option_names) if mask & (1 << bit)}
        data = deepcopy(p51)
        for name, path in p51_options.items():
            if name != "shaft" and name not in enabled:
                remove(data, path)
        dependent = bool(enabled & {"normal_force", "pfactor", "slipstream"})
        valid = not dependent or "angles" in enabled
        cases.append(Case(
            f"combustion-feature-mask:{mask:02d}:" + "+".join(sorted(enabled)),
            data, valid, valid, "v2-feature-dependency",
        ))
    for include_angles in (False, True):
        data = deepcopy(stik)
        if include_angles:
            data["propulsion"]["propeller"]["thrust_angles"] = {
                "value": [0.0, 0.0],
                "unit": "deg",
                "kind": "estimated",
                "source": "AS-04 optional-module validity fixture; axial thrust line",
            }
        cases.append(Case(
            f"combustion-no-shaft:angles-{str(include_angles).lower()}",
            data, True, True, "v2-feature-dependency",
        ))

    # All eight combinations of Avanti's two ram modules and optional thrust angle.
    # The shipped Avanti omits the optional angle module; seed an explicit axial
    # value here so its present/absent combinations both exercise the contract.
    turbine_base = deepcopy(avanti)
    turbine_base["propulsion"]["thrust_angles"] = {
        "value": [0.0, 0.0],
        "unit": "deg",
        "kind": "estimated",
        "source": "AS-04 optional-module validity fixture; axial thrust line",
    }
    turbine_options = {
        "ram_flow": ("propulsion", "engine", "ram_flow"),
        "ram_jet": ("propulsion", "engine", "ram_jet"),
        "thrust_angles": ("propulsion", "thrust_angles"),
    }
    for name, path in turbine_options.items():
        if not at(turbine_base, path):
            raise AssertionError(f"Avanti must contain its audited optional module for the mask test: {name}")
    turbine_names = list(turbine_options)
    for mask in range(1 << len(turbine_names)):
        enabled = {name for bit, name in enumerate(turbine_names) if mask & (1 << bit)}
        data = deepcopy(turbine_base)
        for name, path in turbine_options.items():
            if name not in enabled:
                remove(data, path)
        cases.append(Case(
            f"turbine-option-mask:{mask:02d}:" + "+".join(sorted(enabled)),
            data, True, True, "v2-optional-turbine",
        ))

    # Schema acceptance is structural. This deliberately valid shape violates a
    # coupled area/geometry equation and must be rejected by the public loader only.
    coupled_area = add("runtime-only:reference-area-coupling", stik, schema_ok=True,
                       loader_ok=False, classification="coupled-runtime-only")
    area = coupled_area["reference"]["wing_area"]["value"]
    coupled_area["reference"]["wing_area"]["value"] = area * 1.1

    # This shape is structurally valid but the declared taildragger capability
    # contradicts its tricycle support points. Zero steering keeps the failure
    # isolated to the coupled topology rule rather than steering orientation.
    inverted_gear = add("runtime-only:all-zero-steering-gear-topology", stik,
                        schema_ok=True, loader_ok=False,
                        classification="coupled-runtime-only")
    inverted_gear["capabilities"]["gear"] = "fixed_taildragger"
    for contact in inverted_gear["landing_gear"]["contacts"]:
        contact["max_steering"]["value"] = 0.0

    # Preserve a compact v1 specimen so compatibility remains testable after all
    # production/electric JSON moves to v2. Legacy unknown root metadata stays legal.
    legacy = read_json(LEGACY_V1)
    if legacy.get("format") != "openrc-aircraft v1":
        raise AssertionError("checked-in legacy fixture must remain v1")
    cases.append(Case("legacy-positive:v1-stik", legacy, True, True, "legacy-v1"))
    legacy_extra = deepcopy(legacy)
    legacy_extra["legacy_test_note"] = {"unknown_but_ignored": [1, 2]}
    cases.append(Case("legacy-permissive:unknown-root-metadata", legacy_extra, True, True, "legacy-v1"))
    return cases


def json_pointer(parts: Any) -> str:
    return "/" + "/".join(str(part).replace("~", "~0").replace("/", "~1") for part in parts)


def schema_errors(data: dict[str, Any], validators: dict[Path, Draft202012Validator],
                  schema_paths: dict[str, Path]) -> list[str]:
    contract = schema_validator(data, validators, schema_paths)
    return sorted(f"{json_pointer(error.absolute_path)}: {error.message}" for error in contract.iter_errors(data))


def run_loader(cases: list[Case], godot: Path, timeout: int, app: Path) -> list[dict[str, Any]]:
    with tempfile.TemporaryDirectory(prefix="openrc-as-schema-v2-") as folder:
        temp = Path(folder)
        input_paths: list[str] = []
        for index, case in enumerate(cases):
            path = temp / f"{index:03d}.json"
            path.write_text(json.dumps(case.data, ensure_ascii=False, allow_nan=False), encoding="utf-8")
            input_paths.append(str(path))
        manifest = temp / "manifest.json"
        manifest.write_text(json.dumps(input_paths, ensure_ascii=False), encoding="utf-8")
        engine_log = temp / "godot.log"
        command = [str(godot), "--headless", "--path", str(app), "--script",
                   str(LOADER_PROBE), "--log-file", str(engine_log), "--", str(manifest)]
        run = subprocess.run(command, cwd=ROOT, text=True, capture_output=True,
                             encoding="utf-8", errors="replace", timeout=timeout, check=False)
        combined = run.stdout + run.stderr
        if engine_log.exists():
            combined += engine_log.read_text(encoding="utf-8", errors="replace")
        if run.returncode != 0:
            raise AssertionError(f"public loader probe exited {run.returncode}:\n{combined}")
        errors = ENGINE_ERROR.findall(combined)
        if errors:
            raise AssertionError(f"Godot emitted engine/script errors {errors}:\n{combined}")
        rows: list[dict[str, Any]] = []
        for line in run.stdout.splitlines():
            if line.startswith("DATA4A "):
                rows.append(json.loads(line.removeprefix("DATA4A ")))
        if [row.get("index") for row in rows] != list(range(len(cases))):
            raise AssertionError(
                f"loader result order/count mismatch: received {len(rows)} rows for {len(cases)} inputs\n{combined}"
            )
        return rows


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def report_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(ROOT).as_posix()
    except ValueError:
        return str(resolved)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=DEFAULT_APP,
                        help="app snapshot to validate (defaults to the repository app/)")
    parser.add_argument("--godot", type=Path,
                        default=Path(os.environ.get("OPENRC_TEST_GODOT", DEFAULT_GODOT)))
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--report", type=Path,
                        default=Path(os.environ["OPENRC_SCHEMA_V2_REPORT"]) if os.environ.get("OPENRC_SCHEMA_V2_REPORT") else None)
    args = parser.parse_args()
    app = args.app if args.app.is_absolute() else (ROOT / args.app).resolve()
    godot = args.godot if args.godot.is_absolute() else (ROOT / args.godot).resolve()
    if not godot.is_file():
        parser.error(f"Godot executable not found: {godot}")
    fleet_dir = app / "data" / "aircraft"
    schema_v1 = app / "data" / "schema" / "openrc-aircraft-v1.schema.json"
    schema_v2 = app / "data" / "schema" / "openrc-aircraft-v2.schema.json"
    contract_spec = app / "data" / "schema" / "aircraft-contract-v2.json"
    contract_gd = app / "physics" / "aircraft_contract.gd"
    loader_gd = app / "physics" / "aircraft_data.gd"
    schema_paths = {"openrc-aircraft v1": schema_v1, "openrc-aircraft v2": schema_v2}
    required_paths = (app / "project.godot", schema_v1, schema_v2, contract_spec,
                      contract_gd, loader_gd, LOADER_PROBE, LEGACY_V1)
    for path in required_paths:
        if not path.is_file():
            parser.error(f"required AS-01 input not found: {path}")
    if not fleet_dir.is_dir():
        parser.error(f"required AS-01 fleet directory not found: {fleet_dir}")

    cases = build_cases(app)
    if len({case.name for case in cases}) != len(cases):
        raise AssertionError("case names must be unique")
    validators: dict[Path, Draft202012Validator] = {}
    schema_rows: list[dict[str, Any]] = []
    for case in cases:
        errors = schema_errors(case.data, validators, schema_paths)
        schema_ok = not errors
        schema_rows.append({
            "name": case.name,
            "classification": case.classification,
            "schema_ok": schema_ok,
            "expected_schema_ok": case.schema_ok,
            "schema_errors": errors[:5],
        })
    loader_rows = run_loader(cases, godot, args.timeout, app)
    results: list[dict[str, Any]] = []
    failures: list[str] = []
    for case, schema_row, loader_row in zip(cases, schema_rows, loader_rows):
        loader_ok = bool(loader_row.get("ok"))
        errors = list(loader_row.get("errors", []))
        row = {
            "name": case.name,
            "classification": case.classification,
            "schema_ok": schema_row["schema_ok"],
            "loader_ok": loader_ok,
            "expected_schema_ok": case.schema_ok,
            "expected_loader_ok": case.loader_ok,
            "loader_errors": errors,
        }
        if schema_row["schema_ok"] != case.schema_ok:
            failures.append(f"{case.name}: schema result {schema_row['schema_ok']} != expected {case.schema_ok}: {schema_row['schema_errors']}")
        if loader_ok != case.loader_ok:
            failures.append(f"{case.name}: loader result {loader_ok} != expected {case.loader_ok}: {errors}")
        if not loader_ok and not errors:
            failures.append(f"{case.name}: loader refusal did not include an actionable error")
        if case.classification == "coupled-runtime-only" and not (schema_row["schema_ok"] and not loader_ok):
            failures.append(f"{case.name}: did not remain a schema-pass/loader-fail coupled-physics counterexample")
        if case.schema_ok != case.loader_ok and case.classification != "coupled-runtime-only":
            failures.append(f"{case.name}: unexpected schema/loader disagreement")
        results.append(row)

    counts = {
        "cases": len(results),
        "schema_loader_agreements": sum(row["schema_ok"] == row["loader_ok"] for row in results),
        "positive_fleet": sum(row["classification"] == "positive" and row["loader_ok"] for row in results),
        "combustion_masks": sum(row["classification"] == "v2-feature-dependency" for row in results),
        "turbine_masks": sum(row["classification"] == "v2-optional-turbine" for row in results),
        "legacy_v1": sum(row["classification"] == "legacy-v1" and row["loader_ok"] for row in results),
        "runtime_only_coupled_cases": sum(row["classification"] == "coupled-runtime-only" and row["schema_ok"] and not row["loader_ok"] for row in results),
    }
    report = {
        "format": "openrc-as-schema-v2-loader-agreement-v1",
        "app": str(app.resolve()),
        "godot": str(godot),
        "counts": counts,
        "failures": failures,
        "cases": results,
        "source_sha256": {
            report_path(path): sha256(path)
            for path in [schema_v1, schema_v2, contract_spec, contract_gd, loader_gd, LOADER_PROBE, Path(__file__), LEGACY_V1,
                         *sorted(fleet_dir.glob("*.json"))]
        },
        "classification_policy": "JSON Schema checks v2 structure; coupled physical relationships remain loader-only. V1 is routed explicitly to its legacy schema/loader branch.",
    }
    if args.report:
        report_file = args.report if args.report.is_absolute() else (ROOT / args.report).resolve()
        report_file.parent.mkdir(parents=True, exist_ok=True)
        report_file.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"counts": counts, "failures": failures, "report": str(args.report) if args.report else None}, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
