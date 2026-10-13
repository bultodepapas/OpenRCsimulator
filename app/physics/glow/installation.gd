## Closed opt-in aircraft extension. Source files are fingerprinted with the loaded engine profile.
extends RefCounted

const Profile := preload("res://physics/glow/profile.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")

const INSTALLATION_DIRECTORY := "res://data/glow/"
const FORMAT := "openrc-glow-installation v1"
const SETTINGS := {
	idle_admission = "1",
	servo_time_constant_s = "s",
	air_time_constant_s = "s",
	fuel_transport_time_constant_s = "s",
	stall_rpm = "rpm",
	minimum_start_rpm = "rpm",
	temperature_firing_min_k = "K",
	temperature_firing_full_k = "K",
	temperature_firing_hot_full_k = "K",
	temperature_firing_hot_zero_k = "K",
	lean_misfire_zero_ratio = "1",
	lean_misfire_start_ratio = "1",
	rich_misfire_start_ratio = "1",
	rich_misfire_zero_ratio = "1",
	starter_prime_kg = "kg",
}
const THERMAL := {
	heat_capacity_j_k = "J/K",
	head_heat_fraction = "1",
	cooling_base_w_k = "W/K",
	cooling_airflow_w_s_m_k = "W/(K m/s)",
	premix_evaporation_j_kg = "J/kg",
	evaporation_head_fraction = "1",
}
const PROPELLER := {
	max_rpm = "rpm",
	diameter_m = "m",
	pitch_m = "m",
	chord_m = "m",
	blades = "1",
	lift_slope = "1/rad",
	cd0 = "1",
	induced_drag = "1",
}
const NONNEGATIVE_SETTINGS := ["lean_misfire_zero_ratio", "starter_prime_kg"]
const NONNEGATIVE_THERMAL := [
	"head_heat_fraction", "cooling_base_w_k", "cooling_airflow_w_s_m_k",
	"premix_evaporation_j_kg", "evaporation_head_fraction",
]
const MAX_STARTER_PRIME_KG := 0.001
const MIN_TRANSPORT_TAU_S := 0.02
const MAX_TRANSPORT_TAU_S := 5.0
const MAX_TEMPERATURE_THRESHOLD_K := 1000.0
const MAX_MIXTURE_MULTIPLIER := 4.0


## Loads one bundled install and delegates all semantic validation to prepare_value().
static func attach(raw: Variant, model: Variant) -> Dictionary:
	if not raw is Dictionary or not model is Dictionary:
		return _fail("Glow installation requires validated aircraft data")
	var propulsion: Variant = raw.get("propulsion", {})
	if not propulsion is Dictionary:
		return _fail("Glow installation aircraft propulsion is malformed")
	var engine: Variant = propulsion.get("engine", {})
	if not engine is Dictionary:
		return _fail("Glow installation aircraft engine is malformed")
	var path: Variant = engine.get("glow_installation", null)
	if not _is_bundled_json_path(path):
		return _fail("glow_installation must identify a bundled res://data/glow JSON file")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(String(path))
	if bytes.is_empty():
		return _fail("Cannot read glow installation: " + String(path))
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return _fail("Invalid glow installation JSON: " + parser.get_error_message())
	return prepare_value(parser.data, raw, model, bytes)


