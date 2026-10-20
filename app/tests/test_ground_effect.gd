# M5-GE-1: wing-in-ground-effect module (aero.ground_effect, physics/ground_effect.gd). Known-answer law values
# against the published forms and the T6 image-VLM table; exact inactivity (byte-identical loads) without a ground,
# above the fade height and for an aircraft without the module; C¹ fade; monotone lift gain and drag reduction with
# descending height at fixed α; the banked sign (the low wing gains more); the nose-down tail increment; oracle and
# strip regimes carrying the same increment; the session threading the field terrain into its load path, lagged
# downwash and trace metadata; and the v2 contract/loader rejections. Software verification of the implemented law,
# not physical validation of the Stik's flare.
# Run: godot --headless --path . --script res://tests/test_ground_effect.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Contract := preload("res://physics/aircraft_contract.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")

const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const EXTRA_ID := "gp-extra-300s-60"
# Control without the module: the Extra declared none until EX-14e; the Timber still has none.
const CONTROL_ID := "turbo-lumber-evolution"
const RHO := 1.225
var ZERO_WIND := PackedFloat64Array([0.0, 0.0, 0.0])
# docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md T6 (image-method VLM, AR 5 rectangular, α 4°).
const VLM_INDUCED := {0.10: 0.51, 0.17: 0.67, 0.25: 0.77, 0.5: 0.91, 1.0: 0.97}
const VLM_LIFT := {0.10: 1.35, 0.17: 1.16, 0.25: 1.09, 0.5: 1.03, 1.0: 1.01}
const VLM_TAIL := {0.10: 0.27, 0.17: 0.49, 0.25: 0.67, 0.5: 0.90, 1.0: 0.98} # same-α ratios; the law is per unit wing lift

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	_law_known_answers()
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	_exact_inactivity(session)
	_fixed_alpha_sweep(session)
	_selector_uses_ground_effect_tail(session.aircraft.model)
	_banked_and_regimes(session)
	_session_path(session)
	session.free()
	_data_contract()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _raymer(x: float) -> float:
	var t := 33.0 * M.pow_(x, 1.5)
	return t / (1.0 + t)


func _wieselsberger(x: float) -> float:
	return 1.0 - (1.0 - 1.32 * x) / (1.05 + 7.4 * x)


