# The displacement couple is r cross the incremental lift vector, strip by strip.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RHO := 1.225

var count := 0
var failures := 0
var public_regimes := {attached = false, blended = false, local = false}


func check(label: String, ok: bool, detail := "") -> void:
	count += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func exercise(label: String, model: Dictionary, velocity: PackedFloat64Array, rates: PackedFloat64Array,
		flap_deg: float, deltas := PackedFloat64Array(), check_spatial := false) -> void:
	var state := RB.make_state(M.v3(0, 0, -100), velocity, M.q_identity(), rates)
	var air := Air.compute(state, M.v3(0, 0, 0), RHO)
	var flap := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0, flap = deg_to_rad(flap_deg)}
	var clean := flap.duplicate()
	clean.flap = 0.0
	var zero: Dictionary = model.duplicate(true)
	zero.flaps.lift_reference_offset_m = 0.0
	var absent: Dictionary = model.duplicate(true)
	absent.flaps.erase("lift_reference_offset_m")
	var clean_diag: Array = []
	var flap_diag: Array = []
	var clean_wrench := Aero._local_loads(state, air, clean, zero, RHO, NAN, clean_diag, PackedFloat64Array(), deltas)
	var zero_wrench := Aero._local_loads(state, air, flap, zero, RHO, NAN, flap_diag, PackedFloat64Array(), deltas)
	var offset_wrench := Aero._local_loads(state, air, flap, model, RHO, NAN, null, PackedFloat64Array(), deltas)
	var absent_wrench := Aero._local_loads(state, air, flap, absent, RHO, NAN, null, PackedFloat64Array(), deltas)
	var shifts: PackedFloat64Array = Aero._wing_flow(state, air, flap, model, deltas).flap_shifts
	var arm := Aero._arm(model.reference.arp_le, model.cg_le)
	var ys: PackedFloat64Array = model.envelope.station_ys
	var offset: float = model.flaps.lift_reference_offset_m
	var expected := 0.0
	for i in ys.size():
		if shifts[i] == 0.0:
			continue
		var f0 := velocity[0] + rates[1] * arm[2] - rates[2] * (arm[1] + ys[i])
		if not deltas.is_empty():
			f0 += deltas[3 * i]
		var vp: float = flap_diag[i].plane_speed_mps
		if vp != 0.0:
			# Fz(lift) = -lift * f0 / Vp; r=(-offset,0,0), so My=offset*Fz.
			expected -= offset * (float(flap_diag[i].lift_n) - float(clean_diag[i].lift_n)) * f0 / vp
	var actual: float = offset_wrench[4] - zero_wrench[4]
	check(label + " cross product", absf(actual - expected) < 1e-9, "actual %.12f expected %.12f" % [actual, expected])
	for i in [0, 1, 2, 3, 5]:
		check(label + " preserves other wrench component " + str(i), offset_wrench[i] == zero_wrench[i])
	check(label + " zero and absent offset match", zero_wrench.to_byte_array() == absent_wrench.to_byte_array())
	if deltas.is_empty():
		var public_offset := Aero.loads(state, air, flap, model, RHO)
		var public_zero := Aero.loads(state, air, flap, zero, RHO)
		check(label + " public loads retain transfer", absf(public_offset[4] - public_zero[4] - expected) < 1e-9)
		if flap_deg != 0.0:
			var blend := Aero.local_flow_weight(state, air, clean, model)
			if blend == 0.0: public_regimes.attached = true
			elif blend == 1.0: public_regimes.local = true
			else: public_regimes.blended = true
	elif check_spatial:
		var with_offset := Aero.ambient_spatial_loads(state, air, flap, model, RHO, deltas)
		var with_zero := Aero.ambient_spatial_loads(state, air, flap, zero, RHO, deltas)
		check(label + " public spatial input admitted", with_offset.get("ok", false) and with_zero.get("ok", false), str(with_offset.get("errors", [])))
		if with_offset.get("ok", false) and with_zero.get("ok", false):
			check(label + " public spatial transfer", absf(with_offset.loads[4] - with_zero.loads[4] - expected) < 1e-9)
	if flap_deg == 0.0:
		check(label + " clean output unchanged", offset_wrench.to_byte_array() == clean_wrench.to_byte_array())


