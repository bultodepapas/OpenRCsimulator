# AV-09: symmetric hinged flaps change finite-wing lift, stall, drag, and pitch.
# Run: godot --headless --path . --script res://tests/test_flap_aero.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Flaps := preload("res://physics/flaps.gd")
const PATH := "res://data/aircraft/sebart_avanti_s_a200.json"

var _failures := 0
var _count := 0
var _model: Dictionary


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _state(speed: float, alpha_deg: float, beta_deg := 0.0, rates := [0.0, 0.0, 0.0]) -> PackedFloat64Array:
	var alpha := deg_to_rad(alpha_deg)
	var beta := deg_to_rad(beta_deg)
	var u := speed * M.cos_(beta) * M.cos_(alpha)
	var v := speed * M.sin_(beta)
	var w := speed * M.cos_(beta) * M.sin_(alpha)
	return RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(u, v, w), M.q_identity(), M.v3(rates[0], rates[1], rates[2]))


func _deflections(flap_deg := 0.0, elevator_down_rad := 0.0) -> Dictionary:
	return {aileron_left = 0.0, aileron_right = 0.0, elevator = elevator_down_rad,
		rudder = 0.0, flap = deg_to_rad(flap_deg)}


func _loads(speed: float, alpha_deg: float, flap_deg := 0.0, beta_deg := 0.0,
		rates := [0.0, 0.0, 0.0], elevator_down_rad := 0.0, model := {}) -> PackedFloat64Array:
	var use_model: Dictionary = _model if model.is_empty() else model
	var state := _state(speed, alpha_deg, beta_deg, rates)
	var air := Air.compute(state, M.v3(0.0, 0.0, 0.0))
	return Aero.loads(state, air, _deflections(flap_deg, elevator_down_rad), use_model, Air.RHO_SEA_LEVEL)


func _wing_cl(alpha_deg: float, flap_deg: float) -> float:
	var state := _state(25.0, alpha_deg)
	var air := Air.compute(state, M.v3(0.0, 0.0, 0.0))
	return Aero._wing_lift_coefficient_with(state, air, _deflections(flap_deg), _model, PackedFloat64Array())


