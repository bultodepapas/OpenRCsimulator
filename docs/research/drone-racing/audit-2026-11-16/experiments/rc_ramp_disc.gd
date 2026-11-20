# Observation-only component probe for the shipped default RC track and quad.
# It constructs stationary, accepted synthetic poses above the tabletop ramp;
# it does not claim a flown trajectory, normal player reachability, or realism.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var track: Dictionary = Track.load_default()
	if not field.get("ok", false) or not track.get("ok", false):
		print("SETUP FAILURE ", str(field.get("errors", [])), " ", str(track.get("errors", [])))
		quit(1)
		return
	var s: Node = Session.new()
	root.add_child(s)
	if not s.prepare(field.field, {rc_track = track.track}):
		print("SETUP FAILURE ", s.load_error)
		s.free()
		quit(1)
		return
	print("field=", str(field.field.get("id", "")), " data_sha256=", s.source_sha256,
		" track_sha256=", track.sha256, " track_identity=", Track.identity(track.track))
	var tested := 0
	var found := false
	# Tabletop approach spans approximately e=-5.225 to -4.225 m.
	for e: float in [-5.10, -4.98, -4.86, -4.74, -4.62, -4.50, -4.38]:
		for yaw: float in [0.0, PI * 0.5]:
			for clearance: float in [0.005, 0.010, 0.020]:
				tested += 1
				var witness := _check_pose(s, 39.0, e, yaw, clearance)
				if not witness.is_empty():
					print("OBSERVED synthetic RC-overlay endpoint miss ", JSON.stringify(witness))
					found = true
					break
			if found:
				break
		if found:
			break
	if not found:
		print("NOT OBSERVED in ", tested, " synthetic poses; no conclusion about other poses or tapes")
	print("This is a component witness, not a flown stock-field collision.")
	s.free()
	quit(0)


func _check_pose(s: Node, north: float, east: float, yaw: float, clearance: float) -> Dictionary:
	var attitude: PackedFloat64Array = M.q_from_euler(yaw, 0.0, 0.0)
	var deepest_hub := -INF
	for rotor: Dictionary in s.data.rotors:
		var offset: PackedFloat64Array = M.q_rotate(attitude, rotor.hub_frd)
		var surface: PackedFloat64Array = s.plant.ground.call(north + offset[0], east + offset[1])
		deepest_hub = maxf(deepest_hub, offset[2] + surface[0])
	var body: PackedFloat64Array = RB.make_state(M.v3(north, east, -deepest_hub - clearance),
		M.v3(0.0, 0.0, 0.0), attitude, M.v3(0.0, 0.0, 0.0))
	var frame: Dictionary = s.plant.initial_frame(body)
	for i: int in 4:
		frame.continuous[i] = 1000.0
	if not s.plant.state_validator(frame, {}) or not s.plant.crash_reason(body, body, frame.continuous).is_empty():
		return {}
	var best := {}
	for i: int in 4:
		var rotor: Dictionary = s.data.rotors[i]
		var radius: float = 0.5 * float(rotor.diameter_m)
		for angle_index: int in 32:
			var angle: float = TAU * float(angle_index) / 32.0
			var body_point: PackedFloat64Array = M.add(rotor.hub_frd, M.v3(radius * cos(angle), radius * sin(angle), 0.0))
			var offset: PackedFloat64Array = M.q_rotate(attitude, body_point)
			var surface: PackedFloat64Array = s.plant.ground.call(north + offset[0], east + offset[1])
			var depth: float = body[RB.POS + 2] + offset[2] + surface[0]
			if depth > 0.0 and (best.is_empty() or depth > float(best.depth_m)):
				best = {north_m = north, east_m = east, yaw_rad = yaw, hub_clearance_min_m = clearance,
					rotor_index = i, witness_angle_rad = angle, depth_m = depth,
					witness_north_m = north + offset[0], witness_east_m = east + offset[1],
					terrain_h_m = surface[0], terrain_slope_n = surface[1], terrain_slope_e = surface[2],
					candidate_cg_down_m = body[RB.POS + 2], crash_reason = ""}
	return best
