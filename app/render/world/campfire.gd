## Optional visual campfire for the field. The scaled downloaded log base stays in the world when the
## flame option is off; only its atlas sprites, embers and bounded local light are toggled.
extends Node3D

const BASE_SCENE: PackedScene = preload("res://assets/landscape/night-lighting/campfire-pit.glb")
const FLAME_ATLAS: Texture2D = preload("res://assets/landscape/night-lighting/flames-8x10.png")
const FLAME_SHADER: Shader = preload("res://render/world/campfire_flame.gdshader")

const VISUAL_SCALE := 3.6
const ATLAS_COLUMNS := 8
const FRAME_COUNT := 40
const FRAME_WIDTH := 81
const FRAME_HEIGHT := 123
const FRAME_PADDING := 32
const CELL_WIDTH := 145
const CELL_HEIGHT := 187
const FLAME_SPRITE_COUNT := 5
const EMBER_COUNT := 8
const PARTICLE_COUNT := FLAME_SPRITE_COUNT + EMBER_COUNT
const FLAME_PIXEL_SIZE := 0.0013
const FLAME_LIFETIME_BASE_S := 0.82
const FLAME_LIFETIME_STEP_S := 0.075
const EMBER_PERIOD_S := 2.65
const EMBER_LIFETIME_BASE_S := 0.68
const EMBER_LIFETIME_STEP_S := 0.11
const FLAME_BASE_GAIN := 0.85
const FLAME_DISPLAY_CAP := 1.1
const EMBER_BASE_GAIN := 0.24
const EMBER_DISPLAY_CAP := 0.40
const OMNI_BASE_ENERGY := 0.75
const OMNI_DISPLAY_CAP := 0.35
const OMNI_RANGE_M := 4.2
const LIGHTS_ON_ELEVATION_DEG := 3.0
const FULL_NIGHT_ELEVATION_DEG := -4.0

var _scaled_visuals: Node3D
var _flame_group: Node3D
var _ember_instance: MultiMeshInstance3D
var _ember_material: StandardMaterial3D
var _firelight: OmniLight3D
var _flames: Array[Sprite3D] = []
var _flame_materials: Array[ShaderMaterial] = []
var _flame_origins: Array[Vector3] = []
var _environment: Environment
var _enabled := false
var _local_gain := 1.0
var _clock_s := 0.0
var _wind := Vector3.ZERO


## Creates the persistent log base and effect nodes once. The effects remain deterministic because all animation
## is derived from the supplied visual simulation clock; this helper does not run its own process callback.
static func build() -> Node3D:
	var script: GDScript = load("res://render/world/campfire.gd")
	var campfire: Node3D = script.new()
	campfire.name = "Campfire"
	campfire.call("_build_nodes")
	return campfire


func _build_nodes() -> void:
	set_process(false)
	_scaled_visuals = Node3D.new()
	_scaled_visuals.name = "ScaledVisuals"
	_scaled_visuals.scale = Vector3.ONE * VISUAL_SCALE
	add_child(_scaled_visuals)
	var base := BASE_SCENE.instantiate() as Node3D
	if base == null:
		push_error("Campfire: could not instantiate selected Kenney campfire base")
	else:
		base.name = "CampfireBase"
		_scaled_visuals.add_child(base)
	_flame_group = Node3D.new()
	_flame_group.name = "FlameSprites"
	_scaled_visuals.add_child(_flame_group)
	_build_flame_sprites()
	_build_embers()
	_build_light()
	set_enabled(false)
	update_visual(0.0, Vector3.ZERO)


func _build_flame_sprites() -> void:
	for index in FLAME_SPRITE_COUNT:
		var sprite := Sprite3D.new()
		sprite.name = "Flame%02d" % index
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.pixel_size = FLAME_PIXEL_SIZE
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.texture = FLAME_ATLAS
		sprite.region_enabled = true
		sprite.region_rect = _flame_rect(0)
		var flame_material := ShaderMaterial.new()
		flame_material.shader = FLAME_SHADER
		flame_material.set_shader_parameter("flame_atlas", FLAME_ATLAS)
		sprite.material_override = flame_material
		_flame_materials.append(flame_material)
		_flame_group.add_child(sprite)
		_flames.append(sprite)
		var angle := TAU * float(index) / float(FLAME_SPRITE_COUNT)
		var radius := 0.028 + 0.018 * float(index % 3) / 2.0
		_flame_origins.append(Vector3(cos(angle) * radius, 0.16 + 0.010 * float(index % 4), sin(angle) * radius))


