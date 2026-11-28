extends SceneTree
## NK-7k: the ground audio's rows for wheels beyond the terrain's reach but not clear of the ground (the native wheel
## rows' [0] band) and the skipped ticks' approach speeds, from the native stage. On every published endpoint of
## descents onto the runway, a low pass, a climb-out after a takeoff roll and a descent onto lake-covered ground, for
## fixed and retractable gear:
## - GroundAudioModel.snapshot_contacts returns the same bytes with the native rows on, with them off and with every
##   native answer off (the reference);
## - GroundAudioModel.approach_speeds returns the same speeds and identities with the native answer on and off.
## The native rows and speeds serve most band endpoints; a 1e-9 change to a row or a speed is detected.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const GroundAudioModel := preload("res://audio/ground_audio_model.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const RB := preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0
var _field: Dictionary
var _lake: Dictionary
var _row_mutation_seen := false
var _speed_mutation_seen := false


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
				or not probe._native_stage._native.has_method("stage_wheel_approach_speeds"):
			print("NK7K_SKIP %s" % id)
			if probe != null:
				probe.free()
			continue
		probe.free()
		tested += 1
		for scenario: String in ["descent", "low_pass", "climb_out", "lake_descent"]:
			_flight(id, scenario)
	if tested == 0:
		print("NK7K_SKIP no native session")
	else:
		_check("a 1e-9 change to a band row is detected", _row_mutation_seen)
		_check("a 1e-9 change to an approach speed is detected", _speed_mutation_seen)
	print("native audio band rows: %d checks, %d failed" % [_checks, _failures])
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


func _place(s: Node, north: float, east: float, height: float, sink: float) -> void:
	var state: PackedFloat64Array = s.sim.state.duplicate()
	state[RB.POS] = north
	state[RB.POS + 1] = east
	state[RB.POS + 2] = -(Terrain.sample(north, east, s.ground_surfaces, _lake)[0] + height)
	state[RB.VEL + 2] = sink
	s.sim.state = state
	s.sim.previous = state.duplicate()


