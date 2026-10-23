class_name AirfieldLighting
extends Node3D

## LU-03: scene-local fixture hardware and club windows. Existing FieldLights owns every runway/windsock
## SpotLight3D; this node adds mesh detail, two veranda Omnis, the dusk driver, and two batched runway marker optics.

const Frames := preload("res://render/frames.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const Exposure := preload("res://render/world/exposure.gd")
const RegionalLighting := preload("res://render/landscape_upgrade/regional_lighting.gd")
const WINDOW_SHADER: Shader = preload("res://render/landscape_upgrade/window_glow.gdshader")
const HEAD_PATH := "res://assets/landscape/night-lighting/lamp-head.glb"
const LAMP_SHADER := preload("res://render/landscape_upgrade/field_lamp.gdshader")
const HEAD_SCALE := 2.4
const RUNWAY_MARKER_SHADER: Shader = preload("res://render/landscape_upgrade/runway_marker.gdshader")
const RUNWAY_GROUND_SPILL_SHADER: Shader = preload("res://render/landscape_upgrade/runway_ground_spill.gdshader")

const LIGHTS_ON_ELEVATION_DEG := 3.0
const FULL_NIGHT_ELEVATION_DEG := -4.0
const RUNWAY_SPOT_DISPLAY_CAP := 800.0 # per runway flood, scene-linear after current view exposure; art-directed, not a lux claim.
const AUXILIARY_SPOT_DISPLAY_CAP := 0.6 # windsock flood; lower local display cap, not a lux claim.
const VERANDA_OMNI_DISPLAY_CAP := 0.12 # per light, scene-linear after current view exposure; art-directed, not a lux claim.
const RUNWAY_MARKER_DISPLAY_CAP := 1.0 # bounded screen contribution after exposure; art-directed, not a photometric claim.
const RUNWAY_MARKER_CORE_MIN_PX := 2.5 # practical optical core estimate, measured in the active viewport.
const RUNWAY_MARKER_HALO_MIN_PX := 6.5 # subdued glow diameter estimate; no bloom/post-process dependency.
const RUNWAY_MARKER_CAMERA_OFFSET_M := 0.075 # offsets the optical face by approximately the existing lens radius.
const RUNWAY_MARKER_READABILITY_GAIN_FLOOR := 0.0025 # art-directed floor for a 50 mm light source at the far field.
const RUNWAY_MARKER_FADE_START_M := 300.0 # estimated useful field distance; no photometric claim.
const RUNWAY_MARKER_FADE_END_M := 600.0 # fade the readability aid outside the field.
const RUNWAY_GROUND_SPILL_DIAMETER_M := 0.65 # small dry-turf scatter patch; no reflective streak.
const RUNWAY_GROUND_SPILL_DISPLAY_CAP := 0.05 # bounded display contribution; no lux claim.
const RUNWAY_GROUND_SPILL_RADIANCE := 0.02
const RUNWAY_EDGE_ROW := "runway_edge_stakes"
const RUNWAY_THRESHOLD_ROW := "threshold_stakes"
const FLOOD_HOUSING := Color("#41484a")
const FLOOD_SHADE := Color("#303638")
const METAL_DARK := Color("#373c3b")
const STAKE_BODY := Color("#666a62")
const WINDOW_WOOD := Color("#514133")
const WINDOW_DARK := Color("#282522")
const WINDOW_WARM := Color("#b18a58")

const WINDOW_SPECS: Array[Dictionary] = [
	# Prefabs._window receives the bottom-left elevation; these are the actual glass-centre heights.
	{"center": Vector3(-2.8, 1.575, -3.02), "size": Vector2(1.5, 1.05), "yaw": PI},
	{"center": Vector3(2.8, 1.575, -3.02), "size": Vector2(1.5, 1.05), "yaw": PI},
	{"center": Vector3(-2.2, 1.65, 3.02), "size": Vector2(1.0, 0.7), "yaw": 0.0},
	{"center": Vector3(2.2, 1.65, 3.02), "size": Vector2(1.0, 0.7), "yaw": 0.0},
	{"center": Vector3(-4.52, 1.55, 0.0), "size": Vector2(1.2, 0.9), "yaw": -PI / 2.0},
	{"center": Vector3(4.52, 1.55, 0.0), "size": Vector2(1.2, 0.9), "yaw": PI / 2.0},
]

var _profile := "club"
var _activation := "auto"
var _last_snapshot := {}
var _head_directions := {}
var _environment: Environment
var _field_lights_node: Node3D
var _spot_bindings: Array[Dictionary] = []
var _sprite_bindings: Array[Dictionary] = []
var _omnis: Array[OmniLight3D] = []
var _window_materials: Array[ShaderMaterial] = []
var _ground_spill_material: ShaderMaterial
var _ground_spill_node: MultiMeshInstance3D
var _last_night_factor := -1.0
var _last_exposure := -1.0
var _sdr_local_gain := 1.0
var _regional: Node3D
var _poll_valid := false
var _polled_material: ShaderMaterial
var _polled_direction: Variant = null
var _polled_disc: Variant = null
var _polled_exposure := -1.0


## field_lights is FieldLights.load_from().lights; validated_scenery is the loader's normalized scenery result.
## No light sources are created for runway markers here: their existing MultiMesh sprites remain authoritative.
static func build(field: Dictionary, field_lights: Dictionary = {}, validated_scenery: Dictionary = {}, regional := false) -> Node3D:
	Exposure.register() # the warm window shader shares the existing, live display-exposure global.
	var fixture_data := field_lights
	if not (fixture_data.get("fixtures", null) is Array):
		var loaded := FieldLights.load_from()
		fixture_data = loaded.lights if loaded.ok else {}
	# Load the script resource itself so fresh `--script` runs do not depend on the editor's global class cache.
	var helper_script: GDScript = load("res://render/landscape_upgrade/airfield_lighting.gd")
	var node: Variant = helper_script.new()
	node.name = "AirfieldLighting"
	node._build_fixture_hardware(fixture_data)
	node._build_clubhouse(validated_scenery)
	if regional:
		node._regional = RegionalLighting.build(validated_scenery)
		node.add_child(node._regional)
	node.set_meta("field_id", str(field.get("id", "")))
	node.set_meta("night_factor", 0.0)
	# A direct snapshot may be supplied by a caller; a fixture configuration has no sun fields and starts in daylight.
	node.apply_lighting(field_lights)
	return node as Node3D


## Binds to the actual world sky and the existing FieldLights root. The sky's own uniforms are the shared
## day/night source for the fixed-FW and flowing/explicit-TOD paths.
func bind_environment(environment: Environment, field_lights_node: Node3D = null,
		sdr_local_gain: float = 1.0) -> void:
	_poll_valid = false
	_polled_material = null
	_environment = environment
	# Static TOD snapshots retain their authored SDR exposure. This bounded view gain keeps local fittings useful
	# on that path; output caps below still limit display contribution. It is not a photometric/lux correction.
	_sdr_local_gain = clampf(sdr_local_gain, 0.0, 1000.0)
	set_meta("sdr_local_gain", _sdr_local_gain)
	_last_night_factor = -1.0
	_last_exposure = -1.0
	if field_lights_node != null:
		_bind_field_lights(field_lights_node)
	set_process(_environment != null)
	_update_from_environment()


## Applies a snapshot with sun_elevation_deg, or with sun_dir/disc_dir and optional sun_disc.
## Interpolates continuously from 3° sun elevation to −4°; geometry stays visible throughout daylight.
func apply_lighting(snapshot: Dictionary) -> void:
	# Explicit snapshots/profile changes must be superseded by the next sky poll.
	_poll_valid = false
	_last_snapshot = snapshot.duplicate()
	var night_factor := _night_factor(snapshot)
	# Regional homes/obstruction lights are independent of the club's light switch.
	if is_instance_valid(_regional):
		_regional.apply_night(night_factor)
	var factor := 0.0
	if _profile != "off" and _activation != "off":
		factor = 1.0 if _activation == "on" else night_factor
	var exposure := _current_exposure()
	# In full daylight, exposure and sun direction do not change any fixture output.
	# Keep the snapshot current for later manual/profile changes, then avoid replaying the zero state.
	if factor == 0.0 and _last_night_factor == 0.0:
		_last_exposure = exposure
		return
	if is_equal_approx(factor, _last_night_factor) and is_equal_approx(exposure, _last_exposure):
		return
	_last_night_factor = factor
	_last_exposure = exposure
	set_meta("night_factor", factor)
	for binding: Dictionary in _spot_bindings:
		var spot: SpotLight3D = binding.node
		if is_instance_valid(spot):
			spot.light_energy = minf(float(binding.energy) * _sdr_local_gain,
				float(binding.display_cap) / exposure) * factor
	for binding: Dictionary in _sprite_bindings:
		var material: ShaderMaterial = binding.material
		if is_instance_valid(material):
			if not str(binding.marker_row).is_empty():
				# Marker optics apply inverse-square size gain, dusk-aware display cap, and range fade in the shader.
				# Keep authored radiance intact until after sizing; pre-capping here attenuates twice.
				material.set_shader_parameter("radiance", float(binding.radiance) * _sdr_local_gain * factor)
				material.set_shader_parameter("night_factor", factor)
			else:
				material.set_shader_parameter("radiance", minf(float(binding.radiance) * _sdr_local_gain,
					float(binding.display_cap) / exposure) * factor)
	for omni: OmniLight3D in _omnis:
		if is_instance_valid(omni):
			var base_energy := float(omni.get_meta("lu03_base_energy", 0.0))
			# Scene exposure reaches ~10^4 at night. These two view lights are absent from the FW adaptation
			# irradiance model, so cap their per-light displayed contribution to avoid clipped wall/pool patches.
			omni.light_energy = minf(base_energy * _sdr_local_gain, VERANDA_OMNI_DISPLAY_CAP / exposure) * factor
	for material: ShaderMaterial in _window_materials:
		if is_instance_valid(material):
			material.set_shader_parameter("night_glow", factor)
	if is_instance_valid(_ground_spill_material):
		_ground_spill_material.set_shader_parameter("night_factor", factor)
	if is_instance_valid(_ground_spill_node):
		_ground_spill_node.visible = factor > 0.0


## FW-71: profile changes only presentation; fixtures and physical proxies stay installed.
func set_profile(profile: String) -> bool:
	if not profile in ["club", "airfield", "off"]:
		return false
	_profile = profile
	set_meta("field_lighting", profile)
	for binding: Dictionary in _spot_bindings:
		var spot: SpotLight3D = binding.node
		if is_instance_valid(spot):
			spot.light_color = FieldLights.kelvin_color(5000.0) if profile == "airfield" else binding.color
	for binding: Dictionary in _sprite_bindings:
		if not str(binding.marker_row).is_empty():
			var material: ShaderMaterial = binding.material
			material.set_shader_parameter("edge_color", Color("#fff5e6") if profile == "airfield" else Color("#f4eee2"))
			material.set_shader_parameter("halo_min_px", 5.5 if profile == "airfield" else RUNWAY_MARKER_HALO_MIN_PX)
	if is_instance_valid(_ground_spill_material):
		_ground_spill_material.set_shader_parameter("tint", Color("#fff5e6") if profile == "airfield" else Color("#f4eee2"))
	_last_night_factor = -1.0
	_last_exposure = -1.0
	apply_lighting(_last_snapshot)
	return true


## Manual override affects the visual lamp output only. Hardware and collision proxies stay installed.
func set_activation(activation: String) -> bool:
	if not activation in ["auto", "on", "off"]:
		return false
	_activation = activation
	set_meta("field_activation", activation)
	_last_night_factor = -1.0
	_last_exposure = -1.0
	apply_lighting(_last_snapshot)
	return true


func _process(_delta: float) -> void:
	_update_from_environment()


func _current_exposure() -> float:
	return maxf(float(_environment.tonemap_exposure) if _environment != null else Exposure.last, 0.001)


func _update_from_environment() -> void:
	if _environment == null or _environment.sky == null:
		return
	var material := _environment.sky.sky_material as ShaderMaterial
	if material == null:
		return
	# The visible sun disc can fade out near the horizon. Keep the geometric/apparent solar direction as the
	# transition source so `sun_disc == 0` does not switch the lamps on as a binary jump at sunset.
	var direction_value: Variant = material.get_shader_parameter("disc_dir")
	if not direction_value is Vector3:
		direction_value = material.get_shader_parameter("sun_dir")
	var sun_disc: Variant = null if direction_value is Vector3 else material.get_shader_parameter("sun_disc")
	var exposure := _current_exposure()
	if _poll_valid and material == _polled_material and direction_value == _polled_direction \
			and sun_disc == _polled_disc and exposure == _polled_exposure:
		return
	if direction_value is Vector3:
		var direction: Vector3 = (direction_value as Vector3).normalized()
		apply_lighting({"sun_elevation_deg": rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))})
	elif (sun_disc is float or sun_disc is int) and float(sun_disc) <= 0.0:
		apply_lighting({"sun_disc": 0.0})
	_poll_valid = true
	_polled_material = material
	_polled_direction = direction_value
	_polled_disc = sun_disc
	_polled_exposure = exposure


