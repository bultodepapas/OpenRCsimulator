#!/usr/bin/env python3
"""Compare the frozen calm baseline with calm, steady, and gusty core snapshots."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
SNAPSHOT_FIELDS = ("snapshot_sha256", "trajectory_sha256", "state", "aux", "continuous", "modes", "inputs", "loads")
REGIMES = ("trim", "stall", "ground")


def read_report(path: Path) -> dict:
	return json.loads(path.read_text())


def aircraft_map(report: dict) -> dict[str, dict]:
	return {entry["id"]: entry for entry in report["aircraft"]}


def check_fault_free(report: dict, label: str) -> None:
	for aircraft in report["aircraft"]:
		for regime in REGIMES:
			timing = aircraft["regimes"][regime]["timing"]
			assert timing["fault"] == "", f"{label}/{aircraft['id']}/{regime}: {timing['fault']}"
			assert len(timing["samples_us_per_tick"]) == report["samples"], f"{label}/{aircraft['id']}/{regime}: incomplete timing batches"
		checkpoints = aircraft["regimes"]["trim"]["checkpoints"]
		assert checkpoints["ok"] and checkpoints["ticks"] == 480, f"{label}/{aircraft['id']}: incomplete checkpoint flight"
		assert [row["tick"] for row in checkpoints["checkpoints"]] == [0, 240, 480], f"{label}/{aircraft['id']}: wrong checkpoint times"


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--baseline", type=Path, default=HERE / "baseline.json")
	parser.add_argument("--calm", type=Path, default=HERE / "core-calm.json")
	parser.add_argument("--steady", type=Path, default=HERE / "core-steady.json")
	parser.add_argument("--gusty", type=Path, default=HERE / "core-gusty.json")
	args = parser.parse_args()
	reports = {
		"baseline": read_report(args.baseline),
		"calm": read_report(args.calm),
		"steady": read_report(args.steady),
		"gusty": read_report(args.gusty),
	}
	baseline = reports["baseline"]
	core = {name: reports[name] for name in ("calm", "steady", "gusty")}
	manifest = read_report(HERE / "core-source-manifest.json")
	assert baseline["format"] == "openrc-wind-bench v1"
	assert all(report["format"] == baseline["format"] for report in core.values())
	assert baseline["weather_requested"] == "calm"
	assert all(report["samples"] == 5 and report["ticks_per_sample"] == 240 and report["warmup_ticks_per_sample"] == 240 for report in reports.values())
	assert all(report["source_revision"] == f"wind-core-{manifest['snapshot_sha256']}" for report in core.values())
	assert all(model["identical"] and model["baseline_sha256"] == model["overlay_sha256"] for model in manifest["aircraft_models"].values())
	check_fault_free(baseline, "baseline")
	for name, report in core.items():
		check_fault_free(report, name)
	assert core["calm"]["aircraft"][0]["weather_setup"]["configuration"]["speed_mps"] == 0.0
	assert core["steady"]["aircraft"][0]["weather_setup"]["configuration"]["speed_mps"] == 3.0
	assert core["gusty"]["aircraft"][0]["weather_setup"]["configuration"]["gust_delay_s"] == 0.0
	for aircraft in core["steady"]["aircraft"]:
		for sample in aircraft["weather_samples_ned_mps"]:
			assert sample["wind_ned_mps"] == [0.0, 3.0, 0.0], f"{aircraft['id']}: steady wind sample changed"
	for aircraft in core["gusty"]["aircraft"]:
		peak = next(sample["wind_ned_mps"] for sample in aircraft["weather_samples_ned_mps"] if sample["time_s"] == 2.0)
		assert peak == [0.0, 6.0, -1.5], f"{aircraft['id']}: gust peak changed: {peak}"

	base_aircraft = aircraft_map(baseline)
	core_aircraft = {name: aircraft_map(report) for name, report in core.items()}
	assert set(base_aircraft) == set(core_aircraft["calm"]) == set(core_aircraft["steady"]) == set(core_aircraft["gusty"])
	print("aircraft | fixture | baseline calm | core calm | steady 3 m/s | gusty delay 0 s | steady Δ vs calm | gusty Δ vs calm")
	for aircraft_id, base in base_aircraft.items():
		old_checkpoints = base["regimes"]["trim"]["checkpoints"]["checkpoints"]
		calm_checkpoints = core_aircraft["calm"][aircraft_id]["regimes"]["trim"]["checkpoints"]["checkpoints"]
		assert len(old_checkpoints) == len(calm_checkpoints)
		for old, new in zip(old_checkpoints, calm_checkpoints):
			assert old["tick"] == new["tick"]
			for field in SNAPSHOT_FIELDS:
				assert old[field] == new[field], f"{aircraft_id}/tick {old['tick']}: calm {field} changed"
		for regime in REGIMES:
			values = {
				name: aircraft_map(reports[name])[aircraft_id]["regimes"][regime]["timing"]["median_us_per_tick"]
				for name in reports
			}
			steady_delta = 100.0 * (values["steady"] / values["calm"] - 1.0)
			gust_delta = 100.0 * (values["gusty"] / values["calm"] - 1.0)
			print(
				f"{aircraft_id} | {regime} | {values['baseline']:.2f} | {values['calm']:.2f} | "
				f"{values['steady']:.2f} | {values['gusty']:.2f} | {steady_delta:+.1f}% | {gust_delta:+.1f}%"
			)
		steady_checkpoints = core_aircraft["steady"][aircraft_id]["regimes"]["trim"]["checkpoints"]["checkpoints"]
		gust_checkpoints = core_aircraft["gusty"][aircraft_id]["regimes"]["trim"]["checkpoints"]["checkpoints"]
		assert steady_checkpoints[0]["state"] == gust_checkpoints[0]["state"], f"{aircraft_id}: steady/gust mean-wind starts differ"
		assert all(steady_checkpoints[i]["trajectory_sha256"] != gust_checkpoints[i]["trajectory_sha256"] for i in (1, 2)), f"{aircraft_id}: active gust did not change the trajectory"
	print("calm checkpoints at ticks 0/240/480: exact numeric and hash parity for state, auxiliary, continuous, modes, inputs, and loads on all four aircraft")
	print("steady/gust checkpoints at 240/480: complete, fault-free, and distinct after the gust waveform begins")


if __name__ == "__main__":
	main()
