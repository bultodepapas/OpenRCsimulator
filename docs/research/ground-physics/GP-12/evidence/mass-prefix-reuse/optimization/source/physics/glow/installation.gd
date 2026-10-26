## Closed opt-in aircraft extension. Source files are fingerprinted with the loaded engine profile.
extends RefCounted

const Profile := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/glow/profile.gd")
const FuelMass := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/glow/fuel_mass.gd")
const FuelFeed := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/glow/fuel_feed.gd")
const FuelProperties := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/fuel_properties.gd")
const Carb := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/glow/carburetor.gd")

const INSTALLATION_DIRECTORY := "res://data/glow/"
const FORMAT := "openrc-glow-installation v2"
const SETTINGS := {
	throttle_effective_area_m2 = "m2",
	idle_opening = "1",
	throttle_travel_exponent = "1",
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
const PROPELLER_ZERO_LIFT := "zero_lift_angle_rad"
## NITRO-05: optional fuel-feed block (physics/glow/fuel_feed.gd). The carburetor spray bar is an inventory-frame
## position [aft, right, up] from the wing leading-edge datum, like the tank.
## `fuel_inventory` remains a v1 provenance label; runtime binding is by normalized tank and liquid inventory IDs.
const ROOT_KEYS := ["format", "family", "profile", "fuel_inventory", "settings", "initial_temperature_k", "propeller"]
const FUEL_FEED := {
	idle_drive_pressure_pa = "Pa",
	wot_drive_pressure_pa = "Pa",
}
const MAX_DRIVE_PRESSURE_PA := 100000.0
const NONNEGATIVE_SETTINGS := ["lean_misfire_zero_ratio", "starter_prime_kg"]
const NONNEGATIVE_THERMAL := [
	"head_heat_fraction", "cooling_base_w_k", "cooling_airflow_w_s_m_k",
	"premix_evaporation_j_kg", "evaporation_head_fraction",
]
const MAX_STARTER_PRIME_KG := 0.001
## NITRO-06: no model-aircraft carburettor passes more than this open area (a 113 mm bore).
const MAX_THROTTLE_AREA_M2 := 1.0e-2
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
	if not value is Dictionary or not (_keys(value, ROOT_KEYS) or _keys(value, ROOT_KEYS + ["fuel_feed"])):
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
	# EX-14c: the propeller normal force, P-factor and the quasi-static tail slipstream compose with the Glow shaft (the
	# stage route hands the wake its own thrust and torque). The smooth and transported wakes need wash states the Glow
	# layout does not carry, so they stay refused.
	for optional_module: String in ["normal_force", "pfactor_moment", "slipstream"]:
		var validated: Variant = model_propulsion.get(optional_module)
		if aircraft_propeller.has(optional_module) and (validated == null or not (validated is Dictionary or validated is PackedFloat64Array) or validated.is_empty()):
			return _fail("Glow installation requires a validated propulsion.propeller." + optional_module)
	var slipstream: Variant = model_propulsion.get("slipstream", {})
	if slipstream is Dictionary:
		for stateful: String in ["edge_fraction", "reverse_fade", "transport_speed_floor"]:
			if slipstream.has(stateful):
				return _fail("Glow installation supports only the quasi-static slipstream (no slipstream." + stateful + ")")
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
	# EX-14f: the cambered section's optional zero-lift angle (rad, -0.3..0) is the only signed propeller quantity.
	var propeller_raw: Variant = value.get("propeller")
	var zero_lift: float = 0.0
	if propeller_raw is Dictionary and propeller_raw.has(PROPELLER_ZERO_LIFT):
		zero_lift = _quantity(propeller_raw.get(PROPELLER_ZERO_LIFT), "rad")
		if not is_finite(zero_lift) or zero_lift < -0.3 or zero_lift > 0.0:
			return _fail("Glow propeller zero_lift_angle_rad must be finite and in [-0.3, 0] rad")
		propeller_raw = propeller_raw.duplicate()
		propeller_raw.erase(PROPELLER_ZERO_LIFT)
	var propeller: Dictionary = _group(propeller_raw, PROPELLER)
	if not propeller.is_empty() and value.get("propeller", {}).has(PROPELLER_ZERO_LIFT):
		propeller[PROPELLER_ZERO_LIFT] = zero_lift
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

	var tank_result: Dictionary = _fuel_tank(raw, model, profile)
	if not tank_result.get("ok", false):
		return _fail(str(tank_result.get("message", "Invalid glow fuel inventory")))
	var line_result: Dictionary = {ok = true}
	if tank_result.normalized.has("feed_line"):
		line_result = _fuel_line(raw, model, tank_result)
		if not line_result.get("ok", false):
			return _fail(str(line_result.get("message", "Invalid Glow feed-line inventory")))
	if settings.starter_prime_kg >= tank_result.mass_kg and settings.starter_prime_kg > 0.0:
		return _fail("starter_prime_kg must remain below the installed fuel inventory")
	var feed: Dictionary = {}
	if value.has("fuel_feed"):
		feed = _fuel_feed(value.fuel_feed, model, profile, tank_result)
		if not feed.get("ok", false):
			return _fail(str(feed.get("message", "Invalid glow fuel feed")))
		feed.erase("ok")
	if bool(tank_result.get("has_pickup_position", false)) and feed.is_empty():
		return _fail("An authored Glow pickup position requires the calibrated fuel_feed block")
	var axis_result: Dictionary = _propeller_axis(model_propulsion)
	if not axis_result.get("ok", false):
		return _fail(str(axis_result.get("message", "Invalid glow propeller axis")))

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
		# `initial_fuel_kg` is retained as the authored-reference alias. Sessions start
		# from capacity_fuel_kg times the selected fill fraction.
		initial_fuel_kg = tank_result.mass_kg,
		reference_fuel_kg = tank_result.mass_kg,
		capacity_fuel_kg = tank_result.capacity_kg,
		total_capacity_kg = tank_result.capacity_kg + float(line_result.get("capacity_kg", 0.0)),
		total_reference_fuel_kg = tank_result.mass_kg + float(line_result.get("reference_mass_kg", 0.0)),
		unusable_fuel_kg = tank_result.unusable_kg,
		reserve_fuel_kg = tank_result.reserve_kg,
		fuel_start_fill = tank_result.start_fill,
		fuel_tank = tank_result.normalized,
		tank_position = tank_result.position,
		tank_size = tank_result.size,
		identity = {
			format = FORMAT,
			sha256 = hashing.finish().hex_encode(),
			profile = loaded.input_identity,
		},
		provenance = value.duplicate(true),
	}
	if bool(tank_result.get("has_pickup_position", false)):
		install.pickup_position = tank_result.pickup_position.duplicate()
		install.pickup_position_source = tank_result.pickup_position_source.duplicate(true)
		install.has_pickup_position = true
	if line_result.has("line"):
		install.feed_line = line_result.line.duplicate(true)
	if not feed.is_empty():
		install.fuel_feed = feed
	# FUEL-04: prepare the shared fixed-datum resource inventory once; flight stages only evaluate it.
	if line_result.has("line"):
		var resources: Array = [
			{id = tank_result.id, reference_mass_kg = tank_result.mass_kg,
				capacity_mass_kg = tank_result.capacity_kg, center_body_m = tank_result.position,
				size_body_m = tank_result.size},
			{id = line_result.line.liquid_inventory_id, reference_mass_kg = line_result.line.reference_mass_kg,
				capacity_mass_kg = line_result.line.capacity_kg, center_body_m = line_result.line.position,
				size_body_m = line_result.line.size},
		]
		install.mass_reference = FuelMass.prepare_resources(float(model.mass_kg), model.inertia, resources)
		if install.mass_reference.get("ok", false):
			install.dry_properties = FuelMass.evaluate_resources(install.mass_reference, PackedFloat64Array([0.0, 0.0]))
	else:
		install.mass_reference = FuelMass.prepare(float(model.mass_kg), model.inertia, tank_result.mass_kg,
			tank_result.position, tank_result.size, tank_result.capacity_kg, tank_result.id)
		install.dry_properties = tank_result.dry_properties
	if not install.mass_reference.get("ok", false):
		return _fail("Glow fuel mass reference is invalid: " + str(install.mass_reference.get("error", "")))
	if not install.dry_properties.get("ok", false):
		return _fail("Glow dry resource carrier properties are invalid")
	var carrier_result: Dictionary = _carrier_inertia(install.dry_properties, model_propulsion, axis_result.axis)
	if not carrier_result.get("ok", false):
		return _fail(str(carrier_result.get("message", "Invalid dry carrier inertia")))
	install.rotor_carrier_factor = float(carrier_result.carrier_factor)
	# NITRO-06: derived constants of the carburettor law (physics/glow/carburetor.gd), fixed for the installation.
	install.throttle_idle_offset = Carb.idle_offset(float(settings.idle_opening))
	install.throttle_travel_exponent = float(settings.throttle_travel_exponent)
	install.throttle_capacity_m3_s = Carb.capacity_m3_s(float(settings.throttle_effective_area_m2))
	if not is_finite(install.throttle_idle_offset) or not is_finite(install.throttle_capacity_m3_s):
		return _fail("Glow carburettor idle offset or capacity is nonfinite")
	var out: Dictionary = model.duplicate(true)
	var out_propulsion: Dictionary = out.propulsion
	# A missing thrust-angle quantity means the historical axial (+x) installation convention.
	if not out_propulsion.has("axis"):
		out_propulsion.axis = axis_result.axis.duplicate()
	out_propulsion.glow = install
	return {ok = true, errors = PackedStringArray(), model = out}