func _bind_field_lights(field_lights_node: Node3D) -> void:
	_field_lights_node = field_lights_node
	# Light hardware must remain visible in daylight; energy/radiance, not scene visibility, carries the dusk transition.
	_field_lights_node.visible = true
	_spot_bindings.clear()
	_sprite_bindings.clear()
	for candidate: Node in field_lights_node.find_children("*", "", true, false):
		if candidate is SpotLight3D:
			var spot := candidate as SpotLight3D
			if not spot.has_meta("lu03_base_energy"):
				spot.set_meta("lu03_base_energy", spot.light_energy)
			_spot_bindings.append({"node": spot, "energy": float(spot.get_meta("lu03_base_energy")),
				"display_cap": _spot_display_cap(spot), "color": spot.get_meta("fw_base_color", spot.light_color)})
			spot.set_meta("fw_base_color", _spot_bindings.back().color)
		elif candidate is GeometryInstance3D:
			var mesh: Mesh = null
			if candidate is MeshInstance3D:
				mesh = (candidate as MeshInstance3D).mesh
			elif candidate is MultiMeshInstance3D:
				var multimesh := (candidate as MultiMeshInstance3D).multimesh
				if multimesh != null:
					mesh = multimesh.mesh
			if mesh == null:
				continue
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface) as ShaderMaterial
				if material == null or material.get_shader_parameter("radiance") == null:
					continue
				if _head_directions.has(str(candidate.name)) and material.shader != LAMP_SHADER:
					candidate.position = _head_directions[str(candidate.name)].position
					material = material.duplicate() as ShaderMaterial
					material.shader = LAMP_SHADER
					material.set_shader_parameter("source_direction", _head_directions[str(candidate.name)].forward)
					material.set_shader_parameter("size_m", 0.26)
					mesh.surface_set_material(surface, material)
				var marker_row := _runway_marker_row(candidate.name)
				if not marker_row.is_empty():
					material = _runway_marker_material(material, marker_row)
					mesh.surface_set_material(surface, material)
				if not material.has_meta("lu03_base_radiance"):
					material.set_meta("lu03_base_radiance", float(material.get_shader_parameter("radiance")))
				_sprite_bindings.append({"material": material,
					"radiance": float(material.get_meta("lu03_base_radiance")),
					"display_cap": maxf(float(material.get_shader_parameter("display_cap")), 0.0),
					"marker_row": marker_row})
	_last_night_factor = -1.0
	_last_exposure = -1.0
	set_meta("bound_sprite_materials", _sprite_bindings.size())
	set_profile(_profile)


