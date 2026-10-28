## NK-3 glow component qualification: the four actual catalog installations,
## their prepared 2T/4T sources, annular blades and fuel inventories. Research only;
## this does not admit a complete aircraft stage or simulation backend.
extends "oracle.gd"

const GlowSource := preload("res://physics/glow/source.gd")
const GlowBlade := preload("res://physics/glow/propeller.gd")
const Inventory := preload("res://physics/mass_inventory.gd")
const FixedDatumBody := preload("res://physics/fixed_datum_body.gd")

const GLOW_IDS := ["stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "gp-extra-300s-60"]
const SOURCE_FIELDS := ["indicated_torque_nm", "mechanical_torque_nm", "pumping_torque_nm", "valve_torque_nm",
	"shaft_torque_nm", "delivered_fuel_kg_s", "burned_fuel_kg_s", "unburned_fuel_kg_s", "fuel_input_power_w",
	"chemical_power_w", "indicated_power_w", "mechanical_loss_w", "pumping_loss_w", "valve_loss_w",
	"cycle_work_j", "air_charge_kg_cycle", "cycle_frequency_hz", "opportunity_frequency_hz",
	"firing_frequency_hz", "brake_power_w", "unburned_chemical_power_w"]
const BLADE_FIELDS := ["thrust_n", "torque_nm", "shaft_power_w", "thrust_power_w", "dissipation_w"]
const BLADE_MODEL_FIELDS := ["diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades"]
const MASS_MODEL_FIELDS := ["reference_mass_kg", "reference_inertia_kgm2", "references", "capacities", "centers", "tensors"]


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/glow/source.gd", "res://physics/glow/profile.gd",
			"res://physics/glow/installation.gd", "res://physics/glow/two_stroke.gd", "res://physics/glow/four_stroke.gd",
			"res://physics/glow/propeller.gd", "res://physics/glow/fuel_mass.gd", "res://physics/mass_inventory.gd",
			"res://physics/fixed_datum_body.gd", "res://physics/rigid_body.gd", "res://physics/aircraft_data.gd",
			"res://data/aircraft/stik_glow_61fx_2t.json", "res://data/aircraft/stik_glow_55ax_2t.json",
			"res://data/aircraft/stik_glow_fs64v_4t.json", "res://data/aircraft/gp_extra_300s_60.json",
			"res://data/glow/stik_61fx_2t.json", "res://data/glow/stik_55ax_2t.json",
			"res://data/glow/stik_fs64v_4t.json", "res://data/glow/extra_61fx_2t.json",
			"res://data/glow/os_max_61fx_candidate.json", "res://data/glow/os_max_55ax_candidate.json",
			"res://data/glow/os_fs_64v_candidate.json", "res://data/glow/os_max_61fx_installed_candidate.json",
			"res://data/glow/profile_contract.json", "res://data/fuels/openrc-fuel-registry.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-glow-oracle v1"
	if _states < 2:
		_failures.append("glow oracle needs at least two states per installation")
		return
	_report.glow_cases = []
	var multi_source: Dictionary = {}
	for id: String in GLOW_IDS:
		var loaded: Dictionary = AircraftData.load_file(Catalog.data_for(id))
		if not loaded.get("ok", false):
			_failures.append("glow catalog aircraft failed to load: " + id)
			continue
		var propulsion: Dictionary = loaded.model.propulsion
		if not propulsion.has("glow") or not propulsion.glow is Dictionary:
			_failures.append("catalog aircraft lacks glow installation: " + id)
			continue
		_check_case(id, propulsion.glow)
		if multi_source.is_empty():
			multi_source = propulsion.glow
	if not multi_source.is_empty():
		_check_multi_resource(multi_source)
	if _report.glow_cases.size() != GLOW_IDS.size():
		_failures.append("not all glow catalog installations were exercised")


func _snapshot(install: Dictionary) -> Dictionary:
	var profile: Dictionary = install.profile
	var p: Dictionary = profile.parameters
	var two: bool = profile.family == "glow_2t"
	var source := {family = profile.family, max_rpm = profile.operation.max_rpm, displacement_m3 = p.displacement_m3,
		oil_fraction = p.oil_fraction, stoich_air_fuel_ratio = p.stoich_air_fuel_ratio, fuel_lhv_j_kg = p.fuel_lhv_j_kg,
		breathing = p.delivery_ratio if two else p.volumetric_efficiency,
		pumping_pressure = p.scavenge_pressure_pa if two else p.pumping_pressure_pa,
		mechanical_torque_nm = p.mechanical_torque_nm, combustion_efficiency = p.combustion_efficiency,
		indicated_efficiency = p.indicated_efficiency}
	if two:
		source.trapping_efficiency = p.trapping_efficiency
	else:
		source.intake_pressure_drop_pa = p.intake_pressure_drop_pa
		source.valve_torque_nm = p.valve_torque_nm
	var blade := {}
	for field: String in BLADE_MODEL_FIELDS:
		blade[field] = install.propeller[field]
	if install.propeller.has("zero_lift_angle_rad"):
		blade.zero_lift_angle_rad = install.propeller.zero_lift_angle_rad
	var mass := {}
	for field: String in MASS_MODEL_FIELDS:
		mass[field] = install.mass_reference[field]
	return {format = "openrc-nk3-glow-component-v1", source = source, blade = blade, mass = mass}


func _selected_values(point: Dictionary, fields: Array) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	for field: String in fields:
		values.append(float(point[field]))
	return values


func _mass_values(point: Dictionary) -> PackedFloat64Array:
	var values := PackedFloat64Array([point.mass_kg])
	for field: String in ["cg_body_m", "inertia", "inverse", "inertia_origin"]:
		values.append_array(point[field])
	return values


func _compare_status(name: String, expected: bool, actual: bool, inputs: Array) -> void:
	_compare(name, PackedFloat64Array([1.0 if expected else 0.0]),
		PackedFloat64Array([1.0 if actual else 0.0]), inputs)


func _amounts(prepared: Dictionary, index: int) -> PackedFloat64Array:
	var amounts := PackedFloat64Array()
	for capacity: float in prepared.capacities:
		amounts.append(_rng.randf_range(0.0, capacity))
	if index % 19 == 0:
		for k: int in amounts.size():
			amounts[k] = 0.0 if (index / 19) % 2 == 0 else prepared.capacities[k]
	if index % 47 == 0:
		amounts[0] = -1.0
	elif index % 47 == 1:
		amounts[0] = prepared.capacities[0] + 1.0
	elif index % 113 == 0:
		amounts[0] = _special()
	return amounts


func _body() -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for i: int in 13:
		result.append(_rng.randf_range(-3.0, 3.0))
	return result


func _vector(scale: float) -> PackedFloat64Array:
	return PackedFloat64Array([_rng.randf_range(-scale, scale), _rng.randf_range(-scale, scale),
		_rng.randf_range(-scale, scale)])


func _check_case(name: String, install: Dictionary) -> void:
	var source_prep: Dictionary = GlowSource.prepare_evaluator(install.profile)
	var blade_prep: Dictionary = GlowBlade.prepare_evaluator(install.propeller)
	if not source_prep.get("ok", false) or not blade_prep.get("ok", false) or not install.mass_reference.get("ok", false):
		_failures.append("reference preparation failed: " + name)
		return
	var snapshot: Dictionary = _snapshot(install)
	var native_prep: Dictionary = _native.prepare_glow(snapshot)
	if not native_prep.get("ok", false):
		_failures.append("native glow preparation %s failed: %s" % [name, native_prep.get("error", "")])
		return
	var source_accepted := 0
	var source_rejected := 0
	var blade_accepted := 0
	var blade_rejected := 0
	var mass_accepted := 0
	var mass_rejected := 0
	var max_rpm: float = install.profile.operation.max_rpm
	var mixture_table: PackedFloat64Array = install.profile.parameters.combustion_efficiency
	var max_mixture: float = mixture_table[mixture_table.size() - 2]
	for i: int in _states:
		var rpm: float = _rng.randf_range(0.0, max_rpm)
		var admission: float = _rng.randf_range(0.0, 1.0)
		var mixture: float = _rng.randf_range(0.0, max_mixture)
		var density: float = _rng.randf_range(0.7, 1.5)
		var firing: float = _rng.randf_range(0.0, 1.0)
		var running: bool = i % 5 != 0
		if i % 17 == 0:
			rpm = [0.0, max_rpm, max_rpm / 2.0][(i / 17) % 3]
		if i % 19 == 0:
			admission = [0.0, 0.5, 1.0][(i / 19) % 3]
		if i % 23 == 0:
			mixture = [0.0, max_mixture][(i / 23) % 2]
		if i % 53 == 0:
			rpm = -1.0
		elif i % 53 == 1:
			density = 0.0
		elif i % 53 == 2:
			firing = 1.5
		elif i % 71 == 0:
			match (i / 71) % 5:
				0: rpm = _special()
				1: admission = _special()
				2: mixture = _special()
				3: density = _special()
				4: firing = _special()
		var reference: Dictionary = GlowSource.evaluate_prepared(source_prep.evaluator, rpm, admission, mixture, density, running, firing)
		var unit: Dictionary = GlowSource.unit_fuel_flow_prepared(source_prep.evaluator, rpm, admission, mixture, density)
		var native: Dictionary = _native.glow_source_component(rpm, admission, mixture, density, running, firing)
		var inputs := [name, i, rpm, admission, mixture, density, running, firing]
		var ref_ok: bool = reference.get("ok", false)
		var native_ok: bool = native.get("ok", false)
		_compare_status("glow_source_validity", ref_ok, native_ok, inputs)
		if ref_ok and native_ok:
			_compare("glow_source_values", _selected_values(reference, SOURCE_FIELDS), native.values, inputs)
			source_accepted += 1
		else:
			source_rejected += 1
		var unit_ok: bool = unit.get("ok", false)
		var native_unit_ok: bool = native.get("unit_ok", false)
		_compare_status("glow_unit_validity", unit_ok, native_unit_ok, inputs)
		if unit_ok and native_unit_ok:
			_compare("glow_unit_flow", PackedFloat64Array([unit.unit_fuel_flow_kg_s_per_mixture]),
				PackedFloat64Array([native.unit_flow]), inputs)
		var blade_rpm: float = _rng.randf_range(0.0, max_rpm)
		var axial: float = _rng.randf_range(-35.0, 45.0)
		var blade_rho: float = _rng.randf_range(0.7, 1.5)
		if i % 17 == 0: blade_rpm = 0.0
		if i % 19 == 0: axial = 0.0
		if i % 53 == 0: blade_rho = -1.0
		elif i % 71 == 0:
			match (i / 71) % 3:
				0: blade_rpm = _special()
				1: axial = _special()
				2: blade_rho = _special()
		var blade_ref: Dictionary = GlowBlade.evaluate_prepared(blade_prep.evaluator, blade_rpm, axial, blade_rho)
		var blade_native: Dictionary = _native.glow_blade_component(blade_rpm, axial, blade_rho)
		var blade_inputs := [name, i, blade_rpm, axial, blade_rho]
		var blade_ref_ok: bool = blade_ref.get("ok", false)
		var blade_native_ok: bool = blade_native.get("ok", false)
		_compare_status("glow_blade_validity", blade_ref_ok, blade_native_ok, blade_inputs)
		if blade_ref_ok and blade_native_ok:
			_compare("glow_blade_values", _selected_values(blade_ref, BLADE_FIELDS), blade_native.values, blade_inputs)
			blade_accepted += 1
		else:
			blade_rejected += 1
		var amounts: PackedFloat64Array = _amounts(install.mass_reference, i)
		var mass_ref: Dictionary = Inventory.evaluate_reference(install.mass_reference, amounts)
		var mass_native: Dictionary = _native.glow_mass_component(amounts)
		var mass_inputs := [name, i, amounts]
		var mass_ref_ok: bool = mass_ref.get("ok", false)
		var mass_native_ok: bool = mass_native.get("ok", false)
		_compare_status("glow_mass_validity", mass_ref_ok, mass_native_ok, mass_inputs)
		if mass_ref_ok and mass_native_ok:
			_compare("glow_mass_values", _mass_values(mass_ref), mass_native.values, mass_inputs)
			mass_accepted += 1
			var body: PackedFloat64Array = _body()
			var force: PackedFloat64Array = _vector(40.0)
			var moment: PackedFloat64Array = _vector(10.0)
			var rotor: PackedFloat64Array = _vector(1.0)
			var gravity: float = _rng.randf_range(8.0, 12.0)
			var body_ref: PackedFloat64Array = FixedDatumBody.derivative(body, mass_ref, force, moment, gravity, rotor)
			var body_native: Dictionary = _native.glow_body_component(body, amounts, force, moment, gravity, rotor)
			if not body_native.get("ok", false):
				_failures.append("valid glow body sample refused: %s state %d" % [name, i])
			else:
				_compare("glow_body_derivative", body_ref, body_native.values, [name, i, body, amounts, force, moment, gravity, rotor])
		else:
			mass_rejected += 1
		_tally("glow_" + name, "states")
	if source_accepted == 0 or source_rejected == 0 or blade_accepted == 0 or blade_rejected == 0 or mass_accepted == 0 or mass_rejected == 0:
		_failures.append("glow case %s did not exercise accepted and rejected states in all components" % name)
	_report.glow_cases.append({name = name, family = install.profile.family, resources = install.mass_reference.references.size(),
		states = _states, source_accepted = source_accepted, source_rejected = source_rejected,
		blade_accepted = blade_accepted, blade_rejected = blade_rejected, mass_accepted = mass_accepted, mass_rejected = mass_rejected})
	_check_glow_refusals(name, snapshot)


func _check_glow_refusals(name: String, snapshot: Dictionary) -> void:
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.blade.diameter_m = 0.0
	if _native.prepare_glow(malformed).get("ok", false):
		_failures.append("glow invalid blade was admitted: " + name)
	if _native.glow_blade_component(0.0, 0.0, 1.2).get("ok", false):
		_failures.append("glow failed prepare retained a stale model: " + name)
	malformed = snapshot.duplicate(true)
	malformed.source.unknown = 1.0
	if _native.prepare_glow(malformed).get("ok", false):
		_failures.append("glow unknown source field was admitted: " + name)
	malformed = snapshot.duplicate(true)
	malformed.source.combustion_efficiency = PackedFloat64Array([0.0, 0.1, 0.0, 0.2])
	if _native.prepare_glow(malformed).get("ok", false):
		_failures.append("glow unordered source table was admitted: " + name)
	malformed = snapshot.duplicate(true)
	malformed.mass.reference_inertia_kgm2 = PackedFloat64Array([1.0])
	if _native.prepare_glow(malformed).get("ok", false):
		_failures.append("glow malformed mass inertia was admitted: " + name)


## The installed aircraft currently expose one fuel resource. Build a validated
## second line/tank resource from an actual installation to cover ordering and
## summation in the same prepared MassInventory path used by future aircraft.
func _check_multi_resource(install: Dictionary) -> void:
	var existing: Dictionary = install.mass_reference
	var resources: Array = existing.resources.duplicate(true)
	resources.append({id = "native_oracle_second_resource", reference_mass_kg = 0.01, capacity_mass_kg = 0.04,
		center_body_m = PackedFloat64Array([0.12, -0.04, 0.08]), size_body_m = PackedFloat64Array([0.06, 0.04, 0.02])})
	var prepared: Dictionary = Inventory.prepare_reference(existing.reference_mass_kg, existing.reference_inertia_kgm2, resources)
	if not prepared.get("ok", false):
		_failures.append("cannot prepare two-resource glow mass fixture")
		return
	var snapshot: Dictionary = _snapshot(install)
	for field: String in MASS_MODEL_FIELDS:
		snapshot.mass[field] = prepared[field]
	var native_prep: Dictionary = _native.prepare_glow(snapshot)
	if not native_prep.get("ok", false):
		_failures.append("cannot prepare two-resource native glow mass fixture: " + str(native_prep.get("error", "")))
		return
	var accepted := 0
	var rejected := 0
	for i: int in _states:
		var amounts: PackedFloat64Array = _amounts(prepared, i)
		if i % 59 == 1:
			amounts[1] = prepared.capacities[1] + 1.0
		elif i % 113 == 1:
			amounts[1] = _special()
		var expected: Dictionary = Inventory.evaluate_reference(prepared, amounts)
		var actual: Dictionary = _native.glow_mass_component(amounts)
		var expected_ok: bool = expected.get("ok", false)
		var actual_ok: bool = actual.get("ok", false)
		var inputs := ["two_resource", i, amounts]
		_compare_status("glow_multi_mass_validity", expected_ok, actual_ok, inputs)
		if expected_ok and actual_ok:
			_compare("glow_multi_mass_values", _mass_values(expected), actual.values, inputs)
			var body: PackedFloat64Array = _body()
			var force: PackedFloat64Array = _vector(40.0)
			var moment: PackedFloat64Array = _vector(10.0)
			var rotor: PackedFloat64Array = _vector(1.0)
			var gravity: float = _rng.randf_range(8.0, 12.0)
			var derivative: PackedFloat64Array = FixedDatumBody.derivative(body, expected, force, moment, gravity, rotor)
			var native_body: Dictionary = _native.glow_body_component(body, amounts, force, moment, gravity, rotor)
			if not native_body.get("ok", false):
				_failures.append("valid two-resource glow body refused at state %d" % i)
			else:
				_compare("glow_multi_body_derivative", derivative, native_body.values,
					["two_resource", i, body, amounts, force, moment, gravity, rotor])
			accepted += 1
		else:
			rejected += 1
		_tally("glow_two_resource", "states")
	if accepted == 0 or rejected == 0:
		_failures.append("two-resource glow mass did not exercise accepted and rejected states")
	if _native.glow_mass_component(PackedFloat64Array([0.0])).get("ok", false):
		_failures.append("two-resource glow mass accepted a truncated state")
	if _native.glow_body_component(PackedFloat64Array(), prepared.references, PackedFloat64Array([0.0, 0.0, 0.0]),
			PackedFloat64Array([0.0, 0.0, 0.0]), 9.80665, PackedFloat64Array([0.0, 0.0, 0.0])).get("ok", false):
		_failures.append("glow body accepted a truncated state")
	_report.glow_multi_mass = {resources = resources.size(), states = _states, accepted = accepted, rejected = rejected}
