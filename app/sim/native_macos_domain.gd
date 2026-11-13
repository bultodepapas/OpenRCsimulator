## Structural screen for the named Mac fixed-wing fleet; not proof for arbitrary flight states or input tapes.
## The caller must separately bind the engine, signed binary, profile evidence and every live transition.
extends RefCounted

const WindConfig := preload("res://physics/wind_config.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const Scenery := preload("res://scenery/scenery.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const NativeWeather := preload("res://sim/native/native_weather.gd")

const STOCK_WORLD := "ea0bdec4c9ae6307f0c6a1cac39c89c950526ef4288556169b36a283335e1048"
const STOCK_LAKE := "bcc3774dc2ef339bac49aaec42b6a47b6b6d1104470d9fff35db242f6ab61efa"
const STOCK_WORLD_PROXIES := 6092
const MAX_CONTEXT_BYTES := 64 * 1024 * 1024
const MAX_START_FIELDS := 64
const MAX_START_BYTES := 8 * 1024
const WEATHER_IDS := ["calm", "steady", "crosswind", "gusty", "updraft", "turbulent", "hot-high", "cool-dense",
	"gentle-practice", "standard-column", "spatial-crosswind-v1", "spatial-gusty-v1", "spatial-light-breeze-v1",
	"spatial-realistic-v1", "spatial-shear-v1", "spatial-strong-wind-v1", "spatial-thermal-soaring-v2"]

# Exact aircraft bytes observed in the retained source10 fleet. Unknown modes and future catalog entries fail closed.
const AIRCRAFT := {
	"jensen-das-ugly-stik-60": {"ideal": ["res://data/aircraft/jensen_ugly_stik_60.json", "5635e7f7b2a44bdfc7db5ad2646c74654af42944133bc39a91a0908bac887b66"]},
	"stik-glow-61fx-2t": {"ideal": ["res://data/aircraft/stik_glow_61fx_2t.json", "a214c7d144f3b1a978a01f9f52bb80d2ce76de27644c1d8571d669f291a05350"]},
	"stik-glow-55ax-2t": {"ideal": ["res://data/aircraft/stik_glow_55ax_2t.json", "a71cf12e61a511a868b6e7ff005e116f1fe6cc57633c47850b9ae02d1838d0b9"]},
	"stik-glow-fs64v-4t": {"ideal": ["res://data/aircraft/stik_glow_fs64v_4t.json", "47c0972622f328dbeb62c64fcde0f13057414c18a026cd9c1e74499096b885d8"]},
	"stik-electric-6s": {
		"ideal": ["res://data/aircraft/stik_electric_6s.json", "830137e2daaf43295c404ad0af6676ac44a8fb0102c2d2b81c2c0b4a395337e6"],
		"pack": ["res://data/aircraft/battery/stik_electric_6s_pack.json", "fbbfd74512b8e3141adc530296687721c5ca7e3d94a38c384fbaf10f03c2c73e"]},
	"gp-extra-300s-60": {"ideal": ["res://data/aircraft/gp_extra_300s_60.json", "0f1824940a58aa121bf001ccbf74234c0473a59a607561b0b91ad2b6fc912edf"]},
	"p51d-mustang-120": {"ideal": ["res://data/aircraft/p51d_mustang_120.json", "45a9b854007e4ceed22f4c8ad8bcff166904ef3bb5c23c87f308174e6b31489c"]},
	"f4u-corsair-250": {"ideal": ["res://data/aircraft/f4u_corsair_250.json", "52ec066763aa05baca356737bedb1150c18562b9618b611bfbb6ce305e517f10"]},
	"sebart-avanti-s-a200-p100rx": {"ideal": ["res://data/aircraft/sebart_avanti_s_a200.json", "77674df18312f6235352a28a797c497013ef18451a41eb0141e3f16dffd220b9"]},
	"turbo-lumber-evolution": {
		"ideal": ["res://data/aircraft/turbo_lumber_evolution.json", "3d47e8c4c40665a0b1e2123c8eb1c8919697ca5b2f931472b02e85897d8bc46c"],
		"pack": ["res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json", "63c9fe2d2c89e88eb1d3248115716356a92994ae25e105db3709b364da0dcc53"]},
	"moonrunner-x99": {
		"ideal": ["res://data/aircraft/moonrunner_x99.json", "051b63f37dcd57cd39a7bb3c37ec38ddbc6176eeba9126eec96a0dc21f30ba7c"],
		"pack": ["res://data/aircraft/battery/moonrunner_x99_6s_pack.json", "2df4233db38a2f964fe87db0bba11d91463918dd5d0823c5db37f90062d6d3c0"]},
}
const STIKS := ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"]
const GLOW_STIKS := ["stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"]
const CROSSWIND_RUNWAY := ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t",
	"stik-glow-fs64v-4t", "stik-electric-6s", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx", "turbo-lumber-evolution"]


static func _refusal(reason: String, profile: String = "") -> Dictionary:
	return {ok = false, reason = reason, profile = profile}


## Trim results are small flat dictionaries. Reject unexpected nested or oversized
## values before encoding so a changed live start cannot cause an unbounded tick check.
static func _start_bytes(start: Variant) -> PackedByteArray:
	if not start is Dictionary or start.is_empty() or start.size() > MAX_START_FIELDS:
		return PackedByteArray()
	var estimated_bytes: int = 128 + start.size() * 48
	for key: Variant in start:
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]: return PackedByteArray()
		var key_text := str(key)
		if key_text.length() > 128: return PackedByteArray()
		estimated_bytes += key_text.length() * 4
		var value: Variant = start[key]
		match typeof(value):
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
				pass
			TYPE_STRING, TYPE_STRING_NAME:
				var value_text := str(value)
				if value_text.length() > 1024: return PackedByteArray()
				estimated_bytes += value_text.length() * 4
			TYPE_PACKED_FLOAT64_ARRAY:
				if key_text != "state" or value.size() != 13: return PackedByteArray()
				estimated_bytes += value.size() * 8
			_:
				return PackedByteArray()
		if estimated_bytes > MAX_START_BYTES: return PackedByteArray()
	if not start.get("state") is PackedFloat64Array or start.state.size() != 13:
		return PackedByteArray()
	var encoded := var_to_bytes(start)
	return encoded if not encoded.is_empty() and encoded.size() <= MAX_START_BYTES else PackedByteArray()