static func _runway_marker_row(node_name: String) -> String:
	if node_name == RUNWAY_EDGE_ROW or node_name == RUNWAY_THRESHOLD_ROW:
		return node_name
	return ""


static func _runway_marker_material(source: ShaderMaterial, row_name: String) -> ShaderMaterial:
	var material := source
	# Keep one material per existing row. Rebinding recognizes this shader and does not clone or duplicate it.
	if material.shader != RUNWAY_MARKER_SHADER:
		material = source.duplicate() as ShaderMaterial
		material.shader = RUNWAY_MARKER_SHADER
		material.set_shader_parameter("edge_color", Color("#f4eee2"))
		material.set_shader_parameter("threshold_green", Color("#22e66d"))
		material.set_shader_parameter("threshold_red", Color("#ff453c"))
		material.set_shader_parameter("core_min_px", RUNWAY_MARKER_CORE_MIN_PX)
		material.set_shader_parameter("halo_min_px", RUNWAY_MARKER_HALO_MIN_PX)
		material.set_shader_parameter("camera_offset_m", RUNWAY_MARKER_CAMERA_OFFSET_M)
		material.set_shader_parameter("readability_gain_floor", RUNWAY_MARKER_READABILITY_GAIN_FLOOR)
		material.set_shader_parameter("distance_fade_start_m", RUNWAY_MARKER_FADE_START_M)
		material.set_shader_parameter("distance_fade_end_m", RUNWAY_MARKER_FADE_END_M)
		material.set_shader_parameter("display_cap", RUNWAY_MARKER_DISPLAY_CAP)
	material.set_shader_parameter("threshold_mode", row_name == RUNWAY_THRESHOLD_ROW)
	return material