func _law_known_answers() -> void:
	var worst_raymer_near := 0.0
	var worst_raymer := 0.0
	var worst_wieselsberger := 0.0
	var worst_vlm := 0.0
	var worst_tail := 0.0
	for x: float in VLM_INDUCED:
		var f := GroundEffect.law(x, 33.0, 1.5)
		var t := GroundEffect.law(x, 25.0, 2.0)
		worst_raymer = maxf(worst_raymer, absf(f - _raymer(x)))
		if x <= 0.25:
			worst_raymer_near = maxf(worst_raymer_near, absf(f - _raymer(x)))
			worst_wieselsberger = maxf(worst_wieselsberger, absf(f - _wieselsberger(x)))
		worst_vlm = maxf(worst_vlm, absf(f - float(VLM_INDUCED[x])))
		var per_lift: float = float(VLM_TAIL[x]) / float(VLM_LIFT[x])
		if x <= 0.5:
			worst_tail = maxf(worst_tail, absf(t - per_lift))
		print("info h/b %.2f: σ %.4f (Raymer %.4f, Wieselsberger %.4f, VLM %.2f); σ_ε %.4f (VLM per unit lift %.3f)"
			% [x, f, _raymer(x), _wieselsberger(x), VLM_INDUCED[x], t, per_lift])
	_check("induced law equals Raymer's 33(h/b)^1.5 form within 0.01 up to h/b 0.25 and 0.02 up to 1 (the fade)",
		worst_raymer_near < 0.01 and worst_raymer < 0.02, "worst %.4f / %.4f" % [worst_raymer_near, worst_raymer])
	_check("induced law within 0.05 of Wieselsberger's image theory for h/b 0.10–0.25", worst_wieselsberger < 0.05, "worst %.4f" % worst_wieselsberger)
	_check("induced law within 0.05 of the T6 image-VLM induced-drag ratios", worst_vlm < 0.05, "worst %.4f" % worst_vlm)
	_check("tail downwash law within 0.03 of the T6 image-VLM downwash ratios per unit lift up to h/b 0.5", worst_tail < 0.03, "worst %.4f" % worst_tail)
	_check("σ(0) = 0 and σ = 1 exactly at and above the fade height", GroundEffect.law(0.0, 33.0, 1.5) == 0.0
		and GroundEffect.law(GroundEffect.FADE_SPAN_RATIO, 33.0, 1.5) == 1.0 and GroundEffect.law(2.5, 33.0, 1.5) == 1.0
		and GroundEffect.law(-0.1, 33.0, 1.5) == 0.0)
	var fade := GroundEffect.FADE_SPAN_RATIO
	var slope := (1.0 - GroundEffect.law(fade - 1e-3, 33.0, 1.5)) / 1e-3
	_check("C¹ fade: σ within 1e-7 of 1 at 1 mm·b below the fade height with slope below 1e-4 per span",
		1.0 - GroundEffect.law(fade - 1e-3, 33.0, 1.5) < 1e-7 and slope < 1e-4, "slope %s" % slope)
	var monotone := true
	var previous := -1.0
	for i in 401:
		var f := GroundEffect.law(i * fade / 400.0, 33.0, 1.5)
		monotone = monotone and f >= previous
		previous = f
	_check("σ is nondecreasing through the fade", monotone)


func _exact_inactivity(session: Node) -> void:
	var model: Dictionary = session.aircraft.model
	var state: PackedFloat64Array = session.start.state.duplicate() # trimmed 15 m/s at 30 m
	var d: Dictionary = session._deflections(session.sim.aux)
	var air := Air.compute(state, ZERO_WIND, RHO)
	var stations: int = model.envelope.station_ys.size()
	_check("the Stik declares aero.ground_effect", GroundEffect.enabled(model))
	_check("no factors at 30 m", GroundEffect.factors(state, model, 0.0).is_empty())
	var low := state.duplicate()
	low[RB.POS + 2] = -0.5
	_check("factors at 0.5 m: one per strip, mean and tail", GroundEffect.factors(low, model, 0.0).size() == stations + 2)
	_check("no factors without a ground (NAN)", GroundEffect.factors(low, model, NAN).is_empty())
	var reach := GroundEffect.reach(model)
	var at_reach := state.duplicate()
	at_reach[RB.POS + 2] = -reach
	_check("reach() bounds the module: factors empty at the reach height", reach > 0.0 and GroundEffect.factors(at_reach, model, 0.0).is_empty(), "reach %.3f m" % reach)
	var legacy := Aero.loads(state, air, d, model, RHO)
	_check("30 m: loads with a ground are byte-identical to the legacy call",
		Aero.loads(state, air, d, model, RHO, NAN, 0.0).to_byte_array() == legacy.to_byte_array())
	_check("30 m: Dynamics with a ground is byte-identical", Dynamics.loads(state, model, d, session.start.rpm, RHO, ZERO_WIND,
		NAN, PackedFloat64Array(), 0.0).to_byte_array() == Dynamics.loads(state, model, d, session.start.rpm, RHO, ZERO_WIND).to_byte_array())
	var low_air := Air.compute(low, ZERO_WIND, RHO)
	_check("0.5 m: loads with a ground differ from the free-air loads",
		Aero.loads(low, low_air, d, model, RHO, NAN, 0.0) != Aero.loads(low, low_air, d, model, RHO))
	var extra_data: Dictionary = AD.load_file(Catalog.entry(EXTRA_ID).data)
	_check("the Extra declares aero.ground_effect (EX-14e)", extra_data.get("ok", false) and GroundEffect.enabled(extra_data.model))
	var control := FlightSession.new()
	control.setup(Catalog.entry(CONTROL_ID).data)
	root.add_child(control)
	control.input_enabled = false
	control.reset()
	var control_model: Dictionary = control.aircraft.model
	var control_state: PackedFloat64Array = control.start.state.duplicate()
	control_state[RB.POS + 2] = -0.5
	var control_d: Dictionary = control._deflections(control.sim.aux)
	var control_air := Air.compute(control_state, ZERO_WIND, RHO)
	_check("Timber (no module): no factors at 0.5 m and reach 0", not GroundEffect.enabled(control_model)
		and GroundEffect.factors(control_state, control_model, 0.0).is_empty() and GroundEffect.reach(control_model) == 0.0)
	_check("Timber: loads with a ground are byte-identical", Aero.loads(control_state, control_air, control_d, control_model, RHO, NAN, 0.0).to_byte_array()
		== Aero.loads(control_state, control_air, control_d, control_model, RHO).to_byte_array())
	_check("Timber: the session never samples a ground", control._ground_effect_reach == 0.0 and is_nan(control._ground_up(control_state)))
	control.free()


