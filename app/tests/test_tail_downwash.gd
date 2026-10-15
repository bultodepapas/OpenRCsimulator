# E0a2a: the horizontal tail's downwash split (aero.surfaces.horizontal.downwash_gradient). Downwash follows the wing's
# lift; pitch rate and elevator act on the free tail slope. Checks: derived values; static tail loads (no rates) match
# an independent bounded-angle force/moment calculation; the tail's pitch-rate response grows by
# exactly 1/(1 − dε/dα); the elevator's τ lies within thin-airfoil flap theory's reach for the Stik's elevator chord;
# downwash collapses when the wing stalls (the tail then sees more angle: the stall break).
# Run: godot --headless --path . --script res://tests/test_tail_downwash.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const V := 15.0
const RHO := 1.225

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var model: Dictionary = AD.load_file(PATH).model
	var tail: Dictionary = model.surfaces.horizontal
	var gradient: float = tail.downwash_gradient
	var keep := 1.0 - gradient
	_check("derived free slope = lift_slope/(1 − dε/dα) = %.4f, τ = control_effectiveness·(1 − dε/dα) = %.4f" % [tail.free_slope, tail.elevator_tau],
		absf(tail.free_slope - tail.lift_slope / keep) < 1e-12 and absf(tail.elevator_tau - tail.control_effectiveness * keep) < 1e-12)
	var old := model.duplicate(true) # the former effective law: the same model without the free-tail fields
	for key in ["downwash_gradient", "free_slope", "elevator_tau", "downwash_per_cl", "free_incidence", "wing_cl0"]:
		old.surfaces.horizontal.erase(key)
	# R02 intentionally replaces k*CL by atan2(k*U,Vp). The former static-equivalence
	# assertion is no longer the physical contract. Supply a known dimensional wake,
	# isolate the horizontal tail, then calculate its linear lift, drag and r×F directly.
	# Wing-source correctness is independently checked by test_aero_continuity.
	var no_tail := model.duplicate(true)
	no_tail.surfaces.horizontal.area = 0.0
	var worst_lift := 0.0
	var worst_moment := 0.0
	var q_area: float = 0.5 * RHO * V * V * float(tail.area)
	var arm_x: float = -(tail.position[0] - model.cg_le[0])
	var arm_z: float = -(tail.position[2] - model.cg_le[2])
	for deg in [-2.0, 0.0, 2.0, 4.0, 6.0]:
		for de in [-0.05, 0.0, 0.05]:
			var alpha_s := deg_to_rad(deg)
			var s := _state(alpha_s, 0.0)
			var wake := V * (0.1 + 3.0 * alpha_s)
			var a := _local(model, s, de, wake)
			var b := _local(no_tail, s, de, wake)
			var effective: float = alpha_s - atan2(float(tail.downwash_per_cl) * wake, V) + tail.elevator_tau * de + tail.free_incidence
			assert(absf(effective) < float(model.surfaces.tail_local_limit))
			var cl: float = tail.free_slope * effective
			var cd: float = model.surfaces.tail_CD0 + model.surfaces.tail_k * cl * cl + model.surfaces.tail_CD90 * pow(sin(effective), 2)
			var lift := q_area * cl
			var drag := q_area * cd
			var fx := lift * sin(alpha_s) - drag * cos(alpha_s)
			var fz := -lift * cos(alpha_s) - drag * sin(alpha_s)
			worst_lift = maxf(worst_lift, absf(_lift(a, alpha_s) - _lift(b, alpha_s) - lift) / maxf(1.0, absf(lift)))
			var moment := arm_z * fx - arm_x * fz
			worst_moment = maxf(worst_moment, absf(a[4] - b[4] - moment) / maxf(1.0, absf(moment)))
	_check("no rates, α −2…6°, elevator ±0.05 rad: bounded-wake tail lift matches independent calculation", worst_lift < 1e-11,
		"worst relative %s" % String.num_scientific(worst_lift))
	_check("no rates: tail pitching moment includes the independently calculated lift and drag arms", worst_moment < 1e-11,
		"worst relative %s" % String.num_scientific(worst_moment))
	for deg in [8.0, 10.0]:
		var alpha_d := deg_to_rad(deg)
		var s := _state(alpha_d, 0.0)
		var air := Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
		var d0 := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
		var oracle: float = _drag(Aero._global_loads(s, air, d0, model, RHO), alpha_d)
		var drag_new: float = _drag(_local(model, s, 0.0), alpha_d)
		var drag_old: float = _drag(_local(old, s, 0.0), alpha_d)
		_check("α %.0f°: local drag %.2f N closer to the oracle's %.2f N than the former law's %.2f N" % [deg, drag_new, oracle, drag_old],
			absf(drag_new - oracle) < absf(drag_old - oracle))
	# Pitch-rate response of the horizontal tail alone (only it is removed for the baseline; the fin is common to both).
	var wing_only := model.duplicate(true)
	wing_only.surfaces.horizontal.area = 0.0
	var h := 0.05
	var alpha := deg_to_rad(4.0)
	var tail_new := (_local(model, _state(alpha, h), 0.0)[4] - _local(wing_only, _state(alpha, h), 0.0)[4]) \
		- (_local(model, _state(alpha, -h), 0.0)[4] - _local(wing_only, _state(alpha, -h), 0.0)[4])
	var old_wing := old.duplicate(true)
	old_wing.surfaces.horizontal.area = 0.0
	var tail_old := (_local(old, _state(alpha, h), 0.0)[4] - _local(old_wing, _state(alpha, h), 0.0)[4]) \
		- (_local(old, _state(alpha, -h), 0.0)[4] - _local(old_wing, _state(alpha, -h), 0.0)[4])
	_check("the tail's pitch-rate moment grows by 1/(1 − dε/dα) = %.4f within 5 %% (lift part exact; tail drag and lift tilt add the rest)" % (1.0 / keep),
		absf(tail_new / tail_old * keep - 1.0) < 0.05,
		"ratio %.5f" % (tail_new / tail_old))
	# Elevator τ against thin-airfoil flap theory, τ = 1 − (θ − sin θ)/π with cos θ = 2E − 1, for the Stik's elevator
	# chord fraction E from the model team's geometry (outlines in assets/aircraft/ugly-stik-60/geometry.json).
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../assets/aircraft/ugly-stik-60/geometry.json")) \
		if FileAccess.file_exists("res://../assets/aircraft/ugly-stik-60/geometry.json") else {}
	var flap_tau := -1.0
	if not geometry.is_empty():
		var stab_chord := 0.0
		var elev_chord := 0.0
		for p in geometry.tail.stab_outline:
			stab_chord = maxf(stab_chord, -float(p[1]))
		for p in geometry.tail.elevator_outline:
			elev_chord = maxf(elev_chord, float(p[1]))
		var e: float = elev_chord / (stab_chord + float(geometry.tail.hinge_gap) + elev_chord)
		var theta := acos(2.0 * e - 1.0)
		flap_tau = 1.0 - (theta - sin(theta)) / PI
	_check("elevator τ %.3f within 0.45–0.75 and within 20 %% of thin-airfoil flap theory for the Stik's elevator (%.3f)" % [tail.elevator_tau, flap_tau],
		tail.elevator_tau > 0.45 and tail.elevator_tau < 0.75 and (flap_tau < 0.0 or absf(tail.elevator_tau / flap_tau - 1.0) < 0.20))
	# Downwash follows the wing's lift. At α 14° the wing is partly stalled and the tail still linear: the tail's own
	# angle, recovered from its lift (CL_t / free slope), must equal α − atan2(k_ε·U,V) + i_free and sit above the angle a
	# linear downwash dε/dα·α would leave it: less downwash, more tail lift, the stall break.
	var alpha_b := deg_to_rad(14.0)
	var s_b := _state(alpha_b, 0.0)
	var no_horizontal := model.duplicate(true)
	no_horizontal.surfaces.horizontal.area = 0.0
	var qbar := 0.5 * RHO * V * V
	var lift_all: float = _lift(_local(model, s_b, 0.0), alpha_b)
	var lift_rest: float = _lift(_local(no_horizontal, s_b, 0.0), alpha_b)
	var cl_tail: float = (lift_all - lift_rest) / (qbar * float(tail.area))
	var tail_angle: float = cl_tail / float(tail.free_slope)
	var wake_b := Aero.wing_wake_velocity(s_b, Air.compute(s_b, PackedFloat64Array([0.0, 0.0, 0.0]), RHO),
		{ elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }, model)
	var expected: float = alpha_b - atan2(float(tail.downwash_per_cl) * wake_b, V) + float(tail.free_incidence)
	var linear: float = alpha_b - (gradient * alpha_b + float(tail.downwash_per_cl) * float(tail.wing_cl0)) + float(tail.free_incidence)
	_check("α 14° (wing partly stalled): the tail's angle %.2f° = α − atan2(k_ε·U,V) + i_free (%.2f°), above the linear-downwash %.2f° (stall break)"
		% [rad_to_deg(tail_angle), rad_to_deg(expected), rad_to_deg(linear)],
		absf(tail_angle - expected) < 1e-11 and tail_angle - linear > deg_to_rad(0.5))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _lift(l: PackedFloat64Array, alpha: float) -> float:
	return l[0] * sin(alpha) - l[2] * cos(alpha)


func _drag(l: PackedFloat64Array, alpha: float) -> float:
	return -(l[0] * cos(alpha) + l[2] * sin(alpha))


func _local(model: Dictionary, s: PackedFloat64Array, elevator: float, wake := NAN) -> PackedFloat64Array:
	var d := { elevator = elevator, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	return Aero._local_loads(s, Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO), d, model, RHO, wake)


func _state(alpha: float, q: float) -> PackedFloat64Array:
	return PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, q, 0])