func section_and_drag_controls(model: Dictionary) -> void:
	var velocity := M.v3(24, 1, 8)
	var state := RB.make_state(M.v3(0, 0, -100), velocity, M.q_identity(), M.v3(0, 0, 0))
	var air := Air.compute(state, M.v3(0, 0, 0), RHO)
	var flap := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0, flap = deg_to_rad(20.0)}
	var clean := flap.duplicate()
	clean.flap = 0.0
	var no_section: Dictionary = model.duplicate(true)
	no_section.flaps.thin_airfoil_moment_per_cl = 0.0
	var no_drag: Dictionary = model.duplicate(true)
	no_drag.flaps.profile_drag_coefficient = 0.0
	var clean_diag: Array = []
	var flap_diag: Array = []
	var no_section_diag: Array = []
	var no_drag_diag: Array = []
	Aero._local_loads(state, air, clean, model, RHO, NAN, clean_diag)
	Aero._local_loads(state, air, flap, model, RHO, NAN, flap_diag)
	Aero._local_loads(state, air, flap, no_section, RHO, NAN, no_section_diag)
	Aero._local_loads(state, air, flap, no_drag, RHO, NAN, no_drag_diag)
	var shifts: PackedFloat64Array = Aero._wing_flow(state, air, flap, model).flap_shifts
	var section_actual := 0.0
	var section_expected := 0.0
	var drag_actual := 0.0
	var drag_expected := 0.0
	for i in shifts.size():
		if shifts[i] == 0.0:
			continue
		var chord: float = model.envelope.station_chords[i]
		section_actual += float(flap_diag[i].section_pitch_couple_nm) - float(no_section_diag[i].section_pitch_couple_nm)
		section_expected += (float(flap_diag[i].lift_n) - float(clean_diag[i].lift_n)) * chord * float(model.flaps.thin_airfoil_moment_per_cl)
		drag_actual += float(flap_diag[i].section_pitch_couple_nm) - float(no_drag_diag[i].section_pitch_couple_nm)
		var delta_drag: float = float(flap_diag[i].drag_n) - float(no_drag_diag[i].drag_n)
		var vp: float = flap_diag[i].plane_speed_mps
		var arm_x := -(float(model.flaps.hinge_fraction) + 0.5 * float(model.flaps.chord_fraction) * cos(flap.flap) - 0.25) * chord
		var arm_z := 0.5 * float(model.flaps.chord_fraction) * chord * sin(flap.flap)
		var drag_fx := -delta_drag * velocity[0] / vp
		var drag_fz := -delta_drag * velocity[2] / vp
		drag_expected += arm_z * drag_fx - arm_x * drag_fz
	check("separate section couple retained", absf(section_actual - section_expected) < 1e-9 and absf(section_expected) > 0.1,
		"actual %.12f expected %.12f" % [section_actual, section_expected])
	check("separate profile drag couple retained", absf(drag_actual - drag_expected) < 1e-9 and absf(drag_expected) > 0.01,
		"actual %.12f expected %.12f" % [drag_actual, drag_expected])


func _initialize() -> void:
	var result := AD.load_file("res://data/aircraft/f4u_corsair_250.json")
	check("F4U admitted", result.ok, str(result.errors))
	if result.ok:
		var model: Dictionary = result.model
		check("F4U offset positive", model.flaps.lift_reference_offset_m > 0.0)
		for alpha in [0.0, 12.0, 20.0, 30.0]:
			var rad := deg_to_rad(alpha)
			exercise("alpha %.0f" % alpha, model, M.v3(30.0*cos(rad), 0.0, 30.0*sin(rad)), M.v3(0, 0, 0), 20.0)
		var neutral := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
		for i in 120:
			var angle := deg_to_rad(0.25 * i)
			var velocity := M.v3(30.0*cos(angle), 0.0, 30.0*sin(angle))
			var state := RB.make_state(M.v3(0, 0, -100), velocity, M.q_identity(), M.v3(0, 0, 0))
			var air := Air.compute(state, M.v3(0, 0, 0), RHO)
			var blend := Aero.local_flow_weight(state, air, neutral, model)
			if blend > 0.0 and blend < 1.0:
				exercise("blended public branch", model, velocity, M.v3(0, 0, 0), 20.0)
				break
		exercise("clean", model, M.v3(28, 2, 9), M.v3(0.1, -0.2, 0.3), 0.0)
		exercise("zero plane flow", model, M.v3(0, 7, 0), M.v3(0, 0, 0), 20.0)
		exercise("reverse", model, M.v3(-25, 2, 0), M.v3(0, 0, 0), 20.0)
		var twisted: Dictionary = model.duplicate(true)
		twisted.surfaces.station_incidence = PackedFloat64Array()
		for _i in model.envelope.station_ys.size():
			twisted.surfaces.station_incidence.append(PI)
		exercise("reverse signed projection", twisted, M.v3(-25, 2, 2), M.v3(0, 0, 0), 20.0)
		var spatial := PackedFloat64Array()
		for i in model.envelope.station_ys.size():
			spatial.append_array(PackedFloat64Array([0.7*i, -0.3*i, 0.4*i]))
		# Station-flow bridge also carries horizontal and vertical tail deltas.
		spatial.append_array(PackedFloat64Array([0, 0, 0, 0, 0, 0]))
		exercise("rotating spatial stations", model, M.v3(23, 3, 8), M.v3(0.4, -0.6, 1.2), 20.0, spatial)
		var gentle_spatial := PackedFloat64Array()
		for i in model.envelope.station_ys.size():
			gentle_spatial.append_array(PackedFloat64Array([0.01*i, 0.0, 0.02*i]))
		gentle_spatial.append_array(PackedFloat64Array([0, 0, 0, 0, 0, 0]))
		exercise("admitted spatial", model, M.v3(30, 0, 1), M.v3(0, 0, 0), 20.0, gentle_spatial, true)
		var shifted_cg: Dictionary = model.duplicate(true)
		shifted_cg.cg_le = shifted_cg.cg_le.duplicate()
		shifted_cg.cg_le[0] += 0.04
		exercise("live CG", shifted_cg, M.v3(23, -2, 9), M.v3(-0.3, 0.8, -0.7), 20.0)
		section_and_drag_controls(model)
		check("public attached, blended and local branches exercised", public_regimes.attached and public_regimes.blended and public_regimes.local, str(public_regimes))
	print("Flap offset invariant: %d checks, %d failed" % [count, failures])
	quit(1 if failures else 0)