static func _spot_display_cap(spot: SpotLight3D) -> float:
	if not str(spot.get_meta("installation_id", "")).is_empty() and str(spot.get_meta("role", "")) in ["runway_flood", "club_flood"]:
		return RUNWAY_SPOT_DISPLAY_CAP
	return 24.0 if spot.name.begins_with("flood_") else AUXILIARY_SPOT_DISPLAY_CAP


func _build_fixture_hardware(lights: Dictionary) -> void:
	var fixtures: Array = lights.get("fixtures", [])
	if fixtures.is_empty():
		set_meta("fixture_hardware", {"flood_housings": 0, "marker_posts": 0})
		return
	_build_marker_ground_spill(fixtures)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The existing shaft supports the downloaded, independently aimed heads on one narrow crossarm.
	for installation: Dictionary in lights.get("installations", []):
		if str(installation.get("type", "")) == "mast":
			var mount := _render(float(installation.north), float(installation.east), float(installation.height) - 0.38)
			_add_box(surface, Transform3D(Basis.IDENTITY, mount), Vector3(2.3, 0.10, 0.12), METAL_DARK)
	var floods := 0
	var posts := 0
	for fx: Variant in fixtures:
		if not (fx is Dictionary):
			continue
		if str(fx.get("type", "")) == "flood":
			if not _add_imported_flood(fx):
				_add_flood_hardware(surface, fx)
			floods += 1
		elif str(fx.get("type", "")) == "stake_row":
			posts += _add_marker_row(surface, fx)
	if floods + posts == 0:
		return
	var mesh := surface.commit()
	if mesh.get_surface_count() == 0:
		return
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.84
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "RunwayFixtureHardware"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	set_meta("fixture_hardware", {"flood_housings": floods, "marker_posts": posts})