## Wind-axis lift, drag and the pitch moment of body loads at angle of attack alpha (β ≈ 0 here).
func _wind_axes(loads: PackedFloat64Array, alpha: float) -> Dictionary:
	var ca := M.cos_(alpha)
	var sa := M.sin_(alpha)
	return {L = -loads[2] * ca + loads[0] * sa, D = -loads[0] * ca - loads[2] * sa, Mx = loads[3], My = loads[4]}


## The state at CG height h whose lift in ground effect equals `target` (bisection on α along the trimmed speed).
func _same_lift_state(state0: PackedFloat64Array, d: Dictionary, model: Dictionary, h: float, target: float) -> Dictionary:
	var V := M.norm(M.v3(state0[RB.VEL], state0[RB.VEL + 1], state0[RB.VEL + 2]))
	var euler := M.q_to_euler(M.quat(state0[RB.ATT], state0[RB.ATT + 1], state0[RB.ATT + 2], state0[RB.ATT + 3]))
	var air0 := Air.compute(state0, ZERO_WIND, RHO)
	var lo: float = air0.alpha - deg_to_rad(6.0)
	var hi: float = air0.alpha
	var result := {found = false}
	for i in 60:
		var alpha := 0.5 * (lo + hi)
		var s := state0.duplicate()
		s[RB.POS + 2] = -h
		s[RB.VEL] = V * M.cos_(alpha)
		s[RB.VEL + 1] = 0.0
		s[RB.VEL + 2] = V * M.sin_(alpha)
		var q := M.q_from_euler(euler[0], euler[1] - air0.alpha + alpha, 0.0) # same flight path, new α
		for k in 4:
			s[RB.ATT + k] = q[k]
		var air := Air.compute(s, ZERO_WIND, RHO)
		var w := _wind_axes(Aero.loads(s, air, d, model, RHO, NAN, 0.0), air.alpha)
		if w.L > target:
			hi = alpha
		else:
			lo = alpha
		result = {found = absf(w.L - target) < 1e-6 * target, L = w.L, D = w.D, alpha = alpha}
		if result.found:
			break
	return result


