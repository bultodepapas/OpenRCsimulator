# BAT-10 law-only cost: interleaved blocks of EL2a ElectricSupply.evaluate_dynamics and PackEcm.evaluate (dynamics
# path) on the Timber motor at a mid-flight point. Wall-clock under shared load; read the ratio, not absolutes.
#   "$(app/get-godot.sh)" --headless --path app --script "$PWD/research/battery/bat-10/law_cost.gd"
extends SceneTree

const Supply: Script = preload("res://physics/electric_supply.gd")
const PackEcm: Script = preload("res://physics/battery/pack_ecm.gd")
const BatteryData: Script = preload("res://physics/battery/battery_data.gd")

const CALLS: int = 2000
const ROUNDS: int = 21
const MOTOR := {"kv_rpm_per_volt": 800.0, "resistance_ohm": 0.08, "no_load_current_a": 1.2}


func _initialize() -> void:
	var errors := PackedStringArray()
	var id := "lipo-4s1p-3200-30c-class"
	var battery: Dictionary = BatteryData.load_pack(errors, id, id, BatteryData.file_sha256(BatteryData.PACK_DIR + id + ".json"))
	battery.merge({"kind": "pack_ecm", "initial_soc": 1.0, "auxiliary_current_a": 0.3, "cooling_airflow_fraction": 0.1,
		"weak_capacity_factor": 1.0, "weak_resistance_factor": 1.0, "weak_soc_offset": 0.0, "lvc_filter_s": 0.1}, true)
	var block := PackedFloat64Array()
	block.resize(PackEcm.block_size(battery))
	block[PackEcm.Q] = 0.6 * PackEcm.weak_initial_charge_c(battery)
	block[PackEcm.temperature_index(battery)] = 300.0
	block[PackEcm.limit_index(battery)] = 1.0
	block[PackEcm.cells_index(battery)] = 4.0
	var pack := {"ocv_points": PackedFloat64Array([0.0, 12.0, 0.5, 14.8, 1.0, 16.8]), "capacity_ah": 3.2,
		"resistance_ohm": 0.022, "auxiliary_current_a": 0.3}
	var supply_us: Array = []
	var pack_us: Array = []
	for _round: int in ROUNDS:
		var started: int = Time.get_ticks_usec()
		for _i: int in CALLS:
			Supply.evaluate_dynamics(9000.0, 0.8, 0.6, pack, MOTOR, true, false)
		supply_us.append(float(Time.get_ticks_usec() - started) / CALLS)
		started = Time.get_ticks_usec()
		for _i: int in CALLS:
			PackEcm.evaluate(9000.0, 0.8, true, block, battery, MOTOR, 288.15, 2.0, false, true)
		pack_us.append(float(Time.get_ticks_usec() - started) / CALLS)
	supply_us.sort()
	pack_us.sort()
	var s: float = supply_us[ROUNDS / 2]
	var p: float = pack_us[ROUNDS / 2]
	print("EL2a supply dynamics median %.2f µs/call; pack_ecm dynamics median %.2f µs/call; ratio %.2f; extra per 4-stage tick %.1f µs" % [s, p, p / s, 4.0 * (p - s)])
	quit(0)
