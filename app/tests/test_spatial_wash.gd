# M5-W05c-R2 focused kernel seam: paired ambient wash deltas at actual tail load points.
# Manufactured/retained fixtures verify software contracts only; no spatial scenario is admitted here.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const SwirlLoads := preload("res://physics/swirl_loads.gd")
const WashTransport := preload("res://physics/wash_transport.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const LegacyFixture := preload("res://tests/test_slipstream_downwash.gd")
const SmoothFixture := preload("res://tests/test_wash_profile.gd")
const SwirlReference := preload("res://tests/swirl_e0b6_reference.gd")
const SMOOTH_AIRCRAFT := "res://data/aircraft/p51d_mustang_120.json"
const RHO := 1.225

var _checks := 0
var _failed := 0
var _delta_mode := "zero"
var _delta := PackedFloat64Array([0.0, 0.0, 0.0])
var _sampled_arms: Array[PackedFloat64Array] = []


func _initialize() -> void:
	var legacy := _legacy_model(false)
	var segmented := _legacy_model(true)
	var smooth := _smooth_model(true)
	var smooth_transport := _smooth_model(false, true)
	if legacy.is_empty() or segmented.is_empty() or smooth.is_empty() or smooth_transport.is_empty():
		quit(1)
		return
	_uniform_zero_matches_legacy(legacy, "legacy centroid")
	_uniform_zero_matches_legacy(segmented, "legacy segmented")
	_uniform_zero_matches_legacy(smooth, "smooth profile")
	_uniform_zero_matches_legacy(smooth_transport, "smooth transported")
	_analytic_single_piece(legacy)
	_sample_actual_points(segmented, "legacy segmented")
	_sample_actual_points(smooth, "smooth swirl")
	_smooth_swirl_delta_oracle(smooth)
	_segmented_delta_oracle(segmented)
	_transport_source_oracle(smooth_transport)
	_source_and_held_transport(smooth_transport)
	_invalid_provider_refuses(legacy)
	print("M5-W05c-R2 spatial wash: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	print("%s %s %s" % ["ok" if condition else "FAIL", label, detail])
	if not condition:
		_failed += 1


static func _q(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "M5-W05c-R2 synthetic kernel test; not aircraft calibration"}


func _legacy_model(segmented: bool) -> Dictionary:
	var raw: Dictionary = LegacyFixture.combined_raw()
	var slipstream: Dictionary = raw.propulsion.propeller.slipstream
	if segmented:
		slipstream.propeller_sidewash = _q(0.35, "1")
		slipstream.swirl_factor = _q(0.55, "1")
	var loaded: Dictionary = AD.validate_and_derive(raw)
	_check("legacy fixture validates (segmented=%s)" % segmented, loaded.ok, str(loaded.errors))
	if not loaded.ok:
		return {}
	var model: Dictionary = loaded.model
	if not segmented:
		model.propulsion.slipstream.erase("propeller_sidewash")
		model.propulsion.slipstream.swirl_factor = 0.0
	return model


func _smooth_model(with_swirl: bool, with_transport := false) -> Dictionary:
	var raw: Dictionary = SmoothFixture.combined_raw()
	if with_swirl:
		raw.propulsion.propeller.slipstream.swirl_factor = SmoothFixture.quantity(0.65, "1")
	if with_transport:
		raw.propulsion.propeller.slipstream.transport_speed_floor = SmoothFixture.quantity(1.0, "m/s")
	var loaded: Dictionary = AD.validate_and_derive(raw)
	_check("smooth-profile fixture validates (swirl=%s)" % with_swirl, loaded.ok, str(loaded.errors))
	return loaded.model if loaded.ok else {}


static func _state(velocity: PackedFloat64Array, rates := PackedFloat64Array([0.0, 0.0, 0.0])) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -100.0), velocity, M.q_identity(), rates)


static func _controls() -> Dictionary:
	return {elevator = 0.0, aileron_left = 0.0, aileron_right = 0.0, rudder = 0.0}


