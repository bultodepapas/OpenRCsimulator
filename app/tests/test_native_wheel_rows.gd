extends SceneTree
## NK-6o: the ground audio's wheel rows from the native stage (FlightSession.published_wheel_rows). On every published
## endpoint of takeoff rolls, steered and braked taxis, touchdowns and a lake-shore taxi, for fixed and retractable gear:
## - each native row equals Ground.evaluate's diagnostics and Wheels.frame bit for bit, and [0] answers exactly where
##   the reference has no diagnostics;
## - GroundAudioModel.snapshot_contacts returns the same bytes with the native rows on and off.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const GroundAudioModel := preload("res://audio/ground_audio_model.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const RB := preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0
var _field: Dictionary
var _lake: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var tested := 0
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60", "turbo-lumber-evolution", "stik-glow-61fx-2t",
			"p51d-mustang-120"]:
		var probe := _session(id, Flight.START_RUNWAY)
		if probe == null or probe.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE \
				or not probe._native_stage._native.has_method("stage_wheel_rows"):
			print("NK6O_SKIP %s" % id)
			if probe != null:
				probe.free()
			continue
		probe.free()
		tested += 1
		for scenario: String in ["roll", "taxi", "brake", "touchdown", "shore"]:
			_flight(id, scenario)
	if tested == 0:
		print("NK6O_SKIP no native session")
	print("native wheel rows: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, start: String) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.start_choice = start
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.reset()
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


func _flight(id: String, scenario: String) -> void:
	var s := _session(id, Flight.START_AIRBORNE if scenario == "touchdown" else Flight.START_RUNWAY)
	if s == null:
		return
	var holder := {tick = 0}
	if scenario == "touchdown":
		var state: PackedFloat64Array = s.sim.state.duplicate()
		state[RB.POS + 2] = -0.6
		state[RB.VEL + 2] = 2.0 # body-down sink onto the runway
		s.sim.state = state
		s.sim.previous = state.duplicate()
	elif scenario == "shore":
		var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
		var state: PackedFloat64Array = s.sim.state.duplicate()
		state[RB.POS] = bank[0] - 6.0
		state[RB.POS + 1] = (bank[2] + bank[3]) * 0.5
		s.sim.state = state
		s.sim.previous = state.duplicate()
	s.read_raw = func() -> Dictionary:
		match scenario:
			"taxi", "shore": return {roll = 0.0, pitch = 0.0, yaw = 0.5 * sin(float(holder.tick) / 90.0), throttle = 0.3}
			"brake": return {roll = 0.0, pitch = 0.0, yaw = 0.2, throttle = 0.5 if holder.tick < 500 else 0.0}
			"touchdown": return {roll = 0.0, pitch = -0.2, yaw = 0.0, throttle = 0.0}
		return {roll = 0.0, pitch = 0.1 if holder.tick > 700 else 0.0, yaw = 0.0, throttle = 1.0}
	var stats := {ticks = 0, rows = 0, beyond = 0, refused = 0, mismatched = 0, snapshot_mismatched = 0}
	var first := ""
	for tick in 960:
		holder.tick = tick
		if scenario == "brake" and tick == 500:
			s.set_wheel_brake(1.0)
		_tick(s)
		stats.ticks += 1
		var detail := _compare_rows(s, stats)
		if first.is_empty() and not detail.is_empty():
			first = "tick %d: %s" % [s.sim.tick, detail]
		s.native_wheel_rows_enabled = true
		var native: Array = GroundAudioModel.snapshot_contacts(s, {})
		s.native_wheel_rows_enabled = false
		var reference: Array = GroundAudioModel.snapshot_contacts(s, {})
		s.native_wheel_rows_enabled = true
		if var_to_bytes(native) != var_to_bytes(reference):
			stats.snapshot_mismatched += 1
			if first.is_empty():
				first = "tick %d snapshot differs" % s.sim.tick
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
	var label := "%s %s" % [id, scenario]
	_check(label + ": every native wheel row equals the reference", stats.mismatched == 0, first + str(stats))
	_check(label + ": the ground audio snapshot is byte-identical", stats.snapshot_mismatched == 0, first + str(stats))
	if scenario == "touchdown":
		_check(label + ": the touchdown reaches the wheels", stats.rows > 0, str(stats))
	else:
		_check(label + ": the native stage answered rolling endpoints", stats.rows > stats.ticks / 2, str(stats))
	print("NK6O_FLIGHT %s %s" % [label, str(stats)])
	s.free()


## The inputs snapshot_contacts gives the wheel law, then the native rows against Ground.evaluate and Wheels.frame.
func _compare_rows(s: Node, stats: Dictionary) -> String:
	var sim: Node = s.sim
	var state: PackedFloat64Array = sim.state
	var aux: PackedFloat64Array = sim.aux
	var gear: Dictionary = s.current_landing_gear(aux)
	var contacts: Array = gear.get("contacts", [])
	var wheel_count: int = s.wheel_count()
	var wheel_index: int = s.wheel_index()
	if contacts.is_empty() or wheel_count <= 0:
		return ""
	var steer: float = aux[3]
	var anchors: PackedFloat64Array = aux.slice(4, 4 + s.anchor_count() * Ground.ANCHOR_STRIDE)
	var speeds: PackedFloat64Array = sim.continuous.slice(wheel_index, wheel_index + wheel_count)
	var brake: float = float(sim.inputs[5]) if s.gear_is_retractable() and sim.inputs.size() > 5 else 0.0
	var rows: PackedFloat64Array = s.published_wheel_rows(state, steer, anchors, speeds, brake)
	var evaluation: Dictionary = Ground.evaluate(state, gear, steer, s.ground_surfaces, anchors, speeds, brake, true,
		s._lake, {})
	var diagnostics: Array = evaluation.get("wheels", [])
	if rows.is_empty():
		stats.refused += 1
		return ""
	if rows.size() == 1:
		stats.beyond += 1
		if not diagnostics.is_empty():
			stats.mismatched += 1
			return "[0] answered where the reference has diagnostics"
		return ""
	stats.rows += 1
	if diagnostics.size() != contacts.size() or int(rows[1]) != contacts.size():
		stats.mismatched += 1
		return "row count %d against %d diagnostics" % [int(rows[1]), diagnostics.size()]
	for i in contacts.size():
		var at: int = 2 + i * GroundAudioModel.WHEEL_ROW_SIZE
		var d: Dictionary = diagnostics[i]
		var f: Dictionary = Wheels.frame(state, contacts[i], steer, s.ground_surfaces, PackedFloat64Array(), true, s._lake,
			{})
		var expected := PackedFloat64Array([d.normal_load, d.longitudinal_force, d.lateral_force, d.rim_speed,
			f.compression])
		expected.append_array(f.position)
		expected.append_array(f.normal)
		expected.append_array(f.heading)
		expected.append_array(f.side)
		expected.append(f.long_speed)
		if var_to_bytes(rows.slice(at, at + GroundAudioModel.WHEEL_ROW_SIZE)) != var_to_bytes(expected):
			stats.mismatched += 1
			return "wheel %d: %s / %s" % [i, str(rows.slice(at, at + GroundAudioModel.WHEEL_ROW_SIZE)), str(expected)]
	return ""


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