## All low edge pools use one MultiMesh draw and no additional Light3D or shadow pass.
func _build_marker_ground_spill(fixtures: Array) -> void:
	for fx: Dictionary in fixtures:
		if str(fx.get("id", "")) != RUNWAY_EDGE_ROW or not (fx.get("points", null) is Array):
			continue
		var points: Array = fx.points
		if points.is_empty():
			return
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		_ground_spill_material = ShaderMaterial.new()
		_ground_spill_material.shader = RUNWAY_GROUND_SPILL_SHADER
		_ground_spill_material.set_shader_parameter("radiance", RUNWAY_GROUND_SPILL_RADIANCE)
		_ground_spill_material.set_shader_parameter("display_cap", RUNWAY_GROUND_SPILL_DISPLAY_CAP)
		_ground_spill_material.set_shader_parameter("night_factor", 0.0)
		quad.material = _ground_spill_material
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = quad
		batch.instance_count = points.size()
		var basis := Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(
			RUNWAY_GROUND_SPILL_DIAMETER_M, RUNWAY_GROUND_SPILL_DIAMETER_M, 1.0))
		for i in points.size():
			var point: Array = points[i]
			batch.set_instance_transform(i, Transform3D(basis, _render(float(point[0]), float(point[1]), 0.015)))
		var instance := MultiMeshInstance3D.new()
		instance.name = "RunwayEdgeGroundSpill"
		instance.multimesh = batch
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = RUNWAY_GROUND_SPILL_DIAMETER_M
		add_child(instance)
		_ground_spill_node = instance
		set_meta("ground_spill_instances", points.size())
		return


## Reuse the downloaded module, with optical axis -Z; no procedural replacement housing.
func _add_imported_flood(fx: Dictionary) -> bool:
	if str(fx.get("installation_id", "")).is_empty():
		return false # historical v1 fixtures retain their existing hardware
	var scene := load(HEAD_PATH) as PackedScene
	if scene == null:
		push_error("Night lighting head resource missing: " + HEAD_PATH)
		return false
	var pos := _render(float(fx.north), float(fx.east), float(fx.height))
	var target := _render(float(fx.aim_north), float(fx.aim_east), float(fx.get("aim_height", 0.0)))
	var forward := (target - pos).normalized()
	var basis := Basis.looking_at(forward, Vector3.UP if absf(forward.y) < 0.99 else Vector3.FORWARD)
	var head := scene.instantiate() as Node3D
	head.name = str(fx.id) + "_housing"
	var head_scale := HEAD_SCALE if str(fx.get("role", "")) == "runway_flood" else 1.0
	head.transform = Transform3D(basis.scaled(Vector3.ONE * head_scale), pos)
	add_child(head)
	_head_directions[str(fx.id) + "_lamp"] = {forward = forward, position = pos + forward * (0.0401 * head_scale)}
	for child: Node in head.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return true


func _add_flood_hardware(surface: SurfaceTool, fx: Dictionary) -> void:
	var north := float(fx.get("north", 0.0))
	var east := float(fx.get("east", 0.0))
	var height := float(fx.get("height", 0.0))
	var ground := _render(north, east, 0.0)
	_add_frustum(surface, Transform3D(Basis.IDENTITY, ground), 0.22, 0.17, 0.08, FLOOD_SHADE, 12)
	_add_frustum(surface, Transform3D(Basis.IDENTITY, ground + Vector3(0.0, 0.08, 0.0)), 0.11, 0.095, 0.045, FLOOD_HOUSING, 10)
	var pos := _render(north, east, height)
	var target := _render(float(fx.get("aim_north", north)), float(fx.get("aim_east", east)), float(fx.get("aim_height", 0.0)))
	var forward := (target - pos).normalized()
	var up := Vector3.UP if absf(forward.y) < 0.99 else Vector3.FORWARD
	var basis := Basis.looking_at(forward, up)
	var housing := Transform3D(basis, pos)
	var small := height < 2.0
	var body := Vector3(0.36, 0.22, 0.32) if small else Vector3(0.62, 0.34, 0.42)
	_add_box(surface, _local_transform(housing, Vector3(0.0, 0.0, 0.025)), body, FLOOD_HOUSING)
	# The emitter face sits ahead of the body so the existing light sprite remains visible through the shielded head.
	_add_box(surface, _local_transform(housing, Vector3(0.0, 0.0, -body.z * 0.46)),
		Vector3(body.x * 0.72, body.y * 0.62, 0.018), Color("#e0cfa9"))
	_add_box(surface, _local_transform(housing, Vector3(0.0, body.y * 0.58, -0.10)),
		Vector3(body.x * 1.16, 0.055, body.z * 0.88), FLOOD_SHADE)
	for side: float in [-1.0, 1.0]:
		_add_box(surface, _local_transform(housing, Vector3(side * body.x * 0.48, 0.0, -0.08)),
			Vector3(0.045, body.y * 0.83, body.z * 0.62), FLOOD_SHADE)
	_add_box(surface, _local_transform(housing, Vector3(0.0, -0.23 if not small else -0.14, 0.24)),
		Vector3(0.09, 0.085, 0.48 if not small else 0.32), METAL_DARK)


