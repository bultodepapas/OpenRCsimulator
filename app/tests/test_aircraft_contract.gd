# AS-01/03: independent mutations at the public production load boundary.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Session := preload("res://sim/flight_session.gd")
var failures: int = 0
var checks: int = 0

func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL AS " + label + ": " + str(detail))

func raw_file(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func rejects(label: String, raw: Dictionary) -> void:
	var result: Dictionary = AD.validate_and_derive(raw)
	check(label, not result.ok and not result.errors.is_empty() and result.model.is_empty(), result.errors)

func object_paths(value: Variant, path: Array, result: Array) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		result.append(path.duplicate())
		for key: String in value:
			object_paths(value[key], path + [key], result)
	elif typeof(value) == TYPE_ARRAY:
		for index: int in value.size():
			object_paths(value[index], path + [index], result)

func at(value: Dictionary, path: Array) -> Dictionary:
	var node: Variant = value
	for key: Variant in path:
		node = node[key]
	return node

func _initialize() -> void:
	var paths: Array[String] = []
	for entry: Dictionary in Catalog.airplane_flyable_entries(): # TT-06: previews carry no data file
		paths.append(entry.data)
	for suffix: String in ["4s", "6s", "4s_battery", "6s_battery"]:
		paths.append("res://data/aircraft/synthetic_stik_electric_%s.json" % suffix)
	for path: String in paths:
		var raw: Dictionary = raw_file(path)
		check(path + " authored v2", raw.format == AD.FORMAT)
		var loaded: Dictionary = AD.load_file(path)
		check(path + " loads", loaded.ok, loaded.errors)
		if not loaded.ok:
			continue
		check("actual input format", loaded.input_identity.format == raw.format)
		check("actual input digest", loaded.input_identity.sha256 == FileAccess.get_sha256(path))
		check("explicit capabilities retained", loaded.model.capabilities == raw.capabilities)
		var old: Dictionary = AD.validate_and_derive(AD.legacy_v1_input(raw))
		# X8-03/04: elevons and the tailless law exist only in v2 (the shared parser needs the capability selections);
		# the historical adapter must refuse such a file rather than derive a different airplane.
		var v2_only_layout: bool = raw.capabilities.get("controls", "") == "elevon" or raw.capabilities.has("airframe_layout")
		if v2_only_layout:
			check(path + " v2-only layout refused by the legacy adapter", not old.ok)
		else:
			check("explicit legacy adapter loads", old.ok, old.errors)
		if old.ok and not v2_only_layout:
			# The v1 historical comparator cannot derive v2 tank bindings. Supply the
			# normalized view from this same validated v2 input as test adapter glue;
			# this does not make raw v2 data a supported v1 runtime contract.
			if loaded.model.has("fuel_system"):
				old.model.fuel_system = loaded.model.fuel_system.duplicate(true)
			# The historical adapter derives the common aircraft only. Attach the
			# explicit v2 glow module from the same validated input before comparing;
			# a v1 model alone cannot represent finite fuel or family identity.
			if raw.propulsion.get("engine", {}).has("glow_installation"):
				var installed_old: Dictionary = AD.GlowInstallation.attach(raw, old.model)
				check("explicit glow extension loads", installed_old.ok, installed_old.errors)
				if not installed_old.ok:
					continue
				old.model = installed_old.model
			# GP-03 profiles are attached at load_file's boundary, independently of the
			# v1/v2 aircraft adapter. Compare both adapters after the same profile step.
			var profiled_old: Dictionary = AD.WheelProfiles.apply_to_model(old.model)
			check("legacy wheel profile loads", profiled_old.ok, profiled_old.errors)
			var comparable: Dictionary = loaded.model.duplicate(true)
			# The legacy adapter has no flap module (v2-only, attached after it); flaps have their own law tests.
			# FUEL-03: fuel_system is likewise a v2-only module attached after the adapter (test_fuel_system_contract).
			# FUEL-08: normalized finite-consumption adapters are v2-only too; their behavior has dedicated mass/flow tests.
			for key: String in ["capabilities", "convention_id", "data_sha256", "physical_identity", "flaps", "fuel_system"]:
				comparable.erase(key)
			comparable.propulsion.erase("id")
			comparable.propulsion.erase("liquid_fuel")
			comparable.controls.erase("surface_ids")
			for contact: Dictionary in comparable.landing_gear.get("contacts", []):
				contact.erase("id")
			profiled_old.model.erase("data_sha256")
			profiled_old.model.erase("fuel_system")
			check(path + " same physical derivation", comparable == profiled_old.model)
		# Every object, including quantity/table metadata and each inventory component,
		# must reject a plausible-looking unconsumed tuning field.
		var nodes: Array = []
		object_paths(raw, [], nodes)
		for node_path: Array in nodes:
			var extra: Dictionary = raw.duplicate(true)
			at(extra, node_path)["unconsumed_tuning_gain"] = 1.0
			rejects("unknown " + str(node_path), extra)

	var stik: Dictionary = raw_file(Catalog.entry(Catalog.DEFAULT_ID).data)
	for key: String in ["id", "capabilities", "convention_id", "start", "reference", "inventory", "controls", "propulsion"]:
		var missing: Dictionary = stik.duplicate(true)
		missing.erase(key)
		rejects("missing " + key, missing)
		var null_value: Dictionary = stik.duplicate(true)
		null_value[key] = null
		rejects("null " + key, null_value)
	for bad: Variant in [null, {}, "EDF", 0, false]:
		var module: Dictionary = stik.duplicate(true)
		module.propulsion = bad
		rejects("wrong propulsion type " + str(bad), module)
	for future: String in ["edf", "single_pusher", "multiple_motors"]:
		var unsupported: Dictionary = stik.duplicate(true)
		unsupported.capabilities.propulsion_layout = future
		rejects("unsupported future layout " + future, unsupported)
	for field: String in ["landing_gear", "aero"]:
		var null_module: Dictionary = stik.duplicate(true)
		null_module[field] = null
		rejects("null module " + field, null_module)
	var contradiction: Dictionary = stik.duplicate(true)
	contradiction.capabilities.gear = "locked_up"
	rejects("inactive gear cannot have contacts", contradiction)
	contradiction.erase("landing_gear")
	var gear_up: Dictionary = AD.validate_and_derive(contradiction)
	check("explicit gear-up omits tire law", gear_up.ok and gear_up.model.landing_gear.is_empty(), gear_up.errors)
	contradiction = stik.duplicate(true)
	contradiction.erase("landing_gear")
	rejects("deployed gear needs module", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.capabilities.energy = "ocv_resistance"
	rejects("combustion cannot claim battery", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.propulsion.propeller.rotation = "counterclockwise_from_rear"
	rejects("unimplemented prop direction", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.aero.coefficients.CLadot = contradiction.aero.reference_coefficients.CLadot
	rejects("inert coefficient not an active knob", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.plausibility.inertia_reference.value[0] = 0.0
	rejects("zero inertia reference cannot divide", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.landing_gear.contacts[1].name = contradiction.landing_gear.contacts[0].name
	rejects("duplicate contact names", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.inventory[0].mass.value = NAN
	rejects("nonfinite mass", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.inventory[0].mass.value = true
	rejects("boolean is not number", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.controls.max_throw.aileron.unit = "rad"
	rejects("no implicit unit conversion", contradiction)
	contradiction = stik.duplicate(true)
	contradiction.inventory[0].size.value = [0.0, 0.0, 0.0]
	check("explicit point mass is valid zero", AD.validate_and_derive(contradiction).ok)
	check("zero main steering is valid", stik.landing_gear.contacts[0].max_steering.value == 0.0)
	var inverted_gear: Dictionary = stik.duplicate(true)
	inverted_gear.capabilities.gear = "fixed_taildragger"
	for contact: Dictionary in inverted_gear.landing_gear.contacts:
		contact.max_steering.value = 0.0
	rejects("all-zero steering cannot disguise tricycle support topology", inverted_gear)
	for version: String in ["openrc-aircraft v3", "", "v2"]:
		contradiction = stik.duplicate(true)
		contradiction.format = version
		rejects("unknown version", contradiction)

	# The selected visual identity follows setup AND reload. Candidate failure must
	# preserve the previous model and simulation bytes, not just return an error.
	var flight: Node = Session.new()
	flight.input_enabled = false
	flight.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	check("selected identity starts", flight.is_flyable())
	if flight.is_flyable():
		var state: PackedByteArray = flight.sim.state.to_byte_array()
		var aux: PackedByteArray = flight.sim.aux.to_byte_array()
		var before_id: String = flight.aircraft.model.id
		flight.aircraft_path = Catalog.entry("gp-extra-300s-60").data
		var message: String = flight.reload()
		check("wrong identity reload refused", message.contains("identity mismatch"), message)
		check("failed identity reload preserves aircraft", flight.aircraft.model.id == before_id)
		check("failed identity reload preserves state", state == flight.sim.state.to_byte_array() and aux == flight.sim.aux.to_byte_array())
	flight.free()
	print("AS aircraft contract: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
