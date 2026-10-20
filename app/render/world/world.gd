# FIELD-WORLD-PLAN FW-02: the one place that composes the world around an aircraft: the environment (sky, ambient
# light, tonemap, haze), the validated field and the sun, always in this order. Flight (main.gd), Home, the scenery
# evidence views and the runway scenario call it; nothing else creates the flight Environment or the sun, so a new
# world feature (time of day, moon, field lights) is added here once instead of at every call site.
extends RefCounted

const Atmosphere := preload("res://render/atmosphere.gd")
const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")
const FieldBuilder := preload("res://render/field.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const MoonConfig := preload("res://environment/moon_config.gd")
const Stars := preload("res://render/world/stars.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const AircraftLightState := preload("res://render/world/aircraft_light_state.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const Exposure := preload("res://render/world/exposure.gd")
const LandscapeOptions := preload("res://render/landscape_upgrade/options.gd")
const SunGlare := preload("res://render/landscape_upgrade/sun_glare.gd")
const AirfieldLighting := preload("res://render/landscape_upgrade/airfield_lighting.gd")
const SceneryLayer := preload("res://scenery/scenery.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const StormBank := preload("res://render/weather/storm_bank.gd")

## The club switches its field lights on at dusk (FW-31…34): sun below this elevation in time-of-day mode.
const FIELD_LIGHTS_BELOW_SUN_DEG := 3.0
## LU-03: explicit TOD uses fixed SDR exposure rather than FW eye adaptation. View-light gain is an
## appearance estimate; the helper applies the same bounded displayed energy in either lighting path.
const SNAPSHOT_LOCAL_LIGHT_GAIN := 1000.0
## Eye adaptation to what the camera looks at (FW-23): the exposure follows the light falling on the view target (the
## airplane) in log space, fast toward light and slow back to dark, on simulation time so pauses and replays hold it.
## Rates are game estimates (real dark adaptation takes minutes). A first call, a restart or a jump > MAX_STEP_S snaps.
const ADAPT_TO_LIGHT_PER_S := 2.0
const ADAPT_TO_DARK_PER_S := 0.35
const ADAPT_MAX_STEP_S := 5.0
## Exposure changes below this (log) are not pushed to the renderer.
const ADAPT_PUSH_LOG := 0.02
## Share of the lit ground's light that counts when the ground fills the whole view (estimate, from captures: the
## floodlit ground clipped while the eye followed a dark airplane). Scaled by the screen share below the horizon.
const ADAPT_GROUND_WEIGHT := 0.5

static var _night_profile := "club"
static var _night_options := {field_lighting = "club", field_activation = "auto", campfire = false}
static var _night_owner: WeakRef
static var _night_helper: WeakRef
static var _night_fire: WeakRef
static var _night_legacy_lights: WeakRef
static var _lights := {}
static var _ground_light := 0.0 # floods' light on the runway centre (scene units), computed once per build
static var _adapt_clock := -1.0
static var _adapt_log := 0.0
## The night kit is fitted from dusk (FW-35): sun below this elevation in time-of-day mode.
const NIGHT_KIT_BELOW_SUN_DEG := 6.0

## Stars are only built once the sun is this low (above it the exposure leaves them invisible; saves the draw).
const STARS_BELOW_SUN_DEG := 2.0
## FW-61 time flows: the sky is re-evaluated every FLOW_STEP_SKY_S of sky time (at ×20, every 1.5 s of flight: the sun
## moves ~0.1° per step, below what the eye notices). A session that starts below FLOW_AGX_BELOW_SUN_DEG keeps AgX
## throughout, so the tonemapper never switches mid-flight (FW-26).
const FLOW_STEP_SKY_S := 30.0
const FLOW_AGX_BELOW_SUN_DEG := 10.0
## FW-MOON-06d frame_state: the slow sky terms interpolated between steps. Colours and exposure terms geometrically,
## shape terms linearly; the lobes only while the brighter lobe stays on the same side (dot of the two steps' lobe
## directions above LOBE_SWAP_DOT; one step moves it ~0.1°).
const FRAME_COLOUR_KEYS := ["zenith_lin", "haze_lin", "cloud_lin", "ambient_lin", "moon_lin", "moon_earthshine", "moon_aureole_lin",
	"moon_eclipse_factor"]
const FRAME_SCALAR_KEYS := ["exposure", "gain", "adapt_y", "adapt_y_anchor", "moon_display_scale"]
const FRAME_LINEAR_KEYS := ["moon_radius", "moon_squash", "moon_display_gamma", "moon_phase_l", "moon_phase_k", "moon_umbra_radius",
	"moon_penumbra_radius"]
const LOBE_SWAP_DOT := 0.99
## frame_sky_needed thresholds (estimates; see FW-MOON-06d evidence).
const FRAME_SKY_MIN_LOG := 0.004
const FRAME_SKY_LOW_LIGHT_DEG := 20.0

## Time-flow session: {} when frozen. Keys: when, time_scale, step, environment, sun, stars, lights_node, materials,
## tonemapper, start_lst, latitude.
static var _flow := {}
## FW-MOON-12: the moon choices of the current world, the time before a phase choice moved its date, and weak
## references for applying a new choice in place (set_moon_config).
static var _moon_config: Dictionary = MoonConfig.defaults()
static var _base_when := {}
static var _live := {}

const PRESENTATION_CONTEXT_FORMAT := "openrc-world-presentation v1"


## Captures the one active world's mutable presentation state before a temporary world is built.
## Object pointers are weak references so a context never keeps a discarded candidate scene alive.
static func presentation_context() -> Dictionary:
	return {
		"format": PRESENTATION_CONTEXT_FORMAT,
		"night_profile": _night_profile,
		"night_options": _night_options.duplicate(true),
		"night_owner": _weak_context_ref(_night_owner),
		"night_helper": _weak_context_ref(_night_helper),
		"night_fire": _weak_context_ref(_night_fire),
		"night_legacy_lights": _weak_context_ref(_night_legacy_lights),
		"lights": _lights.duplicate(true),
		"ground_light": _ground_light,
		"adapt_clock": _adapt_clock,
		"adapt_log": _adapt_log,
		"flow": _capture_flow_context(),
		"atmosphere_state": Atmosphere.state.duplicate(true),
		"exposure": Exposure.last,
		"shader_clock": {"clock": ShaderClock.last_clock, "wind": ShaderClock.last_wind},
	}


## Restores a captured active-world context. Invalid weak references are dropped; a broken active flow is
## disabled rather than left pointing into a freed trial scene. The caller owns only one retained context.
static func restore_presentation_context(context: Variant) -> bool:
	if not context is Dictionary or str(context.get("format", "")) != PRESENTATION_CONTEXT_FORMAT:
		return false
	var profile := str(context.get("night_profile", ""))
	var options: Variant = context.get("night_options")
	var lights: Variant = context.get("lights")
	var state: Variant = context.get("atmosphere_state")
	var shader_clock: Variant = context.get("shader_clock")
	if not profile in ["club", "airfield", "off"] or not options is Dictionary or not lights is Dictionary \
			or not state is Dictionary or not shader_clock is Dictionary:
		return false
	if not options.get("field_lighting", "") in ["club", "airfield", "off"] \
			or not options.get("field_activation", "auto") in ["auto", "on", "off"] \
			or not options.get("campfire", false) is bool:
		return false
	if not shader_clock.get("clock", NAN) is float and not shader_clock.get("clock", NAN) is int:
		return false
	if not shader_clock.get("wind", null) is Vector3:
		return false
	var flow_raw: Variant = context.get("flow")
	if not flow_raw is Dictionary:
		return false
	var restored_flow := _restore_flow_context(flow_raw)
	var flow_ok: bool = flow_raw.is_empty() or not restored_flow.is_empty()
	var exposure_value := float(context.get("exposure", NAN))
	if is_nan(exposure_value) or is_inf(exposure_value):
		return false
	var ground_light := float(context.get("ground_light", NAN))
	var adapt_clock := float(context.get("adapt_clock", NAN))
	var adapt_log := float(context.get("adapt_log", NAN))
	if is_nan(ground_light) or is_inf(ground_light) or is_nan(adapt_clock) or is_inf(adapt_clock) \
			or is_nan(adapt_log) or is_inf(adapt_log):
		return false

	_night_profile = profile
	_night_options = options.duplicate(true)
	_night_owner = _weak_context_ref(context.get("night_owner"))
	_night_helper = _weak_context_ref(context.get("night_helper"))
	_night_fire = _weak_context_ref(context.get("night_fire"))
	_night_legacy_lights = _weak_context_ref(context.get("night_legacy_lights"))
	_lights = lights.duplicate(true)
	_ground_light = ground_light
	_adapt_clock = adapt_clock
	_adapt_log = adapt_log
	_flow = restored_flow if flow_ok else {}
	Atmosphere.state = state.duplicate(true)
	Exposure.set_value(exposure_value)
	ShaderClock.update(float(shader_clock.clock), shader_clock.wind)
	# Reapply the restored selection to the still-live scene-owned helpers and owner metadata.
	set_night_options(_night_profile, bool(_night_options.campfire), str(_night_options.get("field_activation", "auto")))
	return flow_ok


static func _weak_context_ref(value: Variant) -> Variant:
	if value == null:
		return null
	if value is WeakRef:
		var target: Variant = value.get_ref()
		return value if target != null and is_instance_valid(target) else null
	if is_instance_valid(value):
		return weakref(value)
	return null


static func _resolve_context_ref(value: Variant) -> Variant:
	if not value is WeakRef:
		return null
	var target: Variant = value.get_ref()
	return target if target != null and is_instance_valid(target) else null


static func _capture_flow_context() -> Dictionary:
	if _flow.is_empty():
		return {}
	var captured: Dictionary = _flow.duplicate(true)
	captured.erase("frame_materials") # FW-MOON-06d: rebuilt on demand; no strong material references in a context
	for key: String in ["environment", "sun", "stars", "lights_node", "airfield_lighting"]:
		captured[key] = _weak_context_ref(_flow.get(key))
	var materials: Array = []
	for material: Variant in _flow.get("materials", []):
		materials.append(_weak_context_ref(material))
	captured["materials"] = materials
	return captured


static func _restore_flow_context(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	for key: String in ["when", "time_scale", "step", "environment", "sun", "stars", "lights_node", "materials",
			"tonemapper", "start_lst", "latitude", "upgraded_lights", "airfield_lighting"]:
		if not raw.has(key):
			return {}
	if not raw.when is Dictionary or not raw.materials is Array or not raw.tonemapper is String \
			or not raw.upgraded_lights is bool:
		return {}
	var environment: Variant = _resolve_context_ref(raw.environment)
	var sun: Variant = _resolve_context_ref(raw.sun)
	if not environment is Environment or not sun is DirectionalLight3D:
		return {}
	var restored: Dictionary = raw.duplicate(true)
	for key: String in ["stars", "lights_node", "airfield_lighting"]:
		restored[key] = _resolve_context_ref(raw[key])
	var materials: Array[ShaderMaterial] = []
	for reference: Variant in raw.materials:
		var material: Variant = _resolve_context_ref(reference)
		if material is ShaderMaterial:
			materials.append(material)
	restored["environment"] = environment
	restored["sun"] = sun
	restored["materials"] = materials
	return restored


## Adds a WorldEnvironment, the field and the sun to `parent`.
## `build_field`, when valid, replaces the production field: it must add its own nodes to `parent` (main.gd's seam,
## overridden by the frozen L1–L4 atmosphere fixture). Otherwise the field is built from `field` (openrc-field data).
## `conditions` (FW-03): Conditions.resolve() output; empty = resolve from the command line and environment.
## A nonempty `lighting` snapshot selects the TOD renderer and clears field-world flow.
## Returns {environment, world_environment, field (null when replaced), field_build_ms, sun, conditions, sky (time-of-day state or {})}.
static func build(parent: Node, field: Dictionary, build_field := Callable(), conditions: Dictionary = {}, lighting: Dictionary = {}, night_options: Dictionary = {}) -> Dictionary:
	_night_options = resolve_night_options(night_options)
	_night_profile = str(_night_options.field_lighting)
	_night_owner = weakref(parent)
	_night_helper = null
	_night_fire = null
	_night_legacy_lights = null
	ShaderClock.register() # before any material that reads sim_clock / wind_vec compiles
	if not lighting.is_empty():
		conditions = {time_of_day = false}
	elif conditions.is_empty():
		conditions = Conditions.resolve()
	# FW-MOON-12: the moon choices; a phase choice moves the date to the nearest night with that phase.
	_moon_config = MoonConfig.resolve()
	_base_when = {}
	_live = {}
	if conditions.time_of_day:
		conditions = conditions.duplicate(true)
		_base_when = conditions.when.duplicate()
		conditions.when = MoonConfig.apply_phase(conditions.when, _moon_config)
		conditions.moon = _moon_config.duplicate()
	# FW-22/23: every material built below reads the chosen hour; no time = the calibrated fixed sun.
	Atmosphere.state = SkyState.state(Ephemeris.sky(conditions.when), _moon_config) if conditions.time_of_day else {}
	var flowing: bool = conditions.time_of_day and float(conditions.get("time_scale", 0.0)) > 0.0
	_flow = {}
	if flowing:
		var start_el: float = Atmosphere.state.sun_elevation_deg
		Atmosphere.state.tonemapper = "agx" if start_el < FLOW_AGX_BELOW_SUN_DEG else "aces"
	# FW-31…34: keep default-field fixtures available for a manual daytime switch as well as dusk flow.
	var lights := {}
	var upgraded_lights: bool = LandscapeOptions.enabled() and field.get("id", "") == "default"
	if field.get("id", "") == "default":
		var loaded := FieldLights.load_from()
		if loaded.ok:
			lights = loaded.lights
		else:
			push_warning("field lights refused, flying without them: " + "; ".join(loaded.errors))
	_lights = lights
	_ground_light = 0.0
	if not lights.is_empty():
		for surface: Dictionary in field.get("surfaces", []):
			if surface.get("id", "") == field.get("runway", ""):
				_ground_light = FieldLights.illuminance_point(lights,
					Frames.ned_to_render([float(surface.center_north), float(surface.center_east), -0.5]))
	_adapt_clock = -1.0 # the first update() with a view target snaps the adaptation
	if not Atmosphere.state.is_empty():
		Exposure.set_value(Atmosphere.state.exposure)
	var world_environment := WorldEnvironment.new()
	var environment := Atmosphere.environment(lighting)
	Exposure.set_value(environment.tonemap_exposure) # reset shader exposure when moving between FW and SDR snapshot worlds
	world_environment.environment = environment
	parent.add_child(world_environment)
	if LandscapeOptions.enabled():
		SunGlare.attach(parent, environment)

	var field_node: Node3D = null
	var t0 := Time.get_ticks_usec()
	if build_field.is_valid():
		build_field.call()
	else:
		field_node = FieldBuilder.build(field, lighting)
	var field_build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	if field_node != null:
		parent.add_child(field_node)
	# A custom field builder attaches its own Field node (the production flight seam).
	var wind_field: Node3D = field_node if field_node != null else parent.get_node_or_null("Field") as Node3D
	if wind_field != null:
		environment.set_meta("fw_wind_field", weakref(wind_field))

	var sun := Atmosphere.create_sun(parent, lighting) # the sky shader draws the sun disc from this light
	var storm_bank := StormBank.new()
	storm_bank.name = "StormBank"
	parent.add_child(storm_bank)
	environment.set_meta("fw_storm_bank", weakref(storm_bank))
	refresh_weather_appearance(environment, 0.0)
	var stars: Node3D = null
	if not Atmosphere.state.is_empty() and (flowing or float(Atmosphere.state.sun_elevation_deg) < STARS_BELOW_SUN_DEG):
		stars = Stars.build(Atmosphere.state, float(conditions.when.latitude_deg), Atmosphere.cloud_state_snapshot()) # FW-24
		parent.add_child(stars)
		environment.set_meta("fw_star_field", weakref(stars))
		Stars.set_distant_cloud_order(stars, storm_bank.visible)
	var lights_node: Node3D = null
	if not lights.is_empty():
		lights_node = FieldLights.build(lights) # FW-31…34: visual only
		lights_node.visible = upgraded_lights or _legacy_lights_enabled(float(Atmosphere.state.get("sun_elevation_deg", 90.0)))
		parent.add_child(lights_node)
	if lights_node != null and not upgraded_lights:
		_night_legacy_lights = weakref(lights_node)
		lights_node.visible = _legacy_lights_enabled(float(Atmosphere.state.get("sun_elevation_deg", 90.0)))
	var airfield_lighting: Node3D = null
	if upgraded_lights:
		var scenery := {}
		var scenery_options := SceneryLayer.options()
		if scenery_options.enabled:
			var loaded_scenery := SceneryLoader.load_from(str(scenery_options.file), field)
			if loaded_scenery.ok:
				scenery = loaded_scenery.scenery
		var regional: bool = not scenery.is_empty() and not scenery_options.file_explicit \
			and str(scenery_options.file) == SceneryLoader.DEFAULT_PATH \
			and SceneryLayer.layout_file_applies(field, scenery_options)
		airfield_lighting = AirfieldLighting.build(field, lights, scenery, regional)
		parent.add_child(airfield_lighting)
		airfield_lighting.bind_environment(environment, lights_node, SNAPSHOT_LOCAL_LIGHT_GAIN if not lighting.is_empty() else 1.0)
		airfield_lighting.set_profile(_night_profile)
		airfield_lighting.set_activation(str(_night_options.field_activation))
		_night_helper = weakref(airfield_lighting)
	# A physical hearth is installed even when its independently controlled flame is off.
	if field.get("id", "") == "default":
		var fire_script: GDScript = load("res://render/world/campfire.gd")
		var fire: Node3D = fire_script.build()
		var fire_installations: Array = lights.get("installations", [])
		if fire_installations.is_empty():
			var fire_data := FieldLights.load_from()
			if fire_data.ok:
				fire_installations = fire_data.lights.get("installations", [])
		for installation: Dictionary in fire_installations:
			if str(installation.get("type", "")) == "campfire_base":
				fire.position = Frames.ned_to_render([float(installation.north), float(installation.east), 0.0])
				fire.rotation.y = -deg_to_rad(float(installation.get("heading", 0.0)))
				fire.set_meta("installation_id", str(installation.id))
				break
		parent.add_child(fire)
		fire.configure(bool(_night_options.campfire), environment, SNAPSHOT_LOCAL_LIGHT_GAIN if not lighting.is_empty() else 1.0)
		_night_fire = weakref(fire)
		environment.set_meta("fw_night_fire", _night_fire)
	parent.set_meta("night_options", _night_options.duplicate())
	if conditions.time_of_day:
		_live = {environment = weakref(environment), sun = weakref(sun), parent = weakref(parent),
			when = conditions.when.duplicate()}
	if flowing:
		_flow = {when = conditions.when.duplicate(), time_scale = float(conditions.time_scale), step = 0,
			environment = environment, sun = sun, stars = stars, lights_node = lights_node,
			materials = haze_materials(parent), tonemapper = Atmosphere.state.tonemapper,
			start_lst = float(Atmosphere.state.lst_deg), latitude = float(conditions.when.latitude_deg), upgraded_lights = upgraded_lights,
			airfield_lighting = airfield_lighting}
	return {environment = environment, world_environment = world_environment, field = field_node, field_build_ms = field_build_ms, sun = sun,
		conditions = conditions, sky = Atmosphere.state, night_options = _night_options.duplicate()}


## Independent presentation choices: explicit build options win over technical CLI defaults.
static func resolve_night_options(supplied: Dictionary = {}) -> Dictionary:
	var result := {field_lighting = "club", field_activation = "auto", campfire = false}
	if supplied.is_empty():
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--field-lighting="):
				var profile := arg.get_slice("=", 1)
				if profile in ["club", "airfield", "off"]:
					result.field_lighting = profile
			if arg.begins_with("--field-activation="):
				var activation := arg.get_slice("=", 1)
				if activation in ["auto", "on", "off"]:
					result.field_activation = activation
			if arg.begins_with("--campfire="):
				result.campfire = arg.get_slice("=", 1) == "on"
	else:
		if str(supplied.get("field_lighting", "club")) in ["club", "airfield", "off"]:
			result.field_lighting = str(supplied.get("field_lighting", "club"))
		if str(supplied.get("field_activation", "auto")) in ["auto", "on", "off"]:
			result.field_activation = str(supplied.get("field_activation", "auto"))
		if supplied.get("campfire", false) is bool:
			result.campfire = bool(supplied.get("campfire", false))
	return result


static func set_night_options(profile: String, campfire: bool, activation: String = "auto") -> bool:
	if not profile in ["club", "airfield", "off"] or not activation in ["auto", "on", "off"]:
		return false
	_night_profile = profile
	_night_options = {field_lighting = profile, field_activation = activation, campfire = campfire}
	if _night_helper != null and is_instance_valid(_night_helper.get_ref()):
		_night_helper.get_ref().set_activation(activation)
		_night_helper.get_ref().set_profile(profile)
	if _night_legacy_lights != null and is_instance_valid(_night_legacy_lights.get_ref()):
		_night_legacy_lights.get_ref().visible = _legacy_lights_enabled(float(Atmosphere.state.get("sun_elevation_deg", 90.0)))
	if _night_fire != null and is_instance_valid(_night_fire.get_ref()):
		_night_fire.get_ref().set_enabled(campfire)
	if _night_owner != null and is_instance_valid(_night_owner.get_ref()):
		var owner: Node = _night_owner.get_ref()
		owner.set_meta("night_options", _night_options.duplicate())
		# Static reflection probes need one refresh after a profile switch, not every flame frame.
		for probe: Node in owner.find_children("*", "ReflectionProbe", true, false):
			var reflection := probe as ReflectionProbe
			var original := reflection.position
			reflection.position = original + Vector3(0.0001, 0.0, 0.0)
			reflection.position = original
	return true


static func _legacy_lights_enabled(sun_elevation_deg: float) -> bool:
	if _night_profile == "off" or str(_night_options.field_activation) == "off":
		return false
	return str(_night_options.field_activation) == "on" or sun_elevation_deg < FIELD_LIGHTS_BELOW_SUN_DEG


## Fits the night-flying kit to an airplane's model root when the chosen hour needs it (FW-35). Call after measuring
## the model (Shadow.model_extent) so the kit never changes the pilot-aid shadow. Returns the kit or null.
static func dress_aircraft(root: Node3D, config: Dictionary = {}, snapshot: Dictionary = {}, clock_s: float = 0.0) -> Node3D:
	var state := AircraftLightState.new()
	state.update(aircraft_local_seconds(config, clock_s),
		1.0 if aircraft_sun_elevation(snapshot) < NIGHT_KIT_BELOW_SUN_DEG else 0.0)
	var kit := root.get_node_or_null("NightKit") as Node3D
	if kit == null and state.active_mode != "off":
		kit = AircraftLights.attach(root)
	if kit != null and str(kit.get_meta("mode", "")) != state.active_mode:
		AircraftLights.set_mode(kit, state.active_mode)
	AircraftLights.set_emission_mode(AircraftLights.prepare_emission(root), state.active_mode, state.gain)
	return kit


## FW-35c: use the accepted fixed TOD selection, or the field world's civil clock.
## Flow is sampled at the exact simulation time, independently of the 30-second sky cadence.
## NAN means the legacy fixed sun has no civil clock; never substitute the OS clock.
static func aircraft_local_seconds(config: Dictionary = {}, clock_s: float = 0.0) -> float:
	if config.get("mode", "legacy") != "legacy":
		return float(config.local_seconds)
	if not _flow.is_empty():
		return fposmod(float(_flow.when.hour) * 3600.0 + maxf(clock_s, 0.0) * float(_flow.time_scale), 86400.0)
	var when: Dictionary = _live.get("when", {})
	return fposmod(float(when.hour) * 3600.0, 86400.0) if not when.is_empty() else NAN


static func aircraft_sun_elevation(snapshot: Dictionary = {}) -> float:
	if snapshot.get("solar") is Dictionary:
		return float(snapshot.solar.elevation_deg)
	return float(Atmosphere.state.get("sun_elevation_deg", 45.0))


## The exposure an eye adapted to `target` (render space) would use: the hour's sky and light, the floods' light on
## the target, and the lit ground in proportion to the view's share below the horizon (`ground_share`, 0–1). The
## calibrated fixed sun (no time chosen) keeps its constant exposure.
static func view_exposure(target: Vector3, ground_share := 0.0) -> float:
	if Atmosphere.state.is_empty():
		return float(Spec.ATMOSPHERE.exposure)
	var extra := 0.0
	if not _lights.is_empty() and _night_profile != "off":
		var light_gain := 1.0
		var upgraded_lights := LandscapeOptions.enabled()
		if upgraded_lights:
			light_gain = AirfieldLighting._night_factor({sun_elevation_deg = float(Atmosphere.state.sun_elevation_deg)})
		# Daylight disables both artificial-light terms; avoid the per-frame fixture scan.
		if light_gain != 0.0 or not is_finite(ground_share) or not target.is_finite():
			extra = FieldLights.illuminance_point(_lights, target) + clampf(ground_share, 0.0, 1.0) * ADAPT_GROUND_WEIGHT * _ground_light
			if upgraded_lights:
				extra *= light_gain
	return float(SkyState.adapt(visual_state(), extra).exposure) # FW-MOON-06d: the eye follows the frame's sky


## Share of a camera's picture below the horizon (0 looking well above it, 1 looking well below), from its pitch and
## vertical field of view.
static func ground_share(camera: Camera3D) -> float:
	if camera == null:
		return 0.0
	# Home builds its world before entering the tree: the local transform is the global one there (child of the root).
	var forward := -(camera.global_transform.basis.z if camera.is_inside_tree() else camera.transform.basis.z)
	var pitch := asin(clampf(forward.y, -1.0, 1.0))
	return clampf(0.5 + tan(-pitch) / (2.0 * tan(deg_to_rad(camera.fov) / 2.0)), 0.0, 1.0)


## Advances the world's visual clock: the shader clock every call, the cloud drift at most once per
## Spec.ATMOSPHERE.cloud_update_s, and, in time-of-day mode with a `view_target`, the eye's adaptation. With time
## flowing, the sky steps (flow_to) and the moon and stars move every frame between steps (flow_frame).
## Returns true when the sky was re-rendered.
static func update(environment: Environment, clock_s: float, wind := Vector3.ZERO, view_target: Variant = null,
		camera: Camera3D = null) -> bool:
	ShaderClock.update(clock_s, wind)
	var field_ref: Variant = environment.get_meta("fw_wind_field") if environment.has_meta("fw_wind_field") else null
	if field_ref is WeakRef:
		var wind_field: Node3D = field_ref.get_ref() as Node3D
		if is_instance_valid(wind_field):
			FieldBuilder.update_wind(wind_field, clock_s, wind)
	if not _flow.is_empty():
		flow_to(clock_s)
		flow_frame(clock_s)
	if view_target is Vector3 and not Atmosphere.state.is_empty():
		adapt(environment, view_target, clock_s, ground_share(camera))
	var fire_ref: Variant = environment.get_meta("fw_night_fire") if environment.has_meta("fw_night_fire") else null
	if fire_ref is WeakRef:
		var fire: Variant = fire_ref.get_ref()
		if is_instance_valid(fire):
			fire.update_visual(clock_s, wind)
	var cloud_changed := Atmosphere.update_clouds(environment, clock_s)
	if cloud_changed:
		refresh_star_cloud_appearance(environment)
	_update_weather_presentation(environment, clock_s)
	return cloud_changed


## Scene-local cloud formations share the accepted sky selection, phase and lighting.
static func refresh_weather_appearance(environment: Environment, clock_s: float) -> void:
	var bank: Node3D = _weather_bank(environment)
	if bank == null:
		return
	var checked: Dictionary = Atmosphere.SkyConfig.validate(Atmosphere.appearance_config())
	if checked.ok:
		bank.configure(checked.profile, int(checked.config.seed))
	_update_weather_presentation(environment, clock_s)


static func _update_weather_presentation(environment: Environment, clock_s: float) -> void:
	var bank: Node3D = _weather_bank(environment)
	if bank != null and bank.visible:
		bank.update_visual(Atmosphere.cloud_state_snapshot(), environment, null, clock_s)
	var star_ref: Variant = environment.get_meta("fw_star_field") if environment.has_meta("fw_star_field") else null
	var stars: Variant = star_ref.get_ref() if star_ref is WeakRef else null
	if is_instance_valid(stars):
		Stars.set_distant_cloud_order(stars, bank != null and bank.visible)


static func _weather_bank(environment: Environment) -> Node3D:
	if environment == null or not environment.has_meta("fw_storm_bank"):
		return null
	var reference: Variant = environment.get_meta("fw_storm_bank")
	return reference.get_ref() as Node3D if reference is WeakRef else null


static func weather_snapshot(environment: Environment) -> Dictionary:
	var bank: Node3D = _weather_bank(environment)
	return bank.snapshot() if bank != null else {}


## Scene-local presentation binding. Consumers must keep only a WeakRef to this node.
static func storm_bank_node(environment: Environment) -> Node3D:
	return _weather_bank(environment)


## Reapply the shared cloud mask after a paused visual preset edit or a cloud transport step.
static func refresh_star_cloud_appearance(environment: Environment) -> void:
	if environment == null or not is_instance_valid(environment) or not environment.has_meta("fw_star_field"):
		return
	var star_ref: Variant = environment.get_meta("fw_star_field")
	if not (star_ref is WeakRef):
		return
	var stars: Variant = star_ref.get_ref()
	if stars is Node3D and is_instance_valid(stars):
		Stars.update_cloud_appearance(stars, Atmosphere.cloud_state_snapshot())


## Moves the exposure toward view_exposure(target) (see ADAPT_*). Returns the exposure now in use.
static func adapt(environment: Environment, target: Vector3, clock_s: float, share := 0.0) -> float:
	var goal := log(view_exposure(target, share))
	var dt := clock_s - _adapt_clock
	var snap := _adapt_clock < 0.0 or dt < 0.0 or dt > ADAPT_MAX_STEP_S
	if snap:
		_adapt_log = goal
	else:
		var rate := ADAPT_TO_LIGHT_PER_S if goal < _adapt_log else ADAPT_TO_DARK_PER_S
		_adapt_log = goal + (_adapt_log - goal) * exp(-rate * dt)
	_adapt_clock = clock_s
	if snap or absf(log(environment.tonemap_exposure) - _adapt_log) > ADAPT_PUSH_LOG:
		environment.tonemap_exposure = exp(_adapt_log)
		Exposure.set_value(environment.tonemap_exposure)
	return environment.tonemap_exposure


## Every ShaderMaterial under `root` whose shader draws its own haze (uniform `haze_lin`): the ground, its surface
## copies and the near grass. Time flow re-applies the haze, lobe and sun uniforms to them.
static func haze_materials(root: Node) -> Array:
	var found := []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var candidates := []
		if node is GeometryInstance3D:
			candidates.append((node as GeometryInstance3D).material_override)
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				candidates.append(mesh.surface_get_material(i))
		for m: Variant in candidates:
			if m is ShaderMaterial and not found.has(m) and (m as ShaderMaterial).shader != null:
				for u: Dictionary in (m as ShaderMaterial).shader.get_shader_uniform_list():
					if u.name == "haze_lin":
						found.append(m)
						break
	return found


## FW-61: moves the sky to `clock_s` of simulation time (time flowing). Steps are quantised to FLOW_STEP_SKY_S of sky
## time, so the same simulation time always gives the same sky. Returns true when a new step was applied.
static func flow_to(clock_s: float) -> bool:
	if _flow.is_empty():
		return false
	var step := floori(maxf(clock_s, 0.0) * float(_flow.time_scale) / FLOW_STEP_SKY_S)
	if step == int(_flow.step):
		return false
	_flow.step = step
	_flow.erase("frame_position") # the stepped sky below rewrites the moon; flow_frame must move it again
	_flow.erase("frame_state")
	var when := _flow_when(step)
	var state := _flow_state(step)
	if not _live.is_empty():
		_live.when = when.duplicate()
	Atmosphere.state = state
	var env: Environment = _flow.environment
	Atmosphere.apply_state_to_sky(env.sky.sky_material)
	Atmosphere.apply_state_to_environment(env)
	Atmosphere.apply_light(_flow.sun)
	for m: ShaderMaterial in _flow.materials:
		Atmosphere._set_haze_uniforms(m)
	if _flow.lights_node != null and not _flow.get("upgraded_lights", false):
		(_flow.lights_node as Node3D).visible = _legacy_lights_enabled(float(state.sun_elevation_deg))
	_turn_stars(float(state.lst_deg))
	if not is_equal_approx(env.tonemap_exposure, state.exposure) and _adapt_clock < 0.0:
		env.tonemap_exposure = state.exposure # no view target adapts it (e.g. evidence views)
		Exposure.set_value(state.exposure)
	if _flow.get("airfield_lighting") != null:
		_flow.airfield_lighting.apply_lighting({sun_elevation_deg = float(state.sun_elevation_deg)})
	return true


## FW-MOON-03b (FW-MOON-01 decision): between flow steps the moon's disc and the stars move every frame. The moon's
## direction and orientation and the sidereal time are interpolated from this step's state toward the next step's, a
## pure function of the simulation clock that meets the stepped state at every step; everything slow (light, sky
## colours, exposure) keeps the step cadence. Sky uniforms are written only while the environment does not use the
## sky's radiance (radiance_unused), because the engine re-renders the cubemap after any sky uniform change when it
## does. Returns true when it moved the moon or the stars.
static func flow_frame(clock_s: float) -> bool:
	if _flow.is_empty() or Atmosphere.state.is_empty():
		return false
	var position := maxf(clock_s, 0.0) * float(_flow.time_scale) / FLOW_STEP_SKY_S
	if position == float(_flow.get("frame_position", -1.0)):
		return false # paused, or the same frame again
	var env: Environment = _flow.environment
	if not radiance_unused(env):
		return false
	_flow.frame_position = position
	var step := int(_flow.step)
	var f := clampf(position - float(step), 0.0, 1.0)
	var now: Dictionary = Atmosphere.state
	var next := _flow_state(step + 1, true)
	var moved := false
	var mat := env.sky.sky_material as ShaderMaterial
	if mat != null and (now.moon_lin != Vector3.ZERO or next.moon_lin != Vector3.ZERO):
		var a := _ned(float(now.moon_azimuth_deg), float(now.moon_elevation_deg))
		var b := _ned(float(next.moon_azimuth_deg), float(next.moon_elevation_deg))
		var v := [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f]
		mat.set_shader_parameter("moon_dir", Frames.ned_to_render(v).normalized())
		if now.get("moon_textured", false) and next.get("moon_textured", false):
			var from := now.moon_render_to_body as Basis
			mat.set_shader_parameter("moon_render_to_body", from.slerp(next.moon_render_to_body as Basis, f))
		moved = true
	var lst_now := float(now.lst_deg)
	moved = _turn_stars(lst_now + (fposmod(float(next.lst_deg) - lst_now + 180.0, 360.0) - 180.0) * f) or moved
	# FW-MOON-06d: the slow sky terms between the steps too (sky, haze, ambient, light, exposure), so twilight falls
	# smoothly instead of ~10 % per step at ×20 and the ground's cloud shadows follow the sun instead of hopping.
	if f > 0.0 and frame_sky_needed(now, next):
		_apply_frame_sky(frame_state(now, next, f))
		moved = true
	elif _flow.has("frame_state"):
		_flow.erase("frame_state")
	return moved


## FW-MOON-06d: whether a step needs the per-frame sky: its sky or light luminance changes by more than
## FRAME_SKY_MIN_LOG (twilight), or the light is up but below FRAME_SKY_LOW_LIGHT_DEG, where one step moves the ground's
## cloud shadows tens of metres. A day or a moonlit night high up changes ~0.2 % per step and stays stepped (no cost).
static func frame_sky_needed(now: Dictionary, next: Dictionary) -> bool:
	var light_el := minf(float(now.light_elevation_deg), float(next.light_elevation_deg))
	if light_el > 0.0 and light_el < FRAME_SKY_LOW_LIGHT_DEG and float(now.light_energy) > 0.0:
		return true
	for key: String in ["zenith_lin", "haze_lin", "ambient_lin"]:
		if absf(log(maxf(SkyState._lum(next[key]), 1e-30) / maxf(SkyState._lum(now[key]), 1e-30))) > FRAME_SKY_MIN_LOG:
			return true
	return absf(log(maxf(float(next.light_energy), 1e-30) / maxf(float(now.light_energy), 1e-30))) > FRAME_SKY_MIN_LOG


## FW-MOON-06d: the visual sky at fraction `f` between two step states. Light-like colours and the exposure terms
## interpolate geometrically per channel (twilight falls exponentially; linearly where one end is zero), directions
## by slerp, the moon as in FW-MOON-03b. Terms whose source changes inside the step (the light passing between sun and
## moon, the brighter lobe swapping) keep the step's value for that one step, so nothing sweeps across the sky.
## Discrete and signature-read terms (shadow strength, light source, tonemapper) keep the step's value.
static func frame_state(now: Dictionary, next: Dictionary, f: float) -> Dictionary:
	var out := now.duplicate()
	for key: String in FRAME_COLOUR_KEYS:
		if now.has(key) and next.has(key):
			out[key] = _geometric3(now[key], next[key], f)
	for key: String in FRAME_SCALAR_KEYS:
		if now.has(key) and next.has(key):
			out[key] = _geometric(float(now[key]), float(next[key]), f)
	for key: String in FRAME_LINEAR_KEYS:
		if now.has(key) and next.has(key):
			out[key] = lerpf(float(now[key]), float(next[key]), f)
	for key: String in ["sun_dir", "moon_sun_dir"]:
		if now.has(key) and next.has(key):
			out[key] = (now[key] as Vector3).slerp(next[key] as Vector3, f)
	var a := _ned(float(now.moon_azimuth_deg), float(now.moon_elevation_deg))
	var b := _ned(float(next.moon_azimuth_deg), float(next.moon_elevation_deg))
	out.moon_dir = Frames.ned_to_render([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f]).normalized()
	if now.get("moon_textured", false) and next.get("moon_textured", false):
		out.moon_render_to_body = (now.moon_render_to_body as Basis).slerp(next.moon_render_to_body as Basis, f)
	var lst := float(now.lst_deg)
	out.lst_deg = lst + (fposmod(float(next.lst_deg) - lst + 180.0, 360.0) - 180.0) * f
	if now.get("moon_eclipse", false) and next.get("moon_eclipse", false): # FW-MOON-10: the shadow edge moves smoothly
		out.moon_shadow_offset = (now.moon_shadow_offset as Vector3).lerp(next.moon_shadow_offset, f)
		out.moon_shadow_axis = (now.moon_shadow_axis as Vector3).slerp(next.moon_shadow_axis, f)
	if now.light_source == next.light_source:
		var c0: Color = (now.light_color as Color).srgb_to_linear()
		var c1: Color = (next.light_color as Color).srgb_to_linear()
		var rgb := _geometric3(Vector3(c0.r, c0.g, c0.b) * float(now.light_energy), Vector3(c1.r, c1.g, c1.b) * float(next.light_energy), f)
		var energy := maxf(maxf(rgb.x, rgb.y), rgb.z)
		out.light_energy = energy
		if energy > 0.0:
			var c := rgb / energy
			out.light_color = Color(c.x, c.y, c.z).linear_to_srgb()
		out.light_dir = (now.light_dir as Vector3).slerp(next.light_dir as Vector3, f)
		out.light_elevation_deg = lerpf(float(now.light_elevation_deg), float(next.light_elevation_deg), f)
		out.cloud_light1_weight = lerpf(float(now.cloud_light1_weight), float(next.cloud_light1_weight), f)
		out.cloud_light2_weight = lerpf(float(now.cloud_light2_weight), float(next.cloud_light2_weight), f)
		out.cloud_light2_dir = (now.cloud_light2_dir as Vector3).slerp(next.cloud_light2_dir as Vector3, f)
	if (now.lobe_dir as Vector3).dot(next.lobe_dir) > LOBE_SWAP_DOT:
		out.lobe_lin = _geometric3(now.lobe_lin, next.lobe_lin, f)
		out.sky_lobe2_lin = _geometric3(now.sky_lobe2_lin, next.sky_lobe2_lin, f)
		for key: String in ["lobe_k", "lobe_height", "sky_lobe2_k", "sky_lobe2_height"]:
			out[key] = lerpf(float(now[key]), float(next[key]), f)
		out.lobe_dir = (now.lobe_dir as Vector3).slerp(next.lobe_dir as Vector3, f)
		out.sky_lobe2_dir = (now.sky_lobe2_dir as Vector3).slerp(next.sky_lobe2_dir as Vector3, f)
	return out


## Writes a frame state through the step's own code paths (profiles and all), then restores the stepped state, so
## everything that reads Atmosphere.state or watches a signature (projected shadows, the lake probe) keeps the step
## cadence. The lake's water material is left at the step: its reflection probe re-renders when it changes.
static func _apply_frame_sky(vis: Dictionary) -> void:
	var stepped: Dictionary = Atmosphere.state
	var env: Environment = _flow.environment
	Atmosphere.state = vis
	Atmosphere.apply_state_to_sky(env.sky.sky_material)
	Atmosphere.apply_state_to_environment(env)
	Atmosphere.apply_light(_flow.sun)
	for m: ShaderMaterial in _frame_materials():
		Atmosphere._set_haze_uniforms(m)
	Atmosphere.state = stepped
	if _adapt_clock < 0.0 and not is_equal_approx(env.tonemap_exposure, float(vis.exposure)):
		env.tonemap_exposure = float(vis.exposure) # no view target adapts it (e.g. evidence views)
		Exposure.set_value(env.tonemap_exposure)
	_flow.frame_state = vis


## The flow's haze materials without those a reflection probe watches (computed once per flow).
static func _frame_materials() -> Array:
	if _flow.has("frame_materials"):
		return _flow.frame_materials
	var watched := []
	var parent: Variant = (_live.parent as WeakRef).get_ref() if _live.get("parent") is WeakRef else null
	if parent is Node:
		for probe: Node in (parent as Node).find_children("*", "ReflectionProbe", true, false):
			var water: Variant = probe.get("water_material")
			if water is ShaderMaterial:
				watched.append(water)
	var out := []
	for m: ShaderMaterial in _flow.materials:
		if not watched.has(m):
			out.append(m)
	_flow.frame_materials = out
	return out


## The visual state this frame: the interpolated frame state with time flowing, else the stepped state.
static func visual_state() -> Dictionary:
	return _flow.get("frame_state", Atmosphere.state) if not _flow.is_empty() else Atmosphere.state


static func _geometric(a: float, b: float, f: float) -> float:
	return a * pow(b / a, f) if a > 0.0 and b > 0.0 else lerpf(a, b, f)


static func _geometric3(a: Vector3, b: Vector3, f: float) -> Vector3:
	return Vector3(_geometric(a.x, b.x, f), _geometric(a.y, b.y, f), _geometric(a.z, b.z, f))


## FW-MOON-01: Godot 4.7.2 Compatibility re-renders the sky's radiance cubemap after a sky uniform change only when the
## environment uses it for ambient light or reflections (directly or through a sky background).
static func radiance_unused(env: Environment) -> bool:
	var sky_bg := env.background_mode == Environment.BG_SKY
	var ambient := env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY \
		or (env.ambient_light_source == Environment.AMBIENT_SOURCE_BG and sky_bg)
	var reflections := env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY \
		or (env.reflected_light_source == Environment.REFLECTION_SOURCE_BG and sky_bg)
	return not ambient and not reflections


## The local date and time of flow step `step`.
static func _flow_when(step: int) -> Dictionary:
	var when: Dictionary = _flow.when.duplicate()
	when.hour = float(when.hour) + step * FLOW_STEP_SKY_S / 3600.0
	return when


## FW-MOON-03b: the sky state of flow step `step`. flow_frame computes the next step's state ahead and keeps it
## (`keep`); flow_to uses it once when the clock reaches that step. The cache is keyed by step, start time and moon
## choices, so the result is always SkyState.state() of that step.
static func _flow_state(step: int, keep := false) -> Dictionary:
	var cached: Dictionary = _flow.get("next", {})
	if not keep:
		_flow.erase("next")
	if not cached.is_empty() and int(cached.step) == step and cached.when == _flow.when and cached.moon == _moon_config:
		return cached.state
	var state := SkyState.state(Ephemeris.sky(_flow_when(step)), _moon_config)
	state.tonemapper = _flow.tonemapper
	if keep:
		_flow.next = {step = step, when = _flow.when.duplicate(), moon = _moon_config.duplicate(), state = state}
	return state


## Turns the star field to local sidereal time `lst_deg` (relative to the session start). Returns false without stars.
static func _turn_stars(lst_deg: float) -> bool:
	if _flow.stars == null or not is_instance_valid(_flow.stars):
		return false
	var lat: float = _flow.latitude
	(_flow.stars as Node3D).basis = Stars.equatorial_basis(lst_deg, lat) * Stars.equatorial_basis(_flow.start_lst, lat).inverse()
	return true


static func _ned(azimuth_deg: float, elevation_deg: float) -> PackedFloat64Array:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return PackedFloat64Array([cos(az) * cos(el), sin(az) * cos(el), -sin(el)])


## FW-MOON-12/13: apply new moon choices to the current field-world scene in place (pause menu, Home). Returns false
## for an invalid configuration; true otherwise (also when no time-of-day scene is live: the next build uses them).
static func set_moon_config(config: Dictionary) -> bool:
	var checked := MoonConfig.validate(config)
	if not checked.ok:
		return false
	_moon_config = checked.config
	if Atmosphere.state.is_empty() or _base_when.is_empty() or _live.is_empty():
		return true
	var env: Environment = _live.environment.get_ref()
	var sun: DirectionalLight3D = _live.sun.get_ref()
	var parent: Node = _live.parent.get_ref()
	if env == null or not is_instance_valid(sun) or not is_instance_valid(parent):
		return true
	var start := MoonConfig.apply_phase(_base_when, _moon_config)
	var when := start.duplicate()
	if not _flow.is_empty():
		_flow.when = start
		_flow.erase("frame_position") # the next frame re-applies the moon's per-frame motion, also while paused
		when.hour = float(start.hour) + int(_flow.step) * FLOW_STEP_SKY_S / 3600.0
	_live.when = when
	var tonemapper: String = Atmosphere.state.get("tonemapper", "agx")
	var state := SkyState.state(Ephemeris.sky(when), _moon_config)
	state.tonemapper = tonemapper
	Atmosphere.state = state
	Atmosphere.apply_state_to_sky(env.sky.sky_material)
	Atmosphere.apply_state_to_environment(env)
	Atmosphere.update_sun(sun)
	for m: ShaderMaterial in haze_materials(parent):
		Atmosphere._set_haze_uniforms(m)
	if _adapt_clock < 0.0:
		env.tonemap_exposure = state.exposure # no view target adapts it (Home, evidence views)
		Exposure.set_value(state.exposure)
	return true


## The moon choices of the current world (MoonConfig format).
static func moon_config() -> Dictionary:
	return _moon_config.duplicate()


## The local date and time the current world shows (after a phase choice), or {} without time of day.
static func shown_when() -> Dictionary:
	return _live.get("when", {}).duplicate()


## The local sky time (hours) of the current time-flow step; -1 when time is frozen.
static func flow_hour() -> float:
	if _flow.is_empty():
		return -1.0
	return float(_flow.when.hour) + int(_flow.step) * FLOW_STEP_SKY_S / 3600.0
