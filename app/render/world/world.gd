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
const Stars := preload("res://render/world/stars.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const Exposure := preload("res://render/world/exposure.gd")
const Preferences := preload("res://app_state/preferences.gd")
const LandscapeOptions := preload("res://render/landscape_upgrade/options.gd")
const SunGlare := preload("res://render/landscape_upgrade/sun_glare.gd")
const AirfieldLighting := preload("res://render/landscape_upgrade/airfield_lighting.gd")
const SceneryLayer := preload("res://scenery/scenery.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")

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

static var _lights := {}
static var _ground_light := 0.0 # floods' light on the runway centre (scene units), computed once per build
static var _configured_lights: Dictionary = {}
static var _configured_ground_light: float = 0.0
static var _night_options: Dictionary = Preferences.NIGHT_DEFAULTS.duplicate(true)
static var _active_world: Node = null
static var _active_lights_node: Node3D = null
static var _active_airfield_lighting: Node3D = null
static var _active_upgraded_lights: bool = false
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

## Time-flow session: {} when frozen. Keys: when, time_scale, step, environment, sun, stars, lights_node, materials,
## tonemapper, start_lst, latitude.
static var _flow := {}


## Adds a WorldEnvironment, the field and the sun to `parent`.
## `build_field`, when valid, replaces the production field: it must add its own nodes to `parent` (main.gd's seam,
## overridden by the frozen L1–L4 atmosphere fixture). Otherwise the field is built from `field` (openrc-field data).
## `conditions` (FW-03): Conditions.resolve() output; empty = resolve from the command line and environment.
## A nonempty `lighting` snapshot selects the TOD renderer and clears field-world flow. `night_options` selects the
## field-lighting presentation; empty keeps the preference defaults for older callers.
## Returns {environment, world_environment, field (null when replaced), field_build_ms, sun, conditions, sky, night_options}.
static func build(parent: Node, field: Dictionary, build_field := Callable(), conditions: Dictionary = {}, lighting: Dictionary = {},
		night_options: Dictionary = {}) -> Dictionary:
	var raw_night_options: Dictionary = Preferences.NIGHT_DEFAULTS if night_options.is_empty() else night_options
	var checked_night: Dictionary = Preferences.validate_night_options(raw_night_options)
	var resolved_night_options: Dictionary = checked_night.options.duplicate(true) if checked_night.get("ok", false) \
		else Preferences.NIGHT_DEFAULTS.duplicate(true)
	if not checked_night.get("ok", false):
		push_warning("invalid world night options; using defaults: " + "; ".join(checked_night.errors))
	_night_options = resolved_night_options.duplicate(true)
	_active_world = parent
	_active_lights_node = null
	_active_airfield_lighting = null
	_active_upgraded_lights = false
	ShaderClock.register() # before any material that reads sim_clock / wind_vec compiles
	if not lighting.is_empty():
		conditions = {time_of_day = false}
	elif conditions.is_empty():
		conditions = Conditions.resolve()
	# FW-22/23: every material built below reads the chosen hour; no time = the calibrated fixed sun.
	Atmosphere.state = SkyState.state(Ephemeris.sky(conditions.when)) if conditions.time_of_day else {}
	var flowing: bool = conditions.time_of_day and float(conditions.get("time_scale", 0.0)) > 0.0
	_flow = {}
	if flowing:
		var start_el: float = Atmosphere.state.sun_elevation_deg
		Atmosphere.state.tonemapper = "agx" if start_el < FLOW_AGX_BELOW_SUN_DEG else "aces"
	# FW-31…34: at dusk the club lights come on (with time flowing they are built at once and switched by the sun).
	var lights := {}
	var upgraded_lights: bool = LandscapeOptions.enabled() and field.get("id", "") == "default"
	if upgraded_lights or (not Atmosphere.state.is_empty() and (flowing or float(Atmosphere.state.sun_elevation_deg) < FIELD_LIGHTS_BELOW_SUN_DEG)):
		var loaded := FieldLights.load_from()
		if loaded.ok:
			lights = loaded.lights
		else:
			push_warning("field lights refused, flying without them: " + "; ".join(loaded.errors))
	_ground_light = 0.0
	if not lights.is_empty():
		for surface: Dictionary in field.get("surfaces", []):
			if surface.get("id", "") == field.get("runway", ""):
				_ground_light = FieldLights.illuminance_point(lights,
					Frames.ned_to_render([float(surface.center_north), float(surface.center_east), -0.5]))
	_configured_lights = lights.duplicate(true)
	_configured_ground_light = _ground_light
	_active_upgraded_lights = upgraded_lights
	_apply_night_options()
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

	var sun := Atmosphere.create_sun(parent, lighting) # the sky shader draws the sun disc from this light
	var stars: Node3D = null
	if not Atmosphere.state.is_empty() and (flowing or float(Atmosphere.state.sun_elevation_deg) < STARS_BELOW_SUN_DEG):
		stars = Stars.build(Atmosphere.state, float(conditions.when.latitude_deg)) # FW-24
		parent.add_child(stars)
	var lights_node: Node3D = null
	if not lights.is_empty():
		lights_node = FieldLights.build(lights) # FW-31…34: visual only
		lights_node.visible = upgraded_lights or float(Atmosphere.state.sun_elevation_deg) < FIELD_LIGHTS_BELOW_SUN_DEG
		parent.add_child(lights_node)
	var airfield_lighting: Node3D = null
	if upgraded_lights:
		var scenery := {}
		var scenery_options := SceneryLayer.options()
		if scenery_options.enabled:
			var loaded_scenery := SceneryLoader.load_from(str(scenery_options.file), field)
			if loaded_scenery.ok:
				scenery = loaded_scenery.scenery
		airfield_lighting = AirfieldLighting.build(field, lights, scenery)
		parent.add_child(airfield_lighting)
		airfield_lighting.bind_environment(environment, lights_node, SNAPSHOT_LOCAL_LIGHT_GAIN if not lighting.is_empty() else 1.0)
	if flowing:
		_flow = {when = conditions.when.duplicate(), time_scale = float(conditions.time_scale), step = 0,
			environment = environment, sun = sun, stars = stars, lights_node = lights_node,
			materials = haze_materials(parent), tonemapper = Atmosphere.state.tonemapper,
			start_lst = float(Atmosphere.state.lst_deg), latitude = float(conditions.when.latitude_deg), upgraded_lights = upgraded_lights,
			airfield_lighting = airfield_lighting}
	_active_lights_node = lights_node
	_active_airfield_lighting = airfield_lighting
	_apply_night_options()
	parent.set_meta("night_options", _night_options.duplicate(true))
	return {environment = environment, world_environment = world_environment, field = field_node, field_build_ms = field_build_ms, sun = sun,
		conditions = conditions, sky = Atmosphere.state, night_options = _night_options.duplicate(true)}


## Changes the active field-lighting presentation without rebuilding the flight or touching simulation state.
## `airfield` keeps the field fixtures and runway markers; `club` also shows the club lighting; `off` hides both.
## Campfire remains part of the resolved presentation options so the field renderer can consume it when present.
static func set_night_options(profile: String, campfire: bool) -> bool:
	var checked: Dictionary = Preferences.validate_night_options({"field_lighting": profile, "campfire": campfire})
	if not checked.get("ok", false):
		return false
	_night_options = checked.options.duplicate(true)
	_apply_night_options()
	if is_instance_valid(_active_world):
		_active_world.set_meta("night_options", _night_options.duplicate(true))
	return true


static func _apply_night_options() -> void:
	var profile: String = str(_night_options.get("field_lighting", "club"))
	var enabled: bool = profile != "off"
	_lights = _configured_lights if enabled else {}
	_ground_light = _configured_ground_light if enabled else 0.0
	if is_instance_valid(_active_lights_node):
		var night_sky: bool = not Atmosphere.state.is_empty() and (float(_flow.get("time_scale", 0.0)) > 0.0 \
			or float(Atmosphere.state.sun_elevation_deg) < FIELD_LIGHTS_BELOW_SUN_DEG)
		_active_lights_node.visible = enabled and (_active_upgraded_lights or night_sky)
	if is_instance_valid(_active_airfield_lighting):
		_active_airfield_lighting.visible = profile == "club"


## Fits the night-flying kit to an airplane's model root when the chosen hour needs it (FW-35). Call after measuring
## the model (Shadow.model_extent) so the kit never changes the pilot-aid shadow. Returns the kit or null.
static func dress_aircraft(root: Node3D) -> Node3D:
	if Atmosphere.state.is_empty() or (_flow.is_empty() and float(Atmosphere.state.sun_elevation_deg) >= NIGHT_KIT_BELOW_SUN_DEG):
		return null
	return AircraftLights.attach(root)


## The exposure an eye adapted to `target` (render space) would use: the hour's sky and light, the floods' light on
## the target, and the lit ground in proportion to the view's share below the horizon (`ground_share`, 0–1). The
## calibrated fixed sun (no time chosen) keeps its constant exposure.
static func view_exposure(target: Vector3, ground_share := 0.0) -> float:
	if Atmosphere.state.is_empty():
		return float(Spec.ATMOSPHERE.exposure)
	var extra := 0.0
	if not _lights.is_empty():
		extra = FieldLights.illuminance_point(_lights, target) + clampf(ground_share, 0.0, 1.0) * ADAPT_GROUND_WEIGHT * _ground_light
		if LandscapeOptions.enabled():
			extra *= AirfieldLighting._night_factor({sun_elevation_deg = float(Atmosphere.state.sun_elevation_deg)})
	return float(SkyState.adapt(Atmosphere.state, extra).exposure)


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
## Spec.ATMOSPHERE.cloud_update_s, and, in time-of-day mode with a `view_target`, the eye's adaptation.
## Returns true when the sky was re-rendered.
static func update(environment: Environment, clock_s: float, wind := Vector3.ZERO, view_target: Variant = null,
		camera: Camera3D = null) -> bool:
	ShaderClock.update(clock_s, wind)
	if not _flow.is_empty():
		flow_to(clock_s)
	if view_target is Vector3 and not Atmosphere.state.is_empty():
		adapt(environment, view_target, clock_s, ground_share(camera))
	return Atmosphere.update_clouds(environment, clock_s)


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
	var when: Dictionary = _flow.when.duplicate()
	when.hour = float(when.hour) + step * FLOW_STEP_SKY_S / 3600.0
	var state := SkyState.state(Ephemeris.sky(when))
	state.tonemapper = _flow.tonemapper
	Atmosphere.state = state
	_apply_night_options()
	var env: Environment = _flow.environment
	Atmosphere.apply_state_to_sky(env.sky.sky_material)
	Atmosphere.apply_state_to_environment(env)
	Atmosphere.apply_light(_flow.sun)
	for m: ShaderMaterial in _flow.materials:
		Atmosphere._set_haze_uniforms(m)
	if _flow.stars != null:
		var lat: float = _flow.latitude
		(_flow.stars as Node3D).basis = Stars.equatorial_basis(state.lst_deg, lat) * Stars.equatorial_basis(_flow.start_lst, lat).inverse()
	if not is_equal_approx(env.tonemap_exposure, state.exposure) and _adapt_clock < 0.0:
		env.tonemap_exposure = state.exposure # no view target adapts it (e.g. evidence views)
		Exposure.set_value(state.exposure)
	if _flow.get("airfield_lighting") != null:
		_flow.airfield_lighting.apply_lighting({sun_elevation_deg = float(state.sun_elevation_deg)})
	return true


## The local sky time (hours) of the current time-flow step; -1 when time is frozen.
static func flow_hour() -> float:
	if _flow.is_empty():
		return -1.0
	return float(_flow.when.hour) + int(_flow.step) * FLOW_STEP_SKY_S / 3600.0