func _add_marker_row(surface: SurfaceTool, fx: Dictionary) -> int:
	var points: Array = fx.get("points", [])
	var height := float(fx.get("height", 0.35))
	var cap_height := minf(0.085, height * 0.26)
	var cap_bottom := maxf(height - cap_height, 0.04)
	var shaft_height := maxf(cap_bottom - 0.045, 0.02)
	var lamp := Color(str(fx.get("color", "#e9d5a8"))) if fx.has("color") else FieldLights.kelvin_color(float(fx.get("color_temperature", 3000.0)))
	# Threshold face color is supplied per view by the batched optics shader (green outward, red inward).
	# Keep its small physical lens neutral so a fixed green cap does not contradict the directional cue.
	var lens := Color("#5f5b52") if str(fx.get("id", "")) == RUNWAY_THRESHOLD_ROW else \
		Color(lerpf(0.27, lamp.r, 0.52), lerpf(0.28, lamp.g, 0.52), lerpf(0.27, lamp.b, 0.52))
	for point: Variant in points:
		if not (point is Array) or (point as Array).size() < 2:
			continue
		var p := _render(float(point[0]), float(point[1]), 0.0)
		_add_frustum(surface, Transform3D(Basis.IDENTITY, p), 0.055, 0.047, 0.045, METAL_DARK, 8)
		_add_frustum(surface, Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.045, 0.0)), 0.026, 0.019, shaft_height, STAKE_BODY, 8)
		_add_frustum(surface, Transform3D(Basis.IDENTITY, p + Vector3(0.0, cap_bottom, 0.0)), 0.043, 0.039, cap_height, lens, 8)
	return points.size()


func _build_clubhouse(scenery: Dictionary) -> void:
	var windows := 0
	var lamps := 0
	var pavilions := 0
	var groups: Array = scenery.get("groups", [])
	for group: Variant in groups:
		if not (group is Dictionary) or str(group.get("type", "")) != "instances":
			continue
		for placement: Variant in group.get("placements", []):
			if not (placement is Dictionary) or str(placement.get("prefab", group.get("prefab", ""))) != "pavilion":
				continue
			var pavilion := Node3D.new()
			pavilion.name = "PavilionLighting_%d" % get_child_count()
			pavilion.transform = _placement_xf(float(placement.get("north", 0.0)), float(placement.get("east", 0.0)), float(placement.get("heading", 0.0)))
			add_child(pavilion)
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for window: Dictionary in WINDOW_SPECS:
				_add_window_insert(surface, window)
			_add_sconce_hardware(surface)
			var mesh := surface.commit()
			if mesh.get_surface_count() > 0:
				var interior_material := StandardMaterial3D.new()
				interior_material.vertex_color_use_as_albedo = true
				interior_material.vertex_color_is_srgb = true
				interior_material.roughness = 0.9
				interior_material.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh.surface_set_material(0, interior_material)
				var room := MeshInstance3D.new()
				room.name = "PavilionShallowInteriors"
				room.mesh = mesh
				room.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pavilion.add_child(room)
			var panes := _window_and_lamp_glow(pavilion)
			if _omnis.is_empty():
				_add_veranda_omnis(pavilion)
				lamps = 2
			pavilion.set_meta("window_count", WINDOW_SPECS.size())
			pavilion.set_meta("mullion_count", WINDOW_SPECS.size())
			pavilion.set_meta("window_centers_y_m", [1.575, 1.575, 1.65, 1.65, 1.55, 1.55])
			pavilion.set_meta("shallow_window_depth_m", 0.16)
			pavilion.set_meta("glow_instances", panes)
			windows += WINDOW_SPECS.size()
			lamps = 2
			pavilions += 1
	set_meta("clubhouse", {"pavilions": pavilions, "windows": windows, "wall_lamps": lamps, "omnis": _omnis.size()})


func _add_window_insert(surface: SurfaceTool, spec: Dictionary) -> void:
	var center: Vector3 = spec.center
	var size: Vector2 = spec.size
	var orientation := Basis(Vector3.UP, float(spec.yaw))
	var outward := orientation * Vector3(0.0, 0.0, 1.0)
	var width := size.x
	var height := size.y
	# The original prefab glazing is an opaque vertex-colour quad. This shallow box is placed just in front of it,
	# so the insert reads through that surface without modifying the shared prefab/material path.
	_add_box(surface, Transform3D(orientation, center + outward * 0.035), Vector3(width - 0.10, height - 0.10, 0.025), WINDOW_DARK)
	var recess_depth := 0.16
	var mid_depth := recess_depth * 0.5
	var side_x := width * 0.5 - 0.035
	var side_y := height * 0.5 - 0.035
	for side: float in [-1.0, 1.0]:
		_add_box(surface, Transform3D(orientation, center + outward * mid_depth + orientation * Vector3(side * side_x, 0.0, 0.0)),
			Vector3(0.045, height - 0.10, recess_depth), WINDOW_WOOD)
		_add_box(surface, Transform3D(orientation, center + outward * mid_depth + orientation * Vector3(0.0, side * side_y, 0.0)),
			Vector3(width - 0.10, 0.04, recess_depth), WINDOW_WOOD)
	# Interior furniture silhouettes and a warm back surface give oblique views real depth cues.
	_add_box(surface, Transform3D(orientation, center + outward * 0.053), Vector3(width - 0.15, height - 0.15, 0.012), WINDOW_WARM)
	_add_box(surface, Transform3D(orientation, center + outward * 0.088 + orientation * Vector3(0.0, -height * 0.25, 0.0)),
		Vector3(width * 0.58, 0.055, 0.055), Color("#6e5136"))
	_add_box(surface, Transform3D(orientation, center + outward * 0.09 + orientation * Vector3(-width * 0.25, -height * 0.01, 0.0)),
		Vector3(0.11, height * 0.30, 0.055), Color("#574636"))
	_add_box(surface, Transform3D(orientation, center + outward * 0.09 + orientation * Vector3(width * 0.20, -height * 0.02, 0.0)),
		Vector3(0.16, height * 0.20, 0.05), Color("#826445"))
	# One narrow vertical bar per pane gives the broad glazing a readable split and masks the depth of the shallow insert.
	# The combined PavilionShallowInteriors mesh keeps this detail within the existing single draw.
	_add_box(surface, Transform3D(orientation, center + outward * 0.12),
		Vector3(0.05, height - 0.10, 0.08), WINDOW_WOOD)