func _build_embers() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.006
	mesh.height = 0.012
	mesh.radial_segments = 6
	mesh.rings = 3
	_ember_material = StandardMaterial3D.new()
	_ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ember_material.vertex_color_use_as_albedo = true
	_ember_material.albedo_color = Color(EMBER_BASE_GAIN, EMBER_BASE_GAIN, EMBER_BASE_GAIN, 1.0)
	# Embers use bounded unshaded albedo rather than emission, which can bypass the display cap.
	mesh.material = _ember_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = EMBER_COUNT
	_ember_instance = MultiMeshInstance3D.new()
	_ember_instance.name = "Embers"
	_ember_instance.multimesh = multimesh
	_ember_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scaled_visuals.add_child(_ember_instance)


func _build_light() -> void:
	_firelight = OmniLight3D.new()
	_firelight.name = "WarmFireLight"
	_firelight.light_color = Color("#ff9559")
	_firelight.light_energy = 0.0
	_firelight.omni_range = OMNI_RANGE_M
	_firelight.shadow_enabled = false
	_firelight.position = Vector3(0.0, 0.53, 0.0)
	add_child(_firelight)


## The base asset is always visible. `enabled` controls only flames, embers and the warm OmniLight3D.
func configure(enabled: bool, environment: Environment, local_gain: float) -> void:
	_environment = environment
	_local_gain = clampf(local_gain, 0.0, 1000.0)
	set_enabled(enabled)
	_update_exposure_materials()
	_update_light()


## Idempotent; enabling/disabling never creates or removes scene nodes.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _flame_group != null:
		_flame_group.visible = _enabled
	if _ember_instance != null:
		_ember_instance.visible = _enabled
	if _firelight != null:
		_firelight.visible = _enabled
		_firelight.light_energy = 0.0 if not _enabled else _firelight.light_energy
		_update_light()


## Advances sprites analytically from simulation time. `wind` is a read-only visual lean input in render-space
## metres per second; it affects presentation only and adds no force to the flight model. It is the instantaneous
## wind sample; no wind history is stored for checkpoints. Smoke is omitted because this asset set's low-resolution
## sheet has not passed side-view quality review.
func update_visual(clock_s: float, wind: Vector3 = Vector3.ZERO) -> void:
	if not is_finite(clock_s):
		return
	_clock_s = clock_s
	_wind = wind if _vector_is_finite(wind) else Vector3.ZERO
	_update_exposure_materials()
	_update_flames()
	_update_embers()
	_update_light()


func particle_count() -> int:
	return PARTICLE_COUNT


func _update_flames() -> void:
	var horizontal_wind := Vector3(_wind.x, 0.0, _wind.z)
	var speed := horizontal_wind.length()
	var lean := Vector3.ZERO
	if speed > 1e-9:
		lean = horizontal_wind / speed * minf(speed * 0.0025, 0.035)
	for index in _flames.size():
		var lifetime := FLAME_LIFETIME_BASE_S + float(index % 5) * FLAME_LIFETIME_STEP_S
		var phase := float(index) * 0.137
		var age := fposmod(_clock_s + phase, lifetime)
		var frame := clampi(floori(age / lifetime * FRAME_COUNT), 0, FRAME_COUNT - 1)
		var variant := (index % 2) * FRAME_COUNT
		var sprite := _flames[index]
		if is_instance_valid(sprite):
			sprite.region_rect = _flame_rect(variant + frame)
			var flicker := 0.5 + 0.5 * sin(_clock_s * 5.7 + float(index) * 1.91)
			sprite.modulate = Color(1.0, 0.84 + 0.12 * flicker, 0.67 + 0.18 * flicker, 0.79 + 0.12 * flicker)
			var origin := _flame_origins[index]
			var height_fraction := clampf((origin.y - 0.16) / 0.09, 0.0, 1.0)
			var drift := sin(_clock_s * 3.1 + float(index) * 1.37) * 0.003
			sprite.position = origin + lean * height_fraction + Vector3(drift, 0.0, -drift * 0.35)


