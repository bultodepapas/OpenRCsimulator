# The Home backdrop (MENU-PLAN §3/§7, UI-01c, UI-05): the selected airplane (the Ugly Stik by default) over our
# field, rendered from the same builders the flight uses (sky, clouds, grass, runway, sun, the model team's airplane), posed in a fixed, still composition.
# No simulation, no input, no animation: shaders get a fixed sim_clock, so every frame is the same picture.
# A live still render follows the current models, imported tree atlas and landscape.
# World (render/world/world.gd, FW-02) composes the environment, field and sun exactly as the flight does.
extends Node3D

const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Shadow := preload("res://render/shadow.gd")
const ProjectedShadow := preload("res://render/projected_shadow.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const World := preload("res://render/world/world.gd")
const HeliNightLights = preload("res://render/rotor/heli_night_lights.gd")
const FieldError = preload("res://ui/field_error.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")

## Composition, in NED metres from the pilot's eyes and degrees: a low pass along the runway at eye height, banked
## toward the camera so the planform shows, seen with a long lens from the field edge (a photographer's view:
## flat perspective, the horizon in the lower third, the airplane in the right third facing the menu).
const AIRPLANE_NED := [15.0, 3.0, -1.05]
const ATTITUDE_DEG := { yaw = -112.0, pitch = 2.0, roll = -30.0 }
const HELICOPTER_ATTITUDE_DEG := { yaw = -112.0, pitch = 0.0, roll = 0.0 }
const CAMERA_NED := [2.0, 3.0, 0.0]
const FOV_DEG := 12.0
## The camera looks this far left of the airplane (deg), and this far above the horizon (deg).
const AIRPLANE_RIGHT_DEG := 4.5
const CAMERA_PITCH_DEG := 3.2
const PROP_ANGLE := 0.6 # rad: a blade off the vertical reads better than a single line
## Fixed clock (s) for clouds and any time-based shader: a still picture.
const CLOCK := 37.0

var field: Dictionary = {}
var lighting_config: Dictionary = {}
var night_options: Dictionary = Preferences.NIGHT_DEFAULTS.duplicate(true)
var sky_config: Dictionary = SkyConfig.defaults()
var _lighting: Dictionary = {}
var field_errors: PackedStringArray = PackedStringArray()

# Bound retained geometry to the current Home: one visible model and two recent selections.
const PREVIEW_MODEL_LIMIT := 3
var _preview_models: Dictionary = {}
var _preview_geometry: Dictionary = {}
var _preview_order: Array[String] = []

signal preview_state_changed(id: String, state: String)
var preview_resources: Node
var preview_pending := false
var requested_aircraft := ""
var _preview_generation := 0

var airplane: Dictionary
var camera: Camera3D
var _shadow: MeshInstance3D


## `aircraft`: the catalog ID to show (app_state/aircraft_catalog.gd); show_aircraft() swaps it in place.
func _init(aircraft := AirplaneBuilder.STIK_ID, field_path: String = FieldLoader.DEFAULT_PATH, selected_lighting: Dictionary = {}, selected_night_options: Dictionary = {}, selected_sky: Dictionary = {}) -> void:
	name = "HomeScene"
	var checked_light: Dictionary = LightingConfig.validate(LightingConfig.defaults() if selected_lighting.is_empty() else selected_lighting)
	if not checked_light.ok:
		field_errors = PackedStringArray(checked_light.errors)
		return
	lighting_config = checked_light.config.duplicate(true)
	var checked_night: Dictionary = Preferences.validate_night_options(
		Preferences.NIGHT_DEFAULTS if selected_night_options.is_empty() else selected_night_options
	)
	if not checked_night.get("ok", false):
		field_errors = PackedStringArray(checked_night.errors)
		return
	night_options = checked_night.options.duplicate(true)
	_lighting = TimeOfDayLighting.snapshot(lighting_config)
	var loaded_field: Dictionary = FieldLoader.load_from(field_path)
	field_errors = loaded_field.errors
	if not loaded_field.ok:
		return
	field = loaded_field.field
	var checked_sky: Dictionary = SkyConfig.validate(SkyConfig.defaults() if selected_sky.is_empty() else selected_sky)
	if not checked_sky.ok:
		field_errors = PackedStringArray(checked_sky.errors)
		return
	sky_config = checked_sky.config
	Atmosphere.configure_appearance(sky_config)
	var snapshot: Dictionary = _lighting if lighting_config.get("mode", "legacy") != "legacy" else {}
	var env: Environment = World.build(self, field, Callable(), {}, snapshot, night_options).environment

	_shadow = Shadow.create(self)
	show_aircraft(aircraft)
	var pos := _composition_position(AIRPLANE_NED)

	camera = Camera3D.new()
	camera.fov = FOV_DEG
	camera.near = Spec.CAMERA.near
	camera.far = Spec.CAMERA.far
	add_child(camera)
	camera.position = _composition_position(CAMERA_NED)
	var to_airplane := pos - camera.position
	var azimuth := atan2(to_airplane.x, -to_airplane.z) - deg_to_rad(AIRPLANE_RIGHT_DEG) # render: x east, -z north
	var elevation := deg_to_rad(CAMERA_PITCH_DEG)
	var look := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
	camera.look_at_from_position(camera.position, camera.position + look, Vector3.UP)
	camera.current = true

	World.update(env, CLOCK, Vector3.ZERO, _composition_position(AIRPLANE_NED), camera) # FW-23: the eye adapts to the view
	_update_helicopter_lights()


func _composition_position(offset_ned: Array) -> Vector3:
	return Frames.ned_to_render([
		float(field.pilot.north) + float(offset_ned[0]),
		float(field.pilot.east) + float(offset_ned[1]),
		float(field.pilot.down) - float(field.pilot.eye_height) + float(offset_ned[2]),
	])


func _ready() -> void:
	if not field_errors.is_empty():
		FieldError.report(self, field_errors)


## Shows `id` in the fixed pose, retaining at most three recent visual models for this Home only.
## Flight still builds and validates independently; replacing Home drops the cache and its resources.
func show_aircraft(id: String) -> bool:
	var retained := _preview_models.has(id)
	var built: Dictionary = _preview_models[id] if retained else AirplaneBuilder.build(id)
	if built.is_empty():
		return false
	if not airplane.is_empty():
		airplane.root.hide()
		airplane.root.process_mode = Node.PROCESS_MODE_DISABLED
	airplane = built
	if not retained:
		_preview_models[id] = built
		add_child(airplane.root)
	airplane.root.show()
	airplane.root.process_mode = Node.PROCESS_MODE_INHERIT
	_preview_order.erase(id)
	_preview_order.append(id)
	if _preview_order.size() > PREVIEW_MODEL_LIMIT:
		var evicted: String = _preview_order.pop_front()
		var obsolete: Node3D = _preview_models[evicted].root
		_preview_models.erase(evicted)
		_preview_geometry.erase(evicted)
		remove_child(obsolete)
		obsolete.queue_free()
	var rotorcraft: bool = Catalog.is_rotorcraft(id)
	var attitude: Dictionary = HELICOPTER_ATTITUDE_DEG if rotorcraft else ATTITUDE_DEG
	var basis := Frames.attitude_to_render(deg_to_rad(attitude.yaw), deg_to_rad(attitude.pitch), deg_to_rad(attitude.roll))
	var pos := _composition_position(AIRPLANE_NED)
	var model_cg: Vector3 = airplane.get("cg_model_m", Vector3.ZERO) if rotorcraft else Vector3.ZERO
	airplane.root.transform = Frames.root_transform(basis, pos, model_cg)
	if rotorcraft:
		var main_pivot: Node3D = airplane.get("main_rotor_pivot") as Node3D
		if main_pivot != null:
			main_pivot.rotation.z = PROP_ANGLE
	else:
		airplane.propeller.rotation.z = PROP_ANGLE
	if not retained:
		# Capture the neutral model before the night kit is fitted; it must not enter the silhouette.
		_preview_geometry[id] = {extent = Shadow.model_extent(airplane.root), shape = ProjectedShadow.collect(airplane.root)}
	var geometry: Dictionary = _preview_geometry[id]
	var extent: Vector2 = geometry.extent
	Shadow.bind_model(_shadow, airplane.root, geometry.shape)
	if not retained:
		if rotorcraft:
			HeliNightLights.attach(airplane)
		else:
			World.dress_aircraft(airplane.root)
	_update_helicopter_lights()
	var snapshot_lighting: bool = lighting_config.get("mode", "legacy") != "legacy"
	var strength: float = Atmosphere.shadow_strength(_lighting) if snapshot_lighting else 1.0
	_shadow.visible = strength > 0.0
	var direction: Vector3 = Atmosphere.sun_direction(_lighting) if snapshot_lighting else Atmosphere.shadow_direction()
	Shadow.update(_shadow, basis, pos, extent.x, extent.y, direction, strength)

	return true


func _update_helicopter_lights() -> void:
	if airplane.is_empty(): return
	var kit: Node3D = airplane.root.get_node_or_null("HelicopterNightKit")
	if kit != null:
		kit.update_visual(HeliNightLights.sun_elevation(_lighting, Atmosphere.state), World.Exposure.last)


## The card updates immediately. Cache misses allow a frame to present before
## starting resource preparation; only the most recent intent may build a model.
func request_aircraft(id: String) -> void:
	_preview_generation += 1
	requested_aircraft = id
	if is_instance_valid(preview_resources): preview_resources.cancel_for(self, false)
	if _preview_models.has(id):
		preview_pending = false
		preview_state_changed.emit(id, "ready" if show_aircraft(id) else "failed")
		return
	preview_pending = true
	preview_state_changed.emit(id, "loading")
	_prepare_preview(id, _preview_generation)


func _prepare_preview(id: String, generation: int) -> void:
	if not is_inside_tree(): return
	# process_frame precedes node processing, so two boundaries guarantee one
	# opportunity to render the new card even for requests made during input.
	await get_tree().process_frame
	if not _current_preview(id, generation): return
	await get_tree().process_frame
	if not _current_preview(id, generation): return
	if is_instance_valid(preview_resources):
		preview_resources.request(preview_resources.path_for(id), _preview_resource_ready.bind(id, generation))
	else:
		_preview_resource_ready(true, id, generation)


func _current_preview(id: String, generation: int) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and generation == _preview_generation and id == requested_aircraft


func _preview_resource_ready(ok: bool, id: String, generation: int) -> void:
	if not _current_preview(id, generation): return
	var shown := ok and show_aircraft(id)
	preview_pending = false
	preview_state_changed.emit(id, "ready" if shown else "failed")


func _exit_tree() -> void:
	_preview_generation += 1
	if is_instance_valid(preview_resources): preview_resources.cancel_for(self)


func _enter_tree() -> void:
	# Ground-vehicle/failed-flight routes may temporarily detach the same Home.
	if preview_pending: request_aircraft.call_deferred(requested_aircraft)
