# Aircraft-generated rate forces and moments use the inventory reference CG for
# rotational inflow, the ARP for stored moments, and a separate live-fuel CG.
extends SceneTree

const Data := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Mass := preload("res://physics/mass_inventory.gd")
const Liquid := preload("res://physics/liquid_fuel.gd")
const Math3 := preload("res://physics/math3d.gd")

const RHO := 1.225
const SPEED := 23.0
const CONTROLS := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
const PATHS := ["res://data/aircraft/gp_extra_300s_60.json", "res://data/aircraft/f4u_corsair_250.json"]
const RATES := [
	[0.02, 0.0, 0.0], [-0.02, 0.0, 0.0],
	[0.0, 0.02, 0.0], [0.0, -0.02, 0.0],
	[0.0, 0.0, 0.02], [0.0, 0.0, -0.02],
	[0.012, -0.017, 0.023], [-0.012, 0.017, -0.023],
]

var checks := 0
var failures := 0
var zero_wind := PackedFloat64Array([0.0, 0.0, 0.0])


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label + " " + detail)


func state(alpha: float, beta: float, rates: Array) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, -100.0,
		SPEED * cos(alpha) * cos(beta), SPEED * sin(beta), SPEED * sin(alpha) * cos(beta),
		1.0, 0.0, 0.0, 0.0, rates[0], rates[1], rates[2]])


func loads(model: Dictionary, alpha: float, beta: float, rates: Array) -> PackedFloat64Array:
	var s := state(alpha, beta, rates)
	return Aero.loads(s, Air.compute(s, zero_wind, RHO), CONTROLS, model, RHO)


# An independent dimensional wrench at the ARP, translated to the chosen CG.
func expected(model: Dictionary, alpha: float, beta: float, rates: Array) -> PackedFloat64Array:
	var a: Dictionary = model.aero
	var ref: Dictionary = model.reference
	var b: float = ref.b
	var c: float = ref.c
	var factor := 0.5 * RHO * SPEED * SPEED * float(ref.S)
	var phat: float = rates[0] * b / (2.0 * SPEED)
	var qhat: float = rates[1] * c / (2.0 * SPEED)
	var rhat: float = rates[2] * b / (2.0 * SPEED)
	var side: float = factor * (float(a.CYp) * phat + float(a.CYr) * rhat)
	var lift: float = factor * float(a.CLq) * qhat
	var force := PackedFloat64Array([
		-cos(alpha) * sin(beta) * side + sin(alpha) * lift,
		cos(beta) * side,
		-sin(alpha) * sin(beta) * side - cos(alpha) * lift,
	])
	var moment := PackedFloat64Array([
		factor * b * (float(a.Clp) * phat + float(a.Clr) * rhat),
		factor * c * float(a.Cmq) * qhat,
		factor * b * (float(a.Cnp) * phat + float(a.Cnr) * rhat),
	])
	var arm := PackedFloat64Array([
		float(model.cg_le[0]) - float(ref.arp_le[0]),
		float(ref.arp_le[1]) - float(model.cg_le[1]),
		float(model.cg_le[2]) - float(ref.arp_le[2]),
	])
	var shifted := Math3.add(moment, Math3.cross(arm, force))
	force.append_array(shifted)
	return force


