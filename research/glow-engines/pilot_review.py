"""Generate and validate a seeded NITRO-03 pilot-review schedule."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
TEMPLATE_PATH = ROOT / "docs/research/glow-engines/NITRO-02/pilot-review-template.json"
MASK64 = (1 << 64) - 1
SCHEMA = "openrc-glow-pilot-review v1"
TRIAL_STATUSES = {"not_run", "completed", "aborted", "invalid"}
COMMON_START_SEQUENCE = [
    "Press R to reset to the selected Runway start, set throttle to idle and press T to begin the trial trace.",
    "Press F7, hold idle for 5 seconds, then smoothly advance throttle to full over 3 seconds and take off. Do not force a static hold; record any idle ground roll.",
    "Climb to the safe test height selected before the session and establish level flight. On the takeoff_climb card, score this takeoff/climb; on other cards use this sequence only to reach the test height.",
]


class SplitMix64:
    """Small fixed PRNG so a seed gives the same schedule across Python versions."""

    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next_u64(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        value = self.state
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & MASK64
        return value ^ (value >> 31)

    def below(self, upper: int) -> int:
        if upper <= 0:
            raise ValueError("upper must be positive")
        bound = (MASK64 + 1) - ((MASK64 + 1) % upper)
        while True:
            value = self.next_u64()
            if value < bound:
                return value % upper

    def shuffle(self, values: list[Any]) -> None:
        for index in range(len(values) - 1, 0, -1):
            other = self.below(index + 1)
            values[index], values[other] = values[other], values[index]


FAMILIES: tuple[dict[str, Any], ...] = (
    {
        "key": "2t",
        "family": "glow_2t",
        "engine": "O.S. MAX-55AX, product 15612, Type 40K carburetor, No.8 plug, stock Power Box silencer",
        "catalog_id": "stik-glow-55ax-2t",
        "profile_id": "os_max_55ax_candidate",
        "profile_path": "app/data/glow/os_max_55ax_candidate.json",
        "installation_path": "app/data/glow/stik_55ax_2t.json",
        "aircraft_path": "app/data/aircraft/stik_glow_55ax_2t.json",
        "propeller": "APC Sport LP12070, 12x7, 1/4-inch bore",
        "build_id": "max55ax_apc_sport_12x7",
        "candidate_fuel": "72/10/18 volume percent methanol/nitromethane/castor oil",
        "engine_reference": "https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15612.htm",
        "field_reference": "https://www.os-engines.co.jp/web_content/202102/index1.html",
        "prop_reference": "https://www.apcprop.com/product/12x7/",
    },
    {
        "key": "4t",
        "family": "glow_4t",
        "engine": "O.S. FS-64V, product 3AY00, Type 61T carburetor, Type F plug, F-4051 silencer",
        "catalog_id": "stik-glow-fs64v-4t",
        "profile_id": "os_fs_64v_candidate",
        "profile_path": "app/data/glow/os_fs_64v_candidate.json",
        "installation_path": "app/data/glow/stik_fs64v_4t.json",
        "aircraft_path": "app/data/aircraft/stik_glow_fs64v_4t.json",
        "propeller": "Master Airscrew K Series 14x6, 1/4-inch shaft",
        "build_id": "fs64v_master_airscrew_k_14x6",
        "candidate_fuel": "72/10/18 volume percent methanol/nitromethane/castor oil",
        "engine_reference": "https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html",
        "field_reference": "https://www.os-engines.co.jp/web_content/202210/index_1.html",
        "prop_reference": "https://www.masterairscrew.com/products/k-series-14x6-propeller",
    },
)

MANEUVERS: tuple[dict[str, Any], ...] = (
    {
        "id": "warm_idle_transition",
        "title": "Warm idle and throttle transitions",
        "steps": [
            "At the preselected safe height, repeat idle-to-full-to-idle twice with 5-second plateaus.",
            "Record start attempts, stalls, hesitation, recovery, RPM trace and handling rating.",
        ],
    },
    {
        "id": "takeoff_climb",
        "title": "Takeoff and climb",
        "steps": [
            "Score the takeoff and climb to the preselected safe test height; hold that height for 20 seconds.",
            "Record takeoff distance, time to height, climb rate, input corrections and any safety stop.",
        ],
    },
    {
        "id": "cruise_hold",
        "title": "Cruise hold",
        "steps": [
            "At safe height, stabilize level flight at 50 percent throttle command for 30 seconds.",
            "Record airspeed, altitude change, RPM, corrections and pilot workload.",
        ],
    },
    {
        "id": "throttle_loading",
        "title": "Throttle loading and recovery",
        "steps": [
            "At safe height, repeat 25-to-75-to-25 percent throttle command three times.",
            "Hold each endpoint for 3 seconds and use the same aircraft attitude target on every trial.",
            "Record RPM rise/fall, hesitation, overshoot, sound impression when audible and corrections.",
        ],
    },
    {
        "id": "engine_out_glide",
        "title": "Engine cutoff and glide",
        "steps": [
            "At safe height in stable level flight, press F6 once to cut fuel and combustion.",
            "Glide for 20 seconds without pressing F7; then land or end the trial using the prebriefed route.",
            "Record RPM decay, glide control, trim change, restart expectation and any safety stop.",
        ],
    },
    {
        "id": "sound_order_review",
        "title": "Idle, midrange, full-power sound review",
        "steps": [
            "At safe height in straight flight, hold idle, mid throttle and full throttle for 5 seconds each.",
            "Reduce to idle after the full-power hold and follow the prebriefed landing route; press F6 only after touchdown.",
            "Record perceived event cadence, modulation, valve/mechanical cues and propeller contribution.",
            "Rate sound only after the flight/handling ratings. In a muted trial, leave sound ratings blank.",
        ],
    },
)


def _sha256(relative_path: str) -> str:
    return hashlib.sha256((ROOT / relative_path).read_bytes()).hexdigest()


def _family_manifest(family: dict[str, Any]) -> dict[str, Any]:
    profile = json.loads((ROOT / family["profile_path"]).read_text(encoding="utf-8"))
    aircraft = json.loads((ROOT / family["aircraft_path"]).read_text(encoding="utf-8"))
    installation = json.loads((ROOT / family["installation_path"]).read_text(encoding="utf-8"))
    if profile.get("id") != family["profile_id"] or profile.get("family") != family["family"]:
        raise ValueError(f"candidate profile identity changed: {family['profile_path']}")
    if aircraft.get("id") != family["catalog_id"]:
        raise ValueError(f"aircraft identity changed: {family['aircraft_path']}")
    if installation.get("family") != family["family"]:
        raise ValueError(f"installation family changed: {family['installation_path']}")
    profile_fuel = profile["fuel"]
    oil_fraction = float(profile_fuel["lubricant_volume_fraction"]["value"])
    nitro_fraction = float(profile_fuel["nitromethane_volume_fraction"]["value"])
    methanol_fraction = 1.0 - nitro_fraction - oil_fraction
    if abs(methanol_fraction + nitro_fraction + oil_fraction - 1.0) > 1e-12:
        raise ValueError(f"fuel fractions do not sum to one for {family['profile_id']}")
    return {
        "family": family["family"],
        "catalog_id": family["catalog_id"],
        "engine": family["engine"],
        "profile": {
            "id": family["profile_id"],
            "status": profile.get("status"),
            "path": family["profile_path"],
            "sha256": _sha256(family["profile_path"]),
        },
        "installation": {
            "path": family["installation_path"],
            "sha256": _sha256(family["installation_path"]),
        },
        "aircraft_data": {
            "path": family["aircraft_path"],
            "sha256": _sha256(family["aircraft_path"]),
            "airframe": "Jensen Stik 60 geometry; physical build identity/weight/CG must be recorded separately",
        },
        "propeller": {
            "build_id": family["build_id"],
            "description": family["propeller"],
            "physical_part_number_or_lot": None,
            "reference_url": family["prop_reference"],
        },
        "fuel": {
            "candidate_profile_blend_volume_fraction": {
                "methanol": methanol_fraction,
                "nitromethane": nitro_fraction,
                "castor_oil": oil_fraction,
            },
            "physical_test_recipe": family["candidate_fuel"],
            "physical_lot": None,
            "physical_density_kg_m3": None,
            "match_required": True,
            "note": "The candidate profile treats lubricant as inert. Matching volume fractions controls blend composition but does not validate oil energy or chemistry. If the physical blend differs, record it and treat the comparison as fuel-mismatched.",
        },
        "provenance": {
            "engine_specification": family["engine_reference"],
            "real_observation": family["field_reference"],
        },
    }


def _pilot_response() -> dict[str, Any]:
    return {
        "handling_similarity_to_real_reference_1_to_7": None,
        "response_predictability_1_to_7": None,
        "workload_1_to_7": None,
        "confidence_1_to_7": None,
        "sound_realism_1_to_7": None,
        "family_guess": None,
        "audio_state_guess": None,
        "material_discrepancy": "",
        "free_text": "",
    }


def build_protocol(seed: int = 20261013) -> dict[str, Any]:
    if not isinstance(seed, int) or seed < 0 or seed > MASK64:
        raise ValueError("seed must be an integer from 0 through 2^64-1")
    rng = SplitMix64(seed)
    family_by_key = {family["key"]: family for family in FAMILIES}
    family_order = [family["key"] for family in FAMILIES]
    rng.shuffle(family_order)
    trials: list[dict[str, Any]] = []
    cards: list[dict[str, Any]] = []
    order_number = 0

    for family_key in family_order:
        family = family_by_key[family_key]
        pairs = [
            (maneuver["id"], repetition)
            for maneuver in MANEUVERS
            for repetition in (1, 2)
        ]
        rng.shuffle(pairs)
        on_first = [True] * (len(pairs) // 2) + [False] * (len(pairs) // 2)
        rng.shuffle(on_first)
        for (maneuver_id, repetition), audio_on_first in zip(pairs, on_first):
            maneuver = next(item for item in MANEUVERS if item["id"] == maneuver_id)
            pair_id = f"{family_key}-{maneuver_id}-r{repetition}"
            conditions = ["audio_on", "muted"] if audio_on_first else ["muted", "audio_on"]
            for condition in conditions:
                order_number += 1
                pilot_token = f"P{order_number:03d}"
                trial = {
                    "order": order_number,
                    "pilot_token": pilot_token,
                    "operator_only": {
                        "family": family["family"],
                        "catalog_id": family["catalog_id"],
                        "profile_id": family["profile_id"],
                        "propeller_build_id": family["build_id"],
                        "pair_id": pair_id,
                        "audio_condition": condition,
                        "condition_order_within_pair": 1 if condition == conditions[0] else 2,
                    },
                    "maneuver_id": maneuver_id,
                    "repetition": repetition,
                    "operator_result": {
                        "run_status": "not_run",
                        "trace_path": None,
                        "trace_sha256": None,
                        "audio_capture_path": None,
                        "safety_stop": None,
                        "deviations": [],
                        "notes": "",
                    },
                    "pilot_response": _pilot_response(),
                }
                trials.append(trial)
                cards.append({
                    "order": order_number,
                    "pilot_token": pilot_token,
                    "maneuver_id": maneuver_id,
                    "title": maneuver["title"],
                    "steps": maneuver["steps"],
                    "common_start_sequence_ref": "common_start_sequence",
                    "rating_instruction": "Rate this run before discussing it. Record your family and audio-state guess only after the ratings.",
                })

    return {
        "schema": SCHEMA,
        "protocol": "NITRO-03 pilot review",
        "protocol_date": "2026-10-13",
        "status": "not_performed",
        "seed": seed,
        "randomization": {
            "algorithm": "SplitMix64, unsigned 64-bit arithmetic, Fisher-Yates shuffle",
            "family_block_order": family_order,
            "counterbalance": "Within each family, 12 maneuver/repetition pairs contain exactly 6 audio-on-first and 6 muted-first pairs.",
            "repeats_per_maneuver_per_family": 2,
            "audio_conditions": ["audio_on", "muted"],
        },
        "blinding": {
            "pilot_material": "pilot_cards contains opaque trial tokens and maneuver instructions only; do not give the operator schedule to the pilot.",
            "family_label": "Mask the app's family and profile labels with an external monitor mask/crop; launch and select the aircraft while the pilot is away from the screen.",
            "audio_condition": "Audio-on versus mute is perceptible and cannot be blinded. Keep the condition order hidden before each run and record the pilot's post-rating guess.",
            "validity_rule": "If family/profile metadata is visible to the pilot, record the exposure and classify family blinding as failed; do not describe the block as blinded.",
        },
        "run_controls": {
            "launch": "Open the pinned Godot build with no user arguments to reach Home; the direct --quick-flight route starts airborne and is not the runway protocol.",
            "pilot_input": "Use one calibrated Mode 2 USB transmitter/gamepad for all trials; record device, mapping, deadband, reversals and rate setting. Keyboard fallback: arrows roll/pitch, A/D rudder, S/W throttle; this is digital input and must be declared.",
            "rates": "normal",
            "engine_keys": {
                "F6": "cut fuel/combustion",
                "F7": "starter",
                "F8": "set mixture to 0.85 times the profile nominal equivalence ratio",
                "F9": "set mixture to 1.15 times the profile nominal equivalence ratio",
                "R": "reset to the selected runway start",
                "T": "start/stop trace recording; capture the saved trace path and SHA-256",
            },
            "baseline_mixture": "Leave mixture at profile nominal for every A/B flight trial; F8/F9 are reserved for separately documented rich/lean diagnostic work.",
            "audio": "Use the same Windows output device and simulator application volume at 50 percent for audio-on trials; set only this application's Volume Mixer level to 0 percent for muted trials. Keep master volume/effects fixed and hidden from the pilot. Mixer percentage is a repeatable setting, not a calibrated sound-pressure level.",
            "environment": "In Home, explicitly choose the default field, calm/default weather, daylight, Runway start and pilot view. Keep the same overlay preset and do not enable developer overlays. Home preferences persist, so inspect and record the actual settings before the first run.",
            "start": "Choose the named aircraft and Runway in Home. The runway-start engine is warm but stopped; press F7. Reset with R between trials.",
        },
        "common_start_sequence": COMMON_START_SEQUENCE,
        "test_conditions": {
            "field_id": "default",
            "weather": "calm/default; freeze and record the exact settings before the first run",
            "time_of_day": "default daylight; keep unchanged",
            "pilot_view": "pilot",
            "rates": "normal",
            "target_test_height_agl_m": None,
            "target_height_note": "Choose one safe height before the session and hold it constant; record the numeric height here.",
            "baseline_throttle_command": 0.5,
            "throttle_loading_sequence_percent": [25, 75, 25],
            "throttle_loading_endpoint_hold_s": 3,
            "idle_to_full_to_idle_plateau_s": 5,
            "engine_out_glide_s": 20,
        },
        "ratings": {
            "scale": "1 to 7; 1=very poor/very dissimilar, 4=neutral or mixed, 7=very good/very similar; workload uses 1=very low and 7=very high.",
            "sound_rating": "Complete only for audio-on trials. Muted sound ratings stay null, not zero.",
            "acceptance": "Ratings are descriptive. A family passes only after the experienced pilot has no material unexplained discrepancy against its labeled real reference; use the plan's separate physical budgets and trace evidence. Do not average away a safety-relevant mismatch or force a family preference.",
        },
        "simulation_build": {
            "godot_version": "4.7.2-stable",
            "release_binary_sha256": None,
            "release_pack_sha256": None,
            "source_revision": None,
            "pilot_machine_and_display": None,
            "audio_output_device_and_fixed_volume_percent": None,
            "input_device_mapping": None,
        },
        "pilot": {
            "participant_code": None,
            "experience_years": None,
            "seasons_flying_2t": None,
            "seasons_flying_4t": None,
            "familiar_with_both_real_baselines": None,
            "notes": "",
        },
        "families": {family["family"]: _family_manifest(family) for family in FAMILIES},
        "real_reference": {
            family["family"]: {
                "status": "not_performed",
                "airframe_build_and_revision": None,
                "engine_serial_and_hours": None,
                "propeller_part_and_condition": None,
                "plug_and_silencer_identity": None,
                "fuel_lot_recipe_and_density": None,
                "installed_mass_cg_and_inertia_record": None,
                "tach_temperature_fuel_instruments_and_calibration": None,
                "atmosphere_and_wind_record": None,
                "audio_reference_clip_tach_sync_and_calibration": None,
                "flight_trace_and_measurement_paths": [],
                "pilot_familiarization_notes": "",
            }
            for family in FAMILIES
        },
        "physical_endurance_blocks": {
            family["family"]: {
                "status": "not_performed",
                "duty_cycle_definition_frozen_before_run": None,
                "full_usable_tank_mass_kg": None,
                "elapsed_time_s": None,
                "fuel_remaining_kg": None,
                "measurement_path_and_sha256": None,
                "note": "One separate logged physical duty-cycle/endurance block per family; do not duplicate it as an audio preference trial.",
            }
            for family in FAMILIES
        },
        "conclusions": {
            family["family"]: {"status": "not_performed", "material_discrepancies": [], "pilot_assessment": None}
            for family in FAMILIES
        },
        "operator_schedule": trials,
        "pilot_cards": cards,
        "not_performed_note": "This is a generated randomized schedule and blank form, not a pilot result. No participant, physical baseline, trial, or acceptance outcome is recorded.",
    }


def validate_review(review: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if review.get("schema") != SCHEMA:
        errors.append(f"schema must be {SCHEMA}")
    status = review.get("status")
    if status not in {"not_performed", "in_progress", "complete"}:
        errors.append("status must be not_performed, in_progress, or complete")
    trials = review.get("operator_schedule")
    cards = review.get("pilot_cards")
    if not isinstance(trials, list) or len(trials) != 48:
        errors.append("operator_schedule must contain exactly 48 seeded trials")
        trials = []
    if not isinstance(cards, list) or len(cards) != len(trials):
        errors.append("pilot_cards must contain one participant-facing card per operator trial")
        cards = []

    tokens = [trial.get("pilot_token") for trial in trials if isinstance(trial, dict)]
    if len(tokens) != len(set(tokens)):
        errors.append("pilot tokens must be unique")
    pair_members: dict[str, list[dict[str, Any]]] = {}
    coverage: dict[tuple[str, str, int, str], int] = {}
    for trial in trials:
        if not isinstance(trial, dict):
            errors.append("each operator schedule item must be an object")
            continue
        operator = trial.get("operator_only", {})
        result = trial.get("operator_result", {})
        response = trial.get("pilot_response", {})
        if operator.get("family") not in {"glow_2t", "glow_4t"}:
            errors.append(f"{trial.get('pilot_token')}: unknown family")
        if operator.get("audio_condition") not in {"audio_on", "muted"}:
            errors.append(f"{trial.get('pilot_token')}: unknown audio condition")
        else:
            key = (str(operator.get("family")), str(trial.get("maneuver_id")),
                   trial.get("repetition"), str(operator.get("audio_condition")))
            coverage[key] = coverage.get(key, 0) + 1
        pair_id = operator.get("pair_id")
        if isinstance(pair_id, str):
            pair_members.setdefault(pair_id, []).append(trial)
        if result.get("run_status") not in TRIAL_STATUSES:
            errors.append(f"{trial.get('pilot_token')}: invalid run status")
        if status == "not_performed":
            if result.get("run_status") != "not_run":
                errors.append(f"{trial.get('pilot_token')}: not_performed review contains a run")
            if any(value not in (None, "", [], {}) for value in response.values()):
                errors.append(f"{trial.get('pilot_token')}: not_performed review contains pilot responses")
        if status == "complete":
            if result.get("run_status") != "completed":
                errors.append(f"{trial.get('pilot_token')}: complete review has an incomplete trial")
            if not result.get("trace_path") or not result.get("trace_sha256"):
                errors.append(f"{trial.get('pilot_token')}: complete review lacks trace provenance")
            for key in (
                "handling_similarity_to_real_reference_1_to_7",
                "response_predictability_1_to_7",
                "workload_1_to_7",
                "confidence_1_to_7",
            ):
                value = response.get(key)
                if not isinstance(value, int) or not 1 <= value <= 7:
                    errors.append(f"{trial.get('pilot_token')}: complete review lacks valid {key}")
            sound_rating = response.get("sound_realism_1_to_7")
            if operator.get("audio_condition") == "audio_on" and (not isinstance(sound_rating, int) or not 1 <= sound_rating <= 7):
                errors.append(f"{trial.get('pilot_token')}: audio-on trial lacks a sound rating")
            if operator.get("audio_condition") == "muted" and sound_rating is not None:
                errors.append(f"{trial.get('pilot_token')}: muted trial must leave sound rating null")
    if len(pair_members) != 24:
        errors.append("schedule must contain exactly 24 paired maneuver/repetition blocks")
    first_condition_counts = {"glow_2t": {"audio_on": 0, "muted": 0},
                              "glow_4t": {"audio_on": 0, "muted": 0}}
    for pair_id, members in pair_members.items():
        ordered = sorted(members, key=lambda item: item.get("operator_only", {}).get("condition_order_within_pair", 0))
        conditions = [item.get("operator_only", {}).get("audio_condition") for item in ordered]
        if conditions != ["audio_on", "muted"] and conditions != ["muted", "audio_on"]:
            errors.append(f"{pair_id}: each pair must contain audio-on and muted exactly once")
        elif len(ordered) == 2:
            family = ordered[0].get("operator_only", {}).get("family")
            if family in first_condition_counts:
                first_condition_counts[family][conditions[0]] += 1
    for family, counts in first_condition_counts.items():
        if counts != {"audio_on": 6, "muted": 6}:
            errors.append(f"{family}: condition order is not balanced 6/6")
    expected_coverage = {
        (family, maneuver["id"], repetition, condition)
        for family in ("glow_2t", "glow_4t")
        for maneuver in MANEUVERS
        for repetition in (1, 2)
        for condition in ("audio_on", "muted")
    }
    if set(coverage) != expected_coverage or any(count != 1 for count in coverage.values()):
        errors.append("schedule must contain every family/maneuver/repetition/audio-condition cell exactly once")
    for card in cards:
        if not isinstance(card, dict):
            continue
        forbidden = {"family", "catalog_id", "profile_id", "propeller_build_id", "audio_condition"}
        if forbidden.intersection(card):
            errors.append("pilot-facing cards must not disclose family, profile, propeller or audio condition")
            break
    card_tokens = [card.get("pilot_token") for card in cards if isinstance(card, dict)]
    if len(card_tokens) != len(tokens) or set(card_tokens) != set(tokens):
        errors.append("pilot cards must map one-to-one to the operator tokens")

    if status == "complete":
        pilot = review.get("pilot", {})
        if not pilot.get("participant_code") or pilot.get("familiar_with_both_real_baselines") is not True:
            errors.append("complete review requires an identified experienced pilot familiar with both real baselines")
        for family in ("glow_2t", "glow_4t"):
            reference = review.get("real_reference", {}).get(family, {})
            if reference.get("status") != "completed" or not reference.get("flight_trace_and_measurement_paths"):
                errors.append(f"complete review requires labeled real-reference evidence for {family}")
            conclusion = review.get("conclusions", {}).get(family, {})
            if conclusion.get("status") not in {"accepted", "open", "not_accepted"} or not conclusion.get("pilot_assessment"):
                errors.append(f"complete review requires a recorded acceptance disposition for {family}")
    return errors


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=20261013, help="fixed unsigned 64-bit schedule seed")
    parser.add_argument("--out", type=Path, default=TEMPLATE_PATH, help="operator template output path")
    parser.add_argument("--pilot-cards-out", type=Path, help="optional separate, identity/condition-masked pilot card file")
    parser.add_argument("--validate", type=Path, help="validate an existing review JSON without changing it")
    args = parser.parse_args(argv)
    if args.validate is not None:
        try:
            review = json.loads(args.validate.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"cannot read review JSON: {exc}", file=sys.stderr)
            return 2
        errors = validate_review(review)
        if errors:
            print("Review validation failed:")
            for error in errors:
                print(f"- {error}")
            return 1
        print(f"Valid review record: status={review['status']}; this does not mean pilot acceptance passed.")
        return 0
    try:
        review = build_protocol(args.seed)
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as exc:
        print(f"cannot generate review schedule: {exc}", file=sys.stderr)
        return 2
    _write_json(args.out, review)
    if args.pilot_cards_out is not None:
        _write_json(args.pilot_cards_out, {
            "schema": "openrc-glow-pilot-cards v1",
            "seed": args.seed,
            "common_start_sequence": review["common_start_sequence"],
            "rating_anchors": review["ratings"],
            "cards": review["pilot_cards"],
        })
    print(f"Wrote {len(review['operator_schedule'])} randomized trials; status remains not_performed: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