static func _settings_error(settings: Dictionary, thermal: Dictionary, profile: Dictionary) -> String:
	if settings.throttle_effective_area_m2 <= 0.0 or settings.throttle_effective_area_m2 > MAX_THROTTLE_AREA_M2:
		return "throttle_effective_area_m2 must be positive and at most 0.01 m2"
	if settings.idle_opening <= 0.0 or settings.idle_opening >= 1.0:
		return "idle_opening must be strictly between zero and one"
	if settings.throttle_travel_exponent < 0.1 or settings.throttle_travel_exponent > 10.0:
		return "throttle_travel_exponent must be in [0.1, 10]"
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


static func _fuel_tank(raw: Dictionary, model: Dictionary, profile: Dictionary) -> Dictionary:
	var system: Variant = model.get("fuel_system", null)
	if not system is Dictionary or system.get("format") != "openrc-fuel-system v1":
		return {ok = false, message = "Glow installation requires a normalized fuel_system"}
	var tanks: Variant = system.get("tanks", null)
	if not tanks is Array or tanks.size() != 1 or not tanks[0] is Dictionary:
		return {ok = false, message = "The single-tank Glow solver requires exactly one normalized tank"}
	var normalized: Dictionary = tanks[0]
	var normalized_id: Variant = normalized.get("id", null)
	if not normalized_id is String or normalized_id.strip_edges().is_empty():
		return {ok = false, message = "Normalized Glow tank requires a stable nonempty tank ID"}
	if normalized.get("family") != "glow":
		return {ok = false, message = "Glow installation tank must use the glow fuel family"}
	var registry: Dictionary = FuelProperties.load_file()
	if not registry.get("ok", false):
		return {ok = false, message = "Glow fuel registry is unavailable: " + str(registry.get("message", ""))}
	var identity: Variant = system.get("registry_sha256", "")
	if identity != registry.get("identity", {}).get("sha256", ""):
		return {ok = false, message = "Normalized tank and current fuel registry identities disagree"}
	var blend_check: Dictionary = Profile.validate_registry_blend(profile, registry, str(normalized.get("fuel", "")))
	if not blend_check.get("ok", false):
		return {ok = false, message = str(blend_check.get("message", "Glow profile does not match its registry blend"))}
	var density: float = float(normalized.get("density_kg_m3", NAN))
	if not is_finite(density) or absf(density - float(blend_check.density_kg_m3)) > 1.0e-9:
		return {ok = false, message = "Normalized Glow tank density disagrees with its registry blend"}
	var inventory: Variant = raw.get("inventory", null)
	if not inventory is Array:
		return {ok = false, message = "Glow fuel requires a validated inventory array"}
	var liquid_id: Variant = normalized.get("liquid_inventory_id", null)
	var shell_id: Variant = normalized.get("shell_inventory_id", null)
	if not liquid_id is String or liquid_id.is_empty() or not shell_id is String or shell_id.is_empty():
		return {ok = false, message = "Normalized Glow tank needs stable liquid and shell inventory IDs"}
	var liquid_matches: Array[Dictionary] = []
	var shell_matches: Array[Dictionary] = []
	for candidate: Variant in inventory:
		if not candidate is Dictionary:
			continue
		if candidate.get("id") == liquid_id:
			liquid_matches.append(candidate)
		if candidate.get("id") == shell_id:
			shell_matches.append(candidate)
	if liquid_matches.size() != 1 or shell_matches.size() != 1 or liquid_id == shell_id:
		return {ok = false, message = "Normalized Glow tank IDs must resolve to one distinct liquid and shell item"}
	var tank: Dictionary = liquid_matches[0]
	if tank.get("energy_source") != "glow_fuel" or shell_matches[0].has("energy_source"):
		return {ok = false, message = "Glow liquid and empty shell energy sources disagree with the normalized tank"}
	var mass: float = _quantity(tank.get("mass"), "kg")
	var position_values: PackedFloat64Array = _quantity_vector(tank.get("position"), "m")
	var size: PackedFloat64Array = _quantity_vector(tank.get("size"), "m")
	if not is_finite(mass) or mass <= 0.0 or position_values.size() != 3 or size.size() != 3:
		return {ok = false, message = "Glow inventory mass, position or size has invalid quantity data"}
	for extent: float in size:
		if extent < 0.0 or extent > 2.0:
			return {ok = false, message = "Glow tank size must be finite and within [0, 2] m"}
	var reference_mass: float = float(normalized.get("liquid_mass_kg", NAN))
	var capacity: float = float(normalized.get("capacity_kg", NAN))
	var capacity_m3: float = float(normalized.get("capacity_m3", NAN))
	var unusable: float = float(normalized.get("unusable_kg", NAN))
	var reserve: float = float(normalized.get("reserve_kg", unusable))
	var start_fill: float = float(normalized.get("start_fill", NAN))
	if not is_finite(reference_mass) or absf(reference_mass - mass) > maxf(1.0e-12, absf(mass) * 1.0e-9):
		return {ok = false, message = "Normalized Glow liquid mass disagrees with its inventory item"}
	if not is_finite(capacity) or not is_finite(capacity_m3) or not is_finite(unusable) \
			or not is_finite(reserve) or not is_finite(start_fill) or capacity <= 0.0 \
			or reference_mass > capacity * (1.0 + 1.0e-9) or unusable < 0.0 or unusable >= capacity \
			or reserve < unusable or reserve > capacity \
			or absf(capacity - capacity_m3 * density) > maxf(1.0e-12, capacity * 1.0e-9) \
			or absf(start_fill - reference_mass / capacity) > 1.0e-9:
		return {ok = false, message = "Normalized Glow capacity, reserve, unusable mass or start fill is inconsistent"}
	var box_volume: float = size[0] * size[1] * size[2]
	if box_volume + 1.0e-12 < capacity_m3:
		return {ok = false, message = "Glow tank box cannot hold its normalized capacity"}
	var model_mass: Variant = model.get("mass_kg", null)
	var model_inertia: Variant = model.get("inertia", null)
	var cg: Variant = model.get("cg_inventory_le", null)
	if typeof(model_mass) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(model_mass)) or float(model_mass) <= reference_mass:
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
	var pickup_position := PackedFloat64Array()
	if normalized.has("pickup_position_inventory_le_m"):
		var pickup_values: Variant = normalized.get("pickup_position_inventory_le_m")
		var pickup_source: Variant = normalized.get("pickup_position_source")
		if not pickup_values is PackedFloat64Array or pickup_values.size() != 3 \
				or not pickup_source is Dictionary or _quantity_vector(pickup_source, "m") != pickup_values:
			return {ok = false, message = "Normalized Glow pickup position or provenance is malformed"}
		for coordinate: float in pickup_values:
			if absf(coordinate) > 3.0:
				return {ok = false, message = "Glow pickup position must lie within 3 m of the inventory datum"}
		pickup_position = PackedFloat64Array([cg[0] - pickup_values[0],
			pickup_values[1] - cg[1], cg[2] - pickup_values[2]])
	var tank_id: String = str(normalized_id)
	var dry: Dictionary = FuelMass.evaluate(float(model_mass), model_inertia, reference_mass, 0.0,
		position, size, capacity, tank_id)
	if not dry.get("ok", false):
		return {ok = false, message = "Glow dry fuel carrier mass properties are invalid"}
	return {ok = true, id = tank_id, liquid_id = str(liquid_id), shell_id = str(shell_id),
		mass_kg = reference_mass, capacity_kg = capacity,
		unusable_kg = unusable, reserve_kg = reserve, start_fill = start_fill, density_kg_m3 = density,
		position = position, size = size, dry_properties = dry, normalized = normalized.duplicate(true),
		has_pickup_position = normalized.has("pickup_position_inventory_le_m"),
		pickup_position = pickup_position,
		pickup_position_source = normalized.get("pickup_position_source", {})}