func _add_sconce_hardware(surface: SurfaceTool) -> void:
	var front := Basis(Vector3.UP, PI)
	for side: float in [-1.0, 1.0]:
		var center := Vector3(side * 4.18, 2.05, -3.02)
		var xf := Transform3D(front, center + Vector3(0.0, 0.0, -0.04))
		_add_box(surface, xf, Vector3(0.20, 0.36, 0.12), METAL_DARK)
		_add_box(surface, _local_transform(xf, Vector3(0.0, 0.22, -0.015)), Vector3(0.30, 0.055, 0.24), FLOOD_SHADE)
		_add_box(surface, _local_transform(xf, Vector3(-0.12, 0.0, -0.015)), Vector3(0.045, 0.30, 0.23), FLOOD_SHADE)
		_add_box(surface, _local_transform(xf, Vector3(0.12, 0.0, -0.015)), Vector3(0.045, 0.30, 0.23), FLOOD_SHADE)


func _window_and_lamp_glow(parent: Node3D) -> int:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = WINDOW_SHADER
	material.set_shader_parameter("night_glow", 0.0)
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.use_custom_data = true
	multimesh.instance_count = WINDOW_SPECS.size() + 2
	for i in WINDOW_SPECS.size():
		var spec: Dictionary = WINDOW_SPECS[i]
		var size: Vector2 = spec.size
		var orientation := Basis(Vector3.UP, float(spec.yaw))
		var outward := orientation * Vector3(0.0, 0.0, 1.0)
		var scaled := orientation * Basis.from_scale(Vector3(size.x - 0.14, size.y - 0.14, 1.0))
		var center: Vector3 = spec.center + outward * 0.145
		multimesh.set_instance_transform(i, Transform3D(scaled, center))
		multimesh.set_instance_custom_data(i, Color(1.0, 0.0, 0.0, 0.0))
	for i in 2:
		var front := Basis(Vector3.UP, PI)
		var center := Vector3(-4.18 if i == 0 else 4.18, 2.05, -3.02) + Vector3(0.0, 0.0, -0.13)
		var scaled := front.scaled(Vector3(0.12, 0.24, 1.0))
		multimesh.set_instance_transform(WINDOW_SPECS.size() + i, Transform3D(scaled, center))
	var glow := MultiMeshInstance3D.new()
	glow.name = "PavilionWarmWindowsAndLamps"
	glow.multimesh = multimesh
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.extra_cull_margin = 4.0
	parent.add_child(glow)
	_window_materials.append(material)
	return multimesh.instance_count


func _add_veranda_omnis(parent: Node3D) -> void:
	for side: float in [-1.0, 1.0]:
		var omni := OmniLight3D.new()
		omni.name = "VerandaPool_%s" % ("West" if side < 0.0 else "East")
		omni.position = Vector3(side * 4.18, 1.95, -3.32)
		omni.light_color = Color("#ffd0a0")
		omni.light_energy = 0.032
		# LU-19: overlap the existing sconces across the entry and veranda edge without
		# extra lights or a higher exposure cap. Authored visibility estimate, not lux data.
		omni.omni_range = 8.0
		omni.omni_attenuation = 1.1
		omni.light_specular = 0.05
		omni.shadow_enabled = false
		omni.set_meta("lu03_base_energy", omni.light_energy)
		parent.add_child(omni)
		_omnis.append(omni)