## Pure value validator used by attach() and contract tests. `source_bytes` is the exact
## file payload in production; tests may pass a serialized candidate value.
static func prepare_value(value: Variant, raw: Variant, model: Variant, source_bytes: PackedByteArray) -> Dictionary:
	if not value is Dictionary or not _keys(value, ["format", "family", "profile", "fuel_inventory", "settings", "initial_temperature_k", "propeller"]):
		return _fail("Malformed glow installation root")
	if value.get("format") != FORMAT or value.get("family") not in ["glow_2t", "glow_4t"]:
		return _fail("Unsupported glow installation format or family")
	if not _is_bundled_json_path(value.get("profile")):
		return _fail("Glow profile must identify a bundled res://data/glow JSON file")
	if not raw is Dictionary or not model is Dictionary:
		return _fail("Glow installation requires validated aircraft data")
	var aircraft_propulsion: Variant = raw.get("propulsion", {})
	var model_propulsion: Variant = model.get("propulsion", {})
	if not aircraft_propulsion is Dictionary or not model_propulsion is Dictionary:
		return _fail("Glow installation aircraft propulsion is malformed")
	if aircraft_propulsion.get("kind") != "glow_prop":
		return _fail("Glow installation requires the glow_prop aircraft family")
	var aircraft_engine: Variant = aircraft_propulsion.get("engine", {})
	var aircraft_propeller: Variant = aircraft_propulsion.get("propeller", {})
	if not aircraft_engine is Dictionary or not aircraft_propeller is Dictionary:
		return _fail("Glow installation aircraft engine or propeller is malformed")
	if aircraft_engine.has("shaft"):
		return _fail("Glow installation cannot be combined with the legacy shaft module")
	for optional_module: String in ["normal_force", "pfactor_moment", "slipstream"]:
		if aircraft_propeller.has(optional_module) or model_propulsion.has(optional_module):
			return _fail("Glow installation does not support propulsion.propeller." + optional_module)
	var capabilities: Variant = raw.get("capabilities", {})
	if not capabilities is Dictionary or capabilities.get("energy") != "finite_glow_fuel":
		return _fail("Glow installation requires the finite_glow_fuel capability")

	var loaded: Dictionary = Profile.load_file(String(value.profile))
	if not loaded.get("ok", false) or loaded.model.get("family") != value.family:
		return _fail("Invalid or mismatched glow engine profile")
	var profile: Dictionary = loaded.model
	if not value.get("settings") is Dictionary or not _keys(value.settings, SETTINGS.keys() + ["thermal"]):
		return _fail("Glow lifecycle settings are missing or contain unknown fields")
	var scalar_settings: Dictionary = value.settings.duplicate(true)
	scalar_settings.erase("thermal")
	var settings: Dictionary = _group(scalar_settings, SETTINGS, NONNEGATIVE_SETTINGS)
	var thermal: Dictionary = _group(value.settings.get("thermal"), THERMAL, NONNEGATIVE_THERMAL)
	var propeller: Dictionary = _group(value.get("propeller"), PROPELLER)
	var initial_temperature: float = _quantity(value.get("initial_temperature_k"), "K")
	if settings.is_empty() or thermal.is_empty() or propeller.is_empty():
		return _fail("Invalid glow installation quantity, unit or provenance")
	if not is_finite(initial_temperature) or initial_temperature < 200.0 or initial_temperature > 600.0:
		return _fail("Initial glow temperature must be finite and in [200, 600] K")
	var settings_error: String = _settings_error(settings, thermal, profile)
	if not settings_error.is_empty():
		return _fail(settings_error)
	var propeller_error: String = _propeller_error(propeller, model_propulsion)
	if not propeller_error.is_empty():
		return _fail(propeller_error)
	settings.thermal = thermal

	var tank_result: Dictionary = _fuel_tank(raw, value.get("fuel_inventory"), model)
	if not tank_result.get("ok", false):
		return _fail(str(tank_result.get("message", "Invalid glow fuel inventory")))
	if settings.starter_prime_kg >= tank_result.mass_kg and settings.starter_prime_kg > 0.0:
		return _fail("starter_prime_kg must remain below the installed fuel inventory")
	var axis_result: Dictionary = _propeller_axis(model_propulsion)
	if not axis_result.get("ok", false):
		return _fail(str(axis_result.get("message", "Invalid glow propeller axis")))
	var carrier_result: Dictionary = _carrier_inertia(tank_result.dry_properties, model_propulsion, axis_result.axis)
	if not carrier_result.get("ok", false):
		return _fail(str(carrier_result.get("message", "Invalid dry carrier inertia")))

	var bytes: PackedByteArray = source_bytes
	if bytes.is_empty():
		bytes = JSON.stringify(value, "", true).to_utf8_buffer()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	var install: Dictionary = {
		profile = profile,
		settings = settings,
		propeller = propeller,
		rotor_axis = axis_result.axis,
		initial_temperature_k = initial_temperature,
		initial_fuel_kg = tank_result.mass_kg,
		tank_position = tank_result.position,
		tank_size = tank_result.size,
		identity = {
			format = FORMAT,
			sha256 = hashing.finish().hex_encode(),
			profile = loaded.input_identity,
		},
		provenance = value.duplicate(true),
	}
	var out: Dictionary = model.duplicate(true)
	var out_propulsion: Dictionary = out.propulsion
	# A missing thrust-angle quantity means the historical axial (+x) installation convention.
	if not out_propulsion.has("axis"):
		out_propulsion.axis = axis_result.axis.duplicate()
	out_propulsion.glow = install
	return {ok = true, errors = PackedStringArray(), model = out}


