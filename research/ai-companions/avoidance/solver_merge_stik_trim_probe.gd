## Research-only Stik trim/state comparison for the solver-merge bridge.
## Run from each immutable application snapshot with --headless --path <app> --script <absolute path>
## -- --output=<new absolute JSON path>. No application input is changed.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Trim := preload("res://physics/trim.gd")

const SPEED_MPS := 15.0
const GRAVITY_MPS2 := 9.80665
const DENSITY_KG_M3 := 1.225
const AIRCRAFT_PATHS := [
	"res://data/aircraft/jensen_ugly_stik_60.json",
	"res://data/aircraft/stik_glow_61fx_2t.json",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := ""
	var external_pilot_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--external-pilot="):
			external_pilot_path = argument.trim_prefix("--external-pilot=")
	if output_path.is_empty() or not output_path.is_absolute_path() or FileAccess.file_exists(output_path):
		printerr("Supply a new absolute --output JSON path.")
		quit(2)
		return
	var report := {
		"format": "openrc-solver-merge-stik-trim-probe v1",
		"engine": Engine.get_version_info().string,
		"solver_sha256": FlightLog.solver_identity(),
		"mode": "level",
		"speed_mps": SPEED_MPS,
		"gravity_mps2": GRAVITY_MPS2,
		"density_kg_m3": DENSITY_KG_M3,
		"aircraft": [],
	}
	if not external_pilot_path.is_empty():
		var external_pilot: Resource = ResourceLoader.load(external_pilot_path)
		report["external_pilot"] = {
			"path": external_pilot_path,
			"is_script": external_pilot is Script,
			"can_instantiate": external_pilot is Script and (external_pilot as Script).can_instantiate(),
			"sha256": FileAccess.get_sha256(external_pilot_path),
		}
	var failed := false
	for path: String in AIRCRAFT_PATHS:
		var loaded: Dictionary = AircraftData.load_file(path)
		if not loaded.get("ok", false):
			failed = true
			report.aircraft.append({"path": path, "load_ok": false, "errors": loaded.get("errors", [])})
			continue
		var model: Dictionary = loaded.model
		var propulsion: Dictionary = model.get("propulsion", {})
		var installed_glow: Dictionary = propulsion.get("glow", {})
		var glow_propeller: Dictionary = installed_glow.get("propeller", {})
		var trim: Dictionary = Trim.solve("level", SPEED_MPS, model, GRAVITY_MPS2, model.controls.throw_rad,
			DENSITY_KG_M3, 1.0)
		var entry := {
			"path": path,
			"load_ok": true,
			"model_id": str(model.get("id", "")),
			"propulsion_source_kind": Propulsion.source_kind(propulsion),
			"modern_glow_installation_present": propulsion.has("glow"),
			"bounded_glow_trim_branch_active": Propulsion.is_glow(propulsion),
			"zero_lift_angle_rad": glow_propeller.get("zero_lift_angle_rad", "absent"),
			"input_identity": model.get("input_identity", {}),
			"trim_ok": bool(trim.get("ok", false)),
			"trim_message": str(trim.get("message", "")),
			"iterations": int(trim.get("iterations", -1)),
		}
		if trim.get("ok", false):
			for key: String in ["V", "alpha", "beta", "gamma", "throttle", "thrust", "rpm",
					"elevator", "aileron", "rudder", "pitch_command", "roll_command", "yaw_command", "residual"]:
				if trim.has(key):
					entry[key] = trim[key]
			var state: PackedFloat64Array = trim.get("state", PackedFloat64Array())
			var state_values: Array[float] = []
			for value: float in state:
				state_values.append(value)
			entry["initial_state"] = state_values
		else:
			failed = true
		report.aircraft.append(entry)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not create probe report.")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("STIK SOLVER MERGE TRIM PROBE COMPLETE %s" % output_path)
	quit(1 if failed else 0)