## The same exact encoding is recorded independently by both fleet trials.
static func start_sha256(start: Variant, production: bool = false) -> String:
	if production and (not start is Dictionary or typeof(start.get("requested_throttle")) != TYPE_FLOAT \
			or start.requested_throttle != 0.5):
		return ""
	var encoded := _start_bytes(start)
	if encoded.is_empty(): return ""
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(encoded)
	return digest.finish().hex_encode()


static func _weather_id(config: Variant) -> String:
	if not config is Dictionary:
		return ""
	var observed: Dictionary = WindConfig.validate(config)
	if not observed.get("ok", false):
		return ""
	var found := ""
	for id: String in WEATHER_IDS:
		var candidate: Dictionary = WindConfig.validate(WindConfig.preset(id))
		if candidate.get("ok", false) and var_to_bytes(observed.config) == var_to_bytes(candidate.config):
			if not found.is_empty(): return "" # Ambiguous presets must not silently select one.
			found = id
	return found


## Inputs must be read from the committed session. This structural classifier does not verify the world or loader.
## `production_qualified` is supplied only by the caller's separately verified matching qualification receipt.
static func screen(selection: Dictionary, production_qualified: bool = false) -> Dictionary:
	var vehicle: Variant = selection.get("vehicle")
	if typeof(vehicle) != TYPE_STRING or vehicle != "fixed-wing" or typeof(selection.get("soft_hull")) != TYPE_BOOL:
		return _refusal("fixed-wing and an explicit contact mode are required")
	var id: Variant = selection.get("aircraft")
	var battery: Variant = selection.get("battery")
	if typeof(id) != TYPE_STRING or typeof(battery) != TYPE_STRING or not AIRCRAFT.has(id) or not AIRCRAFT[id].has(battery):
		return _refusal("aircraft or battery is outside the screened stock catalog")
	var stock: Array = AIRCRAFT[id][battery]
	if typeof(selection.get("path")) != TYPE_STRING or typeof(selection.get("aircraft_sha256")) != TYPE_STRING \
			or selection.path != stock[0] or selection.aircraft_sha256 != stock[1] \
			or not FileAccess.file_exists(stock[0]) or FileAccess.get_sha256(stock[0]) != stock[1]:
		return _refusal("aircraft bytes do not match the screened stock input")
	var throttle: Variant = selection.get("trim_throttle")
	if typeof(throttle) != TYPE_FLOAT:
		return _refusal("trim profile is missing or malformed")
	var profile := "reference" if is_nan(throttle) else ("production" if throttle == 0.5 else "")
	if profile.is_empty():
		return _refusal("custom trim throttle is outside the screened profiles")
	if profile == "production" and not production_qualified:
		return _refusal("production trim profile requires matching qualification", profile)
	var start: Variant = selection.get("start")
	var allowed_starts := ["airborne", "airborne_half_power", "hand_launch"] if id == "moonrunner-x99" \
		else ["airborne", "airborne_half_power", "runway"]
	if typeof(start) != TYPE_STRING or start not in allowed_starts:
		return _refusal("start is outside the screened stock catalog", profile)
	var weather := _weather_id(selection.get("weather"))
	if weather.is_empty():
		return _refusal("weather is not an exact screened preset", profile)
	if start == "runway" and ((weather == "crosswind" and id in CROSSWIND_RUNWAY) \
			or (weather == "spatial-crosswind-v1" and (id in STIKS or id == "stik-electric-6s")) \
			or (weather == "gusty" and id in GLOW_STIKS)):
		return _refusal("runway scenario remains open in the Mac fleet", profile)
	if id == "moonrunner-x99" and ((battery == "pack" and start == "hand_launch" and weather == "spatial-crosswind-v1") \
			or (battery == "ideal" and start == "airborne_half_power" and weather == "hot-high")):
		return _refusal("MoonRunner scenario remains open in the Mac fleet", profile)
	return {ok = true, reason = "", profile = profile, aircraft = id, battery = battery, start = start, weather = weather}