func _fixed_alpha_sweep(session: Node) -> void:
	var model: Dictionary = session.aircraft.model
	var state0: PackedFloat64Array = session.start.state.duplicate()
	var d: Dictionary = session._deflections(session.sim.aux)
	var air := Air.compute(state0, ZERO_WIND, RHO) # velocities only: the same air at every height
	var free := _wind_axes(Aero.loads(state0, air, d, model, RHO), air.alpha)
	var b: float = model.reference.b
	var S: float = model.reference.S
	var c: float = model.reference.c
	# CG height standing on the uncompressed main wheels (body down coordinate of a main contact about the CG).
	var wheel_height: float = model.landing_gear.contacts[0].position[2]
	var previous_lift: float = free.L
	var previous_drag: float = free.D
	var monotone := true
	var at_wheels := {}
	for h: float in [3.5, 3.0, 2.0, 1.5, 1.0, 0.75, 0.5, 0.4, wheel_height]:
		var s := state0.duplicate()
		s[RB.POS + 2] = -h
		var factors := GroundEffect.factors(s, model, 0.0)
		var loads := Aero.loads(s, air, d, model, RHO, NAN, 0.0)
		var w := _wind_axes(loads, air.alpha)
		var elevator_deg := rad_to_deg(-(w.My - free.My) / (air.qbar * S * c * float(model.aero.Cmde)))
		print("info CG %.3f m: σ_mean %.4f σ_ε %.4f, L/L∞ %.4f, D/D∞ %.4f, ΔCm %+.4f = %+.2f° elevator (+ = trailing edge down)"
			% [h, factors[factors.size() - 2] if not factors.is_empty() else 1.0, factors[factors.size() - 1] if not factors.is_empty() else 1.0,
			w.L / free.L, w.D / free.D, (w.My - free.My) / (air.qbar * S * c), elevator_deg])
		monotone = monotone and w.L >= previous_lift - 1e-9
		previous_lift = w.L
		previous_drag = w.D
		if h == wheel_height:
			at_wheels = {L = w.L / free.L, D = w.D / free.D, dCm = (w.My - free.My) / (air.qbar * S * c), elevator = elevator_deg,
				hb = (h - (-(model.reference.arp_le[2] - model.cg_le[2]))) / b}
	_check("fixed α (trimmed 15 m/s): lift rises monotonically as the wing descends", monotone)
	_check("at wheel height the wing gains 3–20 % lift at the same α", at_wheels.L > 1.03 and at_wheels.L < 1.20,
		"L/L∞ %.4f at strip h/b %.3f" % [at_wheels.L, at_wheels.hb])
	# The polar's lift-dependent drag k·(CL − CL_minD)² is near its minimum at the 15 m/s trim, so the same-α drag barely
	# moves (and may rise with the extra lift). The published reduction is at the same CL: lower α at wheel height until
	# the lift equals the free-air lift, then the drag must be lower.
	var same := _same_lift_state(state0, d, model, wheel_height, free.L)
	_check("at wheel height, at the same lift (α lowered by bisection), the drag is lower", same.found and same.D < free.D,
		"D/D∞ %.4f at α %.2f° instead of %.2f°" % [same.D / free.D, rad_to_deg(same.alpha), rad_to_deg(air.alpha)])
	_check("at wheel height the reduced tail downwash pitches nose-down, worth 1–8° of up-elevator",
		at_wheels.dCm < 0.0 and at_wheels.elevator < -1.0 and at_wheels.elevator > -8.0, "ΔCm %.4f, %.2f°" % [at_wheels.dCm, at_wheels.elevator])
	# Continuity through the fade: just below reach the loads differ from the exact legacy loads by less than 1e-6.
	var reach := GroundEffect.reach(model)
	var edge := state0.duplicate()
	edge[RB.POS + 2] = -(reach - 0.01)
	var near_edge := Aero.loads(edge, air, d, model, RHO, NAN, 0.0)
	var legacy := Aero.loads(edge, air, d, model, RHO)
	var worst := 0.0
	for k in 6:
		worst = maxf(worst, absf(near_edge[k] - legacy[k]) / maxf(1.0, absf(legacy[k])))
	_check("1 cm below the reach height the loads are within 1e-6 (relative) of the exact legacy loads", worst < 1e-6, "worst %s" % worst)