static func _night_factor(snapshot: Dictionary) -> float:
	var sun_disc: Variant = snapshot.get("sun_disc", 1.0)
	var elevation := 45.0
	if snapshot.get("sun_elevation_deg") is float or snapshot.get("sun_elevation_deg") is int:
		elevation = float(snapshot.sun_elevation_deg)
	else:
		var direction: Variant = snapshot.get("disc_dir")
		if direction is Vector3:
			elevation = rad_to_deg(asin(clampf((direction as Vector3).normalized().y, -1.0, 1.0)))
		elif (sun_disc is not float and sun_disc is not int or float(sun_disc) > 0.0) and snapshot.get("sun_dir") is Vector3:
			direction = snapshot.sun_dir
			elevation = rad_to_deg(asin(clampf((direction as Vector3).normalized().y, -1.0, 1.0)))
		elif (sun_disc is float or sun_disc is int) and float(sun_disc) <= 0.0:
			return 1.0 # Without a solar direction, the existing sky's moon-dominant state is the night fallback.
	var t := clampf((LIGHTS_ON_ELEVATION_DEG - elevation) / (LIGHTS_ON_ELEVATION_DEG - FULL_NIGHT_ELEVATION_DEG), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _render(north: float, east: float, up: float) -> Vector3:
	return Frames.ned_to_render([north, east, -up])


static func _placement_xf(north: float, east: float, heading_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(heading_deg)), Frames.ned_to_render([north, east, 0.0]))


static func _local_transform(parent: Transform3D, local: Vector3) -> Transform3D:
	return Transform3D(parent.basis, parent.origin + parent.basis * local)


static func _add_box(surface: SurfaceTool, xf: Transform3D, size: Vector3, color: Color) -> void:
	var x := size.x * 0.5
	var y := size.y * 0.5
	var z := size.z * 0.5
	var faces: Array[Array] = [
		[Vector3(x, -y, -z), Vector3(x, -y, z), Vector3(x, y, z), Vector3(x, y, -z), Vector3.RIGHT],
		[Vector3(-x, -y, z), Vector3(-x, -y, -z), Vector3(-x, y, -z), Vector3(-x, y, z), Vector3.LEFT],
		[Vector3(-x, y, -z), Vector3(x, y, -z), Vector3(x, y, z), Vector3(-x, y, z), Vector3.UP],
		[Vector3(-x, -y, z), Vector3(x, -y, z), Vector3(x, -y, -z), Vector3(-x, -y, -z), Vector3.DOWN],
		[Vector3(x, -y, z), Vector3(-x, -y, z), Vector3(-x, y, z), Vector3(x, y, z), Vector3.BACK],
		[Vector3(-x, -y, -z), Vector3(x, -y, -z), Vector3(x, y, -z), Vector3(-x, y, -z), Vector3.FORWARD],
	]
	for face: Array in faces:
		var local_normal: Vector3 = face[4]
		var normal: Vector3 = (xf.basis * local_normal).normalized()
		var a: Vector3 = xf * face[0]
		var b: Vector3 = xf * face[1]
		var c: Vector3 = xf * face[2]
		var d: Vector3 = xf * face[3]
		_add_triangle(surface, a, b, c, color, normal)
		_add_triangle(surface, a, c, d, color, normal)


static func _add_frustum(surface: SurfaceTool, xf: Transform3D, bottom_radius: float, top_radius: float,
		height: float, color: Color, segments: int) -> void:
	if height <= 0.0:
		return
	var top_center := xf * Vector3(0.0, height, 0.0)
	var bottom_center := xf.origin
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var rb0 := Vector3(cos(a0) * bottom_radius, 0.0, sin(a0) * bottom_radius)
		var rb1 := Vector3(cos(a1) * bottom_radius, 0.0, sin(a1) * bottom_radius)
		var rt0 := Vector3(cos(a0) * top_radius, height, sin(a0) * top_radius)
		var rt1 := Vector3(cos(a1) * top_radius, height, sin(a1) * top_radius)
		var n0 := (xf.basis * Vector3(cos(a0), 0.0, sin(a0))).normalized()
		var n1 := (xf.basis * Vector3(cos(a1), 0.0, sin(a1))).normalized()
		_add_triangle(surface, xf * rb0, xf * rt0, xf * rt1, color, n0, n0, n1)
		_add_triangle(surface, xf * rb0, xf * rt1, xf * rb1, color, n0, n1, n1)
		_add_triangle(surface, top_center, xf * rt1, xf * rt0, color, Vector3.UP)
		_add_triangle(surface, bottom_center, xf * rb0, xf * rb1, color, Vector3.DOWN)


static func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color,
		normal_a: Vector3, normal_b: Vector3 = Vector3.ZERO, normal_c: Vector3 = Vector3.ZERO) -> void:
	var na := normal_a.normalized()
	var nb := (normal_a if normal_b == Vector3.ZERO else normal_b).normalized()
	var nc := (normal_a if normal_c == Vector3.ZERO else normal_c).normalized()
	_emit_vertex(surface, a, color, na)
	_emit_vertex(surface, b, color, nb)
	_emit_vertex(surface, c, color, nc)


static func _emit_vertex(surface: SurfaceTool, position: Vector3, color: Color, normal: Vector3) -> void:
	surface.set_color(color)
	surface.set_normal(normal)
	surface.add_vertex(position)
