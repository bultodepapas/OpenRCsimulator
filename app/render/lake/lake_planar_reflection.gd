## VQ-07: optional native High planar lake capture. Rendering state only.
extends "res://render/lake/vendor/smart_planar_reflector/planar_reflector.gd"

const HighGraphics := preload("res://render/high_graphics_profile.gd")
const ENVIRONMENT_KEY := "OPENRC_LAKE_REFLECTIONS"
const BASIN_LAYER := 4
## Live fields owned by Atmosphere/World. Sky resources remain shared; display
## exposure and tonemapping belong only to the final main-camera image.
const LIVE_ENVIRONMENT_PROPERTIES := [
	"background_mode", "background_energy_multiplier", "background_intensity", "background_color",
	"sky", "sky_custom_fov", "sky_rotation", "ambient_light_source", "ambient_light_color",
	"ambient_light_energy", "ambient_light_sky_contribution", "reflected_light_source",
	"fog_enabled", "fog_mode", "fog_light_color", "fog_light_energy", "fog_sun_scatter",
	"fog_density", "fog_height", "fog_height_density", "fog_aerial_perspective", "fog_sky_affect",
]

var _water: MeshInstance3D
var _water_material: ShaderMaterial
var _probe: ReflectionProbe
var _basin: GeometryInstance3D
var _basin_layers := 0
var _probe_mask := 0
var _prepared := false
var _source_environment: Environment
var _capture_environment: Environment


static func requested() -> bool:
	return HighGraphics.active() and OS.get_environment(ENVIRONMENT_KEY).strip_edges().to_lower() == "planar"


func _enter_tree() -> void:
	# Workshop retains the whole flight tree while a trial runs. Exit clears
	# the material dependency, but the existing viewport survives that detach.
	if initialized and is_instance_valid(_water_material):
		_water_material.set_shader_parameter("reflection_texture", reflect_viewport.get_texture())


func configure(probe: ReflectionProbe, water: MeshInstance3D) -> void:
	_probe = probe
	_water = water
	_water_material = water.material_override as ShaderMaterial
	_probe_mask = probe.reflection_mask
	var bounds := water.mesh.get_aabb()
	var quad := QuadMesh.new()
	quad.size = Vector2(bounds.size.x, bounds.size.z)
	mesh = quad
	position = water.position + bounds.get_center()
	rotation.x = -PI / 2.0
	layers = 0 # Bounds for the downloaded camera algorithm, never an extra water mesh.
	set_surface_override_material(0, _water_material)
	resolution_scale = 0.5
	far = 21000.0
	render_enable_layer = -1
	render_disable_layer = 2
	# Main updates the rendered vehicle and camera at the ordinary process priority.
	process_priority = 100
	_basin = probe.get_parent().get_node_or_null("Basin") as GeometryInstance3D
	if _basin != null:
		_basin_layers = _basin.layers
	_prepared = true


func _process(_delta: float) -> void:
	if not _prepared:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(_water) or not _water.is_visible_in_tree() \
			or camera.projection != Camera3D.PROJECTION_PERSPECTIVE \
			or camera.get_camera_transform().origin.y <= _water.global_position.y + 0.1 \
			or (camera.cull_mask & _water.layers) == 0:
		_set_active(false)
		return
	# Camera3D h/v offsets move the rendered eye away from the node origin.
	# The water-side gate above must use that same eye as the mirrored frustum.
	camera_override = camera
	camera_path = get_path_to(camera)
	if not initialized:
		init_mirror()
		reflect_viewport.msaa_3d = Viewport.MSAA_2X
		reflect_viewport.use_hdr_2d = true # Floating-point, linear viewport texture.
	var main_size: Vector2i = get_viewport().size
	resolution_scale = minf(0.5, minf(1280.0 / maxf(main_size.x, 1.0), 720.0 / maxf(main_size.y, 1.0)))
	update_viewport()
	# Exclude the lake receiver and the basin's dedicated layer, not the aircraft.
	reflect_camera.cull_mask = camera.cull_mask & ~(2 | BASIN_LAYER | 8)
	_sync_environment(camera.environment if camera.environment != null else get_world_3d().environment)
	reflect_camera.attributes = null # Do not expose the captured radiance a second time.
	reflect_camera.keep_aspect = camera.keep_aspect
	reflect_camera.h_offset = camera.h_offset
	reflect_camera.v_offset = camera.v_offset
	_set_active(update_reflect_cam())


func _sync_environment(source: Environment) -> void:
	if source != _source_environment or _capture_environment == null:
		_source_environment = source
		_capture_environment = source.duplicate() if source != null else Environment.new()
		_capture_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_capture_environment.tonemap_exposure = 1.0
		_capture_environment.glow_enabled = false
		_capture_environment.adjustment_enabled = false
		_capture_environment.ssr_enabled = false
	if source != null:
		for property: String in LIVE_ENVIRONMENT_PROPERTIES:
			var value: Variant = source.get(property)
			if _capture_environment.get(property) != value:
				_capture_environment.set(property, value)
	reflect_camera.environment = _capture_environment


func _set_active(enabled: bool) -> void:
	if not is_instance_valid(_water_material) or not is_instance_valid(_probe):
		return
	_water_material.set_shader_parameter("planar_reflection_enabled", enabled)
	if is_instance_valid(_basin):
		# Preserve the static probe's bit 8 even during planar rendering, so its
		# fallback cube still captures the original basin. Restore main-view bits
		# whenever the planar capture is inactive.
		_basin.layers = ((_basin_layers & ~1) | BASIN_LAYER) if enabled else _basin_layers
	# The probe otherwise overrides RADIANCE later in Godot's lighting pass.
	_probe.reflection_mask = 0 if enabled else _probe_mask
	if initialized:
		reflect_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
		if enabled:
			reflect_camera.make_current()
		else:
			reflect_camera.clear_current()


func _exit_tree() -> void:
	_set_active(false)
	if is_instance_valid(_water_material):
		# Break the material -> viewport texture dependency before the viewport dies.
		_water_material.set_shader_parameter("reflection_texture", null)
	if is_instance_valid(_basin):
		_basin.layers = _basin_layers
	_source_environment = null
	_capture_environment = null
