#!/usr/bin/env python3
"""Build the NK-3 native stage-evaluator components with the repository's pinned native toolchain.

Reuses research/native-slipstream/build.py (SCons wheel + godot-cpp bootstrap) the way
research/native-math-spike/build.py does. Every output stays under the ignored tmp/native-kernel/:
the library, a runtime-loadable .gdextension descriptor and build-receipt.json.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SHARED_BUILDER = ROOT / "research/native-slipstream/build.py"
SPEC = importlib.util.spec_from_file_location("openrc_locked_gdextension_build", SHARED_BUILDER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load shared GDExtension builder: {SHARED_BUILDER}")
locked = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(locked)

TOOL_ROOT = ROOT / "tmp/native-kernel"
locked.LOCK_PATH = HERE / "toolchain-lock.json"
locked.TOOL_ROOT = TOOL_ROOT
locked.SOURCES = HERE / "src"
NAME = "openrc_native_kernel"
# GDScript sources whose current HEAD arithmetic the port mirrors, operation by operation (identity only:
# the oracle, not this hash, establishes bit identity against whatever app/ holds at run time).
REFERENCE_SOURCES = [
    "app/physics/math3d.gd", "app/physics/ground_terrain.gd", "app/physics/lake_surface.gd",
    "app/physics/ground_wheels.gd", "app/physics/ground_contact.gd", "app/physics/air_data.gd",
    "app/physics/ground_effect.gd", "app/physics/aero.gd", "app/physics/propulsion.gd", "app/physics/dynamics.gd",
    "app/physics/hull_contact.gd", "app/physics/wind_field.gd", "app/sim/environment.gd", "app/sim/flight_session.gd",
    "app/sim/simulation.gd", "app/sim/native_stage.gd", "app/app_state/native_package.gd",
    "app/data/aircraft/jensen_ugly_stik_60.json",
    "app/physics/flaps.gd", "app/physics/wing_polar.gd", "app/physics/aircraft_data.gd",
    "app/physics/wind_config.gd", "app/physics/atmosphere.gd", "app/physics/wind_turbulence.gd",
    "app/physics/wind_spatial_config.gd", "app/physics/wind_spatial_field.gd",
    "app/physics/wind_spatial_presets.gd", "app/physics/wind_thermal_field.gd",
    "app/physics/electric_motor.gd", "app/physics/electric_supply.gd",
    "app/physics/battery/battery_data.gd", "app/physics/battery/pack_ecm.gd",
    "app/physics/rigid_body.gd",
    "app/physics/retractable_gear.gd",
    "app/physics/rotor_coupling.gd",
    "app/physics/slipstream.gd",
    "app/physics/wash_transport.gd",
    "app/physics/fixed_datum_body.gd",
    "app/physics/mass_inventory.gd",
    "app/physics/liquid_fuel.gd",
    "app/physics/turbine.gd",
    "app/physics/wind_aircraft_flow.gd",
    "app/physics/rotorcraft_data.gd",
    "app/physics/glow/carburetor.gd",
    "app/physics/glow/flight.gd",
    "app/physics/glow/four_stroke.gd",
    "app/physics/glow/fuel_feed.gd",
    "app/physics/glow/fuel_mass.gd",
    "app/physics/glow/installation.gd",
    "app/physics/glow/lifecycle.gd",
    "app/physics/glow/operating_point.gd",
    "app/physics/glow/profile.gd",
    "app/physics/glow/propeller.gd",
    "app/physics/glow/source.gd",
    "app/physics/glow/thermal.gd",
    "app/physics/glow/two_stroke.gd",
    "app/physics/glow/vibration.gd",
    "app/physics/rotorcraft/aerodynamic_stage.gd",
    "app/physics/rotorcraft/airframe.gd",
    "app/physics/rotorcraft/drive.gd",
    "app/physics/rotorcraft/dynamic_inflow.gd",
    "app/physics/rotorcraft/electronics.gd",
    "app/physics/rotorcraft/flight_dynamics.gd",
    "app/physics/rotorcraft/geared_coupling.gd",
    "app/physics/rotorcraft/ground_start.gd",
    "app/physics/rotorcraft/hx700_flex_bench.gd",
    "app/physics/rotorcraft/impact_detector.gd",
    "app/physics/rotorcraft/inflow.gd",
    "app/physics/rotorcraft/lifecycle.gd",
    "app/physics/rotorcraft/main_rotor.gd",
    "app/physics/rotorcraft/main_rotor_stage.gd",
    "app/physics/rotorcraft/performance_context.gd",
    "app/physics/rotorcraft/simulation_step_adapter.gd",
    "app/physics/rotorcraft/skid_contact.gd",
    "app/physics/rotorcraft/swash.gd",
    "app/physics/rotorcraft/tail_rotor.gd",
    "app/physics/rotorcraft/trim.gd",
    "app/sim/liquid_fuel_flight.gd",
    "app/sim/helicopter_flight_session.gd",
    "app/sim/vehicle_model.gd",
    "app/sim/native/stage_config.gd",
    "app/sim/native/weather_adapter.gd", "app/sim/native/native_weather.gd",
    "app/sim/native/native_configuration.gd", "app/sim/native/electric_stage_adapter.gd",
    "app/sim/native/liquid_stage_adapter.gd", "app/sim/native/glow_stage_adapter.gd",
    "app/sim/native/helicopter_stage_adapter.gd", "app/sim/native/prescribed_stage_adapter.gd",
    # Tick/event owners and the runtime/data inputs named by the family oracles.
    # Test scripts and synthetic test fixtures stay in each oracle's harness identity.
    "app/sim/aircraft_propulsion_runtime.gd", "app/sim/fuel_sample.gd",
    "app/physics/battery/esc_supervisor.gd", "app/physics/event_step.gd", "app/physics/integrator.gd",
    "app/physics/effective_mass.gd", "app/physics/ground_surfaces.gd", "app/physics/ground_support.gd",
    "app/physics/swirl_loads.gd", "app/physics/wheel_profiles.gd", "app/app_state/aircraft_catalog.gd",
    "app/data/field_loader.gd", "app/data/lake_loader.gd",
    "app/data/fields/default.json", "app/data/fields/lake.json", "app/data/fuels/openrc-fuel-registry.json",
    "app/data/aircraft/f4u_corsair_250.json", "app/data/aircraft/gp_extra_300s_60.json",
    "app/data/aircraft/hx700_electric_3d_experimental.json", "app/data/aircraft/p51d_mustang_120.json",
    "app/data/aircraft/sebart_avanti_s_a200.json", "app/data/aircraft/moonrunner_x99.json",
    "app/data/aircraft/stik_glow_55ax_2t.json", "app/data/aircraft/stik_glow_61fx_2t.json",
    "app/data/aircraft/stik_glow_fs64v_4t.json", "app/data/aircraft/turbo_lumber_evolution.json",
    "app/data/aircraft/xcell_60_research.json",
    "app/data/aircraft/battery/moonrunner_x99_6s_pack.json",
    "app/data/aircraft/battery/turbo_lumber_evolution_4s_pack.json",
    "app/data/batteries/cells/lipo-bak503562-galeotti-v1.json",
    "app/data/batteries/packs/lipo-4s1p-3200-30c-class.json",
    "app/data/batteries/packs/lipo-6s1p-5000-30c-class.json",
    "app/data/glow/extra_61fx_2t.json", "app/data/glow/os_fs_64v_candidate.json",
    "app/data/glow/os_max_55ax_candidate.json", "app/data/glow/os_max_61fx_candidate.json",
    "app/data/glow/os_max_61fx_installed_candidate.json", "app/data/glow/profile_contract.json",
    "app/data/glow/stik_55ax_2t.json", "app/data/glow/stik_61fx_2t.json", "app/data/glow/stik_fs64v_4t.json",
]
LIBM_SYMBOLS = {"sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sqrt", "pow", "exp", "log",
                "sinh", "cosh", "tanh", "fmod", "floor", "sincos"}
# Floating-point policy: NK-1 flags plus the pow shim's asm barrier (no -fno-builtin needed; checked below).
EXTRA_FLAGS = ["-std=c++17"]
# Stage contract identity; must equal nk_kernel.cpp kBackendVersion/kAbi and app/sim/native_stage.gd.
BACKEND_VERSION = "openrc-native-kernel-stage-v2"
ABI_VERSION = 2
RECEIPT_FORMAT = "openrc-native-kernel-receipt"
APP_DESTINATION = ROOT / "app/native/kernel"
APP_DESCRIPTOR = (
    "; NK-3 native stage, installed by research/native-kernel/build.py --install-app.\n"
    "; .gdignore prevents discovery; app/sim/native_stage.gd loads it after receipt checks.\n"
    "[configuration]\n"
    f'entry_symbol = "{NAME}_library_init"\n'
    'compatibility_minimum = "4.7"\n'
    "reloadable = false\n\n"
    "[libraries]\n"
    f'linux.x86_64 = "res://native/kernel/lib{NAME}.so"\n'
)
# Oracle runs an install must cite: same binary, same mirrored sources, verdict pass (results under TOOL_ROOT).
VERIFICATIONS = {
    "stage_oracle": "stage-[0-9]*.json", "trajectory": "trajectory-[0-9]*.json",
    "propeller": "propeller-[0-9]*.json", "electric": "electric-[0-9]*.json",
    "electric_stage": "electric-stage-[0-9]*.json", "liquid": "liquid-[0-9]*.json",
    "liquid_stage": "liquid-stage-[0-9]*.json", "glow": "glow-[0-9]*.json",
    "glow_stage": "glow-stage-[0-9]*.json", "helicopter": "helicopter-[0-9]*.json",
    "helicopter_stage": "helicopter-stage-[0-9]*.json", "weather": "weather-[0-9]*.json",
    "weather_stage": "weather-stage-[0-9]*.json", "wake": "wake-[0-9]*.json",
    "wake_spatial": "wake-spatial-[0-9]*.json", "gear": "gear-[0-9]*.json",
    "prescribed_stage": "prescribed-stage-[0-9]*.json", "legacy_ground": "legacy-ground-[0-9]*.json",
    "negative_control": "stage_mutant-[0-9]*.json",
}
ORACLE_SCRIPTS = {
    "stage_oracle": "stage_oracle.gd", "trajectory": "trajectory.gd",
    **{name: name + "_oracle.gd" for name in (
        "propeller", "electric", "electric_stage", "liquid", "liquid_stage", "glow", "glow_stage",
        "helicopter", "helicopter_stage", "weather", "weather_stage", "wake", "wake_spatial", "gear",
        "prescribed_stage", "legacy_ground")},
    "negative_control": "stage_oracle.gd",
}
ORACLE_ARGUMENTS = {
    "stage_oracle": "--states 12000", "negative_control": "--mutant --states 12000",
    "trajectory": "--option ticks=960 --option skip-timing=true",
    "propeller": "--states 1200", "electric": "--states 1000", "liquid": "--states 1000",
    "glow": "--states 1000", "wake": "--states 1000", "wake_spatial": "--states 1200",
    "gear": "--states 1000", "weather": "--states 12000", "helicopter": "--states 10000",
    "electric_stage": "--states 500 --option ticks=64", "liquid_stage": "--states 500 --option ticks=64",
    "glow_stage": "--states 500 --option ticks=64", "helicopter_stage": "--states 715 --option ticks=64",
    "weather_stage": "--states 12000 --option ticks=64 --option include-spatial=true",
    "prescribed_stage": "--states 250 --option ticks=64", "legacy_ground": "--states 1200 --option ticks=64",
}
MIN_TRAJECTORY_TICKS = 960
MIN_STAGE_STATES = 10000
MIN_COMPONENT_STATES = 1000
MIN_CASE_STATES = 64
MIN_FAMILY_TICKS = 64
WEATHER_PRESETS = {
    "calm", "steady", "crosswind", "gusty", "updraft", "turbulent", "hot-high", "cool-dense",
    "gentle-practice", "standard-column", "spatial-realistic-v1", "spatial-light-breeze-v1",
    "spatial-crosswind-v1", "spatial-gusty-v1", "spatial-shear-v1", "spatial-thermal-soaring-v2",
    "spatial-strong-wind-v1",
}
FAMILY_WEATHER = {"calm", "gusty", "turbulent", "hot-high", "standard-column", "spatial-gusty-v1",
                  "spatial-thermal-soaring-v2"}
ELECTRIC_IDS = {"turbo-lumber-evolution", "moonrunner-x99"}
LIQUID_IDS = {"p51d-mustang-120", "f4u-corsair-250", "sebart-avanti-s-a200-p100rx"}
GLOW_IDS = {"stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "gp-extra-300s-60"}
PRESCRIBED_MODES = {"shaft-split", "shaft-coupled", "shaft-split-transport", "shaft-coupled-transport",
                    "turbine-sampled", "turbine-continuous"}
TRAJECTORY_CASES = {"trim", "runway", "maneuver", "takeoff", "lake"}
# trajectory.gd injects each fault after 1,200 healthy ticks; its report records the expected rejection branch.
FAULT_REASONS = {
    "state_nan_velocity": "step rejected: current state ",
    "continuous_nan_wheel": "step rejected: input or auxiliary state ",
    "overflow_velocity": "step rejected: pre-step produced ",
    "overflow_rates": "step rejected: pre-step produced ",
    "buried_state": "step rejected: joint stage evaluation ",
}
PHASE_TICKS = 1200
FALLBACK_TICKS = 960


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def libm_imports(binary: Path) -> list[str]:
    """Undefined libm symbols with their glibc symbol versions (objdump -T)."""
    output = subprocess.run(["objdump", "-T", str(binary)], check=True, text=True, capture_output=True).stdout
    found = []
    for line in output.splitlines():
        parts = line.split()
        if "*UND*" in parts and parts[-1] in LIBM_SYMBOLS:
            found.append(f"{parts[-1]}@{parts[-2].strip('()')}")
    return sorted(found)


def source_digest() -> str:
    digest = hashlib.sha256()
    for path in sorted([*locked.SOURCES.glob("*.cpp"), *locked.SOURCES.glob("*.hpp")]):
        digest.update(path.name.encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def mirrored_sources() -> dict[str, str]:
    return {name: sha256_file(ROOT / name) for name in REFERENCE_SOURCES}


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _positive(value: object, minimum: int = 1) -> bool:
    return type(value) is int and value >= minimum


def _named(rows: list, names: set[str]) -> dict[str, dict]:
    _require(isinstance(rows, list) and all(isinstance(row, dict) and isinstance(row.get("name"), str)
                                          for row in rows), "malformed coverage cases")
    found = {row["name"]: row for row in rows}
    _require(len(found) == len(rows) and set(found) == names, "missing, repeated, or scoped coverage cases")
    return found


def _counts(components: dict, names: tuple[str, ...], expected: int) -> None:
    for name in names:
        _require(components.get(name, {}).get("count") == expected,
                 "missing or incomplete comparisons: " + name)


def _complete_tapes(rows: dict[str, dict], component: str, components: dict,
                    minimum: int = MIN_FAMILY_TICKS) -> None:
    ticks = 0
    for name, row in rows.items():
        count = row.get("ticks_run")
        _require(_positive(count, minimum) and type(row.get("requested_ticks")) is int and row["requested_ticks"] == count
                 and row.get("complete") is True and row.get("first_divergence") == -1
                 and _positive(row.get("native_context_calls"), count)
                 and _positive(row.get("native_stage_calls"), 4 * count),
                 "incomplete, divergent or uncovered tape: " + name)
        ticks += count + 1  # Each oracle compares the initial state as well as each tick.
    _counts(components, (component,), ticks)


def _family_stage_verification(key: str, data: dict, components: dict) -> None:
    family = key.removesuffix("_stage")
    ids = {"electric": ELECTRIC_IDS, "liquid": LIQUID_IDS, "glow": GLOW_IDS}[family]
    bases = ({name + "/" + battery for name in ids for battery in ("ideal", "pack")}
             if family == "electric" else ids)
    expected = {base + "/" + weather for base in bases for weather in FAMILY_WEATHER}
    evidence = data[key]
    cases = _named(evidence["cases"], expected)
    for name, row in cases.items():
        _require(_positive(row["states"], MIN_CASE_STATES) and _positive(row["finite"]) and _positive(row["refused"])
                 and row["finite"] + row["refused"] == row["states"], "missing finite/refused stages: " + name)
        if family == "electric":
            _require((row["battery_size"] == 0 if "/ideal/" in name else _positive(row["battery_size"]))
                     and row["wheel_count"] == (0 if name.startswith("moonrunner-x99/") else 3),
                     "wrong electric state layout: " + name)
        elif family == "liquid":
            _require(row["family"] == ("turbine" if name.startswith("sebart-") else "gas")
                     and all(_positive(row[field]) for field in ("gear_down", "gear_partial", "gear_up", "source_off")),
                     "missing liquid source/gear conditions: " + name)
        else:
            _require(row["family"] == ("glow_4t" if name.startswith("stik-glow-fs64v-4t/") else "glow_2t"),
                     "missing glow source family: " + name)
    states = sum(row["states"] for row in cases.values())
    _require(states >= MIN_STAGE_STATES, "insufficient actual " + family + " stage samples")
    if family == "electric":
        _counts(components, ("stage_shape",), states)
        shaped = components["stage_bytes"]["count"]
        _require(sum(row["finite"] for row in cases.values()) <= shaped <= states, "missing shaped electric stages")
        _counts(components, ("stage_loads", "stage_derivative", "stage_rotor_momentum"), shaped)
        _require(components["electric_stage_snapshot_refusal"]["count"] >= 34, "missing electric snapshot guards")
        trajectory_names = {"turbo-lumber-evolution/ideal/calm", "turbo-lumber-evolution/pack/turbulent",
                            "moonrunner-x99/ideal/hot-high", "moonrunner-x99/pack/spatial-thermal-soaring-v2"}
        tapes = _named(evidence["trajectories"], trajectory_names)
        _complete_tapes(tapes, "electric_trajectory_tick", components)
        # Event tapes are required separately; nominal exactness cannot establish supervisor behavior.
        event_names = ({name + "/" + battery + "/rotor-stop-restart" for name in ids for battery in ("ideal", "pack")}
                       | {name + "/pack/" + event for name in ids for event in ("battery-exhaustion", "esc-soft-cut")})
        events = _named(evidence["events"], event_names)
        for name, row in events.items():
            _require(row.get("event_observed") is True and row.get("cut_ok") is True
                     and _positive(row.get("event_tick")) and type(row.get("ticks_run")) is int
                     and row["event_tick"] <= row["ticks_run"] and isinstance(row.get("commands"), list)
                     and len(row["commands"]) > 0, "electric event or cut was not observed: " + name)
            if not name.endswith("/esc-soft-cut"):
                _require(row.get("restart_ok") is True and row.get("event_count") == 1,
                         "electric restart or event count was not established: " + name)
        not_applicable = evidence["event_not_applicable"]
        _require(isinstance(not_applicable, list) and len(not_applicable) == len(ids)
                 and {row["aircraft"] for row in not_applicable} == ids
                 and all(row["battery"] == "ideal" and set(row["events"]) == {"battery-exhaustion", "esc-soft-cut"}
                         and isinstance(row["reason"], str) and bool(row["reason"].strip()) for row in not_applicable),
                 "ideal fixed-voltage event applicability is missing")
        _complete_tapes(events, "electric_event_tick", components)
    elif family == "liquid":
        _counts(components, ("liquid_stage_keys", "liquid_stage_bytes", "liquid_stage_loads",
                              "liquid_stage_body_derivative", "liquid_stage_derivative", "liquid_stage_rotor_momentum"), states)
        _require(components["liquid_snapshot_refusal"]["count"] >= 30, "missing liquid snapshot guards")
        for prefix in ("liquid_initial_stage", "liquid_forced_preview", "liquid_nan_time_stage"):
            _require(all(components[prefix + "_" + suffix]["count"] > 0 for suffix in
                         ("keys", "bytes", "loads", "body_derivative", "derivative", "rotor_momentum")),
                     "missing liquid preview or time comparison")
        names = {name + "/" + suffix for name in ids for suffix in
                 ("runway/calm", "trim/spatial-thermal-soaring-v2", "trim/calm/exhaustion")}
        tapes = _named(evidence["trajectories"], names)
        for name, row in tapes.items():
            exhausted = name.endswith("/exhaustion")
            _require(row["exhaustion_expected"] is exhausted and row["exhaustion_observed"] is exhausted,
                     "liquid fuel exhaustion not established: " + name)
        _complete_tapes(tapes, "liquid_trajectory_tick", components)
    else:
        _counts(components, ("glow_stage_shape",), states)
        shaped = components["glow_stage_bytes"]["count"]
        _require(sum(row["finite"] for row in cases.values()) <= shaped <= states, "missing shaped glow stages")
        _counts(components, ("glow_stage_loads", "glow_stage_body", "glow_stage_derivative", "glow_stage_rotor"), shaped)
        _require(components["glow_stage_snapshot_refusal"]["count"] >= 31
                 and components["glow_event_command"]["count"] == 2 * len(ids), "missing glow snapshot or command guards")
        nominal = {"stik-glow-61fx-2t/calm/nominal", "stik-glow-55ax-2t/turbulent/nominal",
                   "stik-glow-fs64v-4t/hot-high/nominal", "gp-extra-300s-60/spatial-thermal-soaring-v2/nominal"}
        names = nominal | {name + "/calm/" + event for name in ids
                           for event in ("exhaustion", "overheat", "stall", "cut_restart")}
        tapes = _named(evidence["trajectories"], names)
        for name, row in tapes.items():
            event = name.rsplit("/", 1)[1]
            _require(row["event_kind"] == event and isinstance(row["located"], list), "missing glow event metadata")
            if event == "exhaustion":
                _require({"fuel_exhausted", "glow_stopped"} <= set(row["located"]), "missing fuel exhaustion: " + name)
            elif event in {"overheat", "stall"}:
                _require("glow_stopped" in row["located"], "missing glow stop: " + name)
            elif event == "cut_restart":
                _require(row["cut_ok"] is True and row["restart_ok"] is True, "missing glow cut/restart: " + name)
        _complete_tapes(tapes, "glow_trajectory_tick", components)


def _helicopter_verification(key: str, data: dict, components: dict) -> None:
    weather = {"calm", "steady", "crosswind", "gusty", "updraft", "hot-high", "cool-dense"}
    starts = {"airborne", "ground"}
    coverage = data["coverage"]
    total = 0
    for start in starts:
        for scenario in weather:
            row = coverage["helicopter_" + start + "_" + scenario]
            _require(_positive(row["states"], MIN_CASE_STATES) and all(_positive(row[name]) for name in
                     ("accepted", "direct", "trainer", "normal", "idle_up", "near_stop", "running", "stopped")),
                     "missing helicopter control/drive coverage")
            if start == "ground":
                _require(_positive(row["contact"]) and _positive(row["unloaded"]), "missing helicopter skid states")
            total += row["states"]
    _require(total >= MIN_STAGE_STATES, "insufficient helicopter stage samples")
    for prefix in ("helicopter_stage_" if key == "helicopter_stage" else "helicopter_",):
        _require(components["helicopter_stage_validity"]["count"] >= total, "missing helicopter validity comparisons")
        accepted = coverage["helicopter"]["accepted"]
        _counts(components, tuple(prefix + name for name in ("loads", "body_derivative", "derivative", "rotor_momentum")), accepted)
        if key == "helicopter_stage": _counts(components, ("helicopter_stage_bytes",), accepted)
    refusals = data["reference_start_refusals"]
    _require(isinstance(refusals, list) and len(refusals) == 2 and {row["start"] for row in refusals} == starts
             and all(row["weather"] == "hot-high" and "hover trim line search" in row["reason"]
                     and row["component_seed"] == "calm reference reset; no hot-high flight start" for row in refusals),
             "unqualified helicopter hot-high reset")
    if key != "helicopter_stage": return
    evidence = data[key]
    cases = evidence["cases"]
    _require(isinstance(cases, list) and len(cases) == 14
             and {(row["start"], row["weather"]) for row in cases} == {(s, w) for s in starts for w in weather},
             "missing helicopter start/weather matrix")
    for row in cases:
        _require(row["states"] == coverage["helicopter_" + row["start"] + "_" + row["weather"]]["states"]
                 and row["continuous_size"] == (14 if row["start"] == "ground" else 6)
                 and row["seeded_only"] is (row["weather"] == "hot-high"), "invalid helicopter case layout")
    names = {s + "/" + w for s in starts for w in weather - {"hot-high"}} | {"airborne/crosswind/rotor-stop"}
    tapes = _named(evidence["trajectories"], names)
    for name, row in tapes.items():
        stop = name.endswith("/rotor-stop")
        _require(row["stop_expected"] is stop and row["stop_observed"] is stop, "missing helicopter rotor stop")
        if not stop:
            _require(row["changed_mode"] is True and row["changed_trainer"] is True and row["held_drive"] is True,
                     "missing helicopter control events")
    _complete_tapes(tapes, "helicopter_trajectory_tick", components)
    replay_rows = evidence["replays"]
    _require(isinstance(replay_rows, list) and len(replay_rows) == 2
             and {row["start"] for row in replay_rows} == starts, "missing helicopter checkpoint replay")
    replays = {row["start"]: row for row in replay_rows}
    _require(all(_positive(row["checkpoint_tick"]) for row in replay_rows), "missing helicopter checkpoint")
    _complete_tapes(replays, "helicopter_replay_tick", components, MIN_FAMILY_TICKS // 2)
    _require(components["helicopter_weather_refusal"]["count"] >= 8, "missing helicopter weather guards")


def _weather_verification(key: str, data: dict, components: dict) -> None:
    if key == "weather":
        evidence = data["weather"]
        _require(set(evidence["presets"]) == WEATHER_PRESETS and len(evidence["presets"]) == len(WEATHER_PRESETS),
                 "missing weather presets")
        scenarios = WEATHER_PRESETS | {"direction-0.0", "direction-45.0", "direction-90.0", "direction-135.0",
                     "direction-180.0", "direction-270.0", "direction-360.0", "column-and-ou",
                     "warm-uniform-atmosphere", "spatial-and-column"}
        _require(set(evidence["scenarios"]) == scenarios and len(evidence["scenarios"]) == len(scenarios),
                 "missing weather scenarios")
        refusals = evidence["refusals"]
        refusal_names = {"unknown_key", "wrong_array_type", "nonfinite_speed", "period_before_duration",
                         "wrong_boolean_type", "nonfinite_temperature", "nonpositive_temperature",
                         "wrong_temperature_type", "spatial_ou_conflict", "incomplete_mode", "nonfinite_mode",
                         "invalid_gust_maximum", "invalid_ground_extension"}
        _require(set(refusals) == refusal_names and all(row.get("refused") is True and row.get("cleared") is True
                 and isinstance(row.get("error"), str) and row["error"] for row in refusals.values()),
                 "missing weather refusal or stale-state guards")
        row = data["coverage"]["weather"]
        _require(_positive(row["point_queries"], MIN_STAGE_STATES) and _positive(row["air_queries"])
                 and _positive(row["real_ou_windows"]) and _positive(row["thermal_cell_samples"]),
                 "insufficient weather, OU or thermal samples")
        _counts(components, ("weather_wind",), row["point_queries"])
        _counts(components, ("weather_atmosphere", "weather_temperature"), row["air_queries"])
        _require(components["weather_refusal"]["count"] >= 13 and components["weather_spatial_provider_guard"]["count"] >= 1,
                 "missing weather guard comparisons")
        return
    evidence = data["weather_stage"]
    names = WEATHER_PRESETS | {"custom-noncardinal", "custom-column-and-ou", "custom-spatial-column"}
    _require(evidence["include_spatial"] is True and evidence["skipped_spatial"] == []
             and set(evidence["scenarios"]) == names and len(evidence["scenarios"]) == len(names)
             and set(evidence["scenario_coverage"]) == names, "scoped or incomplete weather-stage scenarios")
    cases = evidence["scenario_coverage"]
    for name, row in cases.items():
        _require(_positive(row["states"], MIN_CASE_STATES) and _positive(row["finite_stages"]), "missing weather stage: " + name)
        if name.startswith("spatial-") or name == "custom-spatial-column":
            _require(_positive(row["finite_spatial_flows"]) and _positive(row["spatial_gradient_stages"]),
                     "missing nonuniform weather stage: " + name)
    total = sum(row["states"] for row in cases.values())
    aggregate = data["coverage"]["weather_stage"]
    _require(total >= MIN_STAGE_STATES and aggregate["states"] == total
             and all(_positive(aggregate[name]) for name in ("malformed", "real_ou_window_states",
                     "finite_spatial_flows", "spatial_gradient_stages", "spatial_domain_refusals")),
             "incomplete weather-stage samples")
    _require(components["stage_shape"]["count"] >= total and components["weather_provider_guard"]["count"] >= 1
             and components["weather_spatial_component_refusal"]["count"] >= 1, "missing weather stage guards")
    shaped = components["stage_bytes"]["count"]
    _require(shaped >= aggregate["finite_shaped"], "missing finite weather stage")
    _counts(components, ("stage_derivative", "stage_loads", "stage_rotor_momentum"), shaped)
    names = {"active-gust", "spatial-active-gust", "spatial-active-thermal", "standard-column", "turbulent"} | {
        name for name in WEATHER_PRESETS if name.startswith("spatial-")}
    tapes = evidence["trajectories"]
    _require(isinstance(tapes, dict) and set(tapes) == names, "missing weather trajectories")
    _complete_tapes(tapes, "weather_trajectory_tick", components)


def _route_tapes(rows: dict[str, dict], component: str, components: dict, contact: bool = False) -> None:
    ticks = 0
    for name, row in rows.items():
        count = row.get("ticks_run")
        _require(_positive(count, MIN_FAMILY_TICKS) and type(row.get("requested_ticks")) is int
                 and row["requested_ticks"] == count and row.get("complete") is True
                 and row.get("correct_route") is True and row.get("restored") is True
                 and _positive(row.get("native_context_calls"), count)
                 and _positive(row.get("native_stage_calls"), 4 * count)
                 and (not contact or _positive(row.get("contact_ticks"))),
                 "incomplete native callback ownership tape: " + name)
        ticks += count + 1
    _counts(components, (component,), ticks)


def _legacy_ground_verification(data: dict, components: dict) -> None:
    ids = {"jensen-das-ugly-stik-60", "gp-extra-300s-60"}
    bases = {name + "/stock" for name in ids} | {"jensen-das-ugly-stik-60/no-stiction",
                                                   "jensen-das-ugly-stik-60/24-contacts"}
    modes = {"flat", "flat-surfaces", "lake"}
    cases = _named(data["legacy_ground"]["cases"], {base + "/" + mode for base in bases for mode in modes})
    for name, row in cases.items():
        aircraft, variant, terrain = name.split("/")
        anchors = variant != "no-stiction"
        _require(row["aircraft"] == aircraft and row["variant"] == variant and row["mode"] == terrain
                 and row["has_anchors"] is anchors and _positive(row["contacts"])
                 and (variant != "24-contacts" or row["contacts"] == 24)
                 and _positive(row["states"], MIN_COMPONENT_STATES), "missing legacy gear case: " + name)
        coverage = row["coverage"]
        _require(all(_positive(coverage[field]) for field in ("clear", "loaded", "sliding", "malformed"))
                 and (not anchors or _positive(coverage["stuck"]))
                 and (terrain != "lake" or _positive(coverage["lake_slope"]))
                 and (terrain != "lake" or not anchors or _positive(coverage["partial_anchors"])),
                 "missing legacy ground branches: " + name)
    states = sum(row["states"] for row in cases.values())
    _require(states >= MIN_STAGE_STATES, "insufficient legacy ground samples")
    _counts(components, ("legacy_ground_loads",), states)
    edges = data["legacy_ground"]["edge_cases"]
    expected_edges = {name + "/" + edge: size for name in ids for edge, size in
                      (("invalid_surface", 1), ("invalid_lake", 1), ("empty_gear", 0), ("empty_gear_flat", 0))}
    _require(isinstance(edges, dict) and edges == expected_edges
             and all(type(value) is int for value in edges.values()), "missing legacy ground boundary cases")
    _counts(components, ("legacy_ground_edges",), len(expected_edges))
    tapes = _named(data["legacy_ground"]["trajectories"], {mode + "/" + str(count) + "-contacts"
                   for mode in ("flat", "lake") for count in (3, 24)})
    for name, row in tapes.items():
        mode, count = name.split("/")
        expected_contacts = int(count.removesuffix("-contacts"))
        _require(row["mode"] == mode and type(row["contacts"]) is int and row["contacts"] == expected_contacts
                 and type(row["anchor_values"]) is int and row["anchor_values"] == 3 * expected_contacts,
                 "missing full legacy contact anchors: " + name)
    _route_tapes(tapes, "legacy_ground_tape_tick", components, contact=True)


def _prescribed_stage_verification(data: dict, components: dict) -> None:
    evidence = data["prescribed_stage"]
    cases = _named(evidence["cases"], {mode + "/" + weather for mode in PRESCRIBED_MODES for weather in FAMILY_WEATHER})
    for name, row in cases.items():
        _require(_positive(row["states"], MIN_CASE_STATES) and _positive(row["finite"]) and _positive(row["refused"])
                 and row["finite"] + row["refused"] == row["states"], "incomplete prescribed stage case: " + name)
    states = sum(row["states"] for row in cases.values())
    _require(states >= MIN_STAGE_STATES and data["coverage"]["prescribed_stage"]["states"] == states,
             "insufficient prescribed stage samples")
    _counts(components, ("stage_shape",), states)
    shaped = components["stage_bytes"]["count"]
    _require(sum(row["finite"] for row in cases.values()) <= shaped <= states, "missing prescribed stage bytes")
    _counts(components, ("stage_loads", "stage_derivative", "stage_rotor_momentum"), shaped)
    trajectories = _named(evidence["trajectories"], {mode + "/calm" for mode in PRESCRIBED_MODES})
    _complete_tapes(trajectories, "prescribed_trajectory_tick", components)
    events = _named(evidence["events"], {mode + "/power-cut-restart" for mode in PRESCRIBED_MODES})
    for name, row in events.items():
        commands = row["commands"]
        _require(row["event_observed"] is True and row["cut_ok"] is True and row["restart_ok"] is True
                 and _positive(row["event_tick"]) and row["event_tick"] <= row["ticks_run"]
                 and isinstance(commands, list) and len(commands) == 3
                 and all(command.get("engine_running") is expected for command, expected in
                         zip(commands, (True, False, True)))
                 and all(type(command.get("tick")) is int for command in commands)
                 and [command["tick"] for command in commands] == [0, 1, 3],
                 "missing prescribed source cut/restart: " + name)
        expected_seed = ("stopped boundary; hot cutoff has no prescribed law"
                         if name.startswith("turbine-continuous/") else "running source at 0.5 rpm")
        _require(row["seed"] == expected_seed, "incorrect prescribed cutoff applicability: " + name)
    _complete_tapes(events, "prescribed_event_tick", components)
    callback_names = {"legacy-no-gear", "shaft-split-no-gear", "shaft-split-no-gear-transport"}
    _route_tapes(_named(evidence["callback_routes"], callback_names), "prescribed_callback_tick", components)
    previews = _named(evidence["previews"], {mode + "/" + weather for mode in
        ("shaft-coupled", "shaft-coupled-transport") for weather in ("calm", "turbulent", "spatial-thermal-soaring-v2")})
    _require(all(row["present"] is True and row["no_time_ok"] is True and row["identical"] is True
                 and row["initial_body_would_capture"] is True and row["initial_context_accepted"] is True
                 for row in previews.values()), "missing engine-off prescribed previews")
    _counts(components, tuple("prescribed_preview_" + key for key in
            ("presence", "loads", "derivative", "rotor_momentum", "bytes", "nan_time", "empty_body")), len(previews))
    _counts(components, ("prescribed_preview_sampler_valid",), 2)
    _counts(components, ("prescribed_preview_sampler_delta",), 6)
    refusals = evidence["refusals"]
    _require(isinstance(refusals, list) and all(isinstance(row, dict) and row.get("refused") is True for row in refusals),
             "missing prescribed snapshot refusals")
    pairs = {(row["mode"], row["name"]) for row in refusals}
    expected = {(mode, field) for mode in PRESCRIBED_MODES for field in
                ("source_mismatch", "mode", "extra_key", "unregistered_source_on_both_sides", "rotor_capability")}
    expected |= {(mode, "inverse") for mode in ("shaft-coupled", "shaft-coupled-transport")}
    _require(len(pairs) == len(refusals) and pairs >= expected, "incomplete prescribed snapshot refusals")
    _counts(components, ("prescribed_snapshot_refusal",), len(refusals))
    transitions = _named(evidence["shaft_transitions"], {"gearless-split-coupled-split"})
    transition = transitions["gearless-split-coupled-split"]
    _require(all(transition[field] is True for field in ("complete", "initial_body_owned", "coupled_selected",
             "coupled_callbacks_restored", "coupled_reset", "coupled_reinstalled", "split_selected",
             "split_callbacks_restored", "split_reset", "split_reinstalled", "uninstall_restored")),
             "incomplete gearless shaft ownership transition")
    _counts(components, ("prescribed_transition_callbacks",), 2)
    _complete_tapes({"coupled": transition["coupled_tape"], "split": transition["split_tape"]},
                    "prescribed_transition_tick", components)


def _extended_verification(key: str, data: dict, components: dict) -> str:
    """Qualify actual case matrices, comparisons and events, not requested counts or a PASS label."""
    try:
        _require(data["format"] == "openrc-nk3-" + key.replace("_", "-") + "-oracle v1"
                 if key != "gear" else data["format"] == "openrc-nk3-gear-hull-oracle v1",
                 "wrong oracle format")
        coverage = data["coverage"]
        if key == "propeller":
            ids = ELECTRIC_IDS | (LIQUID_IDS - {"sebart-avanti-s-a200-p100rx"}) | {"jensen-das-ugly-stik-60"}
            _require(set(coverage) == {"propeller_" + name for name in ids}, "incomplete propeller catalog")
            accepted = sum(row["states"] for row in coverage.values())
            _require(all(_positive(row["states"], MIN_COMPONENT_STATES) for row in coverage.values()),
                     "insufficient propeller samples")
            _counts(components, ("propeller_velocity", "propeller_thrust_torque", "propeller_loads",
                                  "propeller_rotor", "propeller_normal", "propeller_pfactor"), accepted)
            _require(components["propeller_flow_validity"]["count"] >= accepted, "missing propeller validity checks")
        elif key == "electric":
            real = {name + "/" + battery for name in ELECTRIC_IDS for battery in ("ideal", "pack")}
            synthetic = {"synthetic_ocv", "synthetic_ecm_0_branches", "synthetic_ecm_2_branches"}
            normal = _named(data["electric_cases"], real | synthetic)
            coupled = _named(data["electric_coupled_cases"], real)
            for rows in (normal, coupled):
                for row in rows.values():
                    _require(_positive(row["states"], MIN_COMPONENT_STATES) and _positive(row["accepted"])
                             and _positive(row["rejected"]) and row["accepted"] + row["rejected"] == row["states"],
                             "electric samples omit valid or rejected states")
            for name, row in normal.items():
                kind = ("fixed_voltage" if name.endswith("/ideal") else "ocv_resistance"
                        if name == "synthetic_ocv" else "pack_ecm")
                _require(row["kind"] == kind, "missing electric supply law: " + name)
            for row in coupled.values():
                _require(all(_positive(row[field]) for field in
                             ("locked", "forward_breakaway", "reverse_refused", "negative_trial")),
                         "electric rotor lock, reverse or breakaway was not exercised")
            for prefix, rows, values in (("electric", normal, ("electric_values", "electric_rates")),
                                          ("electric_coupled", coupled, ("electric_coupled_values", "electric_coupled_battery_rates"))):
                _counts(components, (prefix + "_validity",), sum(row["states"] for row in rows.values()))
                _counts(components, values, sum(row["accepted"] for row in rows.values()))
            _require(components["electric_coupled_guard_validity"]["count"] >= 72
                     and components["electric_coupled_guard_values"]["count"] > 0
                     and components["electric_coupled_guard_rates"]["count"] > 0,
                     "electric coupling guard comparisons are missing")
        elif key in {"liquid", "glow"}:
            ids = LIQUID_IDS if key == "liquid" else GLOW_IDS
            rows = _named(data[key + "_cases"], ids)
            kinds = {"liquid": {"p51d-mustang-120": "gas", "f4u-corsair-250": "gas",
                                  "sebart-avanti-s-a200-p100rx": "turbine"},
                     "glow": {name: "glow_4t" if name == "stik-glow-fs64v-4t" else "glow_2t" for name in GLOW_IDS}}[key]
            for name, row in rows.items():
                _require(_positive(row["states"], MIN_COMPONENT_STATES) and row["family"] == kinds[name]
                         and _positive(row["resources"]), "missing source family or samples: " + name)
                for pair in (("mass_accepted", "mass_rejected"), ("source_accepted", "source_rejected")):
                    _require(all(_positive(row[field]) for field in pair)
                             and sum(row[field] for field in pair) == row["states"], "missing source/mass cases: " + name)
                if key == "glow":
                    _require(_positive(row["blade_accepted"]) and _positive(row["blade_rejected"])
                             and row["blade_accepted"] + row["blade_rejected"] == row["states"],
                             "missing glow blade cases: " + name)
            states = sum(row["states"] for row in rows.values())
            _counts(components, (key + "_mass_validity",), states)
            _counts(components, (key + "_mass_values",), sum(row["mass_accepted"] for row in rows.values()))
            if key == "liquid":
                gas = [row for row in rows.values() if row["family"] == "gas"]
                turbine = [row for row in rows.values() if row["family"] == "turbine"]
                _counts(components, ("liquid_gas_laws", "liquid_gas_coupling_validity"), sum(row["states"] for row in gas))
                _counts(components, ("liquid_gas_coupling_values", "liquid_gas_body_derivative"), sum(row["source_accepted"] for row in gas))
                _counts(components, ("liquid_turbine_validity",), sum(row["states"] for row in turbine))
                _counts(components, ("liquid_turbine_values",), sum(row["source_accepted"] for row in turbine))
            else:
                for prefix in ("source", "blade"):
                    _counts(components, ("glow_" + prefix + "_validity",), states)
                    _counts(components, ("glow_" + prefix + "_values",), sum(row[prefix + "_accepted"] for row in rows.values()))
                _counts(components, ("glow_unit_validity",), states)
                _require(components["glow_unit_flow"]["count"] > 0, "missing glow unit fuel flow")
                _counts(components, ("glow_body_derivative",), sum(row["mass_accepted"] for row in rows.values()))
                feed = _named(data["glow_feed_cases"], (GLOW_IDS - {"gp-extra-300s-60"}) | {"synthetic_pickup"})
                for name, row in feed.items():
                    _require(_positive(row["states"], MIN_COMPONENT_STATES) and _positive(row["context_accepted"])
                             and _positive(row["context_rejected"]) and _positive(row["zero_factor"])
                             and row["context_accepted"] + row["context_rejected"] == row["states"]
                             and row["pickup"] is (name == "synthetic_pickup"), "incomplete glow feed: " + name)
                _counts(components, ("glow_feed_context_validity",), sum(row["states"] for row in feed.values()))
                _counts(components, ("glow_feed_context", "glow_feed_factor"), sum(row["context_accepted"] for row in feed.values()))
                multi = data["glow_multi_mass"]
                _require(multi["resources"] == 2 and _positive(multi["states"], MIN_COMPONENT_STATES)
                         and _positive(multi["accepted"]) and _positive(multi["rejected"])
                         and multi["accepted"] + multi["rejected"] == multi["states"], "missing two-resource glow mass")
                _counts(components, ("glow_multi_mass_validity",), multi["states"])
                _counts(components, ("glow_multi_mass_values", "glow_multi_body_derivative"), multi["accepted"])
        elif key == "legacy_ground":
            _legacy_ground_verification(data, components)
        elif key == "prescribed_stage":
            _prescribed_stage_verification(data, components)
        elif key in {"electric_stage", "liquid_stage", "glow_stage"}:
            _family_stage_verification(key, data, components)
        elif key in {"helicopter", "helicopter_stage"}:
            _helicopter_verification(key, data, components)
        elif key in {"weather", "weather_stage"}:
            _weather_verification(key, data, components)
        elif key == "wake":
            names = {"f4u-corsair-250", "p51d-mustang-120", "gp-extra-300s-60", "manufactured_legacy",
                     "manufactured_smooth", "manufactured_smooth_swirl", "manufactured_transport"}
            _require(set(coverage) == {"wake_" + name for name in names}, "incomplete wake models")
            for row in coverage.values():
                _require(_positive(row["states"], MIN_COMPONENT_STATES) and all(_positive(row[name]) for name in
                         ("held_wake", "hub_delta", "nonzero_load", "reverse_flow", "stopped")), "incomplete wake branches")
            _require(_positive(coverage["wake_manufactured_transport"].get("transport")), "missing transported wake")
            _counts(components, ("wake_loads", "wake_state"), sum(row["states"] for row in coverage.values()))
            _counts(components, ("wash_derivative", "wash_target"), coverage["wake_manufactured_transport"]["states"])
            _require(components["wake_reverse_weight"]["count"] > 0, "missing reverse wake weighting")
        elif key == "wake_spatial":
            aircraft = ELECTRIC_IDS | LIQUID_IDS | GLOW_IDS | {"jensen-das-ugly-stik-60"}
            for name in aircraft:
                row = coverage["spatial_aero_" + name]
                _require(all(_positive(row[field]) for field in ("attached", "continuation", "uniform")),
                         "missing spatial aerodynamic cases: " + name)
            for weather in WEATHER_PRESETS:
                row = coverage["weather_" + weather]
                _require(_positive(row["flow_states"]) and (not weather.startswith("spatial-")
                         or _positive(row.get("spatial_field_states"))), "missing spatial weather: " + weather)
            boundary = coverage["spatial_boundaries"]
            _require(all(_positive(boundary[name]) for name in ("zero_quaternion", "nonfinite_body", "density_bound",
                     "infinite_downwash", "infinite_ground", "short_delta", "nonfinite_delta", "delta_bound",
                     "wing_flow_bound", "tail_flow_bound", "inactive_horizontal", "quaternion_norm_above",
                     "quaternion_norm_below", "quaternion_norm_equal")), "missing spatial failure boundaries")
            _require(components["spatial_flow_validity"]["count"] >= MIN_COMPONENT_STATES
                     and components["spatial_aero_validity"]["count"] >= MIN_COMPONENT_STATES,
                     "insufficient spatial samples")
            flow_count = sum(coverage["weather_" + weather]["flow_states"] for weather in WEATHER_PRESETS)
            _counts(components, ("spatial_flow_validity", "spatial_propeller_air", "spatial_reference_wind",
                                  "spatial_station_delta", "spatial_wake_loads", "spatial_wake_source_delta",
                                  "spatial_wake_validity"), flow_count)
            _require(all(components[name]["count"] > 0 for name in
                         ("spatial_aero_delta", "spatial_aero_loads", "spatial_aero_refusal", "spatial_aero_uniform",
                          "spatial_aero_wake", "spatial_aero_zero_planes", "spatial_boundary_error",
                          "spatial_boundary_loads", "spatial_boundary_validity", "spatial_flow_quaternion_validity")),
                     "missing spatial comparisons")
        elif key == "gear":
            gear = _named(data["gear_cases"], LIQUID_IDS)
            for row in gear.values():
                _require(_positive(row["states"], MIN_COMPONENT_STATES) and all(_positive(row[name]) for name in
                         ("loaded_down", "unlocked", "contacts", "air_free", "spatial_invalid", "spatial_nonzero", "path_points")),
                         "missing retractable gear branches")
            _counts(components, ("gear_pose", "gear_drag", "gear_advance", "gear_wheel_derivative", "gear_wheel_loads"),
                    sum(row["states"] for row in gear.values()))
            _require(all(components[name]["count"] > 0 for name in
                         ("gear_actuator_edges", "gear_invalid_pose", "gear_invalid_drag", "gear_invalid_advance")),
                     "missing gear actuator or refusal boundaries")
            hulls = _named(data["live_hull_cases"], LIQUID_IDS | {"stik-glow-61fx-2t", "gp-extra-300s-60"})
            for row in hulls.values():
                _require(_positive(row["states_per_terrain"], MIN_COMPONENT_STATES) and all(_positive(row[name]) for name in
                         ("valid_mass_samples", "bank_loaded", "flat_loaded", "lake_loaded", "unloaded")),
                         "missing live-mass hull branches")
            _require(components["live_hull_status"]["count"] >= sum(row["states_per_terrain"] for row in hulls.values())
                     and components["live_hull_loads"]["count"] == components["live_hull_status"]["count"],
                     "incomplete live hull comparisons")
        else:
            return "unknown verification kind"
    except (KeyError, TypeError, ValueError, AttributeError) as error:
        return str(error) or "malformed verification coverage"
    return ""


def verification_error(key: str, data: dict) -> str:
    """Promotion requires completed work, not merely an oracle's pass label.

    Historical reports without checked-run evidence remain research records; rerun them to install.
    Invalid JSON field types are rejected by find_verification, never coerced into qualifying counts.
    """
    if data["run_valid"] is not True:
        return "run identity or checked execution failed"
    checked = data["checked_run"]
    if key == "negative_control":
        if (checked["complete"] is not True or checked["reason"] != "process_exit"
                or type(checked["process_exit"]) is not int or checked["process_exit"] != 1
                or type(checked["counts"]["error"]) is not int or checked["counts"]["error"] != 0
                or checked["missing_required_text"] != [] or data["verdict"] != "fail"
                or data["format"] != "openrc-nk3-stage-oracle v1"):
            return "mutation control did not fail cleanly and completely"
        components = data["components"]
        counts = [row["count"] for row in components.values()]
        identical = [row["identical"] for row in components.values()]
        if (any(type(value) is not int or value <= 0 for value in counts)
                or any(type(value) is not int or value < 0 or value > counts[i] for i, value in enumerate(identical))
                or data["total"] != {"compared": sum(counts), "identical": sum(identical),
                                    "mismatched": sum(counts) - sum(identical)}
                or components["stage_bytes"]["identical"] >= components["stage_bytes"]["count"]):
            return "mutation did not produce detected stage differences"
        domains = [data["coverage"][name] for name in ("stage_air", "stage_ground", "stage_hull")]
        if (any(not _positive(row["states"], MIN_CASE_STATES) for row in domains)
                or sum(row["states"] for row in domains) < MIN_STAGE_STATES):
            return "mutation control has insufficient stage coverage"
        return ""
    if (checked["ok"] is not True or checked["complete"] is not True
            or checked["reason"] != "passed" or type(checked["process_exit"]) is not int or checked["process_exit"] != 0
            or type(checked["counts"]["error"]) is not int or checked["counts"]["error"] != 0
            or checked["missing_required_text"] != []):
        return "checked Godot run did not complete successfully"
    if data["verdict"] != "pass" or data["failures"] != []:
        return "oracle failed"
    components = data["components"]
    counts = []
    for row in components.values():
        count = row["count"]
        if type(count) is not int or count <= 0 or type(row["identical"]) is not int or row["identical"] != count:
            return "missing or differing comparisons"
        counts.append(count)
    compared = sum(counts)
    if not compared or data["total"] != {"compared": compared, "identical": compared, "mismatched": 0}:
        return "comparison totals do not match"
    if key == "stage_oracle":
        if data["format"] != "openrc-nk3-stage-oracle v1":
            return "wrong stage oracle format"
        coverage = [data["coverage"][name] for name in ("stage_air", "stage_ground", "stage_hull")]
        if any(not _positive(row["states"], MIN_CASE_STATES) for row in coverage):
            return "missing stage domains"
        states = sum(row["states"] for row in coverage)
        if states < MIN_STAGE_STATES or sum(row.get("malformed", 0) for row in coverage) <= 0:
            return "insufficient actual stage states or malformed coverage"
        for name in ("stage_shape", "prop_loads", "hull_loads", "ground_evaluation_ok", "ground_up"):
            if components[name]["count"] != states:
                return "stage components did not cover every state"
        shaped = sum(row["stage_shaped"] for row in coverage)
        for name in ("stage_bytes", "stage_loads", "stage_derivative", "stage_rotor_momentum",
                     "ground_evaluation_loads", "ground_evaluation_derivative"):
            if not 0 < components[name]["count"] <= states:
                return "missing shaped stage comparisons"
            if name.startswith("stage_") and components[name]["count"] != shaped:
                return "shaped stage comparisons do not match coverage"
    elif key == "trajectory":
        if data["format"] != "openrc-nk3-trajectory v2" or set(data["trajectories"]) != TRAJECTORY_CASES:
            return "all five v2 trajectory cases are required"
        trajectory_ticks = 0
        for name, case in data["trajectories"].items():
            requested, actual = case["ticks_requested"], case["ticks_run"]
            if (type(requested) is not int or type(actual) is not int
                    or not MIN_TRAJECTORY_TICKS <= actual <= requested):
                return "insufficient actual trajectory ticks"
            end = case["native_end"]
            if (case["reference_end"] != end or end["fault"] != "" or end["tick"] != actual
                    or case["completion_ok"] is not True):
                return "unexpected trajectory termination"
            expected_crash = name in {"takeoff", "lake"} and end["crashed"] is True
            if expected_crash and end["paused"] is not True:
                return "a crashed trajectory must be paused"
            if not expected_crash and (actual != requested or end["crashed"] is not False or end["paused"] is not False):
                return "truncated or unexpectedly stopped trajectory"
            fingerprint = case["native_fingerprint"]
            if (len(fingerprint) != 64 or case["reference_fingerprint"] != fingerprint
                    or case["first_divergence_tick"] != -1):
                return "trajectory differs from reference"
            if (case["native_lost_install_ticks"] != 0 or case["native_uncovered_ticks"] != 0
                    or case["native_context_calls"] < actual or case["native_stage_calls"] < 4 * actual):
                return "native stage did not cover every tick"
            trajectory_ticks += actual

        faults = data.get("fault_paths")
        if not isinstance(faults, dict) or set(faults) != set(FAULT_REASONS):
            return "all five fault paths are required"
        for name, expected_reason in FAULT_REASONS.items():
            outcome = faults[name]
            if not isinstance(outcome, dict) or outcome.get("advanced") is not False:
                return f"fault path {name} did not reject its step"
            reference, native = outcome.get("reference"), outcome.get("native")
            if not isinstance(reference, dict) or not isinstance(native, dict) or reference != native:
                return f"fault path {name} outcomes differ"
            for end in (reference, native):
                reason = end.get("fault")
                if (type(end.get("tick")) is not int or end["tick"] != PHASE_TICKS
                        or not isinstance(reason, str) or not reason.startswith(expected_reason)
                        or end.get("paused") is not True or end.get("crashed") is not False):
                    return f"fault path {name} did not reach the expected rejection"

        checkpoint = data.get("checkpoint")
        if not isinstance(checkpoint, dict):
            return "checkpoint/restore evidence is missing"
        reference, native, passes = checkpoint.get("reference"), checkpoint.get("native"), checkpoint.get("passes")
        if not isinstance(reference, dict) or not isinstance(native, dict) or not isinstance(passes, list):
            return "checkpoint/restore evidence is malformed"
        if (any(info.get("restored") is not True or info.get("resumed") is not True for info in (reference, native))
                or reference.get("native_after_restore") is not False
                or not (native.get("native_after_restore") is True or native.get("reinstalled") is True)):
            return "checkpoint restore, resume or native stage is missing"
        if (len(passes) != 2 or any(not isinstance(row, dict)
                or type(row.get("ticks_reference")) is not int or row["ticks_reference"] != PHASE_TICKS
                or type(row.get("ticks_native")) is not int or row["ticks_native"] != PHASE_TICKS
                or type(row.get("mismatches")) is not int or row["mismatches"] != 0 for row in passes)):
            return "checkpoint passes must each compare 1200 matching ticks"

        fallback = data.get("fallback")
        if (not isinstance(fallback, dict) or fallback.get("aircraft") != "jensen-das-ugly-stik-60"
                or fallback.get("rejected_configuration") != "weather_pending_reset"
                or fallback.get("refused") is not True or not isinstance(fallback.get("reason"), str)
                or not fallback["reason"].strip() or fallback.get("stage_after_attempt") != "_wheel_evaluate"
                or type(fallback.get("reference_ticks")) is not int or fallback["reference_ticks"] != FALLBACK_TICKS
                or type(fallback.get("ticks")) is not int or fallback["ticks"] != FALLBACK_TICKS
                or fallback.get("fingerprint_equal") is not True):
            return "fallback must refuse and retain the matching reference for 960 ticks"

        required_counts = {
            "trajectory_end": len(TRAJECTORY_CASES), "trajectory_fingerprint": len(TRAJECTORY_CASES),
            **{name: trajectory_ticks for name in ("trajectory_tick_floats", "trajectory_tick_sizes", "trajectory_tick_modes")},
            **{name: len(FAULT_REASONS) for name in ("fault_path_end", "fault_path_bytes", "fault_path_sizes", "fault_path_modes")},
            **{name: 2 * PHASE_TICKS for name in ("checkpoint_tick_floats", "checkpoint_tick_sizes", "checkpoint_tick_modes")},
            "checkpoint_pass_length": 2, "fallback_reference_kept": 1,
        }
        for name, expected in required_counts.items():
            row = components.get(name)
            if (not isinstance(row, dict) or type(row.get("count")) is not int or row["count"] != expected
                    or type(row.get("identical")) is not int or row["identical"] != expected):
                return f"missing or incomplete trajectory comparisons: {name}"
    else:
        return _extended_verification(key, data, components)
    return ""


def pinned_engine_identity() -> tuple[str, str]:
    engine_version = locked.load_lock()["godot"]["version"]
    # The official editor is downloaded/verified by app/get-godot.sh; custom --godot runs remain research only.
    engine_release = engine_version.split(".official.")[0].replace(".beta", "-beta").replace(".rc", "-rc")
    engine_path = ROOT / ".tools" / f"Godot_v{engine_release}_linux.x86_64"
    # Engine.get_version_info().string is the display label, unlike the full `godot --version` identity.
    return f"{engine_release} (official)", sha256_file(engine_path) if engine_path.is_file() else ""


def find_verification(key: str, pattern: str, binary_sha256: str, sources: dict[str, str]) -> dict:
    """Find completed evidence for the current sources, toolchain, harness and binary."""
    engine_version, engine_sha256 = pinned_engine_identity()
    mutant = key == "negative_control"
    candidate_binary = TOOL_ROOT / f"lib/lib{NAME}_mutant.so"
    for path in sorted(TOOL_ROOT.glob(pattern), reverse=True):
        if ("_mutant" in path.name) != mutant:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if (not engine_sha256 or data["engine"] != engine_version
                    or data["engine_sha256_before"] != engine_sha256 or data["engine_sha256_after"] != engine_sha256):
                continue
            receipt = data["build_receipt"]
            expected_binary = sha256_file(candidate_binary) if mutant else binary_sha256
            if (receipt["mutant"] is not mutant or receipt["binary_sha256"] != expected_binary
                    or data["binary_sha256_before"] != expected_binary or data["binary_sha256_after"] != expected_binary
                    or (mutant and (expected_binary == binary_sha256 or "-DNK_MUTATION=1" not in receipt["cxxflags_appended"]))
                    or (not mutant and "-DNK_MUTATION=1" in receipt["cxxflags_appended"])):
                continue
            if (receipt["source_sha256"] != source_digest() or receipt["lock_sha256"] != sha256_file(locked.LOCK_PATH)
                    or receipt["builder_sha256"] != sha256_file(Path(__file__))
                    or receipt["backend_version"] != BACKEND_VERSION or receipt["abi_version"] != ABI_VERSION
                    or receipt["reference_sources_sha256"] != sources
                    or data["reference_sources_before"] != sources or data["reference_sources_after"] != sources):
                continue
            observed = data["sources"]
            if not isinstance(observed, dict) or not observed or data["sources_after"] != observed:
                continue
            for name, value in observed.items():
                if not isinstance(name, str) or not name.startswith("res://"):
                    raise ValueError("unexpected oracle source path")
                file = (ROOT / "app" / name.removeprefix("res://")).resolve()
                if not file.is_relative_to((ROOT / "app").resolve()):
                    raise ValueError("oracle source is outside app")
                relative = str(file.relative_to(ROOT))
                current = sources.get(relative) if relative in sources else sha256_file(file)
                if value != current:
                    raise ValueError("oracle source changed")
            harness = ["research/native-kernel/" + name for name in
                       ("oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "run.py", "build.py", ORACLE_SCRIPTS[key])]
            harness += ["app/sim/native_stage.gd", "tools/godot/run_checked.py"]
            if key == "electric_stage": harness.append("research/native-kernel/electric_oracle.gd")
            if key == "helicopter_stage": harness.append("research/native-kernel/helicopter_oracle.gd")
            if key == "wake_spatial": harness += ["research/native-kernel/weather_oracle.gd", "research/native-kernel/wake_oracle.gd"]
            if any(data["harness_sources"].get(name) != sha256_file(ROOT / name) for name in harness):
                continue
            for name, digest in data["harness_sources"].items():
                file = (ROOT / name).resolve()
                if not file.is_relative_to(ROOT.resolve()) or sha256_file(file) != digest:
                    raise ValueError("oracle harness changed")
            if verification_error(key, data):
                continue
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            continue
        return {"results": path.name, "results_sha256": sha256_file(path), "verdict": "fail" if mutant else "pass",
                "compared": data.get("total", {}).get("compared", 0)}
    raise SystemExit(
        f"--install-app needs complete {'negative-control' if mutant else 'passing'} {key} evidence "
        f"({pattern} in {TOOL_ROOT}) for the current binary, source, harness and engine; run: "
        f"python3 research/native-kernel/run.py --script {ORACLE_SCRIPTS[key]} {ORACLE_ARGUMENTS[key]}")


def prepare_manual_loading(app_dir: Path, destination: Path) -> None:
    """Prevent import-time loading, including registrations from an older installation.

    Run before starting Godot. Its cache is a line-based list, not a project-owned manifest;
    remove only this descriptor and preserve all other registrations byte for byte.
    """
    app_dir = app_dir.resolve()
    expected_destination = app_dir / "native/kernel"
    if (destination.absolute() != expected_destination or (app_dir / "native").is_symlink()
            or destination.is_symlink() or destination.resolve() != expected_destination):
        raise SystemExit(f"Refusing unexpected or symlinked native output: {destination}")
    destination.mkdir(parents=True, exist_ok=True)
    ignore = destination / ".gdignore"
    if ignore.is_symlink() or (ignore.exists() and not ignore.is_file()):
        raise SystemExit(f"Cannot create native import exclusion: {ignore}")
    if not ignore.exists():
        ignore.touch(exist_ok=False)

    registry = app_dir / ".godot/extension_list.cfg"
    if registry.parent.is_symlink() or registry.is_symlink() or not registry.resolve().is_relative_to(app_dir):
        raise SystemExit(f"Refusing to modify an external or symlinked extension list: {registry}")
    if not registry.exists():
        return
    if not registry.is_file():
        raise SystemExit(f"Extension list is not a regular file: {registry}")
    original = registry.read_bytes()
    descriptor = f"res://native/kernel/{NAME}.gdextension".encode("utf-8")
    retained = b"".join(line for line in original.splitlines(keepends=True)
                        if line.rstrip(b"\r\n") != descriptor)
    if retained == original:
        return
    # Replace only after a complete write; a failed migration keeps the previous registry.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=registry.parent, prefix=".nk3-extension-list-", delete=False) as file:
            temporary = Path(file.name)
            file.write(retained)
        os.chmod(temporary, stat.S_IMODE(registry.stat().st_mode))
        os.replace(temporary, registry)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def install_app() -> int:
    """Stage the verified Linux build under the ignored app/native/kernel/ (library, descriptor, receipt, licence)."""
    lock = locked.load_lock()
    build_receipt_path = TOOL_ROOT / "build-receipt.json"
    library = TOOL_ROOT / f"lib/lib{NAME}.so"
    if not build_receipt_path.is_file() or not library.is_file():
        raise SystemExit("No build in tmp/native-kernel; run build.py first.")
    built = json.loads(build_receipt_path.read_text(encoding="utf-8"))
    if built.get("mutant") or built.get("binary_sha256") != sha256_file(library):
        raise SystemExit("The staged library does not match its build receipt (or is the mutant).")
    if built.get("source_sha256") != source_digest():
        raise SystemExit("Native sources changed since the build; rebuild first.")
    sources = mirrored_sources()
    if (built.get("reference_sources_sha256") != sources or built.get("builder_sha256") != sha256_file(Path(__file__))
            or built.get("lock_sha256") != sha256_file(locked.LOCK_PATH)
            or built.get("backend_version") != BACKEND_VERSION or built.get("abi_version") != ABI_VERSION):
        raise SystemExit("Build policy, ABI, toolchain or mirrored sources changed since the build; rebuild first.")
    verification = {key: find_verification(key, pattern, built["binary_sha256"], sources)
                    for key, pattern in VERIFICATIONS.items()}
    record = {
        "platform": "linux", "architecture": "x86_64", "backend": "native", "backend_version": BACKEND_VERSION,
        "abi_version": ABI_VERSION, "binary_sha256": built["binary_sha256"], "source_sha256": built["source_sha256"],
        "lock_sha256": built["lock_sha256"], "builder_sha256": sha256_file(Path(__file__)),
        "shared_builder_sha256": built["shared_builder_sha256"], "godot_cpp_commit": built["godot_cpp_commit"],
        "compiler_version": built["compiler_version"], "cxxflags_appended": built["cxxflags_appended"],
        "libm_imports": built["libm_imports"], "repository_head": built["repository_head"],
        "mirrored_sources": sources, "verification": verification,
        "engine_version": pinned_engine_identity()[0], "engine_sha256": pinned_engine_identity()[1],
    }
    receipt = {"format": RECEIPT_FORMAT, "backend": "native", "backend_version": BACKEND_VERSION,
               "abi_version": ABI_VERSION, "platforms": {"linux": record}}
    destination = APP_DESTINATION
    prepare_manual_loading(ROOT / "app", destination)
    installed_library = destination / library.name
    # Revalidation of unchanged C++ only refreshes the receipt; do not rewrite a library mapped by another app.
    if not installed_library.is_file() or sha256_file(installed_library) != built["binary_sha256"]:
        staged_library = destination / (library.name + ".tmp")
        shutil.copy2(library, staged_library)
        staged_library.replace(installed_library)
    (destination / f"{NAME}.gdextension").write_text(APP_DESCRIPTOR, encoding="utf-8")
    (destination / "build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                                    encoding="utf-8")
    licence = locked.ensure_godot_cpp(lock) / "LICENSE.md"
    if not licence.is_file():
        raise SystemExit(f"Pinned godot-cpp licence not found at {licence}")
    shutil.copy2(licence, destination / "LICENSE.godot-cpp.md")
    print(json.dumps(receipt, indent=2, sort_keys=True))
    print(f"Installed the verified Linux native stage under {destination}.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=4, help="SCons jobs (at most 4 on the shared VM)")
    parser.add_argument("--mutant", action="store_true",
                        help="negative control: build with -DNK_MUTATION (deliberate operation-order changes) as a "
                             "separate *_mutant library the oracle must reject")
    parser.add_argument("--install-app", action="store_true",
                        help="install the existing verified build into the ignored app/native/kernel/ (no rebuild); "
                             "requires complete matching component, stage, trajectory and negative-control evidence")
    args = parser.parse_args()
    if args.install_app:
        if args.mutant:
            parser.error("--install-app never installs the mutant")
        return install_app()
    variant = "_mutant" if args.mutant else ""
    library_name = NAME + variant
    library = TOOL_ROOT / f"lib/lib{library_name}.so"
    descriptor = TOOL_ROOT / f"{library_name}.gdextension"
    if not 1 <= args.jobs <= 4:
        parser.error("--jobs must be between 1 and 4")
    if locked.host_platform_name() != "linux" or locked.host_arch_name() != "x86_64":
        raise SystemExit("The NK-3 research build is Linux x86_64 only.")
    lock = locked.load_lock()
    platform_lock = lock["linux"]
    compiler_version = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
    if compiler_version != platform_lock["compiler_version"]:
        raise SystemExit(f"Expected locked g++ {platform_lock['compiler_version']}, got {compiler_version}.")
    if shutil.disk_usage(ROOT).free < 6 * 1024**3:
        raise SystemExit("Less than 6 GB free; refusing to build.")

    scons = locked.ensure_scons(lock)
    godot_cpp = locked.ensure_godot_cpp(lock)
    build_dir = TOOL_ROOT / f"build/linux-x86_64-template_release{variant}"
    build_dir.mkdir(parents=True, exist_ok=True)
    profile = lock["godot_cpp"]["build_profile"]
    profile_content = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    if hashlib.sha256(profile_content.encode("utf-8")).hexdigest() != profile["sha256"]:
        raise SystemExit("Build profile SHA-256 mismatch.")
    profile_path = build_dir / "build_profile.json"
    profile_path.write_text(profile_content, encoding="utf-8")

    sconstruct = locked.sconstruct_text(godot_cpp, locked.SOURCES, build_dir / "lib", profile_path,
                                        lock["godot"]["extension_api"])
    default_fp = 'env.Append(CXXFLAGS=["-fno-fast-math", "-ffp-contract=off"])'
    flags = [*platform_lock["floating_point_flags"], *platform_lock["exception_flags"], *EXTRA_FLAGS,
             *(["-DNK_MUTATION=1"] if args.mutant else [])]
    if sconstruct.count(default_fp) != 1 or sconstruct.count("openrc_slipstream") != 1:
        raise SystemExit("Shared SConstruct template changed; update this adapter.")
    sconstruct = sconstruct.replace(default_fp, f"env.Append(CXXFLAGS={json.dumps(flags)})")
    (build_dir / "SConstruct").write_text(sconstruct.replace("openrc_slipstream", library_name), encoding="utf-8")
    env = dict(os.environ, CC="gcc", CXX="g++")
    log_path = TOOL_ROOT / f"build{variant}.log"
    with log_path.open("w", encoding="utf-8") as log:
        result = subprocess.run([*scons, "-C", str(build_dir), f"-j{args.jobs}", "platform=linux", "arch=x86_64",
                                 "target=template_release", "verbose=yes"], env=env, stdout=log,
                                stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        tail = log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-40:]
        print("\n".join(tail))
        raise SystemExit(f"SCons failed ({result.returncode}); full log: {log_path}")

    built = build_dir / f"lib/lib{library_name}.so"
    if not built.is_file():
        raise SystemExit(f"SCons finished without producing {built}.")
    library.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built, library)
    imports = libm_imports(library)
    if not any(entry.startswith("pow@") for entry in imports):
        raise SystemExit("libm pow is not imported: a literal exponent was folded; check the pow shim barrier.")
    descriptor.write_text(
        "; NK-3 research descriptor, generated by research/native-kernel/build.py; loaded at run time only.\n"
        "[configuration]\n"
        f'entry_symbol = "{NAME}_library_init"\n'
        'compatibility_minimum = "4.7"\n'
        "reloadable = false\n\n"
        "[libraries]\n"
        f'linux.x86_64 = "lib/lib{library_name}.so"\n', encoding="utf-8")
    receipt = {
        "library": str(library.relative_to(ROOT)),
        "descriptor": str(descriptor.relative_to(ROOT)),
        "mutant": args.mutant,
        "binary_sha256": sha256_file(library),
        "source_sha256": source_digest(),
        "backend_version": BACKEND_VERSION,
        "abi_version": ABI_VERSION,
        "lock_sha256": sha256_file(locked.LOCK_PATH),
        "builder_sha256": sha256_file(Path(__file__)),
        "shared_builder_sha256": sha256_file(SHARED_BUILDER),
        "godot_cpp_commit": locked.run(["git", "rev-parse", "HEAD"], cwd=godot_cpp, capture=True).strip(),
        "scons_wheel_sha256": lock["scons"]["wheel_sha256"],
        "compiler_version": compiler_version,
        "cxxflags_appended": flags,
        "target": "template_release",
        "libm_imports": imports,
        "repository_head": locked.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture=True).strip(),
        "reference_sources_sha256": mirrored_sources(),
    }
    (TOOL_ROOT / f"build-receipt{variant}.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                                   encoding="utf-8")
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
