# P51-11a: the P-51D's simulated plain flaps. Data and provenance; the optional shared-law refinements are byte-identical
# when neutral; flaps raise the maximum lift monotonically (the unrefined law lowered it at 15 deg, research/p51/p51-11);
# the session actuator reaches the kit settings in the authored time; the rendered flaps follow the accepted angle.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"
const RHO := 1.225

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DATA))


func _model(raw: Dictionary) -> Dictionary:
	var r: Dictionary = AD.validate_and_derive(raw)
	return r.model if r.ok else {}


func _state(V: float, alpha: float, beta := 0.0, p := 0.0, q := 0.0, r := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -100), M.v3(V * cos(alpha) * cos(beta), V * sin(beta), V * sin(alpha) * cos(beta)),
		M.q_identity(), M.v3(p, q, r))


## Untrimmed airplane lift coefficient (elevator neutral) at alpha, flap in degrees.
func _cl(model: Dictionary, alpha: float, flap_deg: float) -> float:
	var s := _state(20.0, alpha)
	var d := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0, flap = deg_to_rad(flap_deg) }
	var l := Aero.loads(s, Air.compute(s, M.v3(0, 0, 0), RHO), d, model, RHO)
	return (-l[2] * cos(alpha) + l[0] * sin(alpha)) / (0.5 * RHO * 400.0 * float(model.reference.S))


func _cl_max(model: Dictionary, flap_deg: float) -> float:
	var best := -INF
	for k in 49:
		best = maxf(best, _cl(model, deg_to_rad(0.5 * k), flap_deg))
	return best


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw := _raw()
	var model := _model(raw)
	_check("P-51 data loads with simulated flaps", not model.is_empty() and raw.capabilities.flaps == "simulated" and model.has("flaps"))
	if model.is_empty():
		_finish()
		return
	var f: Dictionary = model.flaps
	_check("kit settings: 15 deg take-off, 45 deg landing (CARF manual)", f.max_angle_deg == 45.0 and is_equal_approx(f.takeoff_fraction, 1.0 / 3.0))
	_check("scaled full-size flap span and chord", is_equal_approx(f.inner_span_m, 0.1249) and is_equal_approx(f.outer_span_m, 0.7996) and is_equal_approx(f.chord_fraction, 0.21))
	_check("refinements present and derived", raw.flaps.stall_shift_fraction.kind == "derived" and raw.flaps.lift_reference_offset_m.kind == "derived"
		and f.stall_shift_fraction > 0.2 and f.stall_shift_fraction < 0.5 and f.lift_reference_offset_m > 0.04 and f.lift_reference_offset_m < 0.07,
		"kappa %.3f offset %.4f m" % [f.stall_shift_fraction, f.lift_reference_offset_m])

	# 1. Neutral refinements are byte-identical to their absence (the Vantage Jet law).
	var absent := raw.duplicate(true)
	absent.flaps.erase("stall_shift_fraction")
	absent.flaps.erase("lift_reference_offset_m")
	var neutral := absent.duplicate(true)
	neutral.flaps.stall_shift_fraction = {value = 1.0, unit = "1", kind = "estimated", source = "test: neutral"}
	neutral.flaps.lift_reference_offset_m = {value = 0.0, unit = "m", kind = "estimated", source = "test: neutral"}
	var m_absent := _model(absent)
	var m_neutral := _model(neutral)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5111
	var identical := not m_absent.is_empty() and not m_neutral.is_empty()
	for i in 300:
		if not identical:
			break
		var s := _state(rng.randf_range(8.0, 40.0), rng.randf_range(-0.3, 0.5), rng.randf_range(-0.3, 0.3), rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var d := { elevator = rng.randf_range(-0.3, 0.3), aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0, flap = deg_to_rad(rng.randf_range(0.0, 45.0)) }
		var air := Air.compute(s, M.v3(0, 0, 0), RHO)
		identical = Aero.loads(s, air, d, m_absent, RHO).to_byte_array() == Aero.loads(s, air, d, m_neutral, RHO).to_byte_array()
	_check("kappa 1 and offset 0 are byte-identical to the absent fields (300 states)", identical)

	# 2. Lift: monotonic maximum lift with flap angle, and the diagnosed failure of the unrefined law.
	var c0 := _cl_max(model, 0.0)
	var c15 := _cl_max(model, 15.0)
	var c45 := _cl_max(model, 45.0)
	_check("flaps raise the maximum lift monotonically (0 / 15 / 45 deg)", c15 > c0 and c45 > c15, "%.3f / %.3f / %.3f" % [c0, c15, c45])
	_check("the unrefined law (kappa 1, offset 0) lowered the take-off-flap maximum lift (P51-11a diagnosis)", _cl_max(m_absent, 15.0) < c0,
		"%.3f vs clean %.3f" % [_cl_max(m_absent, 15.0), c0])
	var a5 := deg_to_rad(5.0)
	_check("at fixed alpha, flaps add lift (5 deg: 0 < 15 < 45 deg)", _cl(model, a5, 0.0) < _cl(model, a5, 15.0) and _cl(model, a5, 15.0) < _cl(model, a5, 45.0))

	# 3. Session actuator: the kit landing setting in the authored travel time.
	var session := FlightSession.new()
	session.setup(DATA)
	root.add_child(session)
	session.input_enabled = false
	var t: Dictionary = session.trim_at(25.0, "level")
	session.reset()
	_check("session exposes the flap channel", session.flaps_available())
	session._flap_requested = 1.0
	var sim: Node = session.sim
	var ticks := int(roundi(float(f.extension_time) / sim.dt())) + 2
	var halfway := NAN
	for i in ticks:
		sim.inputs = session._inputs()
		sim.step()
		if i == int(ticks / 2):
			halfway = float(session.flap_state().angle_deg)
	var state: Dictionary = session.flap_state()
	_check("full flaps reach 45 deg within the 2.5 s travel, about half way at mid travel",
		t.ok and absf(float(state.angle_deg) - 45.0) < 1e-6 and halfway > 18.0 and halfway < 27.0, "%.1f deg at end, %.1f deg half way" % [state.angle_deg, halfway])

	# 4. Rendering: both flap hinges follow the accepted angle, trailing edge down, and return to rest.
	var airplane: Dictionary = AirplaneBuilder.build(AirplaneBuilder.P51_ID)
	root.add_child(airplane.root)
	var flaps: Dictionary = airplane.get("flaps", {})
	_check("two flap hinges outside the control-surface hinges", flaps.size() == 2 and not airplane.hinges.has("flap_left")
		and flaps.left.name == "flap_left_hinge" and flaps.right.name == "flap_right_hinge")
	var mesh: MeshInstance3D = airplane.root.find_child("flap_left", true, false)
	var rest: AABB = mesh.global_transform * mesh.get_aabb()
	AirplaneBuilder.apply_flaps(airplane, 45.0)
	var down: AABB = mesh.global_transform * mesh.get_aabb()
	AirplaneBuilder.apply_flaps(airplane, 0.0)
	var back: AABB = mesh.global_transform * mesh.get_aabb()
	_check("45 deg lowers the flap trailing edge and 0 restores it", down.position.y < rest.position.y - 0.05 and back.is_equal_approx(rest),
		"%.3f m lower" % (rest.position.y - down.position.y))
	_finish()


func _finish() -> void:
	print("P51-11a flaps: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