func delta(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for i in 6:
		result.append(a[i] - b[i])
	return result


func near_array(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != 6 or b.size() != 6:
		return false
	for i in 6:
		if not is_finite(a[i]) or not is_finite(b[i]):
			return false
		if absf(a[i] - b[i]) > 1.0e-8 * maxf(1.0, absf(b[i])):
			return false
	return true


func comparison_controls() -> void:
	var reference := PackedFloat64Array([0.0, -1.0, 2.0, -3.0, 4.0, -5.0])
	check("wrench comparison accepts equal finite components", near_array(reference, reference))
	var close := reference.duplicate()
	close[4] += 1.0e-9
	check("wrench comparison accepts finite roundoff", near_array(close, reference))
	close[4] += 1.0e-4
	check("wrench comparison rejects finite disagreement", not near_array(close, reference))
	for size in [0, 5, 7]:
		var malformed := reference.duplicate()
		malformed.resize(size)
		check("wrench comparison rejects actual size %d" % size, not near_array(malformed, reference))
		check("wrench comparison rejects reference size %d" % size, not near_array(reference, malformed))
	for value: float in [NAN, INF, -INF]:
		for axis in 6:
			var invalid := reference.duplicate()
			invalid[axis] = value
			check("wrench comparison rejects actual %s at %d" % [value, axis], not near_array(invalid, reference))
			check("wrench comparison rejects reference %s at %d" % [value, axis], not near_array(reference, invalid))
			check("wrench comparison rejects matching invalid %s at %d" % [value, axis], not near_array(invalid, invalid))


func flow_weight(model: Dictionary, alpha: float, rates: Array) -> float:
	var s := state(alpha, 0.0, rates)
	return Aero.local_flow_weight(s, Air.compute(s, zero_wind, RHO), CONTROLS, model)


func transition_check(model: Dictionary, path: String, rates: Array) -> void:
	# Find real partial-blend points rather than assuming both aircraft have the
	# same stall, twist, tail, or rate-triggered selector limits.
	var samples: Array[float] = []
	for i in 251:
		var alpha := 0.002 * float(i)
		var weight := flow_weight(model, alpha, rates)
		if weight > 0.02 and weight < 0.98:
			samples.append(alpha)
	check(path.get_file() + " has partial blend for rates=" + str(rates), not samples.is_empty())
	if samples.is_empty():
		return
	var interior: float = samples[int(samples.size() / 2)]
	check(path.get_file() + " transition endpoints bracketed " + str(rates),
		flow_weight(model, 0.0, rates) == 0.0 and flow_weight(model, 0.5, rates) == 1.0)
	# Bisection locates the two actual branch joins (0→positive and <1→1).
	var low := 0.0
	var high := interior
	for _i in 40:
		var mid := 0.5 * (low + high)
		if flow_weight(model, mid, rates) == 0.0:
			low = mid
		else:
			high = mid
	var first_join := 0.5 * (low + high)
	low = interior
	high = 0.5
	for _i in 40:
		var mid := 0.5 * (low + high)
		if flow_weight(model, mid, rates) < 1.0:
			low = mid
		else:
			high = mid
	var last_join := 0.5 * (low + high)
	check(path.get_file() + " crosses 0/partial join " + str(rates),
		flow_weight(model, first_join - 1.0e-6, rates) == 0.0 and flow_weight(model, first_join + 1.0e-6, rates) > 0.0)
	check(path.get_file() + " crosses partial/1 join " + str(rates),
		flow_weight(model, last_join - 1.0e-6, rates) < 1.0 and flow_weight(model, last_join + 1.0e-6, rates) == 1.0)
	for alpha: float in [first_join, interior, last_join]:
		var below := loads(model, alpha - 1.0e-6, 0.0, rates)
		var above := loads(model, alpha + 1.0e-6, 0.0, rates)
		var continuous := true
		for axis in 6:
			continuous = continuous and is_finite(below[axis]) and is_finite(above[axis]) \
				and absf(above[axis] - below[axis]) < 1.0e-3 * maxf(1.0, maxf(absf(below[axis]), absf(above[axis])))
		check(path.get_file() + " transition remains finite and continuous, alpha=" + str(alpha) + " rates=" + str(rates), continuous)


func _initialize() -> void:
	comparison_controls()
	for path: String in PATHS:
		var loaded: Dictionary = Data.load_file(path)
		check(path.get_file() + " production admission", loaded.get("ok", false), str(loaded.get("errors", [])))
		if not loaded.get("ok", false):
			continue
		var model: Dictionary = loaded.model
		var prop: Dictionary = model.propulsion
		var live: Dictionary
		if prop.has("glow"):
			live = Mass.evaluate_reference(prop.glow.mass_reference, PackedFloat64Array([0.1 * float(prop.glow.capacity_fuel_kg)]))
		else:
			var fuel: Dictionary = prop.liquid_fuel
			live = Liquid.properties(fuel, {str(fuel.tank_id): 0.1 * float(fuel.capacity_kg)})
		check(path.get_file() + " reduced fuel properties", live.get("ok", false))
		if not live.get("ok", false):
			continue
		var shift: PackedFloat64Array = live.cg_body_m
		check(path.get_file() + " live CG differs from reference", Math3.norm(shift) > 1.0e-7, str(shift))
		var moved: Dictionary = model.duplicate(true)
		moved.cg_le = PackedFloat64Array([model.cg_le[0] - shift[0], model.cg_le[1] + shift[1], model.cg_le[2] - shift[2]])
		for angles: Array in [[0.0, 0.0], [deg_to_rad(3.5), deg_to_rad(0.5)]]:
			var alpha: float = angles[0]
			var beta: float = angles[1]
			var base := state(alpha, beta, [0.0, 0.0, 0.0])
			check(path.get_file() + " attached branch", Aero.local_flow_weight(base, Air.compute(base, zero_wind, RHO), CONTROLS, model) == 0.0)
			var neutral := loads(model, alpha, beta, [0.0, 0.0, 0.0])
			var neutral_live := loads(moved, alpha, beta, [0.0, 0.0, 0.0])
			for rates: Array in RATES:
				var result := delta(loads(model, alpha, beta, rates), neutral)
				var result_live := delta(loads(moved, alpha, beta, rates), neutral_live)
				var label := "%s angles=%s rates=%s" % [path.get_file(), str(angles), str(rates)]
				check(label + " reference CG", near_array(result, expected(model, alpha, beta, rates)), str(result))
				check(label + " live CG", near_array(result_live, expected(moved, alpha, beta, rates)), str(result_live))
				var live_expected := result.duplicate()
				var correction := Math3.cross(shift, result.slice(0, 3))
				for axis in 3:
					live_expected[axis + 3] -= correction[axis]
				check(label + " single live transfer", near_array(result_live, live_expected), str(shift))
		for rates: Array in [RATES[0], RATES[1], RATES[2], RATES[3], RATES[4], RATES[5], RATES[6], RATES[7]]:
			transition_check(model, path, rates)
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