## The blend selector must see the same ground-reduced downwash as the local tail load.
func _selector_uses_ground_effect_tail(model: Dictionary) -> void:
	var alpha := deg_to_rad(7.8)
	var h: float = 0.05 * float(model.reference.b)
	var s := RB.make_state(M.v3(0.0, 0.0, -h), M.v3(15.0 * cos(alpha), 0.0, 15.0 * sin(alpha)), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var air := Air.compute(s, ZERO_WIND, RHO)
	var d := { aileron_right = 0.0, aileron_left = 0.0, elevator = 0.0, rudder = 0.0 }
	var factors: PackedFloat64Array = GroundEffect.factors(s, model, 0.0)
	var tail: Dictionary = model.surfaces.horizontal
	var wake_ge: float = Aero.wing_wake_velocity(s, air, d, model, 0.0)
	var tail_plane_speed: float = sqrt(air.v_air[0] * air.v_air[0] + air.v_air[2] * air.v_air[2])
	var actual_tail: float = atan2(air.v_air[2], air.v_air[0]) \
		- Aero.downwash_angle(wake_ge * factors[factors.size() - 1], float(tail.downwash_per_cl), tail_plane_speed) \
		+ float(tail.elevator_tau) * d.elevator + float(tail.free_incidence)
	var x := clampf((absf(actual_tail) - float(model.surfaces.attached_limit))
		/ (float(model.surfaces.tail_local_limit) - float(model.surfaces.attached_limit)), 0.0, 1.0)
	var expected_blend := x * x * (3.0 - 2.0 * x)
	var static_blend: float = Aero.local_flow_weight(s, air, d, model)
	var actual_blend: float = Aero.local_flow_weight(s, air, d, model, NAN, factors)
	_check("h/b 0.05: ground effect moves the actual tail beyond the attached limit", rad_to_deg(actual_tail) > rad_to_deg(float(model.surfaces.attached_limit)),
		"tail %.3f°" % rad_to_deg(actual_tail))
	_check("h/b 0.05: default selector retains its static result but explicit ground factors select local flow",
		static_blend == 0.0 and expected_blend > 0.0 and absf(actual_blend - expected_blend) < 1e-12,
		"static %.6f, actual %.6f, expected %.6f" % [static_blend, actual_blend, expected_blend])
	var global := Aero._global_loads(s, air, d, model, RHO, NAN, factors)
	var local := Aero._local_loads(s, air, d, model, RHO, NAN, null, factors)
	var expected_loads := global.duplicate()
	for k in 6:
		expected_loads[k] = lerpf(global[k], local[k], expected_blend)
	_check("Aero.loads applies the ground-aware tail blend", Aero.loads(s, air, d, model, RHO, NAN, 0.0).to_byte_array() == expected_loads.to_byte_array())


func _banked_and_regimes(session: Node) -> void:
	var model: Dictionary = session.aircraft.model
	var state0: PackedFloat64Array = session.start.state.duplicate()
	var d: Dictionary = session._deflections(session.sim.aux)
	var air := Air.compute(state0, ZERO_WIND, RHO)
	var euler := M.q_to_euler(M.quat(state0[RB.ATT], state0[RB.ATT + 1], state0[RB.ATT + 2], state0[RB.ATT + 3]))
	var results := {}
	for bank: float in [20.0, -20.0]:
		var s := state0.duplicate()
		s[RB.POS + 2] = -0.8
		var q := M.q_from_euler(euler[0], euler[1], deg_to_rad(bank))
		for k in 4:
			s[RB.ATT + k] = q[k]
		var with_ground := Aero.loads(s, air, d, model, RHO, NAN, 0.0)
		var without := Aero.loads(s, air, d, model, RHO)
		results[bank] = with_ground[3] - without[3]
	_check("banked 20° right at 0.8 m: the lower right wing gains more lift (roll moment to the left)", results[20.0] < 0.0, "ΔMx %.4f N·m" % results[20.0])
	_check("mirror bank gives the opposite roll moment of the same size within 1 % (the trim is not symmetric)", results[-20.0] > 0.0
		and absf(results[-20.0] + results[20.0]) < 0.01 * absf(results[20.0]), "ΔMx %.4f N·m" % results[-20.0])
	# The oracle (attached regime) and the local strip model carry the same ground-effect increment at the trimmed
	# state, where the session blends toward the oracle.
	var s := state0.duplicate()
	s[RB.POS + 2] = -0.4
	var factors := GroundEffect.factors(s, model, 0.0)
	var oracle_free := Aero._global_loads(s, air, d, model, RHO)
	var oracle_ge := Aero._global_loads(s, air, d, model, RHO, NAN, factors)
	var local_free := Aero._local_loads(s, air, d, model, RHO)
	var local_ge := Aero._local_loads(s, air, d, model, RHO, NAN, null, factors)
	var o := _wind_axes(oracle_ge, air.alpha)
	var of := _wind_axes(oracle_free, air.alpha)
	var l := _wind_axes(local_ge, air.alpha)
	var lf := _wind_axes(local_free, air.alpha)
	print("info 0.4 m increments: oracle ΔL %.3f N ΔD %.3f N ΔMy %.4f N·m; strips ΔL %.3f N ΔD %.3f N ΔMy %.4f N·m"
		% [o.L - of.L, o.D - of.D, o.My - of.My, l.L - lf.L, l.D - lf.D, l.My - lf.My])
	_check("oracle and strip regimes carry the same lift increment within 5 %", absf((o.L - of.L) - (l.L - lf.L)) < 0.05 * absf(o.L - of.L))
	# The drag increment is a few hundredths of a newton. The oracle has no tail induced-drag term, while the strips' tail
	# drag follows its trim load; since D6e-R1 that load is small, so the ratio alone is ill-conditioned. Accept agreement
	# within 15 % or within 1 % of the free-air drag.
	_check("oracle and strip regimes carry the same drag increment within 15 % or 1 % of the free-air drag",
		absf((o.D - of.D) - (l.D - lf.D)) < maxf(0.15 * absf(o.D - of.D), 0.01 * absf(of.D)),
		"oracle ΔD %.4f N, strips ΔD %.4f N, free-air drag %.3f N" % [o.D - of.D, l.D - lf.D, of.D])
	_check("oracle and strip regimes carry the same nose-down increment within 15 %", (o.My - of.My) < 0.0
		and absf((o.My - of.My) - (l.My - lf.My)) < 0.15 * absf(o.My - of.My))
	var blended := _wind_axes(Aero.loads(s, air, d, model, RHO, NAN, 0.0), air.alpha)
	_check("the blended loads at 0.4 m lie between the two regimes' lift", blended.L >= minf(o.L, l.L) - 1e-9 and blended.L <= maxf(o.L, l.L) + 1e-9,
		"blend %.3f N, oracle %.3f N, strips %.3f N" % [blended.L, o.L, l.L])


func _session_path(session: Node) -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field loads", loaded.ok)
	_check("field surfaces accepted", session.set_field(loaded.field))
	var model: Dictionary = session.aircraft.model
	session.set_start_altitude(0.6)
	session.reset()
	var s: PackedFloat64Array = session.sim.state.duplicate()
	var a: PackedFloat64Array = session.sim.aux.duplicate()
	var ground_up: float = session._ground_up(s)
	_check("at 0.6 m the session samples the field terrain under the CG", is_finite(ground_up) and absf(ground_up) <= GroundTerrain.RELIEF_ROUGH_M, "ground %.4f m" % ground_up)
	_check("the sample is the terrain module's own", ground_up == GroundTerrain.sample_validated(s[RB.POS], s[RB.POS + 1], session.ground_surfaces)[0])
	var lag: int = session.downwash_index()
	var d: Dictionary = session._deflections(a)
	var expected := Dynamics.loads(s, model, d, a[0], session.air_density(), session.wind_at(0.0), a[lag], PackedFloat64Array(), ground_up)
	var free := Dynamics.loads(s, model, d, a[0], session.air_density(), session.wind_at(0.0), a[lag])
	var actual: PackedFloat64Array = session._loads(s, 0.0)
	_check("the session's load path carries the ground (airborne wheels add nothing)", actual.to_byte_array() == expected.to_byte_array())
	_check("… and differs from the out-of-ground-effect evaluation", actual != free)
	var wake_ge := Aero.wing_wake_velocity(s, session.air_data(s, 0.0), d, model, ground_up)
	var wake_free := Aero.wing_wake_velocity(s, session.air_data(s, 0.0), d, model)
	_check("the lagged downwash state starts settled on the in-ground-effect wing lift-velocity source",
		absf(a[lag] - wake_ge) < 1e-12 and wake_ge > wake_free,
		"m/s source %.5f in ground effect, %.5f free" % [wake_ge, wake_free])
	_check("trace metadata names the ground-effect law", str(session.trace_meta().ground_effect_model).begins_with("image-induced-factor-v1"))
	var faulted := false
	for i in 48: # 0.2 s of real stepping at 0.6 m: no fault, no crash
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty() or not session.pause_reason.is_empty():
			faulted = true
			break
		if not session.sim.paused:
			session.sim.step()
	_check("the session steps in ground effect without fault or crash", not faulted and session.sim.tick >= 48, "tick %d" % session.sim.tick)
	session.set_start_altitude(30.0)
	session.reset()
	_check("at 30 m the session never samples a ground", is_nan(session._ground_up(session.sim.state)))
	_check("… and keeps the exact legacy loads", session._loads(session.sim.state, 0.0).to_byte_array() == Dynamics.loads(session.sim.state, model,
		session._deflections(session.sim.aux), session.sim.aux[0], session.air_density(), session.wind_at(0.0), session.sim.aux[lag]).to_byte_array())


func _mentions(errors: PackedStringArray, text: String) -> bool:
	for e in errors:
		if String(e).contains(text):
			return true
	return false


func _data_contract() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STIK_PATH))
	var ok: Dictionary = AD.validate_and_derive(raw)
	_check("the Stik v2 file loads with the module", ok.ok and ok.model.envelope.has("ground_effect"), str(ok.errors))
	var extra: Dictionary = raw.duplicate(true)
	extra.aero.ground_effect["gain"] = {value = 1.0, unit = "1", kind = "estimated", source = "x"}
	var issues: PackedStringArray = Contract.validate(extra)
	_check("the structural contract rejects an unknown ground-effect field", issues.size() == 1 and issues[0].begins_with("/aero/ground_effect/gain"), str(issues))
	var missing: Dictionary = raw.duplicate(true)
	missing.aero.ground_effect.erase("downwash_exponent")
	_check("a missing law constant is rejected", not Contract.validate(missing).is_empty() and not AD.validate_and_derive(missing).ok)
	var no_tail: Dictionary = raw.duplicate(true)
	no_tail.aero.surfaces.horizontal.erase("downwash_gradient")
	var r: Dictionary = AD.validate_and_derive(no_tail)
	_check("the module without the free tail law is refused", not r.ok and _mentions(r.errors, "downwash_gradient"), str(r.errors))
	var out_of_range: Dictionary = raw.duplicate(true)
	out_of_range.aero.ground_effect.induced_exponent.value = 9.0
	_check("an out-of-range exponent is refused", not AD.validate_and_derive(out_of_range).ok)
	var wrong_unit: Dictionary = raw.duplicate(true)
	wrong_unit.aero.ground_effect.induced_coefficient.unit = "m"
	_check("a wrong unit is refused", not AD.validate_and_derive(wrong_unit).ok)
	var absent: Dictionary = raw.duplicate(true)
	absent.aero.erase("ground_effect")
	var r2: Dictionary = AD.validate_and_derive(absent)
	_check("the absent module derives without it and with another identity", r2.ok and not r2.model.envelope.has("ground_effect")
		and r2.model.data_sha256 != ok.model.data_sha256)
