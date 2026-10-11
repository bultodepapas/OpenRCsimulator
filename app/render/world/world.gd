# FIELD-WORLD-PLAN FW-02: the one place that composes the world around an aircraft: the environment (sky, ambient
# light, tonemap, haze), the validated field and the sun, always in this order. Flight (main.gd), Home, the scenery
# evidence views and the runway scenario call it; nothing else creates the flight Environment or the sun, so a new
# world feature (time of day, moon, field lights) is added here once instead of at every call site.
extends RefCounted

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Stars := preload("res://render/world/stars.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const FieldLights := preload("res://render/world/field_lights.gd")

## The club switches its field lights on at dusk (FW-31…34): sun below this elevation in time-of-day mode.
const FIELD_LIGHTS_BELOW_SUN_DEG := 3.0
## Weight of the floodlit runway in the eye's adaptation: one exposure serves the whole view, and the pilot mostly
## looks at the sky, where the lit area is a small share of the field of view (estimate, from captures: at full
## weight the moonlit sky and the airplane went black; at 0.08 the lit runway reads without clipping and the sky keeps
## its moon and stars).
const ARTIFICIAL_ADAPTATION_WEIGHT := 0.08
## The night kit is fitted from dusk (FW-35): sun below this elevation in time-of-day mode.
const NIGHT_KIT_BELOW_SUN_DEG := 6.0

## Stars are only built once the sun is this low (above it the exposure leaves them invisible; saves the draw).
const STARS_BELOW_SUN_DEG := 2.0


## Adds a WorldEnvironment, the field and the sun to `parent`.
## `build_field`, when valid, replaces the production field: it must add its own nodes to `parent` (main.gd's seam,
## overridden by the frozen L1–L4 atmosphere fixture). Otherwise the field is built from `field` (openrc-field data).
## `conditions` (FW-03): Conditions.resolve() output; empty = resolve from the command line and environment.
## Returns {environment, field (null when replaced), field_build_ms, sun, conditions, sky (time-of-day state or {})}.
static func build(parent: Node, field: Dictionary, build_field := Callable(), conditions: Dictionary = {}) -> Dictionary:
	ShaderClock.register() # before any material that reads sim_clock / wind_vec compiles
	if conditions.is_empty():
		conditions = Conditions.resolve()
	# FW-22/23: every material built below reads the chosen hour; no time = the calibrated fixed sun.
	Atmosphere.state = SkyState.state(Ephemeris.sky(conditions.when)) if conditions.time_of_day else {}
	# FW-31…34: at dusk the club lights come on, and the eye adapts to the lit runway (before any material reads the
	# exposure).
	var lights := {}
	if not Atmosphere.state.is_empty() and float(Atmosphere.state.sun_elevation_deg) < FIELD_LIGHTS_BELOW_SUN_DEG:
		var loaded := FieldLights.load_from()
		if loaded.ok:
			lights = loaded.lights
			var centre := runway_centre(field)
			Atmosphere.state = SkyState.adapt(Atmosphere.state,
				ARTIFICIAL_ADAPTATION_WEIGHT * FieldLights.illuminance_at(lights, centre.x, centre.y))
		else:
			push_warning("field lights refused, flying without them: " + "; ".join(loaded.errors))
	var world_environment := WorldEnvironment.new()
	var environment := Atmosphere.environment()
	world_environment.environment = environment
	parent.add_child(world_environment)

	var field_node: Node3D = null
	var t0 := Time.get_ticks_usec()
	if build_field.is_valid():
		build_field.call()
	else:
		field_node = FieldBuilder.build(field)
	var field_build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	if field_node != null:
		parent.add_child(field_node)

	var sun := Atmosphere.create_sun(parent) # the sky shader draws the sun disc from this light
	if not Atmosphere.state.is_empty() and float(Atmosphere.state.sun_elevation_deg) < STARS_BELOW_SUN_DEG:
		parent.add_child(Stars.build(Atmosphere.state, float(conditions.when.latitude_deg))) # FW-24
	if not lights.is_empty():
		parent.add_child(FieldLights.build(lights)) # FW-31…34: visual only
	return {environment = environment, field = field_node, field_build_ms = field_build_ms, sun = sun,
		conditions = conditions, sky = Atmosphere.state}


## The runway's centre (north, east) from openrc-field data; the pilot station when there is no runway.
static func runway_centre(field: Dictionary) -> Vector2:
	for surface: Dictionary in field.get("surfaces", []):
		if surface.get("id", "") == field.get("runway", ""):
			return Vector2(float(surface.center_north), float(surface.center_east))
	var pilot: Dictionary = field.get("pilot", {})
	return Vector2(float(pilot.get("north", 0.0)), float(pilot.get("east", 0.0)))


## Fits the night-flying kit to an airplane's model root when the chosen hour needs it (FW-35). Call after measuring
## the model (Shadow.model_extent) so the kit never changes the pilot-aid shadow. Returns the kit or null.
static func dress_aircraft(root: Node3D) -> Node3D:
	if Atmosphere.state.is_empty() or float(Atmosphere.state.sun_elevation_deg) >= NIGHT_KIT_BELOW_SUN_DEG:
		return null
	return AircraftLights.attach(root)


## Advances the world's visual clock: the shader clock every call, the cloud drift at most once per
## Spec.ATMOSPHERE.cloud_update_s. Returns true when the sky was re-rendered.
static func update(environment: Environment, clock_s: float, wind := Vector3.ZERO) -> bool:
	ShaderClock.update(clock_s, wind)
	return Atmosphere.update_clouds(environment, clock_s)
