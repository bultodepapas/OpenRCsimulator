"""Promotion policy checks for family matrices and events; no Godot or native binary required."""

import importlib.util
from pathlib import Path
import re
import unittest


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("nk3_family_policy", HERE / "build.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def base(key):
    return {"format": "openrc-nk3-" + key.replace("_", "-") + "-oracle v1",
            "run_valid": True, "checked_run": {"ok": True, "complete": True, "reason": "passed",
            "process_exit": 0, "counts": {"error": 0}, "missing_required_text": []},
            "verdict": "pass", "failures": [], "components": {}, "coverage": {}}


def comparisons(data, names, count):
    for name in names:
        data["components"][name] = {"count": count, "identical": count}


def finish(data):
    total = sum(row["count"] for row in data["components"].values())
    data["total"] = {"compared": total, "identical": total, "mismatched": 0}
    return data


def tape(name, ticks=64, **fields):
    return dict(name=name, requested_ticks=ticks, ticks_run=ticks, complete=True, first_divergence=-1,
                native_context_calls=ticks, native_stage_calls=4 * ticks, **fields)


def make_electric():
    data = base("electric")
    real = {name + "/" + battery for name in builder.ELECTRIC_IDS for battery in ("ideal", "pack")}
    synthetic = {"synthetic_ocv", "synthetic_ecm_0_branches", "synthetic_ecm_2_branches"}
    data["electric_cases"] = [dict(name=name, states=1000, accepted=900, rejected=100,
        kind="fixed_voltage" if name.endswith("/ideal") else "ocv_resistance" if name == "synthetic_ocv" else "pack_ecm")
        for name in sorted(real | synthetic)]
    data["electric_coupled_cases"] = [dict(name=name, states=1000, accepted=900, rejected=100,
        locked=1, forward_breakaway=1, reverse_refused=1, negative_trial=1) for name in sorted(real)]
    comparisons(data, ("electric_validity",), 7000)
    comparisons(data, ("electric_values", "electric_rates"), 6300)
    comparisons(data, ("electric_coupled_validity",), 4000)
    comparisons(data, ("electric_coupled_values", "electric_coupled_battery_rates"), 3600)
    comparisons(data, ("electric_coupled_guard_validity",), 72)
    comparisons(data, ("electric_coupled_guard_values", "electric_coupled_guard_rates"), 10)
    return finish(data)


def make_family_stage(family):
    data = base(family + "_stage")
    ids = {"electric": builder.ELECTRIC_IDS, "liquid": builder.LIQUID_IDS, "glow": builder.GLOW_IDS}[family]
    bases = ({name + "/" + battery for name in ids for battery in ("ideal", "pack")}
             if family == "electric" else ids)
    rows = []
    for name in sorted(bases):
        for weather in sorted(builder.FAMILY_WEATHER):
            row = dict(name=name + "/" + weather, states=500, finite=490, refused=10)
            if family == "electric":
                row.update(battery_size=0 if name.endswith("/ideal") else 11,
                           wheel_count=0 if name.startswith("moonrunner-x99/") else 3)
            elif family == "liquid":
                row.update(family="turbine" if name.startswith("sebart-") else "gas",
                           gear_down=1, gear_partial=1, gear_up=1, source_off=1)
            else:
                row["family"] = "glow_4t" if name.startswith("stik-glow-fs64v-4t") else "glow_2t"
            rows.append(row)
    states = len(rows) * 500
    evidence = {"cases": rows, "trajectories": []}
    data[family + "_stage"] = evidence
    if family == "electric":
        comparisons(data, ("stage_shape",), states)
        comparisons(data, ("stage_bytes", "stage_loads", "stage_derivative", "stage_rotor_momentum"), len(rows) * 490)
        comparisons(data, ("electric_stage_snapshot_refusal",), 34)
        nominal = {"turbo-lumber-evolution/ideal/calm", "turbo-lumber-evolution/pack/turbulent",
                   "moonrunner-x99/ideal/hot-high", "moonrunner-x99/pack/spatial-thermal-soaring-v2"}
        evidence["trajectories"] = [tape(name) for name in sorted(nominal)]
        events = ({name + "/" + battery + "/rotor-stop-restart" for name in ids for battery in ("ideal", "pack")}
                  | {name + "/pack/" + event for name in ids for event in ("battery-exhaustion", "esc-soft-cut")})
        evidence["events"] = [tape(name, event_observed=True, event_tick=1, event_count=1,
                                   cut_ok=True, restart_ok=True, commands=[{"tick": 0}]) for name in sorted(events)]
        evidence["event_not_applicable"] = [dict(aircraft=name, battery="ideal",
            events=["battery-exhaustion", "esc-soft-cut"], reason="no finite battery or supervisor") for name in sorted(ids)]
        comparisons(data, ("electric_trajectory_tick",), len(nominal) * 65)
        comparisons(data, ("electric_event_tick",), len(events) * 65)
    elif family == "liquid":
        comparisons(data, ("liquid_stage_keys", "liquid_stage_bytes", "liquid_stage_loads", "liquid_stage_body_derivative",
                           "liquid_stage_derivative", "liquid_stage_rotor_momentum"), states)
        comparisons(data, ("liquid_snapshot_refusal",), 30)
        for prefix in ("liquid_initial_stage", "liquid_forced_preview", "liquid_nan_time_stage"):
            comparisons(data, tuple(prefix + "_" + suffix for suffix in
                        ("keys", "bytes", "loads", "body_derivative", "derivative", "rotor_momentum")), 1)
        for name in sorted(ids):
            for suffix in ("runway/calm", "trim/spatial-thermal-soaring-v2", "trim/calm/exhaustion"):
                exhaustion = suffix.endswith("/exhaustion")
                evidence["trajectories"].append(tape(name + "/" + suffix,
                    exhaustion_expected=exhaustion, exhaustion_observed=exhaustion))
        comparisons(data, ("liquid_trajectory_tick",), len(evidence["trajectories"]) * 65)
    else:
        comparisons(data, ("glow_stage_shape",), states)
        comparisons(data, ("glow_stage_bytes", "glow_stage_loads", "glow_stage_body", "glow_stage_derivative", "glow_stage_rotor"), len(rows) * 490)
        comparisons(data, ("glow_stage_snapshot_refusal",), 31)
        comparisons(data, ("glow_event_command",), 8)
        nominal = {"stik-glow-61fx-2t/calm/nominal", "stik-glow-55ax-2t/turbulent/nominal",
                   "stik-glow-fs64v-4t/hot-high/nominal", "gp-extra-300s-60/spatial-thermal-soaring-v2/nominal"}
        names = nominal | {name + "/calm/" + event for name in ids
                           for event in ("exhaustion", "overheat", "stall", "cut_restart")}
        for name in sorted(names):
            event = name.rsplit("/", 1)[1]
            located = (["fuel_exhausted", "glow_stopped"] if event == "exhaustion" else ["glow_stopped"]
                       if event in {"overheat", "stall"} else [])
            evidence["trajectories"].append(tape(name, event_kind=event, located=located, cut_ok=True, restart_ok=True))
        comparisons(data, ("glow_trajectory_tick",), len(names) * 65)
    return finish(data)


def make_helicopter(stage):
    key = "helicopter_stage" if stage else "helicopter"
    data = base(key)
    weather = {"calm", "steady", "crosswind", "gusty", "updraft", "hot-high", "cool-dense"}
    starts = {"airborne", "ground"}
    cases = []
    for start in starts:
        for condition in weather:
            data["coverage"]["helicopter_" + start + "_" + condition] = dict(
                states=715, accepted=715, direct=1, trainer=1, normal=1, idle_up=1, near_stop=1,
                running=1, stopped=1, contact=1, unloaded=1)
            cases.append(dict(start=start, weather=condition, states=715, continuous_size=14 if start == "ground" else 6,
                              seeded_only=condition == "hot-high"))
    data["coverage"]["helicopter"] = {"accepted": 14 * 715}
    data["reference_start_refusals"] = [dict(start=start, weather="hot-high",
        reason="hover trim line search refused", component_seed="calm reference reset; no hot-high flight start") for start in starts]
    prefix = "helicopter_stage_" if stage else "helicopter_"
    comparisons(data, ("helicopter_stage_validity",), 14 * 715)
    comparisons(data, tuple(prefix + name for name in ("loads", "body_derivative", "derivative", "rotor_momentum")), 14 * 715)
    if stage:
        comparisons(data, ("helicopter_stage_bytes",), 14 * 715)
        comparisons(data, ("helicopter_weather_refusal",), 8)
        names = {s + "/" + w for s in starts for w in weather - {"hot-high"}} | {"airborne/crosswind/rotor-stop"}
        trajectories = [tape(name, changed_mode=True, changed_trainer=True, held_drive=True,
            stop_expected=name.endswith("rotor-stop"), stop_observed=name.endswith("rotor-stop")) for name in sorted(names)]
        replays = [dict(tape(start, ticks=32), start=start, checkpoint_tick=32) for start in starts]
        data[key] = {"cases": cases, "trajectories": trajectories, "replays": replays}
        comparisons(data, ("helicopter_trajectory_tick",), 65 * len(names))
        comparisons(data, ("helicopter_replay_tick",), 33 * len(starts))
    return finish(data)


def make_source(family):
    data = base(family)
    ids = builder.LIQUID_IDS if family == "liquid" else builder.GLOW_IDS
    rows = []
    for name in sorted(ids):
        kind = ("turbine" if name.startswith("sebart-") else "gas") if family == "liquid" else (
            "glow_4t" if name == "stik-glow-fs64v-4t" else "glow_2t")
        row = dict(name=name, family=kind, states=1000, resources=1,
                   mass_accepted=900, mass_rejected=100, source_accepted=900, source_rejected=100)
        if family == "glow": row.update(blade_accepted=900, blade_rejected=100)
        rows.append(row)
    data[family + "_cases"] = rows
    comparisons(data, (family + "_mass_validity",), len(ids) * 1000)
    comparisons(data, (family + "_mass_values",), len(ids) * 900)
    if family == "liquid":
        comparisons(data, ("liquid_gas_laws", "liquid_gas_coupling_validity"), 2000)
        comparisons(data, ("liquid_gas_coupling_values", "liquid_gas_body_derivative"), 1800)
        comparisons(data, ("liquid_turbine_validity",), 1000)
        comparisons(data, ("liquid_turbine_values",), 900)
    else:
        comparisons(data, ("glow_source_validity", "glow_blade_validity", "glow_unit_validity"), 4000)
        comparisons(data, ("glow_source_values", "glow_blade_values", "glow_body_derivative"), 3600)
        comparisons(data, ("glow_unit_flow",), 3600)
        feed_names = (builder.GLOW_IDS - {"gp-extra-300s-60"}) | {"synthetic_pickup"}
        data["glow_feed_cases"] = [dict(name=name, pickup=name == "synthetic_pickup", states=1000,
            context_accepted=900, context_rejected=100, zero_factor=1) for name in sorted(feed_names)]
        data["glow_multi_mass"] = dict(resources=2, states=1000, accepted=900, rejected=100)
        comparisons(data, ("glow_feed_context_validity",), 4000)
        comparisons(data, ("glow_feed_context", "glow_feed_factor"), 3600)
        comparisons(data, ("glow_multi_mass_validity",), 1000)
        comparisons(data, ("glow_multi_mass_values", "glow_multi_body_derivative"), 900)
    return finish(data)


def make_weather(stage):
    key = "weather_stage" if stage else "weather"
    data = base(key)
    if not stage:
        directions = {"direction-0.0", "direction-45.0", "direction-90.0", "direction-135.0", "direction-180.0",
                      "direction-270.0", "direction-360.0", "column-and-ou", "warm-uniform-atmosphere", "spatial-and-column"}
        refusals = {"unknown_key", "wrong_array_type", "nonfinite_speed", "period_before_duration", "wrong_boolean_type",
                    "nonfinite_temperature", "nonpositive_temperature", "wrong_temperature_type", "spatial_ou_conflict",
                    "incomplete_mode", "nonfinite_mode", "invalid_gust_maximum", "invalid_ground_extension"}
        data["weather"] = {"presets": list(builder.WEATHER_PRESETS), "scenarios": list(builder.WEATHER_PRESETS | directions),
            "refusals": {name: dict(refused=True, cleared=True, error="refused") for name in refusals}}
        data["coverage"]["weather"] = dict(point_queries=10000, air_queries=200, real_ou_windows=1, thermal_cell_samples=1)
        comparisons(data, ("weather_wind",), 10000)
        comparisons(data, ("weather_atmosphere", "weather_temperature"), 200)
        comparisons(data, ("weather_refusal",), 13)
        comparisons(data, ("weather_spatial_provider_guard",), 1)
    else:
        names = builder.WEATHER_PRESETS | {"custom-noncardinal", "custom-column-and-ou", "custom-spatial-column"}
        coverage = {name: dict(states=500, finite_stages=490, finite_spatial_flows=1, spatial_gradient_stages=1) for name in names}
        tape_names = {"active-gust", "spatial-active-gust", "spatial-active-thermal", "standard-column", "turbulent"} | {
            name for name in builder.WEATHER_PRESETS if name.startswith("spatial-")}
        data[key] = {"include_spatial": True, "skipped_spatial": [], "scenarios": list(names),
            "scenario_coverage": coverage, "trajectories": {name: tape(name) for name in tape_names}}
        data["coverage"][key] = dict(states=10000, finite_shaped=9800, malformed=1, real_ou_window_states=1,
            finite_spatial_flows=1, spatial_gradient_stages=1, spatial_domain_refusals=1)
        comparisons(data, ("stage_shape",), 10000)
        comparisons(data, ("stage_bytes", "stage_derivative", "stage_loads", "stage_rotor_momentum"), 9800)
        comparisons(data, ("weather_provider_guard", "weather_spatial_component_refusal"), 1)
        comparisons(data, ("weather_trajectory_tick",), len(tape_names) * 65)
    return finish(data)


def make_other(key):
    data = base(key)
    coverage = data["coverage"]
    if key == "propeller":
        ids = builder.ELECTRIC_IDS | (builder.LIQUID_IDS - {"sebart-avanti-s-a200-p100rx"}) | {"jensen-das-ugly-stik-60"}
        coverage.update({"propeller_" + name: {"states": 1000} for name in ids})
        comparisons(data, ("propeller_velocity", "propeller_thrust_torque", "propeller_loads", "propeller_rotor",
                           "propeller_normal", "propeller_pfactor", "propeller_flow_validity"), len(ids) * 1000)
    elif key == "wake":
        names = {"f4u-corsair-250", "p51d-mustang-120", "gp-extra-300s-60", "manufactured_legacy",
                 "manufactured_smooth", "manufactured_smooth_swirl", "manufactured_transport"}
        coverage.update({"wake_" + name: dict(states=1000, held_wake=1, hub_delta=1, nonzero_load=1,
            reverse_flow=1, stopped=1, transport=1) for name in names})
        comparisons(data, ("wake_loads", "wake_state"), len(names) * 1000)
        comparisons(data, ("wash_derivative", "wash_target"), 1000)
        comparisons(data, ("wake_reverse_weight",), 1)
    elif key == "wake_spatial":
        ids = builder.ELECTRIC_IDS | builder.LIQUID_IDS | builder.GLOW_IDS | {"jensen-das-ugly-stik-60"}
        coverage.update({"spatial_aero_" + name: dict(attached=1, continuation=1, uniform=1) for name in ids})
        coverage.update({"weather_" + weather: dict(flow_states=100, spatial_field_states=100) for weather in builder.WEATHER_PRESETS})
        boundary_names = ("zero_quaternion", "nonfinite_body", "density_bound", "infinite_downwash", "infinite_ground",
            "short_delta", "nonfinite_delta", "delta_bound", "wing_flow_bound", "tail_flow_bound", "inactive_horizontal",
            "quaternion_norm_above", "quaternion_norm_below", "quaternion_norm_equal")
        coverage["spatial_boundaries"] = {name: 1 for name in boundary_names}
        comparisons(data, ("spatial_flow_validity", "spatial_propeller_air", "spatial_reference_wind", "spatial_station_delta",
                           "spatial_wake_loads", "spatial_wake_source_delta", "spatial_wake_validity"), len(builder.WEATHER_PRESETS) * 100)
        comparisons(data, ("spatial_aero_validity",), 1000)
        comparisons(data, ("spatial_aero_delta", "spatial_aero_loads", "spatial_aero_refusal", "spatial_aero_uniform",
                           "spatial_aero_wake", "spatial_aero_zero_planes", "spatial_boundary_error", "spatial_boundary_loads",
                           "spatial_boundary_validity", "spatial_flow_quaternion_validity"), 1)
    elif key == "gear":
        data["format"] = "openrc-nk3-gear-hull-oracle v1"
        data["gear_cases"] = [dict(name=name, states=1000, loaded_down=1, unlocked=1, contacts=1, air_free=1,
                                   spatial_invalid=1, spatial_nonzero=1, path_points=1) for name in builder.LIQUID_IDS]
        data["live_hull_cases"] = [dict(name=name, states_per_terrain=1000, valid_mass_samples=1, bank_loaded=1,
            flat_loaded=1, lake_loaded=1, unloaded=1) for name in builder.LIQUID_IDS | {"stik-glow-61fx-2t", "gp-extra-300s-60"}]
        comparisons(data, ("gear_pose", "gear_drag", "gear_advance", "gear_wheel_derivative", "gear_wheel_loads"), 3000)
        comparisons(data, ("gear_actuator_edges", "gear_invalid_pose", "gear_invalid_drag", "gear_invalid_advance"), 1)
        comparisons(data, ("live_hull_status", "live_hull_loads"), 5000)
    return finish(data)


def make_legacy_ground():
    data = base("legacy_ground")
    ids = {"jensen-das-ugly-stik-60", "gp-extra-300s-60"}
    bases = ([(name, "stock") for name in sorted(ids)] + [("jensen-das-ugly-stik-60", "no-stiction"),
                                                            ("jensen-das-ugly-stik-60", "24-contacts")])
    cases = []
    for aircraft, variant in bases:
        for mode in ("flat", "flat-surfaces", "lake"):
            anchors = variant != "no-stiction"
            cases.append(dict(name=aircraft + "/" + variant + "/" + mode, aircraft=aircraft,
                variant=variant, mode=mode, states=1200, contacts=24 if variant == "24-contacts" else 3, has_anchors=anchors,
                coverage=dict(clear=600, loaded=600, sliding=300 if anchors else 600,
                    stuck=300 if anchors else 0, malformed=1, invalid_geometry=0, lake_slope=1,
                    partial_anchors=1)))
    edges = {name + "/" + edge: count for name in ids for edge, count in
             (("invalid_surface", 1), ("invalid_lake", 1), ("empty_gear", 0), ("empty_gear_flat", 0))}
    trajectories = [tape(mode + "/" + str(count) + "-contacts", mode=mode, contacts=count, anchor_values=3 * count,
                         correct_route=True, restored=True, contact_ticks=1)
                    for mode in ("flat", "lake") for count in (3, 24)]
    data["legacy_ground"] = dict(cases=cases, edge_cases=edges, trajectories=trajectories)
    comparisons(data, ("legacy_ground_loads",), len(cases) * 1200)
    comparisons(data, ("legacy_ground_edges",), len(edges))
    comparisons(data, ("legacy_ground_tape_tick",), len(trajectories) * 65)
    return finish(data)


def make_prescribed_stage():
    data = base("prescribed_stage")
    cases = [dict(name=mode + "/" + weather, states=250, finite=230, refused=20)
             for mode in builder.PRESCRIBED_MODES for weather in builder.FAMILY_WEATHER]
    trajectories = [tape(mode + "/calm") for mode in builder.PRESCRIBED_MODES]
    commands = [dict(tick=0, engine_running=True), dict(tick=1, engine_running=False), dict(tick=3, engine_running=True)]
    events = [tape(mode + "/power-cut-restart", event_observed=True, cut_ok=True, restart_ok=True, event_tick=1,
        seed="stopped boundary; hot cutoff has no prescribed law" if mode == "turbine-continuous" else "running source at 0.5 rpm",
        commands=commands) for mode in builder.PRESCRIBED_MODES]
    callbacks = [tape(name, correct_route=True, restored=True) for name in
                 ("legacy-no-gear", "shaft-split-no-gear", "shaft-split-no-gear-transport")]
    previews = [dict(name=mode + "/" + weather, present=True, no_time_ok=True, identical=True,
                     initial_body_would_capture=True, initial_context_accepted=True)
        for mode in ("shaft-coupled", "shaft-coupled-transport") for weather in
        ("calm", "turbulent", "spatial-thermal-soaring-v2")]
    refusals = [dict(mode=mode, name=field, refused=True) for mode in builder.PRESCRIBED_MODES
                for field in ("source_mismatch", "mode", "extra_key", "unregistered_source_on_both_sides", "rotor_capability")]
    refusals += [dict(mode=mode, name="inverse", refused=True) for mode in ("shaft-coupled", "shaft-coupled-transport")]
    data["prescribed_stage"] = dict(cases=cases, trajectories=trajectories, events=events,
        callback_routes=callbacks, previews=previews, refusals=refusals,
        shaft_transitions=[dict(name="gearless-split-coupled-split", complete=True, initial_body_owned=True,
            coupled_selected=True, coupled_callbacks_restored=True, coupled_reset=True, coupled_reinstalled=True,
            coupled_tape=tape("coupled"), split_selected=True, split_callbacks_restored=True, split_reset=True,
            split_reinstalled=True, split_tape=tape("split"), uninstall_restored=True)])
    data["coverage"]["prescribed_stage"] = dict(states=len(cases) * 250)
    comparisons(data, ("stage_shape",), len(cases) * 250)
    comparisons(data, ("stage_bytes", "stage_loads", "stage_derivative", "stage_rotor_momentum"), len(cases) * 230)
    comparisons(data, ("prescribed_trajectory_tick", "prescribed_event_tick"), 6 * 65)
    comparisons(data, ("prescribed_callback_tick",), 3 * 65)
    comparisons(data, tuple("prescribed_preview_" + name for name in
                ("presence", "loads", "derivative", "rotor_momentum", "bytes", "nan_time", "empty_body")), 6)
    comparisons(data, ("prescribed_preview_sampler_valid",), 2)
    comparisons(data, ("prescribed_preview_sampler_delta",), 6)
    comparisons(data, ("prescribed_snapshot_refusal",), len(refusals))
    comparisons(data, ("prescribed_transition_callbacks",), 2)
    comparisons(data, ("prescribed_transition_tick",), 2 * 65)
    return finish(data)


class FamilyPromotion(unittest.TestCase):
    def fixtures(self):
        return {"propeller": make_other("propeller"), "electric": make_electric(),
                "electric_stage": make_family_stage("electric"), "liquid": make_source("liquid"),
                "liquid_stage": make_family_stage("liquid"), "glow": make_source("glow"),
                "glow_stage": make_family_stage("glow"), "helicopter": make_helicopter(False),
                "helicopter_stage": make_helicopter(True), "weather": make_weather(False),
                "weather_stage": make_weather(True), "wake": make_other("wake"),
                "wake_spatial": make_other("wake_spatial"), "gear": make_other("gear"),
                "prescribed_stage": make_prescribed_stage(), "legacy_ground": make_legacy_ground()}

    def test_complete_family_evidence_qualifies(self):
        self.assertEqual(set(self.fixtures()), set(builder.VERIFICATIONS) - {"stage_oracle", "trajectory", "negative_control"})
        for key, data in self.fixtures().items():
            with self.subTest(key=key):
                self.assertEqual(builder.verification_error(key, data), "")

    def test_all_oracle_runtime_and_data_sources_are_mirrored(self):
        mirrored = set(builder.REFERENCE_SOURCES)
        self.assertEqual(len(mirrored), len(builder.REFERENCE_SOURCES), "duplicate source path")
        for name in mirrored:
            self.assertTrue((builder.ROOT / name).is_file(), name)
        for script in HERE.glob("*.gd"):
            text = script.read_text()
            for match in re.finditer(r"(?m)^func _source_hashes\([^\n]*\).*?:\s*\n", text):
                rest = text[match.end():]
                following = re.search(r"(?m)^(?:static )?func ", rest)
                body = rest[:following.start()] if following else rest
                for name in re.findall(r'"res://([^\"]+)"', body):
                    path = "app/" + name
                    if not path.startswith("app/tests/"):
                        self.assertIn(path, mirrored, f"{script.name}: {path}")

    def test_missing_cases_or_comparisons_cannot_be_disguised_by_a_pass(self):
        cases = {
            "propeller": lambda d: d["coverage"].pop(next(iter(d["coverage"]))),
            "electric": lambda d: d["electric_cases"].pop(),
            "liquid": lambda d: d["liquid_cases"].pop(),
            "glow": lambda d: d["glow_feed_cases"].pop(),
            "helicopter": lambda d: d["coverage"].pop("helicopter_airborne_calm"),
            "weather": lambda d: d["weather"]["scenarios"].remove("spatial-gusty-v1"),
            "wake": lambda d: d["coverage"].pop("wake_manufactured_transport"),
            "wake_spatial": lambda d: d["coverage"]["spatial_boundaries"].pop("nonfinite_body"),
            "gear": lambda d: d["gear_cases"].pop(),
            "prescribed_stage": lambda d: d["prescribed_stage"]["cases"].pop(),
            "legacy_ground": lambda d: d["legacy_ground"]["cases"].pop(),
        }
        for family in ("electric", "liquid", "glow"):
            cases[family + "_stage"] = lambda d, family=family: d[family + "_stage"]["cases"].pop()
        cases["weather_stage"] = lambda d: d["weather_stage"].update(include_spatial=False)
        cases["helicopter_stage"] = lambda d: d["helicopter_stage"]["replays"].pop()
        for key, change in cases.items():
            with self.subTest(key=key):
                data = self.fixtures()[key]
                change(data)
                self.assertTrue(builder.verification_error(key, data))

    def test_events_require_observation_completion_and_matching_ticks(self):
        for family in ("electric", "liquid", "glow"):
            key = family + "_stage"
            data = make_family_stage(family)
            rows = data[key]["events" if family == "electric" else "trajectories"]
            if family == "electric": row = rows[0]; row["event_observed"] = False
            elif family == "liquid": row = next(row for row in rows if row["name"].endswith("exhaustion")); row["exhaustion_observed"] = False
            else: row = next(row for row in rows if row["event_kind"] == "cut_restart"); row["restart_ok"] = False
            self.assertTrue(builder.verification_error(key, data), family)
            data = make_family_stage(family)
            data[key]["trajectories"][0]["ticks_run"] -= 1
            self.assertTrue(builder.verification_error(key, data), family)
        data = make_helicopter(True)
        next(row for row in data["helicopter_stage"]["trajectories"] if row["name"].endswith("rotor-stop"))["stop_observed"] = False
        self.assertTrue(builder.verification_error("helicopter_stage", data))

        data = make_family_stage("electric")
        next(row for row in data["electric_stage"]["events"] if row["name"].endswith("esc-soft-cut"))["cut_ok"] = False
        self.assertTrue(builder.verification_error("electric_stage", data))
        data = make_family_stage("electric")
        data["electric_stage"]["event_not_applicable"].pop()
        self.assertTrue(builder.verification_error("electric_stage", data))
        data = make_prescribed_stage()
        next(row for row in data["prescribed_stage"]["events"] if row["name"].startswith("turbine-continuous/"))["seed"] = "hot running"
        self.assertTrue(builder.verification_error("prescribed_stage", data))
        data = make_prescribed_stage()
        data["prescribed_stage"]["previews"][0]["no_time_ok"] = False
        self.assertTrue(builder.verification_error("prescribed_stage", data))
        data = make_prescribed_stage()
        data["prescribed_stage"]["previews"][0]["initial_context_accepted"] = False
        self.assertTrue(builder.verification_error("prescribed_stage", data))
        data = make_prescribed_stage()
        data["prescribed_stage"]["callback_routes"][0]["restored"] = False
        self.assertTrue(builder.verification_error("prescribed_stage", data))
        data = make_prescribed_stage()
        data["prescribed_stage"]["shaft_transitions"][0]["coupled_callbacks_restored"] = False
        self.assertTrue(builder.verification_error("prescribed_stage", data))
        data = make_prescribed_stage()
        data["prescribed_stage"]["shaft_transitions"][0]["split_tape"]["native_stage_calls"] -= 1
        self.assertTrue(builder.verification_error("prescribed_stage", data))
        data = make_prescribed_stage()
        data["prescribed_stage"]["shaft_transitions"].clear()
        self.assertTrue(builder.verification_error("prescribed_stage", data))
        data = make_legacy_ground()
        next(row for row in data["legacy_ground"]["cases"] if row["has_anchors"])["coverage"]["stuck"] = 0
        self.assertTrue(builder.verification_error("legacy_ground", data))
        data = make_legacy_ground()
        data["legacy_ground"]["trajectories"][0]["contact_ticks"] = 0
        self.assertTrue(builder.verification_error("legacy_ground", data))
        data = make_legacy_ground()
        next(row for row in data["legacy_ground"]["trajectories"] if row["contacts"] == 24)["anchor_values"] = 64
        self.assertTrue(builder.verification_error("legacy_ground", data))

    def test_incomplete_process_or_uncovered_native_ticks_cannot_promote(self):
        for key, data in self.fixtures().items():
            with self.subTest(key=key):
                data["checked_run"]["counts"]["error"] = 1
                self.assertTrue(builder.verification_error(key, data))
        data = make_family_stage("glow")
        data["glow_stage"]["trajectories"][0]["native_stage_calls"] -= 1
        self.assertTrue(builder.verification_error("glow_stage", data))

    def test_large_aggregate_does_not_hide_a_nearly_empty_case(self):
        for family in ("electric", "liquid", "glow"):
            with self.subTest(family=family):
                data = make_family_stage(family)
                data[family + "_stage"]["cases"][0].update(states=63, finite=62, refused=1)
                self.assertTrue(builder.verification_error(family + "_stage", data))
        data = make_helicopter(True)
        data["coverage"]["helicopter_airborne_calm"]["states"] = 63
        self.assertTrue(builder.verification_error("helicopter_stage", data))
        data = make_weather(True)
        data["weather_stage"]["scenario_coverage"]["calm"]["states"] = 63
        self.assertTrue(builder.verification_error("weather_stage", data))


if __name__ == "__main__":
    unittest.main()