static func _settings_error(settings: Dictionary, thermal: Dictionary, profile: Dictionary) -> String:
	if settings.idle_admission <= 0.0 or settings.idle_admission >= 1.0:
		return "idle_admission must be strictly between zero and one"
	for name: String in ["servo_time_constant_s", "air_time_constant_s", "fuel_transport_time_constant_s"]:
		if settings[name] < MIN_TRANSPORT_TAU_S or settings[name] > MAX_TRANSPORT_TAU_S:
			return "Glow transport time constants must be in [0.02, 5] s"
	if settings.stall_rpm <= 0.0 or settings.minimum_start_rpm <= settings.stall_rpm:
		return "Glow start RPM must exceed a positive stall RPM"
	if settings.minimum_start_rpm >= profile.operation.max_rpm or settings.stall_rpm >= profile.operation.max_rpm:
		return "Glow stall and start RPM must remain below the profile maximum"
	if settings.starter_prime_kg > MAX_STARTER_PRIME_KG:
		return "starter_prime_kg must be in [0, 0.001] kg"
	if not (settings.temperature_firing_min_k >= 200.0
		and settings.temperature_firing_min_k < settings.temperature_firing_full_k
		and settings.temperature_firing_full_k < settings.temperature_firing_hot_full_k
		and settings.temperature_firing_hot_full_k < settings.temperature_firing_hot_zero_k
		and settings.temperature_firing_hot_zero_k <= MAX_TEMPERATURE_THRESHOLD_K):
		return "Firing temperature thresholds must satisfy 200 K ≤ cold minimum < cold full < hot full < hot zero ≤ 1000 K"
	if not (settings.lean_misfire_zero_ratio < settings.lean_misfire_start_ratio
		and settings.lean_misfire_start_ratio < 1.0):
		return "Lean misfire ratios must satisfy 0 ≤ zero < start < nominal"
	if not (settings.rich_misfire_start_ratio > 1.0
		and settings.rich_misfire_start_ratio < settings.rich_misfire_zero_ratio
		and settings.rich_misfire_zero_ratio <= MAX_MIXTURE_MULTIPLIER):
		return "Rich misfire ratios must satisfy nominal < start < zero ≤ 4"
	if thermal.heat_capacity_j_k > 10000.0 or thermal.head_heat_fraction > 1.0:
		return "Glow head heat capacity or combustion heat fraction is outside its domain"
	if thermal.cooling_base_w_k > 1000.0 or thermal.cooling_airflow_w_s_m_k > 1000.0:
		return "Glow cooling conductance is outside its domain"
	if thermal.premix_evaporation_j_kg > 10000000.0 or thermal.evaporation_head_fraction > 1.0:
		return "Glow evaporation heat or partition is outside its domain"
	return ""


static func _propeller_error(propeller: Dictionary, model_propulsion: Dictionary) -> String:
	if propeller.diameter_m < 0.05 or propeller.diameter_m > 2.0:
		return "Glow propeller diameter must be in [0.05, 2] m"
	if propeller.pitch_m > 2.0 or propeller.chord_m > propeller.diameter_m:
		return "Glow propeller pitch or chord is outside its geometric domain"
	if propeller.blades != 2.0 or propeller.lift_slope > 20.0 or propeller.cd0 > 2.0 or propeller.induced_drag > 10.0:
		return "Glow installation supports a bounded two-blade annular propeller model"
	var diameter: Variant = model_propulsion.get("diameter", null)
	if typeof(diameter) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(diameter)) or diameter <= 0.0:
		return "Glow aircraft has an invalid propeller diameter"
	if absf(propeller.diameter_m - float(diameter)) > maxf(1.0e-9, absf(float(diameter)) * 1.0e-6):
		return "Glow installation and aircraft propeller diameters disagree"
	return ""


