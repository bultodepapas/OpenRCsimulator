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
const Landscapes = preload("res://landscapes/catalog.gd")
const World := preload("res://render/world/world.gd")
const HeliNightLights = preload("res://render/rotor/heli_night_lights.gd")
const FieldError = preload("res://ui/field_error.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Presentation := preload("res://ui/home_presentation.gd")

## Render-only parked presentation. Contact points come from the visual wheels/skids;
## the simulator's start state and aircraft configuration remain independent.
const PARKED_YAW_DEG := 80.0
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
## F4U-16: the requested preview's paint scheme; "" is the default paint (AirplaneBuilder.resolve_livery).
var requested_livery := ""
var _preview_generation := 0

var airplane: Dictionary
var camera: Camera3D
var _shadow: MeshInstance3D
var _environment: Environment
var _presentation: Dictionary = {}


## `aircraft`: the catalog ID to show (app_state/aircraft_catalog.gd); show_aircraft() swaps it in place.
func _init(aircraft := AirplaneBuilder.STIK_ID, field_path: String = FieldLoader.DEFAULT_PATH, selected_lighting: Dictionary = {}, selected_night_options: Dictionary = {}, selected_sky: Dictionary = {}, landscape_id: String = Landscapes.DEFAULT_ID, livery := "") -> void:
	name = "HomeScene"
	if not Landscapes.has(landscape_id):
		field_errors = PackedStringArray(["Unknown landscape: " + landscape_id])
		return
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
	var build_field := func() -> void: add_child(Landscapes.build(landscape_id, field, snapshot))
	_environment = World.build(self, field, build_field, {}, snapshot, night_options).environment

	_shadow = Shadow.create(self)
	requested_livery = livery
	show_aircraft(aircraft, livery)
	camera = Camera3D.new()
	camera.near = Spec.CAMERA.near
	camera.far = Spec.CAMERA.far
	add_child(camera)
	camera.current = true


func _parking_position(lift: float) -> Vector3:
	for surface: Dictionary in field.surfaces:
		if surface.id == field.runway:
			# Ordinary fields consolidate the runway into ground. Other accepted
			# layouts retain a raised render plane; support the model on that plane.
			var rendered_surface := get_node_or_null(NodePath("Field/" + str(surface.id))) as Node3D
			var ground_height := rendered_surface.position.y if rendered_surface != null else 0.0
			return Vector3(float(surface.center_east) + minf(7.0, float(surface.length_east_west) * 0.07), lift + ground_height, -float(surface.center_north))
	return Vector3(float(field.pilot.east) + 7.0, lift, -float(field.pilot.north) - 15.0)


func _frame_aircraft() -> void:
	if not is_inside_tree() or camera == null or _presentation.is_empty(): return
	Presentation.fit(camera, airplane.root, _presentation.bounds, get_viewport().get_visible_rect().size)
	World.update(_environment, CLOCK, Vector3.ZERO, airplane.root.position, camera)
	_update_aircraft_lights()


func _ready() -> void:
	if not field_errors.is_empty():
		FieldError.report(self, field_errors)
		return
	get_viewport().size_changed.connect(_frame_aircraft)
	_frame_aircraft()


## Shows `id` in the fixed pose, retaining at most three recent visual models for this Home only.
## Flight still builds and validates independently; replacing Home drops the cache and its resources.
## A non-default `livery` (F4U-16) is its own cached model.
func show_aircraft(id: String, livery := "") -> bool:
	var key := _preview_key(id, livery)
	var retained := _preview_models.has(key)
	var built: Dictionary = _preview_models[key] if retained else AirplaneBuilder.build(id, NAN, {}, livery)
	if built.is_empty():
		return false
	if not airplane.is_empty():
		airplane.root.hide()
		airplane.root.process_mode = Node.PROCESS_MODE_DISABLED
	airplane = built
	if not retained:
		_preview_models[key] = built
		add_child(airplane.root)
	airplane.root.show()
	airplane.root.process_mode = Node.PROCESS_MODE_INHERIT
	_preview_order.erase(key)
	_preview_order.append(key)
	if _preview_order.size() > PREVIEW_MODEL_LIMIT:
		var evicted: String = _preview_order.pop_front()
		var obsolete: Node3D = _preview_models[evicted].root
		_preview_models.erase(evicted)
		_preview_geometry.erase(evicted)
		remove_child(obsolete)
		obsolete.queue_free()
	var rotorcraft: bool = Catalog.is_rotorcraft(id)
	if not retained:
		_preview_geometry[key] = {presentation = Presentation.prepare(airplane)}
	_presentation = _preview_geometry[key].presentation
	var basis := Frames.attitude_to_render(deg_to_rad(PARKED_YAW_DEG), 0.0, 0.0) * (_presentation.alignment as Basis)
	var pos := _parking_position(_presentation.lift)
	airplane.root.transform = Transform3D(basis, pos)
	if rotorcraft:
		var main_pivot: Node3D = airplane.get("main_rotor_pivot") as Node3D
		if main_pivot != null:
			main_pivot.rotation.z = PROP_ANGLE
	else:
		airplane.propeller.rotation.z = PROP_ANGLE
	if not retained:
		# Capture the neutral model before the night kit is fitted; it must not enter the silhouette.
		_presentation.bounds = Presentation.mesh_bounds(airplane.root, airplane.root)
		_preview_geometry[key].merge({extent = Shadow.model_extent(airplane.root), shape = ProjectedShadow.collect(airplane.root)})
	var geometry: Dictionary = _preview_geometry[key]
	var extent: Vector2 = geometry.extent
	Shadow.bind_model(_shadow, airplane.root, geometry.shape)
	if not retained:
		if rotorcraft:
			HeliNightLights.attach(airplane)
	_update_aircraft_lights()
	var snapshot_lighting: bool = lighting_config.get("mode", "legacy") != "legacy"
	var strength: float = Atmosphere.shadow_strength(_lighting) if snapshot_lighting else Atmosphere.shadow_strength() # FW-MOON-03
	_shadow.visible = strength > 0.0
	var direction: Vector3 = Atmosphere.sun_direction(_lighting) if snapshot_lighting else Atmosphere.shadow_direction()
	Shadow.update(_shadow, basis, pos, extent.x, extent.y, direction, strength * 0.65)
	_frame_aircraft()

	return true


func _update_aircraft_lights() -> void:
	if airplane.is_empty(): return
	var kit: Node3D = airplane.root.get_node_or_null("HelicopterNightKit")
	if kit != null:
		kit.update_visual(HeliNightLights.sun_elevation(_lighting, Atmosphere.state), World.Exposure.last, {}, 0.0, 0.0, false,
			World.aircraft_local_seconds(lighting_config, CLOCK))
	else:
		World.dress_aircraft(airplane.root, lighting_config, _lighting, CLOCK)


## The card updates immediately. Cache misses allow a frame to present before
## starting resource preparation; only the most recent intent may build a model.
func request_aircraft(id: String, livery := "") -> void:
	_preview_generation += 1
	requested_aircraft = id
	requested_livery = livery
	if is_instance_valid(preview_resources): preview_resources.cancel_for(self, false)
	if _preview_models.has(_preview_key(id, livery)):
		preview_pending = false
		preview_state_changed.emit(id, "ready" if show_aircraft(id, livery) else "failed")
		return
	preview_pending = true
	preview_state_changed.emit(id, "loading")
	_prepare_preview(id, livery, _preview_generation)


static func _preview_key(id: String, livery: String) -> String:
	return id if livery.is_empty() else id + "#" + livery


func _prepare_preview(id: String, livery: String, generation: int) -> void:
	if not is_inside_tree(): return
	# process_frame precedes node processing, so two boundaries guarantee one
	# opportunity to render the new card even for requests made during input.
	await get_tree().process_frame
	if not _current_preview(id, livery, generation): return
	await get_tree().process_frame
	if not _current_preview(id, livery, generation): return
	if is_instance_valid(preview_resources):
		var path: String = preview_resources.path_for(id) if livery.is_empty() else preview_resources.path_for(id, livery)
		preview_resources.request(path, _preview_resource_ready.bind(id, livery, generation))
	else:
		_preview_resource_ready(true, id, livery, generation)


func _current_preview(id: String, livery: String, generation: int) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and generation == _preview_generation and id == requested_aircraft 		and livery == requested_livery


func _preview_resource_ready(ok: bool, id: String, livery: String, generation: int) -> void:
	if not _current_preview(id, livery, generation): return
	var shown := ok and show_aircraft(id, livery)
	preview_pending = false
	preview_state_changed.emit(id, "ready" if shown else "failed")


func _exit_tree() -> void:
	_preview_generation += 1
	if is_instance_valid(preview_resources): preview_resources.cancel_for(self)


func _enter_tree() -> void:
	# Ground-vehicle/failed-flight routes may temporarily detach the same Home.
	if preview_pending: request_aircraft.call_deferred(requested_aircraft, requested_livery)
