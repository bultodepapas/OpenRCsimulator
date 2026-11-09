extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const DATA := "res://data/aircraft/gp_extra_300s_60.json"
const RHO := 1.225
var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var candidate: Dictionary = AD.validate_and_derive(raw)
	check("candidate admitted", candidate.ok)
	if not candidate.ok:
		printerr(candidate.errors)
		finish()
		return
	var without: Dictionary = raw.duplicate(true)
	without.aero.surfaces.erase("wing_separated_force_offset")
	var base: Dictionary = AD.validate_and_derive(without)
	check("absent option admitted", base.ok)
	var zero: Dictionary = candidate.model.duplicate(true)
	zero.surfaces.wing_separated_force_offset = 0.0
	for value in [-0.001, 0.251, "0.25", INF]:
		var bad: Dictionary = raw.duplicate(true)
		bad.aero.surfaces.wing_separated_force_offset.value = value
		check("invalid offset refused " + str(value), not AD.validate_and_derive(bad).ok)
	var controls := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	for angle_deg in [-180.0, -179.999, -90.001, -90.0, -89.999, -60.0, -30.0, -20.0, 0.0, 5.0, 20.0, 30.0, 60.0, 89.999, 90.0, 90.001, 179.999, 180.0]:
		var angle: float = deg_to_rad(angle_deg)
		var fraction := Aero._separated_offset_fraction(angle)
		check("bounded offset " + str(angle_deg), fraction >= 0.0 and fraction <= 1.0)
		check("offset even " + str(angle_deg), absf(fraction - Aero._separated_offset_fraction(-angle)) < 1e-14)
		for aileron in [-0.1, 0.0, 0.1]:
			controls.aileron_right = aileron
			controls.aileron_left = -aileron
			var state := RB.make_state(M.v3(0.0, 0.0, -300.0), M.v3(20.0*cos(angle), 0.0, 20.0*sin(angle)), M.q_identity(), M.v3(0.0, 0.0, 0.0))
			var air := Air.compute(state, M.v3(0.0, 0.0, 0.0))
			var old := Aero.loads(state, air, controls, base.model, RHO)
			var disabled := Aero.loads(state, air, controls, zero, RHO)
			var now := Aero.loads(state, air, controls, candidate.model, RHO)
			check("zero is byte-identical", old.to_byte_array() == disabled.to_byte_array())
			for axis in [0, 1, 2, 3, 5]:
				check("only pitch moment changes", now[axis] == old[axis])
			check("pitch finite", is_finite(now[4]))
			if angle_deg == 0.0 or angle_deg == 5.0:
				check("attached response exact", now.to_byte_array() == old.to_byte_array())
			var rows := Aero.wing_strip_loads(state, air, controls, candidate.model, RHO)
			var base_rows := Aero.wing_strip_loads(state, air, controls, base.model, RHO)
			for i in rows.size():
				var row: Dictionary = rows[i]
				var expected: float = 0.25 * fraction * float(row.stall_weight) * float(candidate.model.envelope.station_chords[i]) * float(row.force_body_n[2])
				var actual: float = float(row.section_pitch_couple_nm) - float(base_rows[i].section_pitch_couple_nm)
				check("actual-force offset moment, with control incidence", absf(actual - expected) < 1e-10)
	check("reverse endpoint increment zero", Aero._separated_offset_fraction(PI) == 0.0)
	check("normal-flow maximum", Aero._separated_offset_fraction(PI/2.0) == 1.0)
	for join in [0.0, PI/12.0, PI/3.0, PI/2.0, PI]:
		var eps := 1e-6
		var center := Aero._separated_offset_fraction(join)
		var left := Aero._separated_offset_fraction(wrapf(join-eps, -PI, PI))
		var right := Aero._separated_offset_fraction(wrapf(join+eps, -PI, PI))
		check("matching one-sided offset slopes " + str(join), absf((center-left)/eps - (right-center)/eps) < 1e-4)
	for fixture in ["sebart_avanti_s_a200", "moonrunner_x99"]:
		var unsupported: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/" + fixture + ".json"))
		check("unmodified fixture admitted " + fixture, AD.validate_and_derive(unsupported).ok)
		unsupported.aero.surfaces.wing_separated_force_offset = raw.aero.surfaces.wing_separated_force_offset.duplicate(true)
		var result: Dictionary = AD.validate_and_derive(unsupported)
		check("unsupported combination refused " + fixture, not result.ok and str(result.errors).contains("wing_separated_force_offset"))
	check_rate_and_spatial_offset(candidate.model)
	finish()

func check_rate_and_spatial_offset(model: Dictionary) -> void:
	var model_copy: Dictionary = model.duplicate(true)
	model_copy.surfaces.station_incidence = PackedFloat64Array([-0.02, 0.01, 0.01, 0.01, 0.01, -0.02])
	var baseline: Dictionary = model_copy.duplicate(true)
	baseline.surfaces.erase("wing_separated_force_offset")
	var controls := {elevator = 0.0, aileron_right = 0.1, aileron_left = -0.1, rudder = 0.0}
	var rates := M.v3(1.3, -0.8, 0.5)
	var velocity := M.v3(18.0, 2.0, 9.0)
	var state := RB.make_state(M.v3(0.0, 0.0, -300.0), velocity, M.q_identity(), rates)
	var air := Air.compute(state, M.v3(0.0, 0.0, 0.0))
	var stations: int = model_copy.envelope.station_ys.size()
	var deltas := PackedFloat64Array()
	deltas.resize(3*(stations+2))
	for i in stations:
		deltas[3*i] = 0.2 * i
		deltas[3*i+2] = -0.3 * i
	var rows: Array = []
	var old_rows: Array = []
	var now := Aero._local_loads(state, air, controls, model_copy, RHO, NAN, rows, PackedFloat64Array(), deltas)
	var old := Aero._local_loads(state, air, controls, baseline, RHO, NAN, old_rows, PackedFloat64Array(), deltas)
	var expected_total := 0.0
	for i in stations:
		var arp: PackedFloat64Array = model_copy.reference.arp_le
		var cg: PackedFloat64Array = model_copy.cg_le
		var arm := M.v3(-(arp[0]-cg[0]), arp[1]-cg[1]+float(rows[i].y_m), -(arp[2]-cg[2]))
		var local_flow := M.add(velocity, M.cross(rates, arm))
		local_flow[0] += deltas[3*i]
		local_flow[2] += deltas[3*i+2]
		var shift: float = 0.25 * Aero._separated_offset_fraction(atan2(local_flow[2], local_flow[0])) * float(rows[i].stall_weight)
		var displacement := M.v3(-shift * float(model_copy.envelope.station_chords[i]), 0.0, 0.0)
		var moment := M.cross(displacement, old_rows[i].force_body_n)
		check("spatial/rate actual force unchanged", rows[i].force_body_n.to_byte_array() == old_rows[i].force_body_n.to_byte_array())
		check("spatial/rate independent r cross F", absf(float(rows[i].section_pitch_couple_nm)-float(old_rows[i].section_pitch_couple_nm)-moment[1]) < 1e-10)
		expected_total += moment[1]
	check("spatial/rate total pitch increment", absf(now[4] - old[4] - expected_total) < 1e-10)

func finish() -> void:
	print("WING_SEPARATED_OFFSET_COMPLETE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
