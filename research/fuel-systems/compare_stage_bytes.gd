## Fuel hardening proof: hash exact Glow stage queries against separate source checkouts.
## From the repository root, run this same file with each project path and keep stdout:
##   $godot = '.tools/Godot_v4.7.2-stable_win64_console.exe'
##   $probe = (Resolve-Path 'research/fuel-systems/compare_stage_bytes.gd').Path
##   & $godot --headless --path 'tmp/fuel-completion/final-snapshot/app' --audio-driver Dummy --script $probe *> 'tmp/fuel-hardening/20261019-r1/stage-before.log'
##   & $godot --headless --path app --audio-driver Dummy --script $probe *> 'tmp/fuel-hardening/20261019-r1/stage-after.log'
## Compare the stage_sha256 and result_bytes lines; they cover full point dictionaries,
## accepted loads, derivatives, rotor momentum and datum acceleration at 16 real-session samples.
extends SceneTree

const Flight := preload("res://physics/glow/flight.gd")
const Session := preload("res://sim/flight_session.gd")
const AIRCRAFT := "res://data/aircraft/stik_glow_55ax_2t.json"
const SAMPLE_COUNT := 16


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var flight: Node = Session.new()
	root.add_child(flight)
	flight.setup(AIRCRAFT)
	flight.input_enabled = false
	flight.set_physics_process(false)
	if not flight.is_flyable():
		printerr("fixture did not initialize: ", flight.sim.fault_reason)
		flight.free()
		quit(1)
		return
	var model: Dictionary = flight.aircraft.model
	var install: Dictionary = model.propulsion.glow
	var mass_reference: Dictionary = install.get("mass_reference", {})
	var reference_matches: bool = mass_reference.get("reference_mass_kg", NAN) == float(model.mass_kg) \
		and mass_reference.get("reference_inertia_kgm2", PackedFloat64Array()) == model.inertia
	var samples: Array = []
	for index: int in SAMPLE_COUNT:
		flight.sim.inputs[3] = float(index % 4) / 3.0
		var body: PackedFloat64Array = flight.sim.state.duplicate()
		var values: PackedFloat64Array = flight.sim.continuous.duplicate()
		var time_s: float = flight.sim.time()
		var point_before: Dictionary = Flight.point(flight, body, values, time_s)
		var evaluated: Dictionary = Flight.evaluate(body, values, time_s, flight)
		var point_after: Dictionary = Flight.point(flight, body, values, time_s)
		if not point_before.get("ok", false) or evaluated.is_empty() or not point_after.get("ok", false):
			printerr("stage query failed at sample ", index, ": ", flight.sim.fault_reason)
			flight.free()
			quit(1)
			return
		if var_to_bytes(point_before) != var_to_bytes(point_after):
			printerr("point query changed with intervening evaluate() at sample ", index)
			flight.free()
			quit(1)
			return
		samples.append([point_before, point_after, evaluated.loads, evaluated.derivative,
			evaluated.rotor_momentum, evaluated.body_derivative])
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			printerr("flight step failed at sample ", index, ": ", flight.sim.fault_reason)
			flight.free()
			quit(1)
			return
	var bytes: PackedByteArray = var_to_bytes(samples)
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(bytes)
	print("project_root=", ProjectSettings.globalize_path("res://"))
	print("aircraft=", AIRCRAFT)
	print("mass_reference_matches_model=", reference_matches)
	print("query_order_point_bytes_exact=true")
	print("stage_sha256=", hash_context.finish().hex_encode())
	print("query_count=", samples.size(), " result_bytes=", bytes.size())
	flight.free()
	quit(0)
