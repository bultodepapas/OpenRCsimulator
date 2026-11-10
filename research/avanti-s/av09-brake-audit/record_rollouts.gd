# AV-09 / R2: identical seeded runway checkpoint, two stock-law command tapes.
# Technical FlightSession stepping with recorder; see evidence README for limits.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const AIRCRAFT := "res://data/aircraft/sebart_avanti_s_a200.json"
const SECONDS := 6.0
const START_SPEED := 3.0

var destination := ""
var errors: Array[String] = []
var checks := 0
var flight: Node
var csv: FileAccess


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			destination = arg.trim_prefix("--out=")
	if destination.is_empty() or DirAccess.dir_exists_absolute(destination):
		printerr("Use --out=<new absolute directory>")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		printerr("Cannot create output directory")
		quit(1)
		return
	Engine.physics_ticks_per_second = 240
	call_deferred("run")


func require(label: String, condition: bool) -> bool:
	checks += 1
	if not condition:
		errors.append(label)
		printerr("FAIL ", label)
	return condition


func run() -> void:
	flight = Flight.new()
	flight.input_enabled = false
	flight.crash_auto_restart = false
	root.add_child(flight)
	flight.setup(AIRCRAFT)
	var field: Dictionary = FieldLoader.load_from()
	if not require("flyable Avanti, profile, half fuel and field", flight.is_flyable() \
			and flight.wheel_count() == 3 and flight.wheel_brake_input_index() == 5 \
			and flight.set_fuel_start_fill(0.5) and field.ok and flight.set_field(field.field)):
		finish()
		return
	flight.reset()
	var spot: Dictionary = GroundStart.threshold(field.field)
	if not require("runway threshold exists", spot.ok):
		finish()
		return
	var start: Dictionary = flight.try_runway_start(spot.north, spot.east, spot.heading)
	if not require("stock runway pose converged", start.ok and flight.gear_state().extension == 1.0):
		finish()
		return
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	state[RB.VEL] = START_SPEED
	state[RB.VEL + 1] = 0.0
	state[RB.VEL + 2] = 0.0
	flight.sim.state = state
	flight.sim.previous = state.duplicate()
	var aux: PackedFloat64Array = flight.sim.aux.duplicate()
	for i in flight.anchor_count() * Ground.ANCHOR_STRIDE:
		aux[flight.AUX_ANCHORS + i] = 0.0
	flight.sim.aux = aux
	var gear: Dictionary = flight.current_landing_gear(aux)
	var continuous: PackedFloat64Array = flight.sim.continuous.duplicate()
	for i in flight.wheel_count():
		var frame: Dictionary = Wheels.frame(state, gear.contacts[i], aux[flight.AUX_SERVO + 2], flight.ground_surfaces)
		continuous[flight.wheel_index() + i] = frame.long_speed
	flight.sim.continuous = continuous
	flight.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0])
	flight.sim.set_paused(false)
	var checkpoint: Dictionary = flight.checkpoint()
	if not require("seeded checkpoint valid", not checkpoint.is_empty()):
		finish()
		return
	var boundary := boundary_bytes()
	var boundary_hash := sha256(boundary)
	var start_mass: Dictionary = flight.mass_properties()
	var start_engine: Dictionary = flight.turbine_state()
	var backend: Dictionary = flight.stage_backend_identity()
	csv = FileAccess.open(destination.path_join("wheel-endpoints.csv"), FileAccess.WRITE)
	if not require("wheel endpoint output opens", csv != null):
		finish()
		return
	csv.store_csv_line(PackedStringArray(["run", "tick", "time_s", "contact", "north_m", "east_m", "body_u_mps", "normal_load_n", "long_speed_mps", "rim_speed_mps", "long_slip_mps", "side_speed_mps", "slip_force_n", "rolling_force_n", "lateral_force_n", "brake_torque_nm"]))
	var outcomes := []
	for case in [{name = "coast", brake = 0.0}, {name = "brake", brake = 1.0}]:
		if case.name != "coast":
			if not require("restore initial checkpoint", flight.restore_checkpoint(checkpoint)):
				break
			flight.sim.set_paused(false)
		if not require("matched start state, auxiliary state, modes and inputs", boundary_bytes() == boundary):
			break
		var logger := FlightLog.new(flight)
		if not require("recorder starts " + case.name, logger.start(destination.path_join(case.name + ".orfl")) == OK):
			break
		logger.mark("R2 " + case.name + "; seeded moving runway state")
		var initial_tick: int = flight.sim.tick
		capture(case.name)
		for tick in roundi(SECONDS / flight.sim.dt()):
			var input: PackedFloat64Array = flight.sim.inputs.duplicate()
			input[5] = case.brake
			flight.sim.inputs = input
			var previous_tick: int = flight.sim.tick
			flight.sim.step()
			if flight.sim.tick != previous_tick + 1 or not flight.sim.fault_reason.is_empty() or not logger.failure.is_empty():
				errors.append(case.name + " interrupted at tick " + str(flight.sim.tick) + ": " + flight.sim.fault_reason + " " + logger.failure)
				break
			if (tick + 1) % 24 == 0:
				capture(case.name)
		var saved: Error = logger.stop("R2 " + case.name + " finished")
		require("recording completes " + case.name, saved == OK and logger.failure.is_empty() \
			and flight.sim.tick - initial_tick == roundi(SECONDS / flight.sim.dt()))
		outcomes.append({name = case.name, brake = case.brake, ticks = flight.sim.tick - initial_tick,
			end_state = Array(flight.sim.state), recorder_peak_buffer_rows = logger.peak_buffer_rows,
			log_sha256 = FileAccess.get_sha256(destination.path_join(case.name + ".orfl"))})
	csv.flush()
	csv.close()
	require("both matched runs completed", outcomes.size() == 2)
	var report := {checks = checks, errors = errors, checkpoint_boundary_sha256 = boundary_hash,
		aircraft_sha256 = FileAccess.get_sha256(AIRCRAFT), solver_sha256 = FlightLog.solver_identity(),
		stage_backend = backend, engine = Engine.get_version_info(), field_id = flight.ground_field_id,
		initial_body_speed_mps = START_SPEED, fuel_start_fill = 0.5, mass_properties = start_mass,
		turbine_start = start_engine, gear_state = flight.gear_state(),
		initial_state = Array(state), initial_continuous = Array(continuous),
		initial_inputs = [0, 0, 0, 0, 1, 0, 0], dt_s = flight.sim.dt(),
		maneuver = "seeded runway state, 6 s idle-throttle direct simulation ticks; brake 0 or 1 from first tick",
		outcomes = outcomes}
	var file := FileAccess.open(destination.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		errors.append("cannot write manifest")
	else:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		file.flush()
		file.close()
	finish()


func boundary_bytes() -> PackedByteArray:
	return var_to_bytes([flight.sim.state, flight.sim.previous, flight.sim.aux,
		flight.sim.continuous, flight.sim.modes, flight.sim.inputs, flight.sim.tick])


func sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func capture(label: String) -> void:
	var aux: PackedFloat64Array = flight.sim.aux
	var state: PackedFloat64Array = flight.sim.state
	var gear: Dictionary = flight.current_landing_gear(aux)
	var anchors: PackedFloat64Array = aux.slice(flight.AUX_ANCHORS, flight.AUX_ANCHORS + flight.anchor_count() * Ground.ANCHOR_STRIDE)
	var rim: PackedFloat64Array = flight.sim.continuous.slice(flight.wheel_index(), flight.wheel_index() + flight.wheel_count())
	var result := Wheels.evaluate(state, gear, aux[flight.AUX_SERVO + 2], flight.ground_surfaces, anchors, rim, flight.sim.inputs[5])
	if result.wheels.size() != flight.wheel_count():
		errors.append("diagnostics missing wheels at tick " + str(flight.sim.tick))
		return
	for i in result.wheels.size():
		var w: Dictionary = result.wheels[i]
		var frame: Dictionary = Wheels.frame(state, gear.contacts[i], aux[flight.AUX_SERVO + 2], flight.ground_surfaces)
		var row := [label, flight.sim.tick, flight.sim.time(), gear.contacts[i].name, state[RB.POS], state[RB.POS + 1], state[RB.VEL],
			w.normal_load, w.long_speed, w.rim_speed, w.longitudinal_slip, frame.side_speed,
			w.slip_force, w.rolling_force, w.lateral_force, w.brake_torque]
		var values := PackedStringArray()
		for value in row: values.append(String.num(value, 12) if value is float else str(value))
		csv.store_csv_line(values)


func finish() -> void:
	if flight != null: flight.free()
	print("AV09_ROLLOUT %d checks, %d failures" % [checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
