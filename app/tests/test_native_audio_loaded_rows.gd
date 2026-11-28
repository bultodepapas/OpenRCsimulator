extends SceneTree
## NK-7j: the ground audio's loaded contact rows from the native stage (FlightSession.published_wheel_audio_rows). On
## every published endpoint of takeoff rolls, steered and braked taxis, touchdowns, a lake-shore taxi and a stand on
## lake-covered ground, for fixed and retractable gear, GroundAudioModel.snapshot_contacts returns the same bytes with
## the native rows on, with them off (built in GDScript from the native wheel rows) and with every native answer off
## (the reference). The native rows serve most rolling endpoints, reach several surface regions and lake-covered
## ground (a region without a measured material); a 1e-9 change to a row is detected.
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
var _regions := {}
var _materials := {}
var _covered := {}
var _mutation_seen := false


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
				or not probe._native_stage._native.has_method("stage_wheel_audio_rows"):
			print("NK7J_SKIP %s" % id)
			if probe != null:
				probe.free()
			continue
		probe.free()
		tested += 1
		for scenario: String in ["roll", "taxi", "brake", "touchdown", "shore", "bank"]:
			_flight(id, scenario)
	if tested == 0:
		print("NK7J_SKIP no native session")
	else:
		_check("the native rows reach several surface regions", _regions.size() >= 2, str(_regions.keys()))
		_check("the native rows reach lake-covered ground", not _covered.is_empty(), str(_materials.keys()))
		print("NK7J_REGIONS %s materials %s covered %s" % [str(_regions.keys()), str(_materials.keys()),
			str(_covered.keys())])
		_check("a 1e-9 change to a native row is detected", _mutation_seen)
	print("native audio loaded rows: %d checks, %d failed" % [_checks, _failures])
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
	elif scenario == "bank":
		# Standing on lake-covered ground inside the bank polygon, at the runway start's clearance.
		var spot := _covered_spot()
		var state: PackedFloat64Array = s.sim.state.duplicate()
		var clearance: float = -state[RB.POS + 2] \
			- Terrain.sample(state[RB.POS], state[RB.POS + 1], s.ground_surfaces, _lake)[0]
		state[RB.POS] = spot.x
		state[RB.POS + 1] = spot.y
		state[RB.POS + 2] = -(Terrain.sample(spot.x, spot.y, s.ground_surfaces, _lake)[0] + clearance)
		s.sim.state = state
		s.sim.previous = state.duplicate()
	s.read_raw = func() -> Dictionary:
		match scenario:
			"taxi", "shore": return {roll = 0.0, pitch = 0.0, yaw = 0.5 * sin(float(holder.tick) / 90.0), throttle = 0.3}
			"brake": return {roll = 0.0, pitch = 0.0, yaw = 0.2, throttle = 0.5 if holder.tick < 500 else 0.0}
			"touchdown", "bank": return {roll = 0.0, pitch = -0.2 if scenario == "touchdown" else 0.0, yaw = 0.0,
				throttle = 0.0}
		return {roll = 0.0, pitch = 0.1 if holder.tick > 700 else 0.0, yaw = 0.0, throttle = 1.0}
	var stats := {ticks = 0, native = 0, mismatched = 0, reference_mismatched = 0}
	var first := ""
	for tick in (480 if scenario == "bank" else 960):
		holder.tick = tick
		if scenario == "brake" and tick == 500:
			s.set_wheel_brake(1.0)
		_tick(s)
		stats.ticks += 1
		var before: int = s.native_audio_row_answers
		var native: Array = GroundAudioModel.snapshot_contacts(s, {})
		var answered: bool = s.native_audio_row_answers > before
		s.native_audio_rows_enabled = false
		var built: Array = GroundAudioModel.snapshot_contacts(s, {})
		s.native_wheel_rows_enabled = false
		var reference: Array = GroundAudioModel.snapshot_contacts(s, {})
		s.native_wheel_rows_enabled = true
		s.native_audio_rows_enabled = true
		if answered:
			stats.native += 1
			for row: Dictionary in native:
				_regions[str(row.surface_region_id)] = true
				_materials["%s/%s" % [row.material_id, row.surface]] = true
				# A lake-covered sample keeps its region but has no measured material.
				if scenario == "bank" and row.material_id == "unspecified" and not str(row.surface_region_id).is_empty():
					_covered["%s/%s" % [row.surface_region_id, row.material_id]] = true
			if not _mutation_seen and not native.is_empty():
				var altered: Array = native.duplicate(true)
				altered[0].normal_force_n = float(altered[0].normal_force_n) + 1e-9
				_mutation_seen = var_to_bytes(altered) != var_to_bytes(built)
		if var_to_bytes(native) != var_to_bytes(built):
			stats.mismatched += 1
			if first.is_empty():
				first = "tick %d: %s / %s" % [s.sim.tick, str(native), str(built)]
		if var_to_bytes(built) != var_to_bytes(reference):
			stats.reference_mismatched += 1
			if first.is_empty():
				first = "tick %d: the GDScript rows differ from the reference" % s.sim.tick
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
	var label := "%s %s" % [id, scenario]
	_check(label + ": the snapshot is byte-identical with the native rows on and off", stats.mismatched == 0,
		first + str(stats))
	_check(label + ": and with every native answer off", stats.reference_mismatched == 0, first + str(stats))
	if scenario == "touchdown" or scenario == "bank":
		_check(label + ": the native rows answered", stats.native > 0, str(stats))
	else:
		_check(label + ": the native rows served rolling endpoints", stats.native > stats.ticks / 2, str(stats))
	print("NK7J_FLIGHT %s %s" % [label, str(stats)])
	s.free()


## The first lake-covered point 2 m inside the bank polygon on its middle east line, scanning north from the bank.
func _covered_spot() -> Vector2:
	var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
	var east: float = (bank[2] + bank[3]) * 0.5
	var north: float = bank[0] - 2.0
	while north < bank[1]:
		if bool(LakeSurface.sample_covered_terrain_validated(_lake, north, east).get("covered", false)):
			return Vector2(north + 2.0, east)
		north += 0.25
	return Vector2(bank[0], east)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)