## Bind the optional normalized pre-primed line to its distinct liquid inventory item and fixed-datum geometry.
static func _fuel_line(raw: Dictionary, model: Dictionary, tank: Dictionary) -> Dictionary:
	var normalized: Variant = tank.normalized.get("feed_line", null)
	if not normalized is Dictionary:
		return {ok = false, message = "Normalized Glow feed line is malformed"}
	var line_id: Variant = normalized.get("id", null)
	var liquid_id: Variant = normalized.get("liquid_inventory_id", null)
	var fuel: Dictionary = tank.normalized
	if not line_id is String or line_id.strip_edges().is_empty() or not liquid_id is String \
			or liquid_id.strip_edges().is_empty() or line_id == tank.id or liquid_id in [tank.id, tank.liquid_id, tank.shell_id]:
		return {ok = false, message = "Glow feed line needs stable IDs distinct from its tank, liquid and shell"}
	if normalized.get("family") != "glow" or normalized.get("family") != fuel.get("family") \
			or normalized.get("density_kg_m3") != fuel.get("density_kg_m3"):
		return {ok = false, message = "Glow feed line blend family and density must match its tank"}
	var capacity: float = float(normalized.get("capacity_kg", NAN))
	var capacity_m3: float = float(normalized.get("capacity_m3", NAN))
	var reference: float = float(normalized.get("reference_mass_kg", NAN))
	var density: float = float(normalized.get("density_kg_m3", NAN))
	if not is_finite(capacity) or capacity <= 0.0 or capacity > tank.capacity_kg \
			or not is_finite(capacity_m3) or capacity_m3 <= 0.0 \
			or not is_finite(reference) or reference <= 0.0 or reference > capacity \
			or not is_finite(density) or density <= 0.0 \
			or absf(capacity - capacity_m3 * density) > maxf(1.0e-12, capacity * 1.0e-9):
		return {ok = false, message = "Glow feed-line capacity and authored fill are inconsistent"}
	var inventory: Variant = raw.get("inventory", null)
	if not inventory is Array:
		return {ok = false, message = "Glow feed line requires the validated inventory array"}
	var matches: Array[Dictionary] = []
	for item: Variant in inventory:
		if item is Dictionary and item.get("id") == liquid_id:
			matches.append(item)
	if matches.size() != 1:
		return {ok = false, message = "Glow feed-line liquid ID must resolve to exactly one inventory item"}
	var item: Dictionary = matches[0]
	var mass: float = _quantity(item.get("mass"), "kg")
	var source: Variant = normalized.get("source", null)
	var position: Variant = normalized.get("position_inventory_le_m", null)
	var size: Variant = normalized.get("size_m", null)
	var cg: Variant = model.get("cg_inventory_le", null)
	if item.get("energy_source") != "glow_fuel" or not is_finite(mass) \
			or absf(mass - reference) > maxf(1.0e-12, reference * 1.0e-9) \
			or mass > capacity or not source is Dictionary \
			or not source.has_all(["capacity", "mass", "position", "size"]) \
			or absf(_quantity(source.get("capacity"), "l") * 0.001 - capacity_m3) > 1.0e-12 \
			or absf(_quantity(source.get("mass"), "kg") - mass) > maxf(1.0e-12, mass * 1.0e-9) \
			or not position is PackedFloat64Array or position.size() != 3 \
			or not size is PackedFloat64Array or size.size() != 3 \
			or _quantity_vector(source.get("position"), "m") != position \
			or _quantity_vector(source.get("size"), "m") != size \
			or _quantity_vector(item.get("position"), "m") != position \
			or _quantity_vector(item.get("size"), "m") != size \
			or not cg is PackedFloat64Array or cg.size() != 3:
		return {ok = false, message = "Glow feed-line inventory quantity, blend or provenance is inconsistent"}
	var box_volume: float = size[0] * size[1] * size[2]
	if box_volume + 1.0e-12 < capacity_m3:
		return {ok = false, message = "Glow feed-line liquid box cannot hold its normalized capacity"}
	var center := PackedFloat64Array([cg[0] - position[0], position[1] - cg[1], cg[2] - position[2]])
	return {ok = true, line = {id = str(line_id), liquid_inventory_id = str(liquid_id),
		capacity_kg = capacity, capacity_m3 = capacity_m3, reference_mass_kg = reference,
		family = "glow", fuel = str(fuel.get("fuel", "")), density_kg_m3 = density,
		position = center, size = size.duplicate(), sample_store = {id = str(liquid_id),
		fuel = str(fuel.get("fuel", "")), family = "glow", density_kg_m3 = density,
		capacity_kg = capacity, unusable_kg = 0.0, reserve_kg = 0.0,
		reserve_estimated = false, kind = "feed_line"}, source = source.duplicate(true)}}