func _stage_tq(state: PackedFloat64Array, air: Dictionary, model: Dictionary, rpm: float,
		hub_delta := PackedFloat64Array([0.0, 0.0, 0.0])) -> PackedFloat64Array:
	var hub_air: PackedFloat64Array = Propulsion.hub_air_velocity(state, air.v_air, model.propulsion.offset)
	for component in 3:
		if hub_delta[component] != 0.0:
			hub_air[component] += hub_delta[component]
	var point: PackedFloat64Array = Propulsion.thrust_torque(hub_air, rpm, model.propulsion, RHO)
	return PackedFloat64Array([point[0], point[1]])


func _stage(state: PackedFloat64Array, air: Dictionary, model: Dictionary, rpm: float,
		tq: PackedFloat64Array, transported_dv := PackedFloat64Array()) -> PackedFloat64Array:
	return Slipstream.stage_loads(state, air, _controls(), model, rpm, RHO, 0.25,
		transported_dv, 1, tq)


func _attach_sampler(air: Dictionary, mode: String, delta := PackedFloat64Array([0.0, 0.0, 0.0]),
		source_delta := PackedFloat64Array([0.0, 0.0, 0.0])) -> void:
	_delta_mode = mode
	_delta = delta.duplicate()
	_sampled_arms.clear()
	air["ambient_delta_body_at"] = Callable(self, "_ambient_delta_at_arm")
	air["wake_source_delta_body"] = source_delta.duplicate()


func _ambient_delta_at_arm(arm_body_frd: PackedFloat64Array) -> PackedFloat64Array:
	_sampled_arms.append(arm_body_frd.duplicate())
	if _delta_mode == "invalid":
		return PackedFloat64Array([NAN, 0.0, 0.0])
	if _delta_mode == "wrong_size":
		return PackedFloat64Array([0.0, 0.0])
	if _delta_mode == "affine":
		return PackedFloat64Array([0.0, 0.04 * arm_body_frd[1], -0.04 * arm_body_frd[1]])
	return _delta.duplicate()


func _uniform_zero_matches_legacy(model: Dictionary, label: String) -> void:
	var state := _state(M.v3(18.0, 0.35, 0.65), M.v3(0.08, -0.11, 0.07))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var rpm: float = float(model.propulsion.max_rpm)
	var tq := _stage_tq(state, air, model, rpm)
	var transported := PackedFloat64Array()
	if model.propulsion.slipstream.has("transport_speed_floor"):
		transported.resize(model.propulsion.slipstream.pieces.size())
		transported.fill(2.0)
	var legacy := _stage(state, air, model, rpm, tq, transported)
	var sampled_air: Dictionary = air.duplicate()
	_attach_sampler(sampled_air, "zero")
	var with_zero := _stage(state, sampled_air, model, rpm, tq, transported)
	_check("%s zero/absent sampler is byte-identical with the same stage TQ" % label,
		legacy.to_byte_array() == with_zero.to_byte_array(), "calls=%d" % _sampled_arms.size())
	_check("%s zero sampler preserves the held transport input" % label,
		transported.is_empty() or transported == PackedFloat64Array([2.0, 2.0, 2.0]))