## Full one-time selection check, before native preparation. Live changes require the caller's own safe-boundary guard.
static func screen_session(session: Node, production_qualified: bool = false) -> Dictionary:
	if not is_instance_valid(session) or session.get_script() == null \
			or session.get_script().resource_path != "res://sim/flight_session.gd" or session.get("sim") == null:
		return _refusal("only a committed fixed-wing FlightSession can be screened")
	if session.sim.dt() != 1.0 / 240.0:
		return _refusal("the screened fleet uses the fixed 240 Hz timestep")
	var aircraft: Variant = session.get("aircraft")
	if not aircraft is Dictionary or not aircraft.get("ok", false) or not aircraft.get("model") is Dictionary:
		return _refusal("aircraft is not committed")
	if not session.get("_frozen_aircraft").is_empty() or not session.get("workshop_identity").is_empty() \
			or session.get("_failures") != null or not session.get("_out_of_trim").is_empty() \
			or session.get("_airframe_offset") != PackedFloat64Array([0.0, 0.0, 0.0]) \
			or session.get("_shaft_explicit") or session.get("_external_spawn_heading_set") \
			or session.get("fuel_start_fill") != 1.0 or not session.get("_rc_track").is_empty():
		return _refusal("custom flight configuration is outside the screened stock scope")
	var id: String = str(session.get("expected_aircraft_id"))
	var path: String = str(session.get("aircraft_path"))
	var battery := ""
	if AIRCRAFT.has(id):
		for mode: String in AIRCRAFT[id]:
			if AIRCRAFT[id][mode][0] == path: battery = mode
	var identity: Variant = aircraft.get("input_identity")
	if not identity is Dictionary or identity.get("format") != "openrc-aircraft v2" \
			or aircraft.model.get("id") != id:
		return _refusal("stock aircraft identity is missing")
	var result := screen({vehicle = "fixed-wing", aircraft = id, battery = battery, path = path,
		aircraft_sha256 = identity.get("sha256"), start = session.get("start_choice"),
		trim_throttle = session.get("trim_throttle"), weather = session.weather_configuration(),
		soft_hull = session.get("soft_hull_contacts")}, production_qualified)
	if not result.ok: return result
	var stock_aircraft: Dictionary = AircraftData.load_file(path)
	if not stock_aircraft.get("ok", false) or var_to_bytes(stock_aircraft.model) != var_to_bytes(aircraft.model):
		return _refusal("live aircraft differs from its stock bytes", result.profile)
	var start: Variant = session.get("start")
	var start_sha := start_sha256(start, result.profile == "production")
	if start_sha.is_empty():
		return _refusal("start is not the bounded qualified trim result", result.profile)
	if not start is Dictionary or not start.get("state") is PackedFloat64Array \
			or start.state.size() != 13 or start.state[0] != 60.0 or start.state[1] != -40.0 or start.state[2] != -30.0:
		return _refusal("custom spawn is outside the screened stock scope", result.profile)
	result.start_sha256 = start_sha
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from()
	if not field.get("ok", false) or not lake.get("ok", false) \
			or var_to_bytes(field.field) != var_to_bytes(session.get("_runway_field")) \
			or var_to_bytes(lake.lake) != var_to_bytes(session.lake_context()) \
			or lake.lake.get("identity") != STOCK_LAKE:
		return _refusal("field or lake differs from the screened stock context", result.profile)
	var table: Dictionary = GroundSurfaces.load_table(GroundSurfaces.DEFAULT_PATH)
	var surfaces: Dictionary = GroundSurfaces.build(table.table, field.field) if table.get("ok", false) else {}
	var airframe: Dictionary = GroundSurfaces.build_airframe(table.table, field.field) if table.get("ok", false) else {}
	if not surfaces.get("ok", false) or not airframe.get("ok", false) \
			or var_to_bytes(surfaces.rects) != var_to_bytes(session.ground_surfaces) \
			or var_to_bytes(airframe.rects) != var_to_bytes(session.airframe_surfaces):
		return _refusal("contact surfaces differ from the screened stock context", result.profile)
	var options: Dictionary = Scenery.options()
	if not options.get("enabled", false) or options.get("file_explicit", true) \
			or options.get("file") != SceneryLoader.DEFAULT_PATH:
		return _refusal("custom or disabled scenery is outside the screened stock context", result.profile)
	var world: Dictionary = CollisionSetup.build(field.field)
	var actual: Variant = session.get("_collision_world")
	if not world.get("ok", false) or not actual is Dictionary or actual.get("identity") != STOCK_WORLD \
			or not actual.get("proxies") is Array or actual.proxies.size() != STOCK_WORLD_PROXIES \
			or var_to_bytes(world.world) != var_to_bytes(actual):
		return _refusal("collision world differs from the screened stock context", result.profile)
	return result


