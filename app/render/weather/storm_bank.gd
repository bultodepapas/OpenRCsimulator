## FW-83: bounded, scene-owned storm formation made from licensed cloud impostors.
## Coordinates and advection are presentation-only; this node never samples/changes flight physics.
extends Node3D

const StormCell := preload("res://render/weather/storm_cell.gd")
const TEXTURES := ["res://assets/sky/weather/clouds/FX_CloudAlpha03.png", "res://assets/sky/weather/clouds/FX_CloudAlpha06.png"]
const SHADER_PATH := "res://render/weather/storm_bank.gdshader"
const RAIN_SHADER_PATH := "res://render/weather/rain_curtain.gdshader"
const MAX_PUFFS := 30
var _spec: Dictionary = {}
var _seed := -1
var _materials: Array[ShaderMaterial] = []
var _rain_material: ShaderMaterial
var _puffs: Array[MeshInstance3D] = []
var _rain: Array[MeshInstance3D] = []
var _period_m := 57600.0
var _clock_s := 0.0
var _cell_m := 900.0
var _offset_cells := [0.0, 0.0]
var _flash := {event_id = "", level = 0.0, source_world = [0.0, 0.0, 0.0], radiance = 0.0}
var _lighting_ready := false
var _cloud_linear := Vector3.ZERO
var _haze_linear := Vector3.ZERO
var _haze_density := 0.0
var _flash_ready := false
var _flash_source := Vector3.ZERO
var _flash_radiance := 0.0


func configure(profile: Dictionary, visual_seed: int) -> void:
	var next: Dictionary = profile.get("renderer", {}).get("storm_bank", {})
	if next == _spec and visual_seed == _seed:
		return
	_spec = next.duplicate(true)
	_seed = visual_seed
	_lighting_ready = false
	_flash_ready = false
	_flash = {event_id = "", level = 0.0, source_world = [0.0, 0.0, 0.0], radiance = 0.0}
	for child: Node in get_children():
		child.free()
	_materials.clear()
	_puffs.clear()
	_rain.clear()
	_rain_material = null
	visible = not _spec.is_empty()
	if not visible:
		return
	var shader := load(SHADER_PATH) as Shader
	for path: String in TEXTURES:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("cloud_texture", load(path))
		material.set_shader_parameter("bank_base", float(_spec.base_m))
		material.set_shader_parameter("bank_top", float(_spec.top_m))
		_materials.append(material)
	var random_source := RandomNumberGenerator.new()
	random_source.seed = _seed
	var height: float = _spec.top_m - _spec.base_m
	# Three spatially separated lobes per level create actual parallax, rather than one sky card.
	for level in 4:
		for side in 3:
			var angle := float(side) * TAU / 3.0 + float(level) * 0.8
			var size := Vector2(float(_spec.width_m) * (0.48 - level * 0.035), height * 0.48)
			var at := Vector3(cos(angle) * float(_spec.width_m) * 0.10,
				float(_spec.base_m) + height * (0.21 + level * 0.17), sin(angle) * float(_spec.depth_m) * 0.22)
			_add_puff(at, size, level % 2, random_source)
	# Broad upper cap and a low, dark shelf: 10 + 8 cards, capped at 30 in total.
	for row in 2:
		for column in 5:
			_add_puff(Vector3((column - 2.0) * float(_spec.width_m) * 0.15,
				float(_spec.base_m) + height * (0.81 + 0.025 * sin(column * 2.1)),
				(row - 0.5) * float(_spec.depth_m) * 0.45),
				Vector2(float(_spec.width_m) * 0.43, height * 0.36), 0, random_source)
	for row in 2:
		for column in 4:
			_add_puff(Vector3((column - 1.5) * float(_spec.width_m) * 0.18,
				float(_spec.base_m) + height * 0.12, (row - 0.5) * float(_spec.depth_m) * 0.60),
				Vector2(float(_spec.width_m) * 0.43, height * 0.32), 1, random_source)
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = load(RAIN_SHADER_PATH)
	_rain_material.set_shader_parameter("cloud_texture", load(TEXTURES[1]))
	_rain_material.set_shader_parameter("opacity", float(_spec.rain_opacity))
	# Three crossed sheets keep the distant rain volume visible around the cell.
	for index in 3:
		var curtain := MeshInstance3D.new()
		curtain.name = "RainCurtain%d" % index
		var mesh := QuadMesh.new()
		mesh.size = Vector2(float(_spec.width_m) * 0.72, float(_spec.base_m) + height * 0.24)
		curtain.mesh = mesh
		curtain.position.y = mesh.size.y * 0.5
		curtain.rotation.y = float(index) * PI / 3.0
		curtain.material_override = _rain_material
		curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(curtain)
		_rain.append(curtain)


func _add_puff(at: Vector3, size: Vector2, texture_index: int, rng: RandomNumberGenerator) -> void:
	if _puffs.size() >= MAX_PUFFS:
		return
	var puff := MeshInstance3D.new()
	puff.name = "CloudLobe%02d" % _puffs.size()
	var mesh := QuadMesh.new()
	mesh.size = size * rng.randf_range(0.93, 1.06)
	puff.mesh = mesh
	puff.position = at + Vector3(rng.randf_range(-80.0, 80.0), rng.randf_range(-60.0, 60.0), rng.randf_range(-80.0, 80.0))
	puff.material_override = _materials[texture_index]
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Billboard rotation is in the vertex shader; expand the CPU culling box to include every orientation.
	var radius := mesh.size.x * 0.5
	puff.custom_aabb = AABB(Vector3(-radius, -mesh.size.y * 0.5, -radius), Vector3(radius * 2.0, mesh.size.y, radius * 2.0))
	add_child(puff)
	_puffs.append(puff)