func _analytic_single_piece(model: Dictionary) -> void:
	var one: Dictionary = model.duplicate(true)
	one.propulsion.slipstream.pieces = [one.propulsion.slipstream.pieces[0]]
	one.propulsion.slipstream.swirl_factor = 0.0
	for key: String in ["propeller_sidewash", "edge_fraction", "reverse_fade", "transport_speed_floor"]:
		one.propulsion.slipstream.erase(key)
	var tail: Dictionary = one.surfaces.horizontal
	for key: String in ["free_slope", "downwash_per_cl", "elevator_tau", "free_incidence", "wing_cl0"]:
		tail.erase(key)
	tail.incidence = 0.0
	tail.control_effectiveness = 0.0
	var state := _state(M.v3(16.0, 0.15, 0.22), M.v3(0.07, -0.09, 0.12))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var hub_delta := M.v3(0.08, 0.0, -0.03)
	var rpm: float = float(one.propulsion.max_rpm)
	var tq := _stage_tq(state, air, one, rpm, hub_delta)
	var source_v: PackedFloat64Array = M.add(air.v_air, hub_delta)
	var wake: Dictionary = Slipstream.wake(source_v, tq[0], tq[1], one.propulsion, RHO)
	var piece: Dictionary = one.propulsion.slipstream.pieces[0]
	var immersion: Dictionary = Slipstream.immersion(piece, wake, one.propulsion.slipstream.hub,
		one.propulsion, source_v, M.norm(source_v), one)
	_check("single-piece oracle fixture is immersed", float(immersion.area) > 0.0, str(immersion.area))
	if float(immersion.area) <= 0.0:
		return
	var arm: PackedFloat64Array = M.add(Aero._arm(tail.position, one.cg_le), immersion.shift)
	var rate_flow: PackedFloat64Array = M.cross(state.slice(RB.RATE, RB.RATE + 3), arm)
	var ambient_delta := M.v3(0.035, 0.0, -0.055)
	var free_flow: PackedFloat64Array = air.v_air.duplicate()
	for axis in 3:
		free_flow[axis] += rate_flow[axis] + ambient_delta[axis]
	var washed_flow: PackedFloat64Array = free_flow.duplicate()
	var axial_wash: PackedFloat64Array = M.scale(Propulsion.axis(one.propulsion), float(wake.dv))
	for axis in 3:
		washed_flow[axis] += axial_wash[axis]
	var expected_free := _independent_tail_wrench(free_flow, arm, tail, one.surfaces, float(immersion.area))
	var expected_washed := _independent_tail_wrench(washed_flow, arm, tail, one.surfaces, float(immersion.area))
	var expected := _subtract(expected_washed, expected_free)
	var sampled_air: Dictionary = air.duplicate()
	_attach_sampler(sampled_air, "constant", ambient_delta, hub_delta)
	var actual := _stage(state, sampled_air, one, rpm, tq)
	_check("one-point washed-minus-free matches independent section wrench",
		_error(actual, expected) < 2e-8, "error=%s samples=%d" % [String.num_scientific(_error(actual, expected)), _sampled_arms.size()])
	_check("one-piece pair samples its actual shifted force arm once",
		_sampled_arms.size() == 1 and _near3(_sampled_arms[0], arm, 1e-12), str(_sampled_arms))


func _independent_tail_wrench(flow: PackedFloat64Array, arm: PackedFloat64Array, tail: Dictionary,
		surfaces: Dictionary, area: float) -> PackedFloat64Array:
	# Independent attached/separated tail section equations; this deliberately does not call Aero or Slipstream load helpers.
	var plane := sqrt(flow[0] * flow[0] + flow[2] * flow[2])
	if plane <= 0.0 or area <= 0.0:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var alpha := atan2(flow[2], flow[0]) + float(tail.incidence)
	var limit: float = float(surfaces.tail_local_limit)
	var span: float = float(surfaces.tail_stall_end) - limit
	var x := clampf((absf(alpha) - limit) / span, 0.0, 1.0)
	var blend := x * x * (3.0 - 2.0 * x)
	var cd90: float = float(surfaces.tail_CD90)
	var cl: float = (1.0 - blend) * float(tail.lift_slope) * alpha + blend * 0.5 * cd90 * sin(2.0 * alpha)
	var cd: float = float(surfaces.tail_CD0) + float(surfaces.tail_k) * cl * cl + cd90 * pow(sin(alpha), 2.0)
	var drag_scale := -0.5 * RHO * plane * area * cd
	var lift := 0.5 * RHO * plane * plane * area * cl
	var fx := flow[0] * drag_scale + lift * flow[2] / plane
	var fz := flow[2] * drag_scale - lift * flow[0] / plane
	return PackedFloat64Array([fx, 0.0, fz,
		arm[1] * fz, arm[2] * fx - arm[0] * fz, -arm[1] * fx])