class Guard:
	extends RefCounted
	var owner: Node
	var sim: Node
	var world: Dictionary
	var field: Dictionary
	var aircraft_id: String
	var aircraft_path: String
	var start_choice: String
	var start_state: PackedFloat64Array
	var start_bytes: PackedByteArray
	var trim_throttle: float
	var soft_hull: bool


## Deserialization detaches the context. New packed-array aliases can still mutate it;
## the separately prepared native packed-leaf guard must be checked on every automatic tick.
static func _detached_read_only(value: Dictionary) -> Dictionary:
	var encoded := var_to_bytes(value)
	if encoded.is_empty() or encoded.size() > MAX_CONTEXT_BYTES:
		return {}
	var detached: Variant = bytes_to_var(encoded)
	if not detached is Dictionary or var_to_bytes(detached) != encoded:
		return {}
	NativeWeather._freeze_containers(detached)
	return detached


## The caller must stage returned world and field in a rollback-capable owner transaction before using the guard.
## This function does not mutate the live session or any input container.
static func freeze_for_session(session: Node, production_qualified: bool = false) -> Dictionary:
	var selected := screen_session(session, production_qualified)
	if not selected.ok: return selected
	var world := _detached_read_only(session.get("_collision_world"))
	var field := _detached_read_only(session.get("_runway_field"))
	if world.is_empty() or field.is_empty() or not world.is_read_only() or not field.is_read_only():
		return _refusal("stock context could not be detached and frozen", selected.profile)
	var guard := Guard.new()
	guard.owner = session
	guard.sim = session.sim
	guard.world = world
	guard.field = field
	guard.aircraft_id = session.expected_aircraft_id
	guard.aircraft_path = session.aircraft_path
	guard.start_choice = session.start_choice
	guard.start_state = session.start.state.duplicate()
	guard.start_bytes = _start_bytes(session.start)
	if guard.start_bytes.is_empty() or start_sha256(session.start, selected.profile == "production") != selected.start_sha256:
		return _refusal("start changed while the stock context was prepared", selected.profile)
	guard.trim_throttle = session.trim_throttle
	guard.soft_hull = session.soft_hull_contacts
	return {ok = true, reason = "", profile = selected.profile, world = world, field = field, guard = guard}


## O(1) in world size. Native packed-leaf, configuration and weather guards remain required.
static func guard_matches(session: Node, guard: Variant) -> bool:
	if not guard is Guard or not is_instance_valid(session) or session != guard.owner \
			or session.get("sim") != guard.sim or not is_same(session.get("_collision_world"), guard.world) \
			or not is_same(session.get("_runway_field"), guard.field) or not guard.world.is_read_only() \
			or not guard.field.is_read_only():
		return false
	if session.expected_aircraft_id != guard.aircraft_id or session.aircraft_path != guard.aircraft_path \
			or session.start_choice != guard.start_choice or session.soft_hull_contacts != guard.soft_hull \
			or session.sim.dt() != 1.0 / 240.0 or session.fuel_start_fill != 1.0 or session.get("_failures") != null \
			or not session.get("_frozen_aircraft").is_empty() or not session.get("workshop_identity").is_empty() \
			or not session.get("_out_of_trim").is_empty() or not session.get("_rc_track").is_empty() \
			or session.get("_shaft_explicit") or session.get("_shaft_pending_reset") \
			or session.get("_external_spawn_heading_set"):
		return false
	var offset: Variant = session.get("_airframe_offset")
	if not offset is PackedFloat64Array or offset.size() != 3 or offset[0] != 0.0 or offset[1] != 0.0 or offset[2] != 0.0:
		return false
	if is_nan(guard.trim_throttle):
		if not is_nan(session.trim_throttle): return false
	elif session.trim_throttle != guard.trim_throttle:
		return false
	var current_start := _start_bytes(session.get("start"))
	return not current_start.is_empty() and current_start == guard.start_bytes
