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
const PreviewGeometry := preload("res://ui/home_preview_geometry.gd")
const Conditions := preload("res://render/world/conditions.gd")

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
# Await a Home-owned signal so removing or freeing this scene cannot leave a
# coroutine connected to the longer-lived SceneTree.
signal _preview_frame
var preview_resources: Node
var preview_geometry: Node
var presentation_pending := false
var _presentation_generation := 0
var _preview_failed := false
var _pending_presentation: Dictionary = {}
var _source_field_path := ""
var _source_field_hash := ""
var _source_landscape := ""
var _world: Dictionary = {}
var _preview_candidate: Node3D
signal presentation_refresh_failed
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
	_source_field_path = field_path
	_source_landscape = landscape_id
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
	_source_field_hash = FileAccess.get_sha256(field_path)
	var checked_sky: Dictionary = SkyConfig.validate(SkyConfig.defaults() if selected_sky.is_empty() else selected_sky)
	if not checked_sky.ok:
		field_errors = PackedStringArray(checked_sky.errors)
		return
	sky_config = checked_sky.config
	Atmosphere.configure_appearance(sky_config)
	var snapshot: Dictionary = _lighting if lighting_config.get("mode", "legacy") != "legacy" else {}
	var build_field := func() -> void: add_child(Landscapes.build(landscape_id, field, snapshot))
	_world = World.build(self, field, build_field, {}, snapshot, night_options)
	_world.field = get_node_or_null("Field")
	_environment = _world.environment

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
	if airplane.root.get_parent() == null:
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
		# A hull-rested (gearless) airplane parks its blades level, clear of the field.
		airplane.propeller.rotation.z = float(_presentation.get("propeller_angle", PROP_ANGLE))
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
		var geometry: Dictionary = _preview_geometry[_preview_order.back()]
		var layout: Dictionary = geometry.get("light_layout", {})
		var layout_key := ""
		if airplane.root.get_node_or_null("NightKit") == null:
			layout_key = _light_layout_key(airplane)
			if not layout_key.is_empty():
				for cached: Dictionary in _preview_geometry.values():
					if cached.get("light_layout_key", "") == layout_key:
						layout = cached.get("light_layout", {})
						break
		kit = World.dress_aircraft(airplane.root, lighting_config, _lighting, CLOCK, layout)
		if kit != null:
			geometry.light_layout = kit.get_meta("geometry_layout")
		if kit != null and not layout_key.is_empty():
			# Share only compact measurements, bounded by the existing three previews.
			geometry.light_layout_key = layout_key
			geometry.light_layout = kit.get_meta("geometry_layout")


## Imported liveries are validated against one generated airframe. Include the
## full manifest identity and every local pose (including propeller scale), so
## different aircraft revisions, equipment or articulation cannot share a layout.
## The world pose is irrelevant. Flight and unregistered models never use this cache.
static func _light_layout_key(model: Dictionary) -> String:
	var manifest: Dictionary = model.get("model_manifest", {})
	var identity: String = model.get("model_manifest_sha256", "")
	if identity.is_empty() or manifest.get("builder", {}).get("adapter", "") != "imported_glb" or manifest.get("liveries", []).size() < 2:
		return ""
	var model_root: Node3D = model.root
	var poses: Array = []
	for node: Node in model_root.find_children("*", "Node3D", true, false):
		if str(node.name) == "NightKit" or model_root.get_node_or_null("NightKit") != null and model_root.get_node("NightKit").is_ancestor_of(node):
			continue
		poses.append([str(model_root.get_path_to(node)), (node as Node3D).transform])
	# The presence of an authored landing seat determines whether a fallback is traced.
	poses.append((model_root.get_meta("light_anchors", {}) as Dictionary).has("landing"))
	return identity + ":" + var_to_bytes(poses).hex_encode().sha256_text()


## The card updates immediately. Cache misses allow a frame to present before
## starting resource preparation; only the most recent intent may build a model.
func request_aircraft(id: String, livery := "") -> void:
	_preview_generation += 1
	requested_aircraft = id
	requested_livery = livery
	_preview_failed = false
	_discard_preview_candidate()
	if is_instance_valid(preview_resources): preview_resources.cancel_for(self, false)
	if _preview_models.has(_preview_key(id, livery)):
		preview_pending = false
		_preview_failed = not show_aircraft(id, livery)
		_publish_preview_state()
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
	await _preview_frame
	if not _current_preview(id, livery, generation): return
	await _preview_frame
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
	if not ok:
		_finish_preview(false)
	elif not is_instance_valid(preview_geometry):
		_finish_preview(show_aircraft(id, livery))
	else:
		_build_requested_preview(id, livery, generation)


var retain_resources_on_exit := false


## Loading owns the next scene. Invalidate callbacks before they can block its first feedback frame.
func suspend_preview() -> void:
	_preview_generation += 1
	_presentation_generation += 1
	_discard_preview_candidate()
	if is_instance_valid(preview_geometry): preview_geometry.cancel_for(self)
	if is_instance_valid(preview_resources): preview_resources.cancel_for(self, false)


