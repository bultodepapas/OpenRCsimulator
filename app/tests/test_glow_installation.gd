extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Installation := preload("res://physics/glow/installation.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
const Profile := preload("res://physics/glow/profile.gd")

var _checks: int = 0
var _failures: int = 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _initialize() -> void:
	_check("malformed direct attachment is refused without an exception", not Installation.attach({}, {}).get("ok", false))
	for entry: Dictionary in [
		{"label": "Extra 61FX", "aircraft": "res://data/aircraft/gp_extra_300s_60.json"},
		{"label": "2T", "aircraft": "res://data/aircraft/stik_glow_55ax_2t.json"},
		{"label": "4T", "aircraft": "res://data/aircraft/stik_glow_fs64v_4t.json"},
		{"label": "2T APC variant", "aircraft": "res://data/aircraft/stik_glow_55ax_2t_apc_13x6.json"},
		{"label": "4T APC variant", "aircraft": "res://data/aircraft/stik_glow_fs64v_4t_apc_13x6.json"},
	]:
		_test_installation(str(entry.label), str(entry.aircraft))
	_test_path_gate()
	_test_capacity_roundoff()
	print("glow installation contract: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_capacity_roundoff() -> void:
	var reference: float = 0.5
	var one_ulp_below: float = reference - 1.1102230246251565e-16
	var wet_inertia := PackedFloat64Array([1.0, 1.2, 1.5, 0.0, 0.0, 0.0])
	var center := PackedFloat64Array([0.1, 0.0, 0.0])
	var size := PackedFloat64Array([0.1, 0.2, 0.3])
	var prepared: Dictionary = FuelMass.prepare(2.0, wet_inertia, reference,
		center, size, one_ulp_below, "roundoff_tank")
	var capacities: PackedFloat64Array = prepared.get("capacities", PackedFloat64Array())
	_check("Glow mass reference canonicalizes a one-ULP full-tank capacity roundoff",
		prepared.get("ok", false) and capacities.size() == 1 and capacities[0] == reference,
		str(prepared.get("error", "")))
	var real_overage: Dictionary = FuelMass.prepare(2.0, wet_inertia, reference,
		center, size, reference - 1.0e-12, "overfull_tank")
	_check("Glow mass reference still refuses a material full-tank capacity overage",
		not real_overage.get("ok", false), str(real_overage.get("error", "")))
	var resources: Array = [
		{id = "roundoff_tank", reference_mass_kg = reference, capacity_mass_kg = one_ulp_below,
			center_body_m = center, size_body_m = size},
		{id = "line_store", reference_mass_kg = 0.1, capacity_mass_kg = 0.2,
			center_body_m = PackedFloat64Array([-0.1, 0.0, 0.0]), size_body_m = size},
	]
	var multi_prepared: Dictionary = FuelMass.prepare_resources(2.0, wet_inertia, resources)
	_check("Glow multi-store reference canonicalizes the same one-ULP capacity roundoff",
		multi_prepared.get("ok", false) and resources[0].capacity_mass_kg == one_ulp_below,
		str(multi_prepared.get("error", "")))
	var bad_resources: Array = resources.duplicate(true)
	bad_resources[0].capacity_mass_kg = reference - 1.0e-12
	var bad_multi: Dictionary = FuelMass.prepare_resources(2.0, wet_inertia, bad_resources)
	_check("Glow multi-store reference refuses a material full-tank capacity overage",
		not bad_multi.get("ok", false), str(bad_multi.get("error", "")))


func _test_installation(label: String, aircraft_path: String) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(aircraft_path))
	_check(label + " generated aircraft JSON parses", raw is Dictionary)
	if not raw is Dictionary:
		return
	var legacy: Dictionary = AircraftData._validate_legacy(AircraftData.legacy_v1_input(raw))
	if legacy.get("ok", false):
		var fuel_errors := PackedStringArray()
		legacy.model.fuel_system = AircraftData._fuel_system(fuel_errors, raw)
		if not fuel_errors.is_empty():
			legacy.ok = false
			legacy.errors = fuel_errors
	_check(label + " aircraft mass, propulsion and normalized fuel system derive", legacy.get("ok", false), str(legacy.get("errors", [])))
	if not legacy.get("ok", false):
		return
	var source_path: String = str(raw.propulsion.engine.glow_installation)
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	_check(label + " generated installation JSON parses", value is Dictionary)
	if not value is Dictionary:
		return
	_check(label + " generated install includes explicit starter prime quantity", value.settings.has("starter_prime_kg"))
	var attached: Dictionary = Installation.attach(raw, legacy.model)
	_check(label + " generated installation attaches before flight", attached.get("ok", false), str(attached.get("errors", [])))
	if not attached.get("ok", false):
		return
	_check(label + " installed profile family matches its 2T/4T data", attached.model.propulsion.glow.profile.family == value.family)
	_check(label + " installed identity hashes exact source bytes",
		attached.model.propulsion.glow.identity.sha256 == FileAccess.get_sha256(source_path))
	var runtime_axis: Variant = attached.model.propulsion.get("axis", null)
	var axis_norm_squared := 0.0
	if runtime_axis is PackedFloat64Array:
		for component: float in runtime_axis:
			axis_norm_squared += component * component
	_check(label + " installed propeller has a unit runtime axis",
		runtime_axis is PackedFloat64Array and runtime_axis.size() == 3 and absf(axis_norm_squared - 1.0) < 1.0e-9)
	var install: Dictionary = attached.model.propulsion.glow
	_check(label + " keeps authored reference fuel separate from tank capacity",
		install.initial_fuel_kg == install.reference_fuel_kg
		and install.reference_fuel_kg == install.fuel_tank.liquid_mass_kg
		and install.capacity_fuel_kg == install.fuel_tank.capacity_kg
		and install.unusable_fuel_kg == install.fuel_tank.unusable_kg)
	_check(label + " preserves an explicit or estimated reserve at/above unusable fuel",
		install.reserve_fuel_kg >= install.unusable_fuel_kg
		and install.reserve_fuel_kg == install.fuel_tank.reserve_kg)
	var full_mass: Dictionary = FuelMass.evaluate(float(legacy.model.mass_kg), legacy.model.inertia,
		install.reference_fuel_kg, install.capacity_fuel_kg, install.tank_position, install.tank_size,
		install.capacity_fuel_kg, str(install.fuel_tank.id))
	_check(label + " capacity fill adds only mass above the authored reference amount",
		full_mass.get("ok", false)
		and absf(float(full_mass.mass_kg) - (float(legacy.model.mass_kg) - install.reference_fuel_kg + install.capacity_fuel_kg)) < 1.0e-9)
	var over_capacity: Dictionary = FuelMass.evaluate(float(legacy.model.mass_kg), legacy.model.inertia,
		install.reference_fuel_kg, install.capacity_fuel_kg + 1.0e-6, install.tank_position, install.tank_size,
		install.capacity_fuel_kg, str(install.fuel_tank.id))
	_check(label + " live mass sample refuses fuel above the normalized tank capacity", not over_capacity.get("ok", false))
	_check(label + " attachment does not mutate its input model", not legacy.model.propulsion.has("glow"))
	var aircraft_load: Dictionary = AircraftData.load_file(aircraft_path)
	_check(label + " full aircraft loader completes glow validation before flight",
		aircraft_load.get("ok", false) and aircraft_load.model.propulsion.glow.profile.family == value.family,
		str(aircraft_load.get("errors", [])))
	var no_angle_raw: Dictionary = raw.duplicate(true)
	no_angle_raw.propulsion.propeller.erase("thrust_angles")
	var default_axis_load: Dictionary = AircraftData.validate_and_derive(no_angle_raw)
	_check(label + " omitted thrust angles resolve to the documented +x runtime rotor axis",
		default_axis_load.get("ok", false)
		and default_axis_load.model.propulsion.axis == PackedFloat64Array([1.0, 0.0, 0.0]),
		str(default_axis_load.get("errors", [])))

	var install_bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
	var detached: Dictionary = legacy.model.duplicate(true)
	var valid: Dictionary = Installation.prepare_value(value, raw, detached, install_bytes)
	_check(label + " pure validator accepts generated candidate value", valid.get("ok", false), str(valid.get("errors", [])))
	if not valid.get("ok", false):
		return
	_check(label + " pure validator returns a detached normalized install",
		valid.model != detached and valid.model.propulsion.glow.settings.thermal is Dictionary)
	_test_bad_install_values(label, value, raw, legacy.model)
	_test_inventory_and_axis(label, value, raw, legacy.model)
	_test_unsupported_modules(label, value, raw, legacy.model)


func _test_bad_install_values(label: String, baseline: Dictionary, raw: Dictionary, model: Dictionary) -> void:
	var cases: Array[Dictionary] = []
	var value := baseline.duplicate(true)
	value.extra = 1
	cases.append({"label": "unknown root field", "value": value})
	value = baseline.duplicate(true)
	value.settings.unknown_transport = {"value": 1.0, "unit": "1", "kind": "estimated", "source": "test"}
	cases.append({"label": "unknown lifecycle setting", "value": value})
	value = baseline.duplicate(true)
	value.settings.erase("starter_prime_kg")
	cases.append({"label": "missing starter prime setting", "value": value})
	value = baseline.duplicate(true)
	value.propeller.wash_table = []
	cases.append({"label": "unsupported installation wash table", "value": value})
	value = baseline.duplicate(true)
	value.profile = "res://data/glow/../glow/os_max_55ax_candidate.json"
	cases.append({"label": "profile traversal", "value": value})
	value = baseline.duplicate(true)
	value.family = "glow_turbine"
	cases.append({"label": "unknown family", "value": value})
	value = baseline.duplicate(true)
	value.family = "glow_4t" if baseline.family == "glow_2t" else "glow_2t"
	cases.append({"label": "profile family mismatch", "value": value})
	value = baseline.duplicate(true)
	value.settings.idle_admission.unit = "percent"
	cases.append({"label": "quantity unit mismatch", "value": value})
	value = baseline.duplicate(true)
	value.settings.servo_time_constant_s.value = true
	cases.append({"label": "boolean quantity", "value": value})
	value = baseline.duplicate(true)
	value.settings.air_time_constant_s.source = "  "
	cases.append({"label": "blank provenance", "value": value})
	value = baseline.duplicate(true)
	value.settings.fuel_transport_time_constant_s.value = INF
	cases.append({"label": "nonfinite quantity", "value": value})
	value = baseline.duplicate(true)
	value.settings.servo_time_constant_s.value = 0.019
	cases.append({"label": "transport time constant below integrator envelope", "value": value})
	value = baseline.duplicate(true)
	value.settings.idle_admission.value = 1.0
	cases.append({"label": "idle admission upper bound", "value": value})
	value = baseline.duplicate(true)
	value.settings.temperature_firing_full_k.value = value.settings.temperature_firing_hot_full_k.value + 1.0
	cases.append({"label": "cold full temperature crosses hot full", "value": value})
	value = baseline.duplicate(true)
	value.settings.temperature_firing_hot_full_k.value = value.settings.temperature_firing_full_k.value - 1.0
	cases.append({"label": "hot full temperature below cold full", "value": value})
	value = baseline.duplicate(true)
	value.settings.temperature_firing_hot_zero_k.value = value.settings.temperature_firing_hot_full_k.value
	cases.append({"label": "hot zero temperature equals hot full", "value": value})
	value = baseline.duplicate(true)
	value.settings.lean_misfire_start_ratio.value = 1.0
	cases.append({"label": "lean threshold reaches nominal mixture", "value": value})
	value = baseline.duplicate(true)
	value.settings.rich_misfire_zero_ratio.value = value.settings.rich_misfire_start_ratio.value
	cases.append({"label": "rich threshold is unordered", "value": value})
	value = baseline.duplicate(true)
	value.settings.starter_prime_kg.value = Installation.MAX_STARTER_PRIME_KG + 1.0e-6
	cases.append({"label": "starter prime mass upper bound", "value": value})
	value = baseline.duplicate(true)
	value.settings.starter_prime_kg.unit = "g"
	cases.append({"label": "starter prime unit mismatch", "value": value})
	value = baseline.duplicate(true)
	value.settings.starter_prime_kg.value = -1.0e-6
	cases.append({"label": "negative starter prime mass", "value": value})
	value = baseline.duplicate(true)
	value.settings.thermal.head_heat_fraction.value = 1.01
	cases.append({"label": "thermal partition above one", "value": value})
	value = baseline.duplicate(true)
	value.settings.thermal.cooling_base_w_k.value = -0.1
	cases.append({"label": "negative thermal cooling coefficient", "value": value})
	value = baseline.duplicate(true)
	value.settings.thermal.heat_capacity_j_k.value = 0.0
	cases.append({"label": "zero thermal capacity", "value": value})
	value = baseline.duplicate(true)
	value.settings.thermal.head_heat_fraction.value = 0.0
	value.settings.thermal.cooling_base_w_k.value = 0.0
	value.settings.thermal.cooling_airflow_w_s_m_k.value = 0.0
	value.settings.thermal.premix_evaporation_j_kg.value = 0.0
	value.settings.thermal.evaporation_head_fraction.value = 0.0
	var zero_thermal: Dictionary = Installation.prepare_value(value, raw, model.duplicate(true), PackedByteArray())
	_check(label + " accepts zero heat partitions and cooling terms at their inclusive domain boundary",
		zero_thermal.get("ok", false), str(zero_thermal.get("errors", [])))
	value = baseline.duplicate(true)
	value.settings.starter_prime_kg.value = 0.0
	var no_prime: Dictionary = Installation.prepare_value(value, raw, model.duplicate(true), PackedByteArray())
	_check(label + " accepts a zero starter prime when no priming fuel is used",
		no_prime.get("ok", false), str(no_prime.get("errors", [])))
	value = baseline.duplicate(true)
	value.propeller.blades.value = 3.0
	cases.append({"label": "unsupported blade count", "value": value})
	value = baseline.duplicate(true)
	value.propeller.chord_m.value = value.propeller.diameter_m.value + 0.01
	cases.append({"label": "blade chord exceeds diameter", "value": value})
	value = baseline.duplicate(true)
	value.propeller.lift_slope.value = 21.0
	cases.append({"label": "propeller lift slope domain", "value": value})
	value = baseline.duplicate(true)
	value.propeller.diameter_m.value += 0.01
	cases.append({"label": "aircraft and install propeller diameter mismatch", "value": value})
	value = baseline.duplicate(true)
	value.initial_temperature_k.value = 601.0
	cases.append({"label": "initial head temperature above installation bound", "value": value})
	for item: Dictionary in cases:
		var result: Dictionary = Installation.prepare_value(item.value, raw, model.duplicate(true), PackedByteArray())
		_check(label + " rejects " + str(item.label), not result.get("ok", false), str(result.get("errors", [])))


func _test_inventory_and_axis(label: String, baseline: Dictionary, raw: Dictionary, model: Dictionary) -> void:
	var renamed_raw: Dictionary = raw.duplicate(true)
	for item: Dictionary in renamed_raw.inventory:
		if item.get("id") == model.fuel_system.tanks[0].liquid_inventory_id:
			item.name = "renamed display text is not a runtime identity"
	var renamed: Dictionary = Installation.prepare_value(baseline, renamed_raw, model.duplicate(true), PackedByteArray())
	_check(label + " tank runtime binding survives display-name changes because it uses stable IDs", renamed.get("ok", false))

	var invalid_raw := raw.duplicate(true)
	for item: Dictionary in invalid_raw.inventory:
		if item.get("id") == model.fuel_system.tanks[0].liquid_inventory_id:
			item.energy_source = "battery"
	var bad_fuel: Dictionary = Installation.prepare_value(baseline, invalid_raw, model.duplicate(true), PackedByteArray())
	_check(label + " refuses a non-glow energy source tank", not bad_fuel.get("ok", false))

	invalid_raw = raw.duplicate(true)
	for item: Dictionary in invalid_raw.inventory:
		if item.get("id") == model.fuel_system.tanks[0].liquid_inventory_id:
			item.position.unit = "cm"
	var bad_position: Dictionary = Installation.prepare_value(baseline, invalid_raw, model.duplicate(true), PackedByteArray())
	_check(label + " refuses malformed tank geometry quantity", not bad_position.get("ok", false))
	invalid_raw = raw.duplicate(true)
	for item: Dictionary in invalid_raw.inventory:
		if item.get("id") == model.fuel_system.tanks[0].liquid_inventory_id:
			invalid_raw.inventory.append(item.duplicate(true))
			break
	var duplicate_fuel: Dictionary = Installation.prepare_value(baseline, invalid_raw, model.duplicate(true), PackedByteArray())
	_check(label + " refuses duplicate liquid inventory IDs", not duplicate_fuel.get("ok", false))

	var candidate_model: Dictionary = model.duplicate(true)
	candidate_model.propulsion.axis = PackedFloat64Array([2.0, 0.0, 0.0])
	var bad_axis: Dictionary = Installation.prepare_value(baseline, raw, candidate_model, PackedByteArray())
	_check(label + " refuses a non-unit rotor axis", not bad_axis.get("ok", false))

	candidate_model = model.duplicate(true)
	candidate_model.fuel_system.tanks[0].liquid_inventory_id = "missing-liquid"
	var missing_id: Dictionary = Installation.prepare_value(baseline, raw, candidate_model, PackedByteArray())
	_check(label + " refuses a normalized tank liquid ID that does not resolve", not missing_id.get("ok", false))

	candidate_model = model.duplicate(true)
	candidate_model.fuel_system.registry_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
	var wrong_registry: Dictionary = Installation.prepare_value(baseline, raw, candidate_model, PackedByteArray())
	_check(label + " refuses normalized fuel metadata from a different registry identity", not wrong_registry.get("ok", false))
	candidate_model = model.duplicate(true)
	candidate_model.fuel_system.tanks[0].fuel = "unknown-glow-blend"
	var wrong_blend: Dictionary = Installation.prepare_value(baseline, raw, candidate_model, PackedByteArray())
	_check(label + " refuses a fuel blend that the engine profile does not model", not wrong_blend.get("ok", false))
	candidate_model = model.duplicate(true)
	candidate_model.fuel_system.tanks[0].reserve_kg = candidate_model.fuel_system.tanks[0].capacity_kg
	var full_capacity_reserve: Dictionary = Installation.prepare_value(baseline, raw, candidate_model, PackedByteArray())
	_check(label + " accepts reserve equal to full tank capacity", full_capacity_reserve.get("ok", false),
		str(full_capacity_reserve.get("errors", [])))
	candidate_model = model.duplicate(true)
	candidate_model.fuel_system.tanks[0].reserve_kg = candidate_model.fuel_system.tanks[0].capacity_kg + 1.0e-6
	var over_capacity_reserve: Dictionary = Installation.prepare_value(baseline, raw, candidate_model, PackedByteArray())
	_check(label + " refuses reserve above tank capacity", not over_capacity_reserve.get("ok", false))
	candidate_model = model.duplicate(true)
	candidate_model.fuel_system.tanks[0].reserve_kg = candidate_model.fuel_system.tanks[0].unusable_kg - 1.0e-6
	var below_unusable_reserve: Dictionary = Installation.prepare_value(baseline, raw, candidate_model, PackedByteArray())
	_check(label + " refuses reserve below unusable fuel", not below_unusable_reserve.get("ok", false))

	var tank: Dictionary = Installation._fuel_tank(raw, model, Profile.load_file(String(baseline.profile)).model)
	var carrier_model: Dictionary = model.duplicate(true)
	var carrier_raw: Dictionary = raw.duplicate(true)
	var axis := PackedFloat64Array([cos(deg_to_rad(10.0)), sin(deg_to_rad(10.0)), 0.0])
	carrier_raw.propulsion.propeller.thrust_angles.value = [0.0, 10.0]
	carrier_model.propulsion.axis = axis
	# Construct a valid synthetic wet tensor around a deliberately weak dry axis.
	# 1.95e-4 is below dry Jxx (2e-4) but above the tensor's inertia about this 10° axis.
	var dry_tensor := PackedFloat64Array([2.0e-4, 1.0e-4, 3.0e-4, 0.0, 0.0, 0.0])
	var dry_mass: float = float(carrier_model.mass_kg) - tank.mass_kg
	var dry_cg: PackedFloat64Array = PackedFloat64Array([
		-tank.mass_kg * tank.position[0] / dry_mass,
		-tank.mass_kg * tank.position[1] / dry_mass,
		-tank.mass_kg * tank.position[2] / dry_mass,
	])
	var wet_tensor: PackedFloat64Array = dry_tensor.duplicate()
	_add_tensor(wet_tensor, FuelMass.tensor_per_kg(dry_cg, PackedFloat64Array([0.0, 0.0, 0.0])), dry_mass)
	_add_tensor(wet_tensor, FuelMass.tensor_per_kg(tank.position, tank.size), tank.mass_kg)
	carrier_model.inertia = wet_tensor
	carrier_model.propulsion.rotor_inertia = 1.95e-4
	var over_limit: Dictionary = Installation.prepare_value(baseline, carrier_raw, carrier_model, PackedByteArray())
	_check(label + " rejects rotor inertia above the axis-projected dry carrier even below Jxx",
		not over_limit.get("ok", false), str(over_limit.get("errors", [])))
	carrier_model.propulsion.rotor_inertia = 1.8e-4
	var under_limit: Dictionary = Installation.prepare_value(baseline, carrier_raw, carrier_model, PackedByteArray())
	_check(label + " accepts rotor inertia below the axis-projected dry carrier limit",
		under_limit.get("ok", false), str(under_limit.get("errors", [])))


func _test_unsupported_modules(label: String, baseline: Dictionary, raw: Dictionary, model: Dictionary) -> void:
	for module: String in ["normal_force", "pfactor_moment", "slipstream"]:
		var candidate := raw.duplicate(true)
		candidate.propulsion.propeller[module] = {}
		var result: Dictionary = Installation.prepare_value(baseline, candidate, model.duplicate(true), PackedByteArray())
		_check(label + " rejects unsupported optional propeller module " + module, not result.get("ok", false))
	var legacy_shaft: Dictionary = raw.duplicate(true)
	legacy_shaft.propulsion.engine.shaft = {}
	var shaft_result: Dictionary = Installation.prepare_value(baseline, legacy_shaft, model.duplicate(true), PackedByteArray())
	_check(label + " rejects mixed legacy shaft module", not shaft_result.get("ok", false))


func _test_path_gate() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/stik_glow_55ax_2t.json"))
	if not raw is Dictionary:
		_check("path-gate fixture loads", false)
		return
	var legacy: Dictionary = AircraftData._validate_legacy(AircraftData.legacy_v1_input(raw))
	if not legacy.get("ok", false):
		_check("path-gate model derives", false, str(legacy.get("errors", [])))
		return
	for path: Variant in ["user://install.json", "res://data/glow/../stik_55ax_2t.json", "res://data/glow/sub/install.json", "res://data/glow/install.json.bak", 5]:
		var candidate: Dictionary = raw.duplicate(true)
		candidate.propulsion.engine.glow_installation = path
		var result: Dictionary = Installation.attach(candidate, legacy.model)
		_check("unsafe glow install path rejected: " + str(path), not result.get("ok", false))


func _add_tensor(target: PackedFloat64Array, tensor: PackedFloat64Array, scale: float) -> void:
	for index: int in 6:
		target[index] += tensor[index] * scale
