## FW-83: bounded, scene-owned storm formation made from licensed cloud impostors.
## Coordinates and advection are presentation-only; this node never samples/changes flight physics.
extends Node3D

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


func configure(profile: Dictionary, visual_seed: int) -> void:
	var next: Dictionary = profile.get("renderer", {}).get("storm_bank", {})
	if next == _spec and visual_seed == _seed:
		return
	_spec = next.duplicate(true)
	_seed = visual_seed
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
	_period_m = 64.0 * cell_m
	var offset: Vector2 = layer.offset
	# The background samples p + offset, so geometry translates by -offset. The tile seam lies
	# beyond the 21 km camera far plane plus the formation radius (catalog validation enforces this).
	position = Vector3(wrapf(float(_spec.east_m) - float(offset.x) * cell_m, -_period_m * 0.5, _period_m * 0.5), 0.0,
		wrapf(-float(_spec.north_m) - float(offset.y) * cell_m, -_period_m * 0.5, _period_m * 0.5))
	visible = true
	var sky := environment.sky.sky_material as ShaderMaterial
	var cloud_linear: Vector3 = sky.get_shader_parameter("cloud_lin")
	var haze_linear: Vector3 = sky.get_shader_parameter("haze_lin")
	var gain := environment.tonemap_exposure
	var cloud_display := _display_color(cloud_linear * gain)
	var haze_display := _display_color(haze_linear * gain)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("cloud_color", cloud_display)
		material.set_shader_parameter("haze_color", haze_display)
		material.set_shader_parameter("haze_density", environment.fog_density * 0.35)
		material.set_shader_parameter("bank_base", float(_spec.base_m))
		material.set_shader_parameter("bank_top", float(_spec.top_m))
	_rain_material.set_shader_parameter("rain_color", cloud_display * 0.28)
	_rain_material.set_shader_parameter("haze_color", haze_display)
	_rain_material.set_shader_parameter("haze_density", environment.fog_density * 0.35)


static func _display_color(value: Vector3) -> Vector3:
	var color := Color(maxf(value.x, 0.0), maxf(value.y, 0.0), maxf(value.z, 0.0)).linear_to_srgb()
	return Vector3(clampf(color.r, 0.0, 0.95), clampf(color.g, 0.0, 0.95), clampf(color.b, 0.0, 0.95))


## Detached diagnostic data for captures/tests. No rendering state is stored in the simulation.
func snapshot() -> Dictionary:
	var centers: Array = []
	for puff: MeshInstance3D in _puffs:
		centers.append([puff.position.x, puff.position.y, puff.position.z])
	return {enabled = visible and not _spec.is_empty(), layout_version = int(_spec.get("layout_version", 0)),
		seed = _seed, center = [position.x, position.y, position.z], puff_centers = centers,
		target = [position.x, (float(_spec.get("base_m", 0.0)) + float(_spec.get("top_m", 0.0))) * 0.5, position.z],
		puff_count = _puffs.size(), rain_count = _rain.size(), period_m = _period_m, clock_s = _clock_s}