func _flame_rect(frame_index: int) -> Rect2:
	var col := frame_index % ATLAS_COLUMNS
	var row := frame_index / ATLAS_COLUMNS
	return Rect2(
		col * CELL_WIDTH + FRAME_PADDING,
		row * CELL_HEIGHT + FRAME_PADDING,
		FRAME_WIDTH,
		FRAME_HEIGHT
	)


func _update_exposure_materials() -> void:
	var exposure := _current_exposure()
	for material in _flame_materials:
		material.set_shader_parameter("exposure_value", exposure)
		material.set_shader_parameter("base_gain", FLAME_BASE_GAIN)
		material.set_shader_parameter("display_cap", FLAME_DISPLAY_CAP)
	if _ember_material != null:
		var ember_gain := minf(EMBER_BASE_GAIN, EMBER_DISPLAY_CAP / exposure)
		_ember_material.albedo_color = Color(ember_gain, ember_gain, ember_gain, 1.0)


func _update_embers() -> void:
	if _ember_instance == null or _ember_instance.multimesh == null:
		return
	var multimesh := _ember_instance.multimesh
	var horizontal_wind := Vector3(_wind.x, 0.0, _wind.z)
	var speed := horizontal_wind.length()
	var wind_direction := horizontal_wind / speed if speed > 1e-9 else Vector3.ZERO
	for index in EMBER_COUNT:
		var lifetime := EMBER_LIFETIME_BASE_S + float(index % 3) * EMBER_LIFETIME_STEP_S
		var age := fposmod(_clock_s + float(index) * 0.61, EMBER_PERIOD_S)
		var active := age < lifetime
		if active:
			var progress := age / lifetime
			var angle := TAU * float(index) / float(EMBER_COUNT) + age * 2.4
			var radius := 0.012 + progress * 0.025
			var wind_offset := wind_direction * minf(speed * 0.0017, 0.025) * progress
			var position := Vector3(cos(angle) * radius, 0.16 + 0.12 * progress, sin(angle) * radius) + wind_offset
			var radius_scale := 0.66 + 0.34 * sin(progress * PI)
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius_scale), position))
			multimesh.set_instance_color(index, Color(1.0, 0.62 + 0.2 * (1.0 - progress), 0.31, 1.0 - progress * 0.65))
		else:
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
			multimesh.set_instance_color(index, Color.TRANSPARENT)


func _update_light() -> void:
	if _firelight == null:
		return
	if not _enabled:
		_firelight.light_energy = 0.0
		return
	var exposure := _current_exposure()
	var cap_energy := OMNI_DISPLAY_CAP / exposure
	var flicker := 1.0 + 0.08 * sin(_clock_s * 3.4 + 0.2) + 0.045 * sin(_clock_s * 7.9 + 1.1)
	var light_energy := minf(OMNI_BASE_ENERGY * _local_gain, cap_energy) * _dusk_factor() * flicker
	_firelight.light_energy = minf(light_energy, cap_energy)


func _current_exposure() -> float:
	return maxf(float(_environment.tonemap_exposure) if _environment != null else 1.0, 0.001)


func _dusk_factor() -> float:
	if _environment == null or _environment.sky == null:
		return 1.0
	var material := _environment.sky.sky_material as ShaderMaterial
	if material == null:
		return 1.0
	var direction_value: Variant = material.get_shader_parameter("disc_dir")
	if not direction_value is Vector3:
		direction_value = material.get_shader_parameter("sun_dir")
	if not direction_value is Vector3:
		return 1.0
	var direction: Vector3 = (direction_value as Vector3).normalized()
	var elevation_deg := rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
	var transition := clampf((LIGHTS_ON_ELEVATION_DEG - elevation_deg) /
		(LIGHTS_ON_ELEVATION_DEG - FULL_NIGHT_ELEVATION_DEG), 0.0, 1.0)
	return transition * transition * (3.0 - 2.0 * transition)


func _vector_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