func _sample_actual_points(model: Dictionary, label: String) -> void:
	var state := _state(M.v3(20.0, 0.7, 1.0), M.v3(0.04, -0.07, 0.09))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var rpm: float = float(model.propulsion.max_rpm)
	var tq := _stage_tq(state, air, model, rpm)
	var transported := PackedFloat64Array()
	if model.propulsion.slipstream.has("transport_speed_floor"):
		transported.resize(model.propulsion.slipstream.pieces.size())
		for i in transported.size():
			transported[i] = 1.3 + 0.2 * i
	var sampled_air: Dictionary = air.duplicate()
	_attach_sampler(sampled_air, "affine")
	var result := _stage(state, sampled_air, model, rpm, tq, transported)
	var finite := true
	for value: float in result:
		finite = finite and is_finite(value)
	var unique := _unique_arm_count(_sampled_arms)
	_check("%s ambient wash samples active load points and returns finite loads" % label,
		finite and _sampled_arms.size() > model.propulsion.slipstream.pieces.size(),
		"calls=%d unique=%d pieces=%d" % [_sampled_arms.size(), unique, model.propulsion.slipstream.pieces.size()])
	_check("%s evaluates more than one actual spanwise force arm" % label,
		unique > 1 and _has_span_offset(_sampled_arms, model),
		"calls=%d unique=%d" % [_sampled_arms.size(), unique])


