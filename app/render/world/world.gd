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

static var _night_profile := "club"
static var _night_options := {field_lighting = "club", campfire = false}
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

## Time-flow session: {} when frozen. Keys: when, time_scale, step, environment, sun, stars, lights_node, materials,
## tonemapper, start_lst, latitude.
static var _flow := {}

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
	if not options.get("field_lighting", "") in ["club", "airfield", "off"] or not options.get("campfire", false) is bool:
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
	set_night_options(_night_profile, bool(_night_options.campfire))
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

	var sun := Atmosphere.create_sun(parent, lighting) # the sky shader draws the sun disc from this light
	var stars: Node3D = null
	if not Atmosphere.state.is_empty() and (flowing or float(Atmosphere.state.sun_elevation_deg) < STARS_BELOW_SUN_DEG):
		stars = Stars.build(Atmosphere.state, float(conditions.when.latitude_deg), Atmosphere.cloud_state_snapshot()) # FW-24
		parent.add_child(stars)
		environment.set_meta("fw_star_field", weakref(stars))
	var lights_node: Node3D = null
	if not lights.is_empty():
		lights_node = FieldLights.build(lights) # FW-31…34: visual only
		lights_node.visible = upgraded_lights or float(Atmosphere.state.sun_elevation_deg) < FIELD_LIGHTS_BELOW_SUN_DEG
		parent.add_child(lights_node)
	if lights_node != null and not upgraded_lights:
		_night_legacy_lights = weakref(lights_node)
		lights_node.visible = lights_node.visible and _night_profile != "off"
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
		airfield_lighting.set_profile(_night_profile)
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
	var result := {field_lighting = "club", campfire = false}
	if supplied.is_empty():
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--field-lighting="):
				var profile := arg.get_slice("=", 1)
				if profile in ["club", "airfield", "off"]:
					result.field_lighting = profile
			if arg.begins_with("--campfire="):
				result.campfire = arg.get_slice("=", 1) == "on"
	else:
		if str(supplied.get("field_lighting", "club")) in ["club", "airfield", "off"]:
			result.field_lighting = str(supplied.get("field_lighting", "club"))
		if supplied.get("campfire", false) is bool:
			result.campfire = bool(supplied.get("campfire", false))
	return result


static func set_night_options(profile: String, campfire: bool) -> bool:
	if not profile in ["club", "airfield", "off"]:
		return false
	_night_profile = profile
	_night_options = {field_lighting = profile, campfire = campfire}
	if _night_helper != null and is_instance_valid(_night_helper.get_ref()):
		_night_helper.get_ref().set_profile(profile)
	if _night_legacy_lights != null and is_instance_valid(_night_legacy_lights.get_ref()):
		_night_legacy_lights.get_ref().visible = profile != "off" and float(Atmosphere.state.get("sun_elevation_deg", 90.0)) < FIELD_LIGHTS_BELOW_SUN_DEG
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
	if not _lights.is_empty() and _night_profile != "off":
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
	var fire_ref: Variant = environment.get_meta("fw_night_fire") if environment.has_meta("fw_night_fire") else null
	if fire_ref is WeakRef:
		var fire: Variant = fire_ref.get_ref()
		if is_instance_valid(fire):
			fire.update_visual(clock_s, wind)
	var cloud_changed := Atmosphere.update_clouds(environment, clock_s)
	if cloud_changed:
		refresh_star_cloud_appearance(environment)
	return cloud_changed


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
	var when: Dictionary = _flow.when.duplicate()
	when.hour = float(when.hour) + step * FLOW_STEP_SKY_S / 3600.0
	var state := SkyState.state(Ephemeris.sky(when))
	state.tonemapper = _flow.tonemapper
	Atmosphere.state = state
	var env: Environment = _flow.environment
	Atmosphere.apply_state_to_sky(env.sky.sky_material)
	Atmosphere.apply_state_to_environment(env)
	Atmosphere.apply_light(_flow.sun)
	for m: ShaderMaterial in _flow.materials:
		Atmosphere._set_haze_uniforms(m)
	if _flow.lights_node != null and not _flow.get("upgraded_lights", false):
		(_flow.lights_node as Node3D).visible = _night_profile != "off" and float(state.sun_elevation_deg) < FIELD_LIGHTS_BELOW_SUN_DEG
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