## NITRO-05: the fuel-feed block in body FRD about the wet-CG datum, with the premix density of the profile's fuel,
## its rated rpm and the needled head per unit gravity (level flight, full tank).
static func _fuel_feed(value: Variant, model: Dictionary, profile: Dictionary, tank: Dictionary) -> Dictionary:
	if not value is Dictionary or not _keys(value, FUEL_FEED.keys() + ["carburetor_position"]):
		return {ok = false, message = "Glow fuel_feed must hold exactly carburetor_position and the drive pressures"}
	var pressures: Dictionary = {}
	for key: String in FUEL_FEED:
		pressures[key] = _quantity(value.get(key), FUEL_FEED[key])
	var idle: float = pressures.get("idle_drive_pressure_pa", NAN)
	var wot: float = pressures.get("wot_drive_pressure_pa", NAN)
	if not is_finite(idle) or not is_finite(wot) or idle <= 0.0 or wot < idle or wot > MAX_DRIVE_PRESSURE_PA:
		return {ok = false, message = "Glow fuel_feed drive pressures must satisfy 0 < idle ≤ full throttle ≤ 100 kPa"}
	var position: PackedFloat64Array = _quantity_vector(value.get("carburetor_position"), "m")
	var cg: Variant = model.get("cg_inventory_le", null)
	if position.size() != 3 or not cg is PackedFloat64Array or cg.size() != 3:
		return {ok = false, message = "Glow fuel_feed carburetor_position must be a sourced [aft, right, up] metre vector"}
	var carburetor := PackedFloat64Array([cg[0] - position[0], position[1] - cg[1], cg[2] - position[2]])
	for coordinate: float in carburetor:
		if absf(coordinate) > 2.0:
			return {ok = false, message = "Glow carburetor must lie within 2 m of the centre of gravity"}
	var feed := {
		ok = true,
		carburetor_body_m = carburetor,
		idle_drive_pressure_pa = idle,
		wot_drive_pressure_pa = wot,
		density_kg_m3 = float(tank.density_kg_m3),
		rated_rpm = float(profile.operation.rated_rpm),
	}
	var needled := FuelFeed.needled_head_pa(feed, tank.position, tank.size, FuelFeed.STANDARD_GRAVITY)
	if idle + needled <= 0.0:
		return {ok = false, message = "Glow fuel_feed idle pressure cannot lift fuel to the carburetor in level flight"}
	return feed


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