func _smooth_swirl_delta_oracle(model: Dictionary) -> void:
	var state := _state(M.v3(20.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var rpm: float = float(model.propulsion.max_rpm)
	var hub_air: PackedFloat64Array = Propulsion.hub_air_velocity(state, air.v_air, model.propulsion.offset)
	var tq: PackedFloat64Array = Propulsion.thrust_torque(hub_air, rpm, model.propulsion, RHO)
	var wake: Dictionary = Slipstream.wake(air.v_air, tq[0], tq[1], model.propulsion, RHO)
	var delta := M.v3(2.0, 0.0, 0.0)
	var shifted_air: Dictionary = air.duplicate()
	shifted_air.v_air = M.add(air.v_air, delta)
	var sampled_air: Dictionary = air.duplicate()
	_attach_sampler(sampled_air, "constant", delta)
	var sampler := Callable(self, "_ambient_delta_at_arm")
	var actual: PackedFloat64Array = SwirlLoads.correction(state, sampled_air, _controls(), model,
		wake, 0.75, RHO, 0.25, sampler, air.v_air)
	var expected: PackedFloat64Array = SwirlReference.correction(state, shifted_air, _controls(), model,
		wake, 0.75, RHO, 0.25)
	var calls: int = _sampled_arms.size()
	_check("smooth swirl applies constant ambient delta at every active Gauss load node",
		calls > 1 and _error(actual, expected) < 2e-8,
		"error=%s calls=%d" % [String.num_scientific(_error(actual, expected)), calls])


func _segmented_delta_oracle(model: Dictionary) -> void:
	var state := _state(M.v3(18.0, 0.0, 0.0), M.v3(0.06, -0.08, 0.11))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var piece: Dictionary = model.propulsion.slipstream.pieces[0]
	var tail: Dictionary = model.surfaces[piece.surface]
	var chords: PackedFloat64Array = piece.chords
	var span: float = float(piece.span)
	var c0: float = chords[0]
	var slope: float = (chords[1] - c0) / span
	var centre := M.v3(0.0, 0.0, 0.0)
	var axis: PackedFloat64Array = Propulsion.axis(model.propulsion)
	var wash: PackedFloat64Array = M.scale(axis, 2.5)
	var delta := M.v3(1.75, 0.0, 0.0)
	_delta_mode = "constant"
	_delta = delta.duplicate()
	_sampled_arms.clear()
	var sampler := Callable(self, "_ambient_delta_at_arm")
	var actual: PackedFloat64Array = Slipstream._segmented_increment(piece, tail, 0.0, span, c0, slope,
		0.0, 0.0, centre, axis, 0.025, 0.035, wash, state, air.v_air, _controls(), model, RHO, 0.25,
		1, sampler)
	var calls: int = _sampled_arms.size()
	var shifted_v: PackedFloat64Array = M.add(air.v_air, delta)
	var expected: PackedFloat64Array = Slipstream._segmented_increment(piece, tail, 0.0, span, c0, slope,
		0.0, 0.0, centre, axis, 0.025, 0.035, wash, state, shifted_v, _controls(), model, RHO, 0.25)
	_check("segmented wash applies constant ambient delta once to both free and washed passes",
		calls > 0 and _error(actual, expected) < 2e-8,
		"error=%s centroid samples=%d" % [String.num_scientific(_error(actual, expected)), calls])


func _transport_source_oracle(model: Dictionary) -> void:
	var state := _state(M.v3(19.0, 0.25, 0.4), M.v3(0.09, -0.12, 0.07))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var prop: Dictionary = model.propulsion
	var hub_delta := M.v3(0.35, -0.08, 0.12)
	var point_air: PackedFloat64Array = Propulsion.hub_air_velocity(state, air.v_air, prop.offset)
	for axis in 3:
		point_air[axis] += hub_delta[axis]
	var explicit_air: Dictionary = air.duplicate()
	explicit_air["propulsion_air_body"] = point_air.duplicate()
	explicit_air["wake_source_delta_body"] = hub_delta.duplicate()
	var rpm: float = float(prop.max_rpm)
	var tq: PackedFloat64Array = Propulsion.thrust_torque(point_air, rpm, prop, RHO)
	var source: PackedFloat64Array = M.add(air.v_air, hub_delta)
	var wake: Dictionary = Slipstream.wake(source, tq[0], tq[1], prop, RHO)
	var equilibrium: float = wake.dv
	if rpm < Propulsion.STOPPED_RPM or Slipstream.reverse_weight(source, rpm, prop) == 0.0:
		equilibrium = 0.0
	var expected_target := PackedFloat64Array([equilibrium,
		maxf(wake.u + wake.w, prop.slipstream.transport_speed_floor)])
	var actual_target: PackedFloat64Array = WashTransport.stage_target(state, explicit_air, rpm, prop, RHO)
	_check("transport target uses hub-point TQ and ambient-only wake source",
		_error(actual_target, expected_target) < 1e-12,
		"error=%s" % String.num_scientific(_error(actual_target, expected_target)))
	var lagged := PackedFloat64Array()
	lagged.resize(prop.slipstream.pieces.size())
	for i in lagged.size():
		lagged[i] = 0.9 + 0.4 * i
	var expected_derivative := PackedFloat64Array()
	expected_derivative.resize(lagged.size())
	for i in expected_derivative.size():
		var distance: float = prop.slipstream.pieces[i].root[0] - prop.slipstream.hub[0]
		expected_derivative[i] = (expected_target[0] - lagged[i]) * expected_target[1] / distance
	var actual_derivative: PackedFloat64Array = WashTransport.stage_derivative(state, explicit_air, rpm,
		prop, RHO, lagged)
	_check("transport derivative uses the matched source target and held lag state",
		_error(actual_derivative, expected_derivative) < 1e-12, "error=%s" %
		String.num_scientific(_error(actual_derivative, expected_derivative)))
	var legacy_target: PackedFloat64Array = WashTransport.target(air.v_air, rpm, prop, RHO)
	var stage_legacy_target: PackedFloat64Array = WashTransport.stage_target(state, air, rpm, prop, RHO)
	_check("legacy transport target remains byte-identical without explicit fields",
		legacy_target.to_byte_array() == stage_legacy_target.to_byte_array())
	var legacy_derivative: PackedFloat64Array = WashTransport.derivative(air.v_air, rpm, prop, RHO, lagged)
	var stage_legacy_derivative: PackedFloat64Array = WashTransport.stage_derivative(state, air, rpm,
		prop, RHO, lagged)
	_check("legacy transport derivative remains byte-identical without explicit fields",
		legacy_derivative.to_byte_array() == stage_legacy_derivative.to_byte_array())
	var malformed: Dictionary = explicit_air.duplicate()
	malformed["propulsion_air_body"] = PackedFloat64Array([NAN, 0.0, 0.0])
	var refused_target: PackedFloat64Array = WashTransport.stage_target(state, malformed, rpm, prop, RHO)
	var refused_derivative: PackedFloat64Array = WashTransport.stage_derivative(state, malformed, rpm,
		prop, RHO, lagged)
	_check("malformed explicit propulsion point refuses transport target and derivative",
		refused_target.size() == 2 and not is_finite(refused_target[0]) and not is_finite(refused_target[1])
			and refused_derivative.size() == 1 and not is_finite(refused_derivative[0]))


func _source_and_held_transport(model: Dictionary) -> void:
	var state := _state(M.v3(19.0, 0.8, 0.9), M.v3(0.06, -0.08, 0.11))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var hub_delta := M.v3(0.05, -0.02, 0.07)
	var tail_delta := M.v3(-0.01, 0.03, -0.045)
	var rpm: float = float(model.propulsion.max_rpm)
	var tq := _stage_tq(state, air, model, rpm, hub_delta)
	var transported := PackedFloat64Array()
	transported.resize(model.propulsion.slipstream.pieces.size())
	for i in transported.size():
		transported[i] = 1.1 + 0.35 * i
	var before := transported.to_byte_array()
	var candidate_air: Dictionary = air.duplicate()
	_attach_sampler(candidate_air, "constant", tail_delta, hub_delta)
	var candidate := _stage(state, candidate_air, model, rpm, tq, transported)
	var candidate_calls := _sampled_arms.size()
	var shifted_air: Dictionary = air.duplicate()
	shifted_air["v_air"] = M.add(air.v_air, hub_delta)
	_attach_sampler(shifted_air, "constant", M.sub(tail_delta, hub_delta))
	shifted_air.erase("wake_source_delta_body")
	var shifted := _stage(state, shifted_air, model, rpm, tq, transported)
	_check("hub ambient source delta is applied once; tail samples stay local",
		_error(candidate, shifted) < 2e-8,
		"error=%s candidate calls=%d" % [String.num_scientific(_error(candidate, shifted)), candidate_calls])
	_check("same stage source and transported wash are held read-only across the pair",
		transported.to_byte_array() == before and candidate_calls > 0, "dv=%s" % str(transported))


func _invalid_provider_refuses(model: Dictionary) -> void:
	var state := _state(M.v3(16.0, 0.2, 0.4))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var rpm: float = float(model.propulsion.max_rpm)
	var tq := _stage_tq(state, air, model, rpm)
	var bad_air: Dictionary = air.duplicate()
	_attach_sampler(bad_air, "invalid")
	var result := _stage(state, bad_air, model, rpm, tq)
	var refused := result.size() == 6
	for value: float in result:
		refused = refused and not is_finite(value)
	_check("nonfinite point sampler refuses the whole wash wrench without a partial result",
		refused and not _sampled_arms.is_empty(), str(result))
	var malformed_air: Dictionary = air.duplicate()
	_attach_sampler(malformed_air, "wrong_size")
	var malformed := _stage(state, malformed_air, model, rpm, tq)
	var malformed_refused := malformed.size() == 6
	for value: float in malformed:
		malformed_refused = malformed_refused and not is_finite(value)
	_check("wrong-size ambient delta refuses the whole wash wrench", malformed_refused, str(malformed))


func _unique_arm_count(arms: Array[PackedFloat64Array]) -> int:
	var unique: Array[PackedFloat64Array] = []
	for arm: PackedFloat64Array in arms:
		var seen := false
		for other: PackedFloat64Array in unique:
			if _near3(arm, other, 1e-12):
				seen = true
				break
		if not seen:
			unique.append(arm)
	return unique.size()


func _has_span_offset(arms: Array[PackedFloat64Array], model: Dictionary) -> bool:
	for arm: PackedFloat64Array in arms:
		for surface: String in ["horizontal", "vertical"]:
			var origin: PackedFloat64Array = Aero._arm(model.surfaces[surface].position, model.cg_le)
			if absf(arm[1] - origin[1]) > 1e-5 or absf(arm[2] - origin[2]) > 1e-5:
				return true
	return false


static func _near3(a: PackedFloat64Array, b: PackedFloat64Array, tolerance: float) -> bool:
	if a.size() != 3 or b.size() != 3:
		return false
	for axis in 3:
		if absf(a[axis] - b[axis]) > tolerance:
			return false
	return true


static func _subtract(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = a[i] - b[i]
	return out


static func _error(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != b.size():
		return INF
	var worst := 0.0
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]):
			return INF
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst
