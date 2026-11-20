# Third-pass audit: stock fixed-wing geometry and an authored dry lake bank.
# Prescribed nose-down starts advance through the real coupled stage and session guard.
# Rim samples provide positive geometric witnesses; they are not a global clearance certificate.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Loader := preload("res://data/lake_loader.gd")
const Lake := preload("res://physics/lake_surface.gd")
const Hull := preload("res://physics/hull_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const RIM_SAMPLES := 128
const MAX_TICKS := 40
var checks: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool, detail: Dictionary = {}) -> void:
	checks.append({"label": label, "passed": passed, "detail": detail})
	if not passed:
		failures += 1

func _plain(values: PackedFloat64Array) -> Array:
	var out: Array = []
	for value: float in values:
		out.append(value)
	return out

func _surface(lake: Dictionary, point: PackedFloat64Array, time_s: float) -> Dictionary:
	var terrain: Dictionary = Lake.sample_terrain_validated(lake, point[0], point[1])
	var surface_down := 0.0
	var material := "flat"
	if bool(terrain.get("covered", false)):
		surface_down = float(terrain.ground_down_m)
		material = str(terrain.region)
		var water: float = Lake.water_height_down(lake, point[0], point[1], time_s)
		if is_finite(water):
			surface_down = water
			material = "water"
	return {"down": surface_down, "material": material,
		"slope_north": float(terrain.get("slope_north", 0.0)),
		"slope_east": float(terrain.get("slope_east", 0.0))}

func _observation(s: Node, lake: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = s.sim.state
	var q: PackedFloat64Array = RB._att(state)
	var position: PackedFloat64Array = RB._slice3(state, RB.POS)
	var disc: Dictionary = s._prop_disc
	var axis: PackedFloat64Array = disc.axis
	var u: PackedFloat64Array = M.cross(axis, M.v3(0.0, 1.0, 0.0))
	if M.norm(u) < 0.1:
		u = M.cross(axis, M.v3(0.0, 0.0, 1.0))
	u = M.scale(u, 1.0 / M.norm(u))
	var v: PackedFloat64Array = M.cross(axis, u)
	v = M.scale(v, 1.0 / M.norm(v))
	var max_depth := -INF
	var witness: Dictionary = {}
	var all_bank := true
	var time_s: float = s.sim.time()
	for i in RIM_SAMPLES:
		var phase: float = TAU * float(i) / float(RIM_SAMPLES)
		var rim_body: PackedFloat64Array = M.add(disc.hub, M.scale(
			M.add(M.scale(u, cos(phase)), M.scale(v, sin(phase))), float(disc.radius)))
		var point: PackedFloat64Array = M.add(position, M.q_rotate(q, rim_body))
		var surface: Dictionary = _surface(lake, point, time_s)
		all_bank = all_bank and str(surface.material) == "bank"
		var depth: float = point[2] - float(surface.down)
		if depth > max_depth:
			max_depth = depth
			witness = {"point_ned_m": _plain(point), "surface_down_m": surface.down,
				"material": surface.material, "phase_rad": phase,
				"slope_north": surface.slope_north, "slope_east": surface.slope_east,
				"body_point_m": _plain(rim_body)}
	var actual: Dictionary = Hull.prop_disc_depth(state, disc, lake, time_s)
	var hull_depth := -INF
	var hull: PackedFloat64Array = s.aircraft.model.crash_hull
	for at in range(0, hull.size(), 3):
		var point: PackedFloat64Array = M.add(position, M.q_rotate(q, hull.slice(at, at + 3)))
		hull_depth = maxf(hull_depth, point[2] - float(_surface(lake, point, time_s).down))
	return {"tick": int(s.sim.tick), "time_s": time_s, "body": _plain(state),
		"reported_depth_m": float(actual.depth), "reported_point_ned_m": _plain(actual.point_ned),
		"sampled_rim_max_depth_m": max_depth, "rim_witness": witness, "all_rim_samples_on_dry_bank": all_bank,
		"hull_max_sampled_depth_m": hull_depth, "gear_collapsed": bool(s.gear_collapsed(state)),
		"rpm": float(s.sim.aux[Flight.AUX_RPM]), "engine_running": bool(s.engine_running),
		"prop_strike": not s.prop_strike.is_empty(), "crashed": not s.crash.is_empty(),
		"fault": str(s.sim.fault_reason)}

func _case(label: String, lake: Dictionary, hub_north: float, hub_east: float,
		clearance: float, down_speed: float, immediate: bool = false) -> Dictionary:
	var s: Node = Flight.new()
	s.input_enabled = false
	s.crash_auto_restart = false
	root.add_child(s)
	s.set_physics_process(false)
	s.setup()
	s.sim.process_mode = Node.PROCESS_MODE_DISABLED
	var ready: bool = s.is_flyable() and s.set_lake_context(lake) and not s._prop_disc.is_empty()
	_check(label + ": stock aircraft and authored lake prepare", ready)
	if not ready:
		s.free()
		return {"label": label, "valid": false}
	var q: PackedFloat64Array = M.q_from_euler(0.0, -PI / 2.0, 0.0)
	var surface: Dictionary = _surface(lake, M.v3(hub_north, hub_east, 0.0), 0.0)
	var hub_world: PackedFloat64Array = M.v3(hub_north, hub_east, float(surface.down) - clearance)
	var origin: PackedFloat64Array = M.sub(hub_world, M.q_rotate(q, s._prop_disc.hub))
	var velocity: PackedFloat64Array = M.q_rotate(M.q_conj(q), M.v3(0.0, 0.0, down_speed))
	var initial: PackedFloat64Array = RB.make_state(origin, velocity, q, M.v3(0.0, 0.0, 0.0))
	var reset_ok: bool = s.sim.reset(initial)
	_check(label + ": prescribed nose-down start accepted", reset_ok)
	if not reset_ok:
		var bad := {"label": label, "valid": false, "fault": str(s.sim.fault_reason)}
		s.free()
		return bad
	s.resume()
	var start: Dictionary = _observation(s, lake)
	_check(label + ": powered spinning prop and clear hull/gear", bool(start.engine_running)
		and float(start.rpm) > Hull.STRIKE_MIN_RPM and float(start.hull_max_sampled_depth_m) < 0.0
		and not bool(start.gear_collapsed) and not bool(start.crashed), start)
	var observations: Array[Dictionary] = [start]
	var witness := {}
	if immediate:
		s._session_after_input()
		witness = _observation(s, lake)
		observations.append(witness)
	else:
		_check(label + ": sampled rim starts clear", float(start.sampled_rim_max_depth_m) < 0.0)
		for _i in MAX_TICKS:
			if not s._session_after_input():
				break
			s.sim.step()
			if not s.sim.fault_reason.is_empty():
				break
			var sample: Dictionary = _observation(s, lake)
			s._session_after_input() # the normal owner guard before the next tick
			var after_guard: Dictionary = _observation(s, lake)
			observations.append(after_guard)
			if float(sample.sampled_rim_max_depth_m) > 0.000001:
				witness = after_guard
				break
			if bool(after_guard.prop_strike) or bool(after_guard.crashed):
				witness = after_guard
				break
	var final: Dictionary = _observation(s, lake)
	var out := {"label": label, "valid": true, "aircraft_path": str(s.aircraft.get("path", "default")),
		"stock_prop_radius_m": float(s._prop_disc.radius), "clearance_at_hub_start_m": clearance,
		"initial_down_speed_mps": down_speed, "immediate_guard_control": immediate,
		"initial": start, "witness": witness, "final": final, "samples": observations}
	s.free()
	return out

func _run() -> void:
	var loaded: Dictionary = Loader.load_from()
	_check("stock authored lake loads", bool(loaded.get("ok", false)))
	if not bool(loaded.get("ok", false)):
		_finish({"cases": []})
		return
	var lake: Dictionary = loaded.lake
	var bank := _case("dry_bank_nose_down", lake, 110.0, 173.0, 0.04, 0.5)
	var flat := _case("flat_nose_down_control", lake, 400.0, 400.0, 0.04, 0.5)
	var deep := _case("bank_hub_penetration_control", lake, 110.0, 173.0, -0.005, 0.0, true)
	if bool(bank.valid):
		var w: Dictionary = bank.witness
		var conclusive: bool = not w.is_empty() and int(w.tick) > 0 and str(w.fault).is_empty() \
			and bool(w.all_rim_samples_on_dry_bank) and float(w.sampled_rim_max_depth_m) > 0.000001 \
			and float(w.hull_max_sampled_depth_m) < 0.0 and not bool(w.gear_collapsed) and not bool(w.crashed)
		_check("bank positive rim witness occurs on an accepted nonterminal tick with clear hull/gear", conclusive, w)
		if conclusive:
			_check("bank prop overlap is detected by disc depth or the production strike guard",
				float(w.reported_depth_m) > 0.0 or bool(w.prop_strike), w)
	if bool(flat.valid):
		var w: Dictionary = flat.witness
		_check("flat control reaches accepted prop contact and cuts the engine", not w.is_empty()
			and int(w.tick) > 0 and bool(w.prop_strike) and not bool(w.engine_running)
			and not bool(w.crashed) and str(w.fault).is_empty(), w)
	if bool(deep.valid):
		var w: Dictionary = deep.witness
		_check("bank hub penetration control is detected and cuts the engine", bool(w.prop_strike)
			and not bool(w.engine_running) and not bool(w.crashed) and float(w.reported_depth_m) > 0.0, w)
	_finish({"scope": "stock aircraft and lake; prescribed nose-down starts; real accepted coupled ticks and owner guards",
		"rim_samples": RIM_SAMPLES, "lake_identity": str(lake.identity), "cases": [bank, flat, deep]})

func _finish(out: Dictionary) -> void:
	out["checks"] = checks
	out["check_count"] = checks.size()
	out["failures"] = failures
	print("ROUND3_PROP_BANK_RIM_JSON " + JSON.stringify(out))
	print("ROUND3_PROP_BANK_RIM_COMPLETE checks=%d failures=%d" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)
