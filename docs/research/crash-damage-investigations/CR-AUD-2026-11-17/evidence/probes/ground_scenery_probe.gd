extends SceneTree

# Baseline observation probe: compares the actual road callback with a positive
# control that adds one existing axis-aligned proxy as a supported wall box.
# Static overlap telemetry is not a driven impact or a visual alignment test.
const FieldLoader := preload("res://data/field_loader.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Session := preload("res://sim/ground_vehicle/session.gd")

const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
const CONTROLS := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s %s" % ["PASS" if condition else "FAIL", label, detail])

func _run() -> void:
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	var field_result: Dictionary = FieldLoader.load_from()
	var track_result: Dictionary = Track.load_default()
	_check("stock field and RC track load", bool(field_result.get("ok", false)) \
		and bool(track_result.get("ok", false)), "field=%s track=%s" % [field_result.get("errors", []), track_result.get("errors", [])])
	if not field_result.get("ok", false) or not track_result.get("ok", false):
		_finish()
		return
	var world_result: Dictionary = CollisionSetup.build(field_result.field, track_result.track)
	_check("shared scenery world builds", bool(world_result.get("ok", false)), str(world_result.get("errors", [])))
	if not world_result.get("ok", false):
		_finish()
		return
	var world: Dictionary = world_result.world
	var tyre: Dictionary = {}
	var building: Dictionary = {}
	for proxy: Dictionary in world.proxies:
		# Track._dressing_box prefixes every item ID with "rc_track:".
		if str(proxy.id) == "rc_track:tyres:01" and str(proxy.kind) == "rc_track" \
				and str(proxy.part) == "tyre_stack":
			tyre = proxy
		# Restrict the positive-control translation to exactly axis-aligned box solids.
		if building.is_empty() and str(proxy.kind) == "building" and str(proxy.shape) == "box" \
				and (absf(float(proxy.sin_heading)) < 1.0e-9 or absf(float(proxy.cos_heading)) < 1.0e-9) \
				and float(proxy.bounds_down_min) < -0.2 and float(proxy.bounds_down_max) >= -0.01:
			building = proxy
	_check("tyre stack and axis-aligned field building proxies exist", not tyre.is_empty() and not building.is_empty(),
		"tyre=%s building=%s world_count=%d" % [tyre.get("id", ""), building.get("id", ""), world.proxies.size()])
	if tyre.is_empty() or building.is_empty():
		_finish()
		return
	for vehicle_id: String in ["mt8-bisonte", "monster-car-2"]:
		var s: Node = Session.new()
		root.add_child(s)
		var prepared: bool = s.prepare_airfield(field_result, {}, {}, vehicle_id)
		_check(vehicle_id + " stock airfield session prepares", prepared, str(s.load_error))
		if not prepared:
			s.free()
			continue
		var open_road: Dictionary = s.environment.course(15.0, 0.0)
		var wall_road: Dictionary = s.environment.course(44.0, -6.0)
		_check(vehicle_id + " road has no nearby wall on the runway", is_finite(float(open_road.get("height_m", NAN))) \
			and open_road.get("walls", []).is_empty(), str(open_road.get("walls", [])))
		_check(vehicle_id + " stock slalom wall is provided", not wall_road.get("walls", []).is_empty(), str(wall_road.get("walls", [])))
		var normal_tick: bool = s.tick_once(NEUTRAL) and s.resume() and s.tick_once(NEUTRAL)
		_check(vehicle_id + " normal dry start accepts a finite tick", normal_tick and s.fault_reason.is_empty(), str(s.fault_reason))
		_compare_proxy(s, world, tyre, vehicle_id + " tyre stack")
		_compare_proxy(s, world, building, vehicle_id + " field building")
		s.free()
	_finish()

func _compare_proxy(s: Node, world: Dictionary, proxy: Dictionary, label: String) -> void:
	var n: float = float(proxy.north)
	var e: float = float(proxy.east)
	var road: Callable = s._road
	var sample: Dictionary = road.call(n, e)
	var near: Array[Dictionary] = CollisionWorld.nearby(world, n, e, float(proxy.down), 0.0)
	var found := false
	for item: Dictionary in near:
		if str(item.id) == str(proxy.id):
			found = true
	_check(label + " actual road omits an existing solid proxy", found and sample.get("walls", []).is_empty() \
		and is_finite(float(sample.get("height_m", NAN))),
		"id=%s position=(%.3f, %.3f) road_walls=%s" % [proxy.id, n, e, sample.get("walls", [])])
	var state: PackedFloat64Array = s.state_snapshot()
	var old: Dictionary = road.call(state[0], state[1])
	state[0] = n
	state[1] = e
	# Preserve the prepared vehicle's relative CG height as the ground changes.
	state[2] -= float(sample.height_m) - float(old.height_m)
	var actual: Dictionary = s._telemetry_for_model(state, s._model, road, CONTROLS)
	var box := {"id": "audit-positive-control", "north_min_m": float(proxy.bounds_north_min),
		"north_max_m": float(proxy.bounds_north_max), "east_min_m": float(proxy.bounds_east_min),
		"east_max_m": float(proxy.bounds_east_max), "bottom_up_m": -float(proxy.bounds_down_max),
		"top_up_m": -float(proxy.bounds_down_min), "mu": 0.5}
	var injected := func(north: float, east: float) -> Dictionary:
		var value: Dictionary = road.call(north, east)
		value["walls"] = [box]
		return value
	var control: Dictionary = s._telemetry_for_model(state, s._model, injected, CONTROLS)
	var actual_load: float = float(actual.get("wall_normal_load_n", NAN))
	var control_load: float = float(control.get("wall_normal_load_n", NAN))
	_check(label + " static overlap is absent from actual solver, detected by injected box", \
		bool(actual.get("ok", false)) and bool(control.get("ok", false)) \
		and int(actual.get("wall_contact_count", -1)) == 0 and is_finite(actual_load) \
		and int(control.get("wall_contact_count", 0)) > 0 and is_finite(control_load) and control_load > 0.0,
		"state down=%.3f actual count/load=%s/%s injected count/load=%s/%s errors=%s/%s" % \
		[state[2], actual.get("wall_contact_count", "?"), actual_load, control.get("wall_contact_count", "?"),
		control_load, actual.get("error", ""), control.get("error", "")])

func _finish() -> void:
	print("GROUND_SCENERY_PROBE: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