func _flight(id: String, scenario: String) -> void:
	var s := _session(id, Flight.START_RUNWAY if scenario == "climb_out" else Flight.START_AIRBORNE)
	if s == null:
		return
	var holder := {tick = 0}
	match scenario:
		"descent":
			_place(s, s.sim.state[RB.POS], s.sim.state[RB.POS + 1], 6.0, 1.2)
		"low_pass":
			_place(s, s.sim.state[RB.POS], s.sim.state[RB.POS + 1], 3.0, 0.0)
		"climb_out":
			# A rolling start, so that every aircraft lifts off within the run.
			var rolling: PackedFloat64Array = s.sim.state.duplicate()
			rolling[RB.VEL] = 20.0
			s.sim.state = rolling
			s.sim.previous = rolling.duplicate()
		"lake_descent":
			var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
			var east: float = (bank[2] + bank[3]) * 0.5
			var north: float = bank[0] - 2.0
			while north < bank[1] and not bool(LakeSurface.sample_covered_terrain_validated(_lake, north, east) \
					.get("covered", false)):
				north += 0.25
			_place(s, north + 2.0, east, 4.0, 1.0)
	s.read_raw = func() -> Dictionary:
		match scenario:
			"descent", "lake_descent": return {roll = 0.0, pitch = -0.05, yaw = 0.0, throttle = 0.25}
			"low_pass": return {roll = 0.0, pitch = 0.04, yaw = 0.1 * sin(float(holder.tick) / 60.0), throttle = 0.7}
		return {roll = 0.0, pitch = 0.25 if holder.tick > 120 else 0.0, yaw = 0.0, throttle = 1.0}
	var stats := {ticks = 0, band = 0, native_rows = 0, native_speeds = 0, mismatched = 0, reference_mismatched = 0,
		speed_mismatched = 0}
	var first := ""
	for tick in 1200:
		holder.tick = tick
		_tick(s)
		stats.ticks += 1
		var rows_before: int = s.native_audio_row_answers
		var native: Array = GroundAudioModel.snapshot_contacts(s, {})
		var answered: bool = s.native_audio_row_answers > rows_before
		# The band: wheel rows [0] (beyond the terrain's reach) while snapshot_contacts still builds full rows.
		var band: bool = not GroundAudioModel.wheels_clear_of_ground(s) \
			and s.published_wheel_rows(s.sim.state, s.sim.aux[3], _anchors(s), _speeds(s), _brake(s)).size() == 1
		s.native_audio_rows_enabled = false
		var built: Array = GroundAudioModel.snapshot_contacts(s, {})
		s.native_wheel_rows_enabled = false
		var reference: Array = GroundAudioModel.snapshot_contacts(s, {})
		s.native_wheel_rows_enabled = true
		s.native_audio_rows_enabled = true
		if band:
			stats.band += 1
			if answered:
				stats.native_rows += 1
				if not _row_mutation_seen and not native.is_empty():
					var altered: Array = native.duplicate(true)
					altered[0].approach_speed_mps = float(altered[0].approach_speed_mps) + 1e-9
					_row_mutation_seen = var_to_bytes(altered) != var_to_bytes(built)
		if var_to_bytes(native) != var_to_bytes(built):
			stats.mismatched += 1
			if first.is_empty():
				first = "tick %d: %s / %s" % [s.sim.tick, str(native), str(built)]
		if var_to_bytes(built) != var_to_bytes(reference):
			stats.reference_mismatched += 1
			if first.is_empty():
				first = "tick %d: the GDScript rows differ from the reference" % s.sim.tick
		# The skipped ticks' approach speeds, wherever the rows are not clear of the ground.
		var speeds_before: int = s.native_approach_answers
		var native_ids := PackedStringArray()
		var native_speeds := GroundAudioModel.approach_speeds(s, native_ids)
		if s.native_approach_answers > speeds_before:
			stats.native_speeds += 1
			if not _speed_mutation_seen and not native_speeds.is_empty():
				var altered_speeds := native_speeds.duplicate()
				altered_speeds[0] += 1e-9
				_speed_mutation_seen = var_to_bytes(altered_speeds) != var_to_bytes(native_speeds)
		s.native_approach_speeds_enabled = false
		var reference_ids := PackedStringArray()
		var reference_speeds := GroundAudioModel.approach_speeds(s, reference_ids)
		s.native_approach_speeds_enabled = true
		if var_to_bytes(native_speeds) != var_to_bytes(reference_speeds) or native_ids != reference_ids:
			stats.speed_mismatched += 1
			if first.is_empty():
				first = "tick %d: speeds %s %s / %s %s" % [s.sim.tick, str(native_ids), str(native_speeds),
					str(reference_ids), str(reference_speeds)]
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
	var label := "%s %s" % [id, scenario]
	_check(label + ": the snapshot is byte-identical with the native rows on and off", stats.mismatched == 0,
		first + str(stats))
	_check(label + ": and with every native answer off", stats.reference_mismatched == 0, first + str(stats))
	_check(label + ": the approach speeds are identical with the native answer on and off", stats.speed_mismatched == 0,
		first + str(stats))
	_check(label + ": the native rows served every band endpoint", stats.band > 0 and stats.native_rows == stats.band,
		str(stats))
	_check(label + ": the native approach speeds answered", stats.native_speeds > 0, str(stats))
	print("NK7K_FLIGHT %s %s" % [label, str(stats)])
	s.free()


func _anchors(s: Node) -> PackedFloat64Array:
	return s.sim.aux.slice(4, 4 + s.anchor_count() * GroundAudioModel.Ground.ANCHOR_STRIDE)


func _speeds(s: Node) -> PackedFloat64Array:
	return s.sim.continuous.slice(s.wheel_index(), s.wheel_index() + s.wheel_count())


func _brake(s: Node) -> float:
	return float(s.sim.inputs[5]) if s.gear_is_retractable() and s.sim.inputs.size() > 5 else 0.0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)