func _initialize() -> void:
	var loaded := AD.load_file(PATH)
	_check("authored Avanti source validates", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		quit(1)
		return
	_model = loaded.model
	_check("optional flap law is enabled only by its explicit module", Flaps.enabled(_model))
	_check("flap law has a stable classifier identity", Flaps.LAW == "controls.flaps.hinged_trailing_edge.v1")
	_check("manual settings derive 20° takeoff = normalized 0.4", absf(_model.flaps.takeoff_fraction - 0.4) < 1e-12)
	_check("manual 50° setting is the configured maximum", _model.flaps.max_angle_deg == 50.0)
	_check("actuator reaches full extension in authored effective time",
		absf(Flaps.advance(0.0, 1.0, 1.5, _model.flaps) - 1.0) < 1e-12)
	_check("actuator retracts with its own time constant",
		absf(Flaps.advance(1.0, 0.0, 0.75, _model.flaps) - 0.5) < 1e-12)
	_check("actuator clamps requests and position to normalized range",
		Flaps.advance(-0.4, 1.4, 1.5, _model.flaps) == 1.0)
	_check("nonpositive sample time holds accepted position",
		Flaps.advance(0.3, 1.0, 0.0, _model.flaps) == 0.3)
	_check("nonfinite requests hold accepted actuator position",
		Flaps.advance(0.3, NAN, 0.1, _model.flaps) == 0.3)

	# Preserve the literal clean path and the paired aero-disabled sensitivity model.
	var state := _state(29.0, 3.0)
	var air := Air.compute(state, M.v3(0.0, 0.0, 0.0))
	var clean_d := _deflections(0.0)
	clean_d.erase("flap")
	var clean := Aero.loads(state, air, clean_d, _model, Air.RHO_SEA_LEVEL)
	var zero_flap := Aero.loads(state, air, _deflections(0.0), _model, Air.RHO_SEA_LEVEL)
	_check("zero commanded flap preserves clean load bits", clean.to_byte_array() == zero_flap.to_byte_array())
	var disabled_model: Dictionary = _model.duplicate(true)
	disabled_model.flaps.aerodynamic_gain = 0.0
	var disabled := Aero.loads(state, air, _deflections(50.0), disabled_model, Air.RHO_SEA_LEVEL)
	_check("zero-gain sensitivity control preserves clean aero exactly", clean.to_byte_array() == disabled.to_byte_array())

	# The hinged-flap input raises lift below stall and raises the post-stall maximum
	# through the same bounded section/polar law. Reported CL is the six-strip mean.
	var clean_max := -INF
	var takeoff_max := -INF
	var landing_max := -INF
	var clean_stall_alpha := 0.0
	var takeoff_stall_alpha := 0.0
	var landing_stall_alpha := 0.0
	for alpha in range(-8, 76):
		var cl_clean := _wing_cl(float(alpha), 0.0)
		var cl_takeoff := _wing_cl(float(alpha), 20.0)
		var cl_landing := _wing_cl(float(alpha), 50.0)
		if cl_clean > clean_max:
			clean_max = cl_clean
			clean_stall_alpha = float(alpha)
		if cl_takeoff > takeoff_max:
			takeoff_max = cl_takeoff
			takeoff_stall_alpha = float(alpha)
		if cl_landing > landing_max:
			landing_max = cl_landing
			landing_stall_alpha = float(alpha)
	_check("20° flap increases bounded wing CLmax", takeoff_max > clean_max + 0.02,
		"clean %.3f takeoff %.3f" % [clean_max, takeoff_max])
	_check("50° flap further increases bounded wing CLmax", landing_max > takeoff_max + 0.02,
			"takeoff %.3f landing %.3f" % [takeoff_max, landing_max])
	_check("flapped maximum lift remains finite and bounded", landing_max < 2.0 and is_finite(landing_max), str(landing_max))
	_check("post-stall wing lift rolls over instead of extrapolating linearly",
		_wing_cl(70.0, 50.0) < landing_max, "peak %.2f°; peak CL %.3f" % [landing_stall_alpha, landing_max])
	_check("clean stall peak remains finite", is_finite(clean_stall_alpha) and clean_stall_alpha > 0.0)
	_check("flap incidences raise lift at negative, attached alpha", _wing_cl(-4.0, 20.0) > _wing_cl(-4.0, 0.0))
	var negative_alpha := _loads(29.0, -4.0, 50.0)
	var negative_velocity := M.v3(29.0 * M.cos_(deg_to_rad(4.0)), 0.0, -29.0 * M.sin_(deg_to_rad(4.0)))
	var negative_power: float = M.dot(M.v3(negative_alpha[0], negative_alpha[1], negative_alpha[2]), negative_velocity)
	var negative_finite := true
	for component in negative_alpha:
		negative_finite = negative_finite and is_finite(component)
	_check("negative-alpha flap response stays finite and dissipative", negative_finite and negative_power < 0.0,
		"loads %s; air power %.2f W" % [negative_alpha, negative_power])

	# At a fixed forward attitude the added lift and panel profile drag must cost
	# air-relative power; symmetric flap deployment cannot create a roll/yaw bias.
	var clean_forward := _loads(29.0, 3.0)
	var takeoff_forward := _loads(29.0, 3.0, 20.0)
	var landing_forward := _loads(29.0, 3.0, 50.0)
	_check("20° flap adds lift in attached forward flight", takeoff_forward[2] < clean_forward[2],
		"clean Fz %.2f; takeoff Fz %.2f" % [clean_forward[2], takeoff_forward[2]])
	_check("50° flap adds lift beyond the 20° setting", landing_forward[2] < takeoff_forward[2],
		"20° Fz %.2f; 50° Fz %.2f" % [takeoff_forward[2], landing_forward[2]])
	var speed_vector := M.v3(29.0 * M.cos_(deg_to_rad(3.0)), 0.0, 29.0 * M.sin_(deg_to_rad(3.0)))
	var clean_power: float = M.dot(M.v3(clean_forward[0], clean_forward[1], clean_forward[2]), speed_vector)
	var flap_power: float = M.dot(M.v3(landing_forward[0], landing_forward[1], landing_forward[2]), speed_vector)
	_check("flap lift and profile drag do not add translational energy", flap_power < clean_power and flap_power < 0.0,
		"clean P %.2f W; landing P %.2f W" % [clean_power, flap_power])
	_check("symmetric deployment preserves no roll, side-force, or yaw moment",
		absf(landing_forward[1]) < 1e-9 and absf(landing_forward[3]) < 1e-9 and absf(landing_forward[5]) < 1e-9,
		str(landing_forward))

	# A downward elevator mix is a separate manual setting, not hidden aerodynamic
	# compensation. Its sign and fractional travel match the AV-09 session mapping.
	var takeoff_mix_rad: float = 0.20 * (20.0 / 50.0) * _model.controls.throw_rad.elevator
	var landing_mix_rad: float = 0.20 * (50.0 / 50.0) * _model.controls.throw_rad.elevator
	var takeoff_mixed := _loads(29.0, 3.0, 20.0, 0.0, [0.0, 0.0, 0.0], takeoff_mix_rad)
	var landing_mixed := _loads(29.0, 3.0, 50.0, 0.0, [0.0, 0.0, 0.0], landing_mix_rad)
	_check("manual takeoff down-elevator mix moves pitch moment nose-down", takeoff_mixed[4] < takeoff_forward[4],
		"unmixed %.2f; mixed %.2f" % [takeoff_forward[4], takeoff_mixed[4]])
	_check("manual landing down-elevator mix moves pitch moment nose-down", landing_mixed[4] < landing_forward[4],
		"unmixed %.2f; mixed %.2f" % [landing_forward[4], landing_mixed[4]])
	var local_clean_diag: Array = []
	var local_flap_diag: Array = []
	Aero._local_loads(state, air, clean_d, _model, Air.RHO_SEA_LEVEL, NAN, local_clean_diag)
	Aero._local_loads(state, air, _deflections(20.0), _model, Air.RHO_SEA_LEVEL, NAN, local_flap_diag)
	var incremental_section_couple := 0.0
	for i in local_clean_diag.size():
		incremental_section_couple += float(local_flap_diag[i].section_pitch_couple_nm) - float(local_clean_diag[i].section_pitch_couple_nm)
	_check("plain-flap intrinsic quarter-chord couple is nose-down",
		incremental_section_couple < 0.0 and is_finite(incremental_section_couple), str(incremental_section_couple))
	_check("coupled whole-aircraft pitch response remains finite",
		is_finite(takeoff_forward[4]) and is_finite(landing_forward[4]),
		"takeoff My %.2f; landing My %.2f" % [takeoff_forward[4], landing_forward[4]])

	# Reverse/edge-on flow has no flap camber or panel-drag contribution.
	var reverse_clean := _loads(29.0, 180.0)
	var reverse_flap := _loads(29.0, 180.0, 50.0)
	var reverse_equal := true
	for component in 6:
		reverse_equal = reverse_equal and absf(reverse_clean[component] - reverse_flap[component]) < 1e-10
	_check("reverse flow cannot turn flap incidence into lift or thrust", reverse_equal,
		"clean %s; flap %s" % [reverse_clean, reverse_flap])

	print("AV-09 flap aero peaks: clean %.3f at %.0f°, 20° %.3f at %.0f°, 50° %.3f at %.0f°" % [
		clean_max, clean_stall_alpha, takeoff_max, takeoff_stall_alpha, landing_max, landing_stall_alpha])
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
