## Closed opt-in aircraft extension. Source files are fingerprinted with the loaded engine profile.
extends RefCounted
const Profile := preload("res://physics/glow/profile.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
const SETTINGS := {idle_admission="1",servo_time_constant_s="s",air_time_constant_s="s",
	fuel_transport_time_constant_s="s",stall_rpm="rpm",minimum_start_rpm="rpm",
	temperature_firing_min_k="K",temperature_firing_full_k="K",lean_misfire_zero_ratio="1",
	lean_misfire_start_ratio="1",rich_misfire_start_ratio="1",rich_misfire_zero_ratio="1"}
const THERMAL := {heat_capacity_j_k="J/K",head_heat_fraction="1",cooling_base_w_k="W/K",
	cooling_airflow_w_s_m_k="W/(K m/s)",premix_evaporation_j_kg="J/kg",evaporation_head_fraction="1"}
const PROPELLER := {diameter_m="m",pitch_m="m",chord_m="m",blades="1",lift_slope="1/rad",cd0="1",induced_drag="1"}

static func attach(raw: Dictionary, model: Dictionary) -> Dictionary:
	var path: Variant = raw.propulsion.engine.get("glow_installation")
	if not path is String or not path.begins_with("res://data/glow/") or ".." in path:
		return _fail("glow_installation must identify a bundled glow data file")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not value is Dictionary or not _keys(value,["format","family","profile","fuel_inventory","settings","initial_temperature_k","propeller"]):
		return _fail("Malformed glow installation")
	if value.format!="openrc-glow-installation v1" or value.family not in ["glow_2t","glow_4t"] or not value.profile is String or not value.profile.begins_with("res://data/glow/") or ".." in value.profile:
		return _fail("Unsupported glow installation family/format/profile")
	var loaded: Dictionary=Profile.load_file(value.profile)
	if not loaded.ok or loaded.model.family!=value.family:
		return _fail("Invalid or mismatched glow engine profile")
	if not value.settings is Dictionary or not _keys(value.settings,SETTINGS.keys()+["thermal"]):
		return _fail("Glow lifecycle settings missing/unknown")
	var scalar_settings: Dictionary=value.settings.duplicate(true)
	scalar_settings.erase("thermal")
	var settings: Dictionary=_group(scalar_settings,SETTINGS)
	var thermal: Dictionary=_group(value.settings.thermal,THERMAL)
	var prop: Dictionary=_group(value.propeller,PROPELLER)
	var temperature: float=_quantity(value.initial_temperature_k,"K")
	if settings.is_empty() or thermal.is_empty() or prop.is_empty() or not is_finite(temperature) or temperature<200.0 or temperature>600.0:
		return _fail("Invalid glow installation quantity/unit/provenance")
	settings.thermal=thermal
	if settings.idle_admission<=0.0 or settings.idle_admission>=1.0 or settings.stall_rpm>=settings.minimum_start_rpm or settings.minimum_start_rpm>=loaded.model.operation.max_rpm:
		return _fail("Invalid glow idle/start envelope")
	if minf(settings.servo_time_constant_s,minf(settings.air_time_constant_s,settings.fuel_transport_time_constant_s))<0.02:
		return _fail("Glow transport is outside qualified 240 Hz timestep envelope")
	if settings.temperature_firing_min_k>=settings.temperature_firing_full_k or settings.lean_misfire_zero_ratio>=settings.lean_misfire_start_ratio or settings.lean_misfire_start_ratio>=1.0 or settings.rich_misfire_start_ratio<=1.0 or settings.rich_misfire_start_ratio>=settings.rich_misfire_zero_ratio:
		return _fail("Unordered glow stability thresholds")
	if thermal.head_heat_fraction>1.0 or thermal.evaporation_head_fraction>1.0 or prop.blades!=2.0 or absf(prop.diameter_m-model.propulsion.diameter)>1e-12:
		return _fail("Unsupported blade count, diameter mismatch or heat partition")
	var matches: Array=[]
	for item: Dictionary in raw.inventory:
		if item.name==value.fuel_inventory: matches.append(item)
	if matches.size()!=1 or matches[0].get("energy_source")!="glow_fuel":
		return _fail("Glow fuel tank must name one explicit glow_fuel inventory item")
	var tank: Dictionary=matches[0]
	var cg: PackedFloat64Array=model.cg_inventory_le
	var position:=PackedFloat64Array([cg[0]-tank.position.value[0],tank.position.value[1]-cg[1],cg[2]-tank.position.value[2]])
	var size:=PackedFloat64Array(tank.size.value)
	var mass: float=tank.mass.value
	var dry: Dictionary=FuelMass.evaluate(model.mass_kg,model.inertia,mass,0.0,position,size)
	if not dry.ok or model.propulsion.rotor_inertia<=0.0 or model.propulsion.rotor_inertia>=dry.inertia[0]:
		return _fail("Glow dry carrier inertia is invalid")
	var hashing:=HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	var install: Dictionary={profile=loaded.model,settings=settings,propeller=prop,
		initial_temperature_k=temperature,initial_fuel_kg=mass,tank_position=position,tank_size=size,
		identity={format=value.format,sha256=hashing.finish().hex_encode(),profile=loaded.input_identity},provenance=value}
	var out: Dictionary=model.duplicate(true)
	out.propulsion.glow=install
	return {ok=true,model=out}

static func _group(value: Variant, spec: Dictionary) -> Dictionary:
	if not value is Dictionary or not _keys(value,spec.keys()): return {}
	var out: Dictionary={}
	for key in spec:
		var number: float=_quantity(value[key],spec[key])
		if not is_finite(number) or number<=0.0: return {}
		out[key]=number
	return out

static func _quantity(value: Variant, unit: String) -> float:
	if not value is Dictionary or not _keys(value,["value","unit","kind","source"]): return NAN
	if value.unit!=unit or value.kind not in Profile.KINDS or not value.source is String or value.source.strip_edges().is_empty() or typeof(value.value) not in [TYPE_FLOAT,TYPE_INT]: return NAN
	return float(value.value)

static func _keys(value: Dictionary, keys: Array) -> bool:
	return value.size()==keys.size() and value.has_all(keys)

static func _fail(message: String) -> Dictionary:
	return {ok=false,errors=PackedStringArray([message]),model={}}