func update_visual(snapshot: Dictionary, environment: Environment, _sun: DirectionalLight3D, clock_s: float) -> void:
	if _spec.is_empty() or environment == null:
		return
	_clock_s = clock_s
	var layers: Array = snapshot.get("cloud_layers", [])
	var index: int = int(_spec.advection_layer)
	if index >= layers.size():
		visible = false
		return
	var layer: Dictionary = layers[index]
	var cell_m := float(layer.scale_m)
	_cell_m = cell_m
	_period_m = 64.0 * cell_m
	var offset: Vector2 = layer.offset
	_offset_cells = [float(offset.x), float(offset.y)]
	# The background samples p + offset, so geometry translates by -offset. Select the nearest
	# periodic copy, keeping its world centre fixed as the camera moves within a tile. A copy
	# switch is beyond this camera's far plane plus the formation radius, even far from the field.
	# Home builds its World before attachment. Initialize the materials and origin copy
	# there too; the next attached update selects the actual viewport's camera.
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	var eye := camera.global_position if camera != null else Vector3.ZERO
	select_view_copy(eye)
	visible = true
	var sky := environment.sky.sky_material as ShaderMaterial
	var cloud_linear: Vector3 = sky.get_shader_parameter("cloud_lin")
	var haze_linear: Vector3 = sky.get_shader_parameter("haze_lin")
	var haze_density := environment.fog_density * 0.35
	# Camera rebasing and the visual clock above still advance every call.
	# Only skip identical material uploads; configure invalidates new materials.
	if _lighting_ready and cloud_linear == _cloud_linear and haze_linear == _haze_linear \
			and haze_density == _haze_density:
		return
	_lighting_ready = true
	_cloud_linear = cloud_linear
	_haze_linear = haze_linear
	_haze_density = haze_density
	# Match the sky's scene-linear radiance. GLES3 applies exposure once after the material.
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("cloud_lin", cloud_linear)
		material.set_shader_parameter("haze_lin", haze_linear)
		material.set_shader_parameter("haze_density", haze_density)
	_rain_material.set_shader_parameter("rain_lin", cloud_linear * 0.28)
	_rain_material.set_shader_parameter("haze_lin", haze_linear)
	_rain_material.set_shader_parameter("haze_density", haze_density)


## Camera rigs may move after World.update; synchronize the copy before the lightning query.
func select_view_copy(eye: Vector3) -> void:
	if not _spec.is_empty():
		position = StormCell.center_from_offset(_spec, _cell_m, _offset_cells, eye)


## Detached descriptor for emission-time lightning placement; no node is owned by the scheduler.
func cell_spec() -> Dictionary:
	return _spec.duplicate(true)


## Scene-linear addition inside the existing cloud mask. Exposure is applied once by GLES3.
## The inverse cap bounds the added display radiance only; base sky lighting is never changed.
func apply_flash(event: Dictionary, level: float, exposure: float) -> void:
	var strength := clampf(level, 0.0, 1.0) if is_finite(level) and visible and not event.is_empty() else 0.0
	var safe_exposure := maxf(exposure, 0.001) if is_finite(exposure) else 1.0
	var source := Vector3.ZERO
	var raw: Variant = event.get("source_world", [])
	if (raw is Array or raw is PackedFloat64Array) and raw.size() == 3:
		source = Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	else:
		strength = 0.0
	if not source.is_finite():
		strength = 0.0
		source = Vector3.ZERO
	var radiance := strength * 0.85 / safe_exposure
	_flash = {event_id = str(event.get("event_id", "")) if strength > 0.0 else "",
		level = strength, source_world = [source.x, source.y, source.z], radiance = radiance}
	# Event metadata remains current even if its displayed uniforms are unchanged.
	if _flash_ready and source == _flash_source and radiance == _flash_radiance:
		return
	_flash_ready = true
	_flash_source = source
	_flash_radiance = radiance
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("flash_source", source)
		material.set_shader_parameter("flash_radiance", radiance)
	if _rain_material != null:
		_rain_material.set_shader_parameter("flash_source", source)
		_rain_material.set_shader_parameter("flash_radiance", radiance * 0.16)


## Detached diagnostic data for captures/tests. No rendering state is stored in the simulation.
func snapshot() -> Dictionary:
	var centers: Array = []
	for puff: MeshInstance3D in _puffs:
		centers.append([puff.position.x, puff.position.y, puff.position.z])
	return {enabled = visible and not _spec.is_empty(), layout_version = int(_spec.get("layout_version", 0)),
		seed = _seed, center = [position.x, position.y, position.z], puff_centers = centers,
		target = [position.x, (float(_spec.get("base_m", 0.0)) + float(_spec.get("top_m", 0.0))) * 0.5, position.z],
		puff_count = _puffs.size(), rain_count = _rain.size(), period_m = _period_m, clock_s = _clock_s,
		flash = _flash.duplicate(true)}