func resume_preview() -> void:
	if preview_pending: request_aircraft.call_deferred(requested_aircraft, requested_livery)
	if presentation_pending and not _pending_presentation.is_empty():
		_presentation_generation += 1
		_apply_pending_presentation.call_deferred(_presentation_generation)


func _exit_tree() -> void:
	_preview_generation += 1
	_presentation_generation += 1
	# Wake nested waits while this script still exists. Their generation checks
	# reject the old work before the relay is disconnected, even when processing
	# is disabled or the scene is freed immediately after detachment.
	_preview_frame.emit()
	if get_tree().process_frame.is_connected(_relay_preview_frame):
		get_tree().process_frame.disconnect(_relay_preview_frame)
	_discard_preview_candidate()
	if is_instance_valid(preview_geometry): preview_geometry.cancel_for(self)
	if is_instance_valid(preview_resources): preview_resources.cancel_for(self, not retain_resources_on_exit)


func _enter_tree() -> void:
	get_tree().process_frame.connect(_relay_preview_frame)
	# Ground-vehicle/failed-flight routes may temporarily detach the same Home.
	resume_preview()


func _relay_preview_frame() -> void:
	_preview_frame.emit()


func _publish_preview_state() -> void:
	var id: String = requested_aircraft if not requested_aircraft.is_empty() else str(airplane.get("aircraft_id", ""))
	preview_state_changed.emit(id, "loading" if preview_pending or presentation_pending else ("failed" if _preview_failed else "ready"))


func _finish_preview(shown: bool) -> void:
	preview_pending = false
	_preview_failed = not shown
	_publish_preview_state()


func _release_candidate(candidate: Variant) -> void:
	if not is_instance_valid(candidate): return
	if _preview_candidate == candidate: _preview_candidate = null
	(candidate as Node).queue_free()


func _discard_preview_candidate() -> void:
	_release_candidate(_preview_candidate)
	_preview_candidate = null


## Build an accepted model on main; yield between preparation phases. Only
## immutable numeric fitting runs on the root-owned worker.
func _build_requested_preview(id: String, livery: String, generation: int) -> void:
	while preview_geometry.busy():
		await _preview_frame
		if not _current_preview(id, livery, generation): return
	var built: Dictionary = AirplaneBuilder.build(id, NAN, {}, livery)
	if built.is_empty():
		_finish_preview(false)
		return
	_preview_candidate = built.root
	var current := func() -> bool: return _current_preview(id, livery, generation) and is_instance_valid(built.get("root"))
	await _preview_frame
	if not current.call():
		_release_candidate(built.get("root"))
		return
	var presentation: Dictionary = Presentation.prepare(built)
	var basis := Frames.attitude_to_render(deg_to_rad(PARKED_YAW_DEG), 0.0, 0.0) * (presentation.alignment as Basis)
	built.root.transform = Transform3D(basis, _parking_position(presentation.lift))
	if Catalog.is_rotorcraft(id):
		var pivot: Node3D = built.get("main_rotor_pivot") as Node3D
		if pivot != null: pivot.rotation.z = PROP_ANGLE
	else:
		built.propeller.rotation.z = float(presentation.get("propeller_angle", PROP_ANGLE))
	await _preview_frame
	if not current.call():
		_release_candidate(built.get("root"))
		return
	presentation.bounds = Presentation.mesh_bounds(built.root, built.root)
	var geometry := {presentation = presentation, extent = Shadow.model_extent(built.root), shape = ProjectedShadow.collect(built.root)}
	if Catalog.is_rotorcraft(id): HeliNightLights.attach(built)
	if not Catalog.is_rotorcraft(id) and _needs_night_layout(lighting_config, Conditions.resolve()):
		var layout: Dictionary = await _prepare_light_layout(built.root, current)
		if not current.call():
			_release_candidate(built.get("root"))
			return
		if layout.is_empty():
			_release_candidate(built.get("root"))
			_finish_preview(false)
			return
		geometry.light_layout = layout
	if not current.call():
		_release_candidate(built.get("root"))
		return
	var key := _preview_key(id, livery)
	_preview_models[key] = built
	_preview_geometry[key] = geometry
	_preview_candidate = null
	_finish_preview(show_aircraft(id, livery))


func _prepare_light_layout(model: Node3D, current: Callable) -> Dictionary:
	while preview_geometry.busy():
		await _preview_frame
		if not current.call() or not is_instance_valid(model): return {}
	var snapshot := PreviewGeometry.Snapshot.new(model)
	while not snapshot.advance():
		await _preview_frame
		if not current.call() or not is_instance_valid(model): return {}
	if snapshot.failed or not current.call(): return {}
	while preview_geometry.busy():
		await _preview_frame
		if not current.call(): return {}
	var completion := {done = false, layout = {}}
	var receive := func(layout: Dictionary) -> void:
		# Bind the callback to Home so cancel_for(self) can suppress it while the
		# broker still drains its worker, and reject a superseded result.
		if not is_inside_tree() or not current.call(): return
		completion.layout = layout
		completion.done = true
	if not preview_geometry.request(snapshot.data, receive): return {}
	while not completion.done:
		await _preview_frame
		if not current.call(): return {}
	return completion.layout