static func _fuel_tank(raw: Dictionary, fuel_name: Variant, model: Dictionary) -> Dictionary:
	if not fuel_name is String or fuel_name.strip_edges().is_empty():
		return {ok = false, message = "Glow fuel inventory name must be a nonempty string"}
	var inventory: Variant = raw.get("inventory", null)
	if not inventory is Array:
		return {ok = false, message = "Glow fuel requires a validated inventory array"}
	var matches: Array[Dictionary] = []
	for candidate: Variant in inventory:
		if candidate is Dictionary and candidate.get("name") == fuel_name:
			matches.append(candidate)
	if matches.size() != 1 or matches[0].get("energy_source") != "glow_fuel":
		return {ok = false, message = "Glow fuel tank must name one explicit glow_fuel inventory item"}
	var tank: Dictionary = matches[0]
	var mass: float = _quantity(tank.get("mass"), "kg")
	var position_values: PackedFloat64Array = _quantity_vector(tank.get("position"), "m")
	var size: PackedFloat64Array = _quantity_vector(tank.get("size"), "m")
	if not is_finite(mass) or mass <= 0.0 or position_values.size() != 3 or size.size() != 3:
		return {ok = false, message = "Glow inventory mass, position or size has invalid quantity data"}
	for extent: float in size:
		if extent < 0.0 or extent > 2.0:
			return {ok = false, message = "Glow tank size must be finite and within [0, 2] m"}
	var model_mass: Variant = model.get("mass_kg", null)
	var model_inertia: Variant = model.get("inertia", null)
	var cg: Variant = model.get("cg_inventory_le", null)
	if typeof(model_mass) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(model_mass)) or float(model_mass) <= mass:
		return {ok = false, message = "Glow fuel mass must be below the validated aircraft mass"}
	if not model_inertia is PackedFloat64Array or model_inertia.size() != 6 or not cg is PackedFloat64Array or cg.size() != 3:
		return {ok = false, message = "Glow aircraft mass properties are malformed"}
	for value: float in model_inertia + cg:
		if not is_finite(value):
			return {ok = false, message = "Glow aircraft mass properties must be finite"}
	# Inventory LE coordinates [aft, right, up] become body FRD coordinates about the wet-CG datum.
	var position := PackedFloat64Array([
		cg[0] - position_values[0],
		position_values[1] - cg[1],
		cg[2] - position_values[2],
	])
	var dry: Dictionary = FuelMass.evaluate(float(model_mass), model_inertia, mass, 0.0, position, size)
	if not dry.get("ok", false):
		return {ok = false, message = "Glow dry fuel carrier mass properties are invalid"}
	return {ok = true, mass_kg = mass, position = position, size = size, dry_properties = dry}


static func _propeller_axis(model_propulsion: Dictionary) -> Dictionary:
	var source: Variant = model_propulsion.get("axis", PackedFloat64Array([1.0, 0.0, 0.0]))
	var axis := PackedFloat64Array()
	if source is PackedFloat64Array:
		axis = source.duplicate()
	elif source is Array:
		if source.size() != 3:
			return {ok = false, message = "Glow propeller axis must have three finite components"}
		for component: Variant in source:
			if typeof(component) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(component)):
				return {ok = false, message = "Glow propeller axis must be finite"}
			axis.append(float(component))
	if axis.size() != 3:
		return {ok = false, message = "Glow propeller axis must have three finite components"}
	var norm_squared: float = 0.0
	for component: float in axis:
		if not is_finite(component):
			return {ok = false, message = "Glow propeller axis must be finite"}
		norm_squared += component * component
	if not is_finite(norm_squared) or absf(norm_squared - 1.0) > 1.0e-9:
		return {ok = false, message = "Glow propeller axis must be unit length"}
	return {ok = true, axis = axis}


