# FUEL-04: the shared fixed-datum resource kernel (MassInventory.prepare_reference/evaluate_reference) and the
# shared open-system derivative (FixedDatumBody). Bit identity with the historical glow FuelMass on the installed
# glow Stiks; agreement with the dry-up MassInventory form for two resources, including fills above the authored
# amount; refusals; and momentum conservation of the body plus its ejected fuel under RK4.
# Run: godot --headless --path app --script res://tests/test_fuel_mass_reference.gd
extends SceneTree

const MassInventory := preload("res://physics/mass_inventory.gd")
const FixedDatumBody := preload("res://physics/fixed_datum_body.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
const AD := preload("res://physics/aircraft_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const GLOW := ["res://data/aircraft/stik_glow_55ax_2t.json", "res://data/aircraft/stik_glow_61fx_2t.json",
	"res://data/aircraft/stik_glow_fs64v_4t.json"]

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_bit_identity()
	_two_resources()
	_refusals()
	_reference_inverse_limits()
	_momentum()
	print("FUEL-04 fixed-datum resources: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


## Verbatim body of app/physics/glow/fuel_mass.gd evaluate() at commit 97136354, before FUEL-04: the oracle.
func _legacy(wet_mass: float, wet_inertia: PackedFloat64Array, initial_fuel: float,
		remaining: float, tank_position: PackedFloat64Array, tank_size: PackedFloat64Array) -> Dictionary:
	if wet_inertia.size() != 6 or tank_position.size() != 3 or tank_size.size() != 3:
		return {ok = false}
	for value in [wet_mass, initial_fuel, remaining]:
		if not is_finite(value): return {ok = false}
	if initial_fuel < 0.0 or remaining < 0.0 or remaining > initial_fuel or wet_mass <= initial_fuel:
		return {ok = false}
	for value in wet_inertia + tank_position + tank_size:
		if not is_finite(value): return {ok = false}
	for value in tank_size:
		if value < 0.0: return {ok = false}
	var removed: float = initial_fuel - remaining
	var mass: float = wet_mass - removed
	var cg: PackedFloat64Array = M.scale(tank_position, -removed / mass)
	var inertia_origin: PackedFloat64Array = wet_inertia.duplicate()
	var tank_tensor: PackedFloat64Array = MassInventory.rectangular_box_per_kg(tank_position, tank_size)
	var parallel: PackedFloat64Array = MassInventory.rectangular_box_per_kg(cg, PackedFloat64Array([0.,0.,0.]))
	var inertia: PackedFloat64Array = wet_inertia.duplicate()
	for i in 6:
		inertia_origin[i] -= removed * tank_tensor[i]
		inertia[i] = inertia_origin[i] - mass * parallel[i]
	var inverse: PackedFloat64Array = RB.inertia_inverse(inertia)
	if inertia[0] <= 0.0 or inertia[0]*inertia[1]-inertia[3]*inertia[3] <= 0.0:
		return {ok = false}
	var determinant: float = inertia[0]*(inertia[1]*inertia[2]-inertia[5]*inertia[5])-inertia[3]*(inertia[3]*inertia[2]-inertia[4]*inertia[5])+inertia[4]*(inertia[3]*inertia[5]-inertia[4]*inertia[1])
	if determinant <= 0.0: return {ok = false}
	for v in inverse:
		if not is_finite(v): return {ok = false}
	return {ok = true, mass_kg = mass, cg_body_m = cg, inertia = inertia, inverse = inverse, inertia_origin = inertia_origin}


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.ok and b.ok and a.mass_kg == b.mass_kg and a.cg_body_m == b.cg_body_m and a.inertia == b.inertia \
		and a.inverse == b.inverse and a.inertia_origin == b.inertia_origin


func _bit_identity() -> void:
	for path: String in GLOW:
		var loaded: Dictionary = AD.load_file(path)
		if not loaded.get("ok", false):
			_check("%s loads" % path.get_file(), false, str(loaded.get("errors", "")))
			continue
		var model: Dictionary = loaded.model
		var install: Dictionary = model.propulsion.glow
		var reference: Dictionary = install.get("mass_reference", {})
		_check("%s installation prepares the shared reference (%s)" % [path.get_file(), MassInventory.REFERENCE_LAW],
			reference.get("ok", false) and reference.law == MassInventory.REFERENCE_LAW
			and reference.reference_mass_kg == model.mass_kg and reference.reference_inertia_kgm2 == model.inertia)
		var f0: float = install.initial_fuel_kg
		var mismatches := 0
		for fuel: float in [f0, 0.75 * f0, 0.5 * f0, 0.25 * f0, 1.0e-30, 0.0]:
			var old: Dictionary = _legacy(model.mass_kg, model.inertia, f0, fuel, install.tank_position, install.tank_size)
			var cached: Dictionary = MassInventory.evaluate_reference(reference, PackedFloat64Array([fuel]))
			var wrapped: Dictionary = FuelMass.evaluate(model.mass_kg, model.inertia, f0, fuel, install.tank_position, install.tank_size)
			if not (_same(old, cached) and _same(old, wrapped)):
				mismatches += 1
		_check("%s new kernel equals the historical FuelMass bit for bit at six fuel levels" % path.get_file(), mismatches == 0,
			"%d mismatches" % mismatches)
		_check("%s excess fuel stays refused while capacity equals the authored load" % path.get_file(),
			not MassInventory.evaluate_reference(reference, PackedFloat64Array([f0 * (1.0 + 1.0e-12)])).ok
			and not MassInventory.evaluate_reference(reference, PackedFloat64Array([-1.0e-12])).ok)


func _two_resources() -> void:
	# Dry body plus a main tank and a smoke tank, in the dry-up form about an arbitrary datum D.
	var dry := [
		{id = "airframe", mass_kg = 9.0, center_body_m = PackedFloat64Array([-0.05, 0.0, 0.02]),
			inertia_centroid_kgm2 = PackedFloat64Array([1.1, 2.3, 3.1, 0.02, -0.04, 0.01])},
		{id = "turbine", mass_kg = 1.2, center_body_m = PackedFloat64Array([-0.6, 0.0, -0.03]),
			inertia_centroid_kgm2 = PackedFloat64Array([0.004, 0.02, 0.02, 0.0, 0.0, 0.0])},
	]
	var main_size := PackedFloat64Array([0.25, 0.14, 0.10])
	var smoke_size := PackedFloat64Array([0.12, 0.10, 0.08])
	var main_center := PackedFloat64Array([0.19, 0.0, 0.03])
	var smoke_center := PackedFloat64Array([0.05, 0.0, 0.05])
	var main_capacity: float = 2.6
	var smoke_capacity: float = 1.1
	var resources := [
		{id = "main", capacity_mass_kg = main_capacity, center_body_m = main_center,
			inertia_centroid_at_capacity_kgm2 = _box(main_size, main_capacity), distribution_model = MassInventory.RESOURCE_DISTRIBUTION},
		{id = "smoke", capacity_mass_kg = smoke_capacity, center_body_m = smoke_center,
			inertia_centroid_at_capacity_kgm2 = _box(smoke_size, smoke_capacity), distribution_model = MassInventory.RESOURCE_DISTRIBUTION},
	]
	var dry_up: Dictionary = MassInventory.prepare("D", dry, resources)
	# The authored state: half main tank, empty smoke tank. Its CG is the fixed datum O.
	var ref_amounts := {"main": 1.3, "smoke": 0.0}
	var authored: Dictionary = MassInventory.evaluate(dry_up, ref_amounts)
	_check("dry-up inventory evaluates the authored state", dry_up.ok and authored.ok,
		str(dry_up.get("error", "")) + " " + str(authored.get("error", "")))
	if not authored.ok:
		return
	var o: PackedFloat64Array = authored.cg_body_m
	var prepared: Dictionary = MassInventory.prepare_reference(authored.mass_kg, authored.inertia_cg_kgm2, [
		{id = "main", reference_mass_kg = 1.3, capacity_mass_kg = main_capacity, center_body_m = M.sub(main_center, o), size_body_m = main_size},
		{id = "smoke", reference_mass_kg = 0.0, capacity_mass_kg = smoke_capacity, center_body_m = M.sub(smoke_center, o), size_body_m = smoke_size},
	])
	_check("reference form prepares two resources", prepared.get("ok", false), str(prepared.get("error", "")))
	if not prepared.get("ok", false):
		return
	var worst := 0.0
	for pair: Array in [[1.3, 0.0], [0.0, 0.0], [2.6, 0.0], [2.6, 1.1], [0.4, 0.7], [1.0e-9, 1.1]]:
		var ref: Dictionary = MassInventory.evaluate_reference(prepared, PackedFloat64Array(pair))
		var up: Dictionary = MassInventory.evaluate(dry_up, {"main": pair[0], "smoke": pair[1]})
		if not ref.ok or not up.ok:
			worst = INF
			break
		worst = maxf(worst, absf(ref.mass_kg - up.mass_kg))
		worst = maxf(worst, M.norm(M.sub(M.add(ref.cg_body_m, o), up.cg_body_m)))
		for k: int in 6:
			worst = maxf(worst, absf(ref.inertia[k] - up.inertia_cg_kgm2[k]) / 3.1)
	_check("reference form agrees with the dry-up form for two resources (≤ 1e-12)", worst <= 1.0e-12, "worst %s" % str(worst))
	var full: Dictionary = MassInventory.evaluate_reference(prepared, PackedFloat64Array([main_capacity, 0.0]))
	_check("a fill above the authored amount adds mass and moves the CG toward that tank",
		full.ok and absf(full.mass_kg - (authored.mass_kg + 1.3)) <= 1e-12 and M.dot(full.cg_body_m, M.sub(main_center, o)) > 0.0)
	_check("amounts above capacity, negative or not finite are refused",
		not MassInventory.evaluate_reference(prepared, PackedFloat64Array([main_capacity + 1.0e-9, 0.0])).ok
		and not MassInventory.evaluate_reference(prepared, PackedFloat64Array([0.5, -1.0e-9])).ok
		and not MassInventory.evaluate_reference(prepared, PackedFloat64Array([NAN, 0.0])).ok
		and not MassInventory.evaluate_reference(prepared, PackedFloat64Array([0.5])).ok)


func _refusals() -> void:
	var inertia := PackedFloat64Array([0.1, 0.3, 0.4, 0.0, 0.0, 0.0])
	var tank := {id = "t", reference_mass_kg = 0.1, capacity_mass_kg = 0.2, center_body_m = PackedFloat64Array([0.2, 0.0, 0.0]),
		size_body_m = PackedFloat64Array([0.1, 0.05, 0.05])}
	_check("valid single tank prepares", MassInventory.prepare_reference(2.5, inertia, [tank]).ok)
	var cases := {
		"resources heavier than the aircraft": [0.1, inertia, [tank]],
		"no resources": [2.5, inertia, []],
		"five inertia entries": [2.5, inertia.slice(0, 5), [tank]],
		"duplicate ids": [2.5, inertia, [tank, tank]],
		"reference above capacity": [2.5, inertia, [_with(tank, "capacity_mass_kg", 0.05)]],
		"negative size": [2.5, inertia, [_with(tank, "size_body_m", PackedFloat64Array([0.1, -0.05, 0.05]))]],
		"non-finite center": [2.5, inertia, [_with(tank, "center_body_m", PackedFloat64Array([NAN, 0.0, 0.0]))]],
		"empty id": [2.5, inertia, [_with(tank, "id", " ")]],
	}
	for label: String in cases:
		var args: Array = cases[label]
		_check("prepare refuses %s" % label, not MassInventory.prepare_reference(args[0], args[1], args[2]).get("ok", true))


## FUEL-00 fixture in the runtime kernels: zero wrench and gravity, non-principal spin, steady co-moving burn.
## Body momentum m·R(v_O + ω×c) plus the integrated ejecta momentum must stay constant.
func _momentum() -> void:
	var loaded: Dictionary = AD.load_file(GLOW[1])
	if not loaded.get("ok", false):
		_check("momentum fixture aircraft loads", false)
		return
	var install: Dictionary = loaded.model.propulsion.glow
	var reference: Dictionary = install.mass_reference
	var f0: float = install.initial_fuel_kg
	var rate: float = f0 / 40.0
	var tank: PackedFloat64Array = install.tank_position
	# RK4 refinement separates integration error (4th order) from a law error (independent of the step).
	var corrected: float = _momentum_error(reference, tank, rate, f0, true, 240)
	var corrected_fine: float = _momentum_error(reference, tank, rate, f0, true, 480)
	var uncorrected: float = _momentum_error(reference, tank, rate, f0, false, 240)
	var uncorrected_fine: float = _momentum_error(reference, tank, rate, f0, false, 480)
	_check("body plus ejected fuel conserves momentum through a 30 s burn (|ΔP| %s kg·m/s of ~14 at 240 Hz)" % str(corrected),
		corrected < 1.0e-5)
	_check("the residual is RK4 integration error: halving dt divides it by %s (> 8)" % str(corrected / corrected_fine),
		corrected / corrected_fine > 8.0)
	_check("without the datum correction the error is a law error: %s, unchanged by halving dt (%s)" % [str(uncorrected), str(uncorrected_fine)],
		uncorrected > 1.0e3 * corrected and absf(uncorrected / uncorrected_fine - 1.0) < 0.05)


func _momentum_error(reference: Dictionary, tank: PackedFloat64Array, rate: float, f0: float, correct: bool, hz: int) -> float:
	# State: 13 rigid-body values, fuel, 3 ejected-momentum components (world frame).
	var s: PackedFloat64Array = RB.make_state(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([5.0, 0.0, 0.0]),
		M.q_normalized(PackedFloat64Array([0.9, 0.1, -0.2, 0.3])), PackedFloat64Array([2.0, 3.0, 1.0]))
	s.append(f0)
	s.append_array(PackedFloat64Array([0.0, 0.0, 0.0]))
	var p0: PackedFloat64Array = _total_momentum(s, reference)
	var dt: float = 1.0 / float(hz)
	for _step: int in 30 * hz:
		var k1: PackedFloat64Array = _rate(s, reference, tank, rate, correct)
		var k2: PackedFloat64Array = _rate(_axpy(s, k1, 0.5 * dt), reference, tank, rate, correct)
		var k3: PackedFloat64Array = _rate(_axpy(s, k2, 0.5 * dt), reference, tank, rate, correct)
		var k4: PackedFloat64Array = _rate(_axpy(s, k3, dt), reference, tank, rate, correct)
		for i: int in s.size():
			s[i] += dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
		var q: PackedFloat64Array = M.q_normalized(s.slice(RB.ATT, RB.ATT + 4))
		for i: int in 4:
			s[RB.ATT + i] = q[i]
	return M.norm(M.sub(_total_momentum(s, reference), p0))


func _rate(s: PackedFloat64Array, reference: Dictionary, tank: PackedFloat64Array, rate: float, correct: bool) -> PackedFloat64Array:
	var properties: Dictionary = MassInventory.evaluate_reference(reference, PackedFloat64Array([maxf(0.0, s[RB.SIZE])]))
	var body: PackedFloat64Array = s.slice(0, RB.SIZE)
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	var out: PackedFloat64Array = FixedDatumBody.derivative(body, properties, zero, zero, 0.0, PackedFloat64Array()) if correct \
		else RB.derivative(body, properties.mass_kg, properties.inertia, properties.inverse, zero, zero, 0.0, PackedFloat64Array())
	out.append(-rate)
	var q: PackedFloat64Array = body.slice(RB.ATT, RB.ATT + 4)
	var leaving: PackedFloat64Array = M.add(body.slice(RB.VEL, RB.VEL + 3), M.cross(body.slice(RB.RATE, RB.RATE + 3), tank))
	out.append_array(M.scale(M.q_rotate(q, leaving), rate))
	return out


func _total_momentum(s: PackedFloat64Array, reference: Dictionary) -> PackedFloat64Array:
	var properties: Dictionary = MassInventory.evaluate_reference(reference, PackedFloat64Array([maxf(0.0, s[RB.SIZE])]))
	var v_cm: PackedFloat64Array = M.add(s.slice(RB.VEL, RB.VEL + 3), M.cross(s.slice(RB.RATE, RB.RATE + 3), properties.cg_body_m))
	var body: PackedFloat64Array = M.scale(M.q_rotate(s.slice(RB.ATT, RB.ATT + 4), v_cm), properties.mass_kg)
	return M.add(body, s.slice(RB.SIZE + 1, RB.SIZE + 4))


func _axpy(s: PackedFloat64Array, k: PackedFloat64Array, h: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = s.duplicate()
	for i: int in out.size():
		out[i] += h * k[i]
	return out


func _box(size: PackedFloat64Array, mass: float) -> PackedFloat64Array:
	return PackedFloat64Array([mass * (size[1] * size[1] + size[2] * size[2]) / 12.0,
		mass * (size[0] * size[0] + size[2] * size[2]) / 12.0, mass * (size[0] * size[0] + size[1] * size[1]) / 12.0, 0.0, 0.0, 0.0])


func _with(base: Dictionary, key: String, value: Variant) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	out[key] = value
	return out


func _reference_inverse_limits() -> void:
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	var resource := {id = "point", reference_mass_kg = 0.0, capacity_mass_kg = 0.0,
		center_body_m = zero, size_body_m = zero}
	# A well-conditioned physical tensor with nonzero products of inertia.
	# J * (J^-1 * e_i) = e_i supplies an independent oracle on every axis.
	for magnitude: float in [1.0, 1.0e150, 1.0e-150, 1.0e200, 1.0e-200, 1.0e-105]:
		var tensor := PackedFloat64Array([1.0, 1.25, 1.5, 0.1, -0.05, 0.075])
		for i in 6:
			tensor[i] *= magnitude
		var prepared: Dictionary = MassInventory.prepare_reference(1.0, tensor, [resource])
		var result: Dictionary = MassInventory.evaluate_reference(prepared, PackedFloat64Array([0.0]))
		_check("reference inverse accepts finite physical scale %s" % String.num_scientific(magnitude), result.ok)
		if not result.ok:
			continue
		_check("accepted reference inverse has six entries", result.inverse.size() == 6)
		if result.inverse.size() != 6:
			continue
		var worst := 0.0
		for axis in 3:
			var basis := zero.duplicate()
			basis[axis] = 1.0
			var product: PackedFloat64Array = RB.inertia_mul(tensor, RB.inertia_mul(result.inverse, basis))
			for i in 3:
				worst = maxf(worst, absf(product[i] - basis[i])) if is_finite(product[i]) else INF
		_check("reference inverse identity residual <= 1e-12 at scale %s" % String.num_scientific(magnitude), worst <= 1.0e-12)
	var subnormal: float = pow(2.0, -1030.0)
	_check("unrepresentable-inverse fixture has nonzero subnormal inertia", subnormal > 0.0 and not is_finite(1.0 / subnormal))
	for tensor: PackedFloat64Array in [
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 1.0, 0.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 1.0, -1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([subnormal, subnormal, subnormal, 0.0, 0.0, 0.0])]:
		var prepared: Dictionary = MassInventory.prepare_reference(1.0, tensor, [resource])
		var result: Dictionary = MassInventory.evaluate_reference(prepared, PackedFloat64Array([0.0]))
		_check("reference inverse refuses singular, indefinite or unrepresentable inverse", not result.ok)