## Evaluate the target policy without publishing any global atmosphere/flow.
func _needs_night_layout(config: Dictionary, conditions: Dictionary) -> bool:
	var light := World.AircraftLightState.new()
	var local_seconds := NAN
	var elevation := 45.0
	if config.get("mode", "legacy") != "legacy":
		local_seconds = float(config.local_seconds)
		elevation = float(TimeOfDayLighting.snapshot(config).solar.elevation_deg)
	elif bool(conditions.get("time_of_day", false)):
		var when: Dictionary = World.MoonConfig.apply_phase(conditions.when, World.MoonConfig.resolve())
		when.hour = float(when.hour) + CLOCK * float(conditions.get("time_scale", 0.0)) / 3600.0
		local_seconds = fposmod(float(when.hour) * 3600.0, 86400.0)
		elevation = float(World.Ephemeris.sky(when).sun.elevation_deg)
	light.update(local_seconds, 1.0 if elevation < World.NIGHT_KIT_BELOW_SUN_DEG else 0.0)
	return light.active_mode != "off"


func can_refresh_presentation(field_path: String, landscape_id: String) -> bool:
	return field_path == _source_field_path and landscape_id == _source_landscape \
		and FileAccess.file_exists(field_path) and FileAccess.get_sha256(field_path) == _source_field_hash


## Keep independent preview and world intents. A reversal invalidates fitting,
## not another aircraft's resource request or pending/error indication.
func refresh_presentation(selected_lighting: Dictionary, selected_night: Dictionary, selected_sky: Dictionary) -> bool:
	var light: Dictionary = LightingConfig.validate(selected_lighting)
	var night: Dictionary = Preferences.validate_night_options(selected_night)
	var sky: Dictionary = SkyConfig.validate(selected_sky)
	if not light.ok or not night.ok or not sky.ok: return false
	_presentation_generation += 1
	_pending_presentation = {config = light.config, night = night.options, sky = sky.config, conditions = Conditions.resolve()}
	if not is_instance_valid(preview_geometry) or not _presentation_needs_layout():
		return _commit_presentation(_presentation_generation)
	presentation_pending = true
	_publish_preview_state()
	_apply_pending_presentation(_presentation_generation)
	return true


func _presentation_needs_layout() -> bool:
	if airplane.is_empty() or Catalog.is_rotorcraft(str(airplane.get("aircraft_id", ""))): return false
	if airplane.root.get_node_or_null("NightKit") != null: return false
	var geometry: Dictionary = _preview_geometry[_preview_order.back()]
	return not geometry.has("light_layout") and _needs_night_layout(_pending_presentation.config, _pending_presentation.conditions)


func _apply_pending_presentation(generation: int) -> void:
	var current := func() -> bool:
		return is_inside_tree() and not is_queued_for_deletion() and generation == _presentation_generation
	while current.call() and _presentation_needs_layout():
		var key: String = _preview_order.back()
		var model: Node3D = airplane.root
		var layout: Dictionary = await _prepare_light_layout(model, current)
		if not current.call(): return
		if is_instance_valid(model) and _preview_models.has(key) and _preview_models[key].root == model and not layout.is_empty():
			_preview_geometry[key].light_layout = layout
		elif not is_instance_valid(model) or airplane.root != model:
			continue
		elif layout.is_empty():
			presentation_pending = false
			_pending_presentation.clear()
			_publish_preview_state()
			presentation_refresh_failed.emit()
			return
	if current.call() and not _commit_presentation(generation):
		presentation_refresh_failed.emit()


func _commit_presentation(generation: int) -> bool:
	if generation != _presentation_generation or _pending_presentation.is_empty(): return false
	var request: Dictionary = _pending_presentation
	var snapshot: Dictionary = TimeOfDayLighting.snapshot(request.config) if request.config.get("mode", "legacy") != "legacy" else {}
	var result: Dictionary = World.refresh_presentation(self, get_node_or_null("Field"), _world,
		request.conditions, snapshot, request.night, request.sky)
	presentation_pending = false
	_pending_presentation = {}
	if not result.get("ok", false):
		_publish_preview_state()
		return false
	_world = result
	_environment = result.environment
	lighting_config = request.config
	night_options = request.night
	sky_config = request.sky
	_lighting = TimeOfDayLighting.snapshot(lighting_config)
	# Reapply the selected cached model's shadow and emission at the same still clock.
	if not airplane.is_empty():
		show_aircraft(str(airplane.aircraft_id), requested_livery if str(airplane.aircraft_id) == requested_aircraft else str(airplane.get("livery", "")))
	_publish_preview_state()
	return true