static func _carrier_inertia(dry: Dictionary, propulsion: Dictionary, axis: PackedFloat64Array) -> Dictionary:
	var rotor: Variant = propulsion.get("rotor_inertia", null)
	if typeof(rotor) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(rotor)) or float(rotor) <= 0.0 or float(rotor) > 0.1:
		return {ok = false, message = "Glow rotating inertia must be finite and in (0, 0.1] kg·m²"}
	var inverse: PackedFloat64Array = dry.get("inverse", PackedFloat64Array())
	if inverse.size() != 6:
		return {ok = false, message = "Glow dry aircraft inertia tensor is unavailable"}
	var inverse_axis := PackedFloat64Array([
		inverse[0] * axis[0] + inverse[3] * axis[1] + inverse[4] * axis[2],
		inverse[3] * axis[0] + inverse[1] * axis[1] + inverse[5] * axis[2],
		inverse[4] * axis[0] + inverse[5] * axis[1] + inverse[2] * axis[2],
	])
	var projected_inverse: float = axis[0] * inverse_axis[0] + axis[1] * inverse_axis[1] + axis[2] * inverse_axis[2]
	var carrier_factor: float = 1.0 - float(rotor) * projected_inverse
	if not is_finite(projected_inverse) or projected_inverse <= 0.0 or not is_finite(carrier_factor) or carrier_factor <= 1.0e-12:
		return {ok = false, message = "Subtracting the glow rotor leaves nonpositive dry carrier inertia along its axis"}
	return {ok = true, carrier_factor = carrier_factor}


static func _group(value: Variant, spec: Dictionary, allow_zero: Array = []) -> Dictionary:
	if not value is Dictionary or not _keys(value, spec.keys()):
		return {}
	var out: Dictionary = {}
	for key: String in spec:
		var number: float = _quantity(value.get(key), spec[key])
		if not is_finite(number) or number < 0.0 or (number == 0.0 and not allow_zero.has(key)):
			return {}
		out[key] = number
	return out


static func _quantity(value: Variant, unit: String) -> float:
	if not value is Dictionary or not _keys(value, ["value", "unit", "kind", "source"]):
		return NAN
	if value.get("unit") != unit or not Profile.KINDS.has(value.get("kind")):
		return NAN
	var source: Variant = value.get("source")
	var number: Variant = value.get("value")
	if not source is String or source.strip_edges().is_empty() or typeof(number) not in [TYPE_FLOAT, TYPE_INT]:
		return NAN
	return float(number)


static func _quantity_vector(value: Variant, unit: String) -> PackedFloat64Array:
	if not value is Dictionary or not _keys(value, ["value", "unit", "kind", "source"]):
		return PackedFloat64Array()
	if value.get("unit") != unit or not Profile.KINDS.has(value.get("kind")):
		return PackedFloat64Array()
	var source: Variant = value.get("source")
	var coordinates: Variant = value.get("value")
	if not source is String or source.strip_edges().is_empty() or not coordinates is Array or coordinates.size() != 3:
		return PackedFloat64Array()
	var out := PackedFloat64Array()
	for coordinate: Variant in coordinates:
		if typeof(coordinate) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(coordinate)):
			return PackedFloat64Array()
		out.append(float(coordinate))
	return out


static func _is_bundled_json_path(path: Variant) -> bool:
	if not path is String or not path.begins_with(INSTALLATION_DIRECTORY) or not path.ends_with(".json") or ".." in path:
		return false
	var basename: String = String(path).substr(INSTALLATION_DIRECTORY.length())
	if basename.is_empty() or "/" in basename or "\\" in basename:
		return false
	for index: int in basename.length():
		var code: int = basename.unicode_at(index)
		if code == 46 or code == 45 or code == 95 or (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			continue
		return false
	return true


static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key: Variant in keys:
		if not value.has(key):
			return false
	return true


static func _fail(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message]), model = {}}
