# BAT-06 independent-oracle probe: evaluate the runtime pack_ecm law on seeded random states of shipped packs and
# write inputs and outputs for research/battery/bat-06/compare_law.py (research/battery/ecm_reference.py oracle).
# Run from the repository root:
#   "$(app/get-godot.sh)" --headless --path app --script "$PWD/research/battery/bat-06/law_probe.gd" -- --out=/tmp/bat06.json
extends SceneTree

const BatteryData: Script = preload("res://physics/battery/battery_data.gd")
const PackEcm: Script = preload("res://physics/battery/pack_ecm.gd")

const PACKS: Array[String] = ["lipo-4s1p-3200-30c-class", "lipo-6s1p-5000-30c-class", "liion-4s2p-6000-hg2"]
const CASES_PER_PACK: int = 400
const MOTOR := {"kv_rpm_per_volt": 800.0, "resistance_ohm": 0.08, "no_load_current_a": 1.2}


func _initialize() -> void:
	var out_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var report: Dictionary = {"format": "openrc-bat06-law-probe-v1", "motor": MOTOR, "cases": []}
	for pack_id: String in PACKS:
		var errors := PackedStringArray()
		var pack: Dictionary = BatteryData.load_pack(errors, pack_id, pack_id, BatteryData.file_sha256(BatteryData.PACK_DIR + pack_id + ".json"))
		if pack.is_empty():
			push_error("pack %s refused: %s" % [pack_id, ", ".join(errors)])
			quit(1)
			return
		for index: int in CASES_PER_PACK:
			var battery: Dictionary = pack.duplicate()
			battery.merge({"kind": "pack_ecm", "initial_soc": rng.randf_range(0.3, 1.0),
				"auxiliary_current_a": rng.randf_range(0.0, 1.0), "cooling_airflow_fraction": rng.randf_range(0.0, 0.5),
				"weak_capacity_factor": rng.randf_range(0.8, 1.0), "weak_resistance_factor": rng.randf_range(1.0, 2.0),
				"weak_soc_offset": rng.randf_range(0.0, 0.1), "lvc_filter_s": rng.randf_range(0.02, 0.5)}, true)
			var block := PackedFloat64Array()
			block.resize(PackEcm.block_size(battery))
			var q0: float = PackEcm.weak_initial_charge_c(battery)
			block[PackEcm.Q] = 0.0 if index % 50 == 0 else rng.randf_range(0.0, 1.0) * q0
			block[PackEcm.ENERGY] = rng.randf_range(0.0, 1e5)
			block[PackEcm.LOSS] = rng.randf_range(0.0, 1e4)
			for k: int in 2 * int(battery.branches):
				block[PackEcm.RC + k] = rng.randf_range(-0.02, 0.15)
			block[PackEcm.temperature_index(battery)] = rng.randf_range(263.15, 323.15)
			block[PackEcm.sense_index(battery)] = rng.randf_range(10.0, 25.0)
			block[PackEcm.limit_index(battery)] = rng.randf_range(0.0, 1.0) if index % 3 == 0 else 1.0
			block[PackEcm.cells_index(battery)] = float(battery.series)
			var rpm: float = rng.randf_range(0.0, 14000.0)
			var duty: float = rng.randf_range(0.0, 1.0)
			var enabled: bool = index % 7 != 0
			var ambient: float = rng.randf_range(263.15, 313.15)
			var airspeed: float = rng.randf_range(0.0, 30.0)
			var cooling: float = float(battery.cooling_airflow_fraction) * airspeed
			var point: Dictionary = PackEcm.evaluate(rpm, duty, enabled, block, battery, MOTOR, ambient, cooling)
			report.cases.append({"pack": pack_id, "initial_soc": battery.initial_soc, "auxiliary_current_a": battery.auxiliary_current_a,
				"cooling_airflow_fraction": battery.cooling_airflow_fraction, "capacity_factor": battery.weak_capacity_factor,
				"resistance_factor": battery.weak_resistance_factor, "soc_offset": battery.weak_soc_offset,
				"voltage_filter_s": battery.lvc_filter_s, "block": Array(block), "rpm": rpm, "duty": duty, "enabled": enabled,
				"ambient_k": ambient, "airspeed_mps": airspeed, "ok": point.get("ok", false), "message": point.get("message", ""),
				"bus_voltage_v": point.get("bus_voltage_v", NAN), "pack_current_a": point.get("pack_current_a", NAN),
				"motor_current_a": point.get("motor_current_a", NAN), "effective_duty": point.get("effective_duty", NAN),
				"pack_loss_w": point.get("pack_loss_w", NAN), "rates": Array(point.get("rates", PackedFloat64Array()))})
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "", false, true))
	file.close()
	print("BAT-06 probe: %d cases" % report.cases.size())
	quit(0)
