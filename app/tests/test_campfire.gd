## FW-67: downloaded campfire base stays present while clock-driven effects toggle without growing the scene.
extends SceneTree

const Campfire := preload("res://render/world/campfire.gd")


## Count the groups that submit visual changes; repeated identical paused frames must not call them.
class CountingCampfire extends Campfire:
	var effect_updates: Array[int] = [0, 0, 0, 0]

	func _update_exposure_materials() -> void:
		effect_updates[0] += 1
		super._update_exposure_materials()

	func _update_flames() -> void:
		effect_updates[1] += 1
		super._update_flames()

	func _update_embers() -> void:
		effect_updates[2] += 1
		super._update_embers()

	func _update_light() -> void:
		effect_updates[3] += 1
		super._update_light()

## Independent reference for the original enabled-frame behavior.
class UncachedCampfire extends CountingCampfire:
	func update_visual(clock_s: float, wind: Vector3 = Vector3.ZERO) -> void:
		if not is_finite(clock_s):
			return
		_clock_s = clock_s
		_wind = wind if _vector_is_finite(wind) else Vector3.ZERO
		if not _enabled:
			return
		_update_exposure_materials()
		_update_flames()
		_update_embers()
		_update_light()


var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Read the rendered state through the effect nodes to compare hidden updates and resumed presentation.
func _effect_snapshot(flames: Node3D, embers: MultiMeshInstance3D) -> Array:
	var state: Array = []
	for child: Node in flames.get_children():
		var sprite := child as Sprite3D
		state.append([sprite.region_rect, sprite.transform, sprite.modulate])
	for index in embers.multimesh.instance_count:
		state.append([embers.multimesh.get_instance_transform(index), embers.multimesh.get_instance_color(index)])
	return state


## Capture every value written by the fire, including materials and its light.
func _full_fire_snapshot(fire: Node3D) -> Array:
	var flames := fire.get_node("ScaledVisuals/FlameSprites") as Node3D
	var embers := fire.get_node("ScaledVisuals/Embers") as MultiMeshInstance3D
	var light := fire.get_node("WarmFireLight") as OmniLight3D
	var state := _effect_snapshot(flames, embers)
	for child: Node in flames.get_children():
		var material := (child as Sprite3D).material_override as ShaderMaterial
		state.append([material.get_shader_parameter("exposure_value"), material.get_shader_parameter("base_gain"),
			material.get_shader_parameter("display_cap")])
	var ember_material := embers.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
	state.append([flames.visible, embers.visible, ember_material.albedo_color, light.visible, light.light_energy])
	return state


func _fire_case(counted: CountingCampfire, reference: UncachedCampfire, clock_s: float, wind: Vector3,
		expected_updates: Array[int], label: String) -> void:
	var before := counted.effect_updates.duplicate()
	counted.update_visual(clock_s, wind)
	reference.update_visual(clock_s, wind)
	var actual_updates: Array[int] = []
	for index in 4:
		actual_updates.append(counted.effect_updates[index] - before[index])
	_check(label + " updates only dependent groups", actual_updates == expected_updates, str(actual_updates))
	_check(label + " matches original visual and light state", _full_fire_snapshot(counted) == _full_fire_snapshot(reference))


func _test_enabled_frame_cache() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://render/sky.gdshader")
	sky_material.set_shader_parameter("disc_dir", Vector3(0.0, -1.0, 0.0))
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.sky = sky
	env.tonemap_exposure = 0.5
	var counted := CountingCampfire.new()
	var reference := UncachedCampfire.new()
	for fire: CountingCampfire in [counted, reference]:
		fire._build_nodes()
		fire.configure(true, env, 0.2)
	var wind := Vector3(2.0, 3.0, 4.0)
	_fire_case(counted, reference, 12.375, wind, [1, 1, 1, 1], "first enabled frame")
	var before := counted.effect_updates.duplicate()
	for frame in 16:
		counted.update_visual(12.375, wind)
		reference.update_visual(12.375, wind)
	_check("identical enabled frames submit no effect updates", counted.effect_updates == before, str(counted.effect_updates))
	_check("identical enabled frames match the original outputs", _full_fire_snapshot(counted) == _full_fire_snapshot(reference))
	_fire_case(counted, reference, 12.5, wind, [0, 1, 1, 1], "clock change")
	for axis: int in 3:
		wind[axis] += 1.0
		_fire_case(counted, reference, 12.5, wind, [0, 1, 1, 0], "wind component %d" % axis)
	env.tonemap_exposure = 2.5
	_fire_case(counted, reference, 12.5, wind, [1, 0, 0, 1], "mutable exposure change")
	sky_material.set_shader_parameter("disc_dir", Vector3(0.0, 0.0, 1.0))
	_fire_case(counted, reference, 12.5, wind, [0, 0, 0, 1], "mutable sky-light change")
	var fallback_shader := Shader.new()
	fallback_shader.code = "shader_type sky; uniform vec3 sun_dir; void sky() { COLOR = vec3(0.0); }"
	var fallback_material := ShaderMaterial.new()
	fallback_material.shader = fallback_shader
	fallback_material.set_shader_parameter("sun_dir", Vector3(0.0, -1.0, 0.0))
	sky.sky_material = fallback_material
	_fire_case(counted, reference, 12.5, wind, [0, 0, 0, 1], "mutable fallback sun change")
	counted._local_gain = 0.4
	reference._local_gain = 0.4
	_fire_case(counted, reference, 12.5, wind, [0, 0, 0, 1], "local gain change")
	_fire_case(counted, reference, 12.5, Vector3(NAN, 0.0, 0.0), [0, 1, 1, 0], "invalid wind sanitization")
	_fire_case(counted, reference, 12.5, Vector3(INF, 0.0, 0.0), [0, 0, 0, 0], "same sanitized wind")
	for fire: CountingCampfire in [counted, reference]:
		fire.set_enabled(false)
		fire.update_visual(19.0, Vector3(-3.0, 0.0, 1.0))
	env.tonemap_exposure = 0.9
	for fire: CountingCampfire in [counted, reference]: fire.set_enabled(true)
	_check("re-enable immediately matches original clock, wind, exposure, and light",
		_full_fire_snapshot(counted) == _full_fire_snapshot(reference))
	_fire_case(counted, reference, 19.0, Vector3(-3.0, 0.0, 1.0), [1, 1, 1, 1], "first frame after enabling")
	var replacement := Environment.new()
	replacement.tonemap_exposure = 1.3
	for fire: CountingCampfire in [counted, reference]: fire.configure(true, replacement, 0.1)
	_check("reconfigure immediately matches the original output", _full_fire_snapshot(counted) == _full_fire_snapshot(reference))
	_fire_case(counted, reference, 19.0, Vector3(-3.0, 0.0, 1.0), [1, 1, 1, 1], "first frame after reconfigure")
	# Explicit public reassertion invalidates the cache even if outside code changed owned nodes.
	for fire: CountingCampfire in [counted, reference]:
		fire._flames[0].position = Vector3(99.0, 99.0, 99.0)
		fire._flame_materials[0].set_shader_parameter("base_gain", 0.01)
		fire.set_enabled(true)
	_fire_case(counted, reference, 19.0, Vector3(-3.0, 0.0, 1.0), [1, 1, 1, 1], "enabled reassertion after external edits")
	counted.free()
	reference.free()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fire: Node3D = Campfire.build()
	_check("built a campfire node", fire != null)
	if fire == null:
		quit(1)
		return
	var base := fire.get_node_or_null("ScaledVisuals/CampfireBase")
	var scaled := fire.get_node_or_null("ScaledVisuals") as Node3D
	var flames := fire.get_node_or_null("ScaledVisuals/FlameSprites") as Node3D
	var embers := fire.get_node_or_null("ScaledVisuals/Embers") as MultiMeshInstance3D
	var light := fire.get_node_or_null("WarmFireLight") as OmniLight3D
	_check("selected Kenney log base exists", base != null)
	_check("visual scale makes the base about one metre across", scaled != null and absf(scaled.scale.x - 3.6) < 0.001)
	_check("flame sprite group starts hidden", flames != null and not flames.visible)
	_check("exactly eight embers are batched", embers != null and embers.multimesh.instance_count == 8)
	_check("one warm Omni has no shadow", light != null and not light.shadow_enabled and light.omni_range <= 4.2)
	_check("bounded particle count", fire.particle_count() == 13 and fire.particle_count() <= 96)
	var child_count := fire.get_child_count()
	fire.configure(false, null, 1000.0)
	fire.set_enabled(false)
	_check("base remains visible when disabled", base != null and (base as Node3D).visible)
	_check("off hides effects and light", flames != null and not flames.visible and light != null and not light.visible)
	_check("repeated toggle adds no nodes", fire.get_child_count() == child_count)
	var environment := Environment.new()
	environment.tonemap_exposure = 0.5
	fire.configure(true, environment, 1000.0)
	fire.update_visual(12.375, Vector3(8.0, 0.0, -4.0))
	_check("enabled shows fire and light", flames != null and flames.visible and light != null and light.visible and light.light_energy > 0.0)
	_check("display contribution remains capped", light != null and light.light_energy * environment.tonemap_exposure <= 0.350001)
	_check("light range stays bounded and shadowless", light != null and absf(light.omni_range - 4.2) < 0.001 and not light.shadow_enabled)
	var first_sprite := flames.get_child(0) as Sprite3D if flames != null and flames.get_child_count() > 0 else null
	var first_material := first_sprite.material_override as ShaderMaterial if first_sprite != null else null
	var first_transform := first_sprite.transform if first_sprite != null else Transform3D.IDENTITY
	var first_region: Rect2 = first_sprite.region_rect if first_sprite != null else Rect2()
	_check("flames use the bounded exposure shader", first_material != null and first_material.shader != null and is_equal_approx(float(first_material.get_shader_parameter("exposure_value")), 0.5))
	_check("flames use one raw atlas with a Sprite3D source region", first_sprite != null and first_sprite.texture == load("res://assets/landscape/night-lighting/flames-8x10.png") and first_sprite.region_enabled)
	var ember_material := embers.multimesh.mesh.surface_get_material(0) as StandardMaterial3D if embers != null and embers.multimesh != null else null
	_check("embers avoid unbounded emission", ember_material != null and not ember_material.emission_enabled)
	environment.tonemap_exposure = 2.5
	fire.configure(true, environment, 1000.0)
	fire.update_visual(12.375, Vector3(8.0, 0.0, -4.0))
	_check("flame shader tracks bright exposure", first_material != null and is_equal_approx(float(first_material.get_shader_parameter("exposure_value")), 2.5))
	_check("exposure does not extinguish ember alpha", ember_material != null and is_equal_approx(ember_material.albedo_color.a, 1.0))
	_check("ember albedo stays under its display cap", ember_material != null and ember_material.albedo_color.r * environment.tonemap_exposure <= 0.400001)
	_check("firelight stays capped after flicker", light != null and light.light_energy * environment.tonemap_exposure <= 0.350001)
	environment.tonemap_exposure = 0.5
	fire.configure(true, environment, 1000.0)
	fire.update_visual(12.375, Vector3(8.0, 0.0, -4.0))
	fire.update_visual(13.25, Vector3(8.0, 0.0, -4.0))
	var later_region := first_sprite.region_rect if first_sprite != null else Rect2()
	_check("flame atlas region follows explicit clock", first_region != later_region)
	fire.update_visual(12.375, Vector3(8.0, 0.0, -4.0))
	_check("same clock and wind reproduce sprite state", first_sprite != null and first_sprite.region_rect == first_region and first_sprite.transform == first_transform)
	var saved_children := fire.get_child_count()
	fire.set_enabled(false)
	var hidden_state := _effect_snapshot(flames, embers)
	var hidden_exposure: Variant = first_material.get_shader_parameter("exposure_value")
	var resumed_wind := Vector3(-4.0, 0.0, 7.0)
	environment.tonemap_exposure = 1.5
	fire.update_visual(13.25, resumed_wind)
	_check("disabled effects do not rewrite hidden visual state", _effect_snapshot(flames, embers) == hidden_state)
	_check("disabled effects do not rewrite their exposure", first_material.get_shader_parameter("exposure_value") == hidden_exposure)
	environment.tonemap_exposure = 2.5 # The clock is paused; no new visual update follows before enabling.
	fire.set_enabled(true)
	var reference: Node3D = Campfire.build()
	reference.configure(true, environment, 1000.0)
	reference.update_visual(13.25, resumed_wind)
	var reference_flames := reference.get_node("ScaledVisuals/FlameSprites") as Node3D
	var reference_embers := reference.get_node("ScaledVisuals/Embers") as MultiMeshInstance3D
	var reference_light := reference.get_node("WarmFireLight") as OmniLight3D
	_check("enabling immediately presents the latest clock and wind", _effect_snapshot(flames, embers) == _effect_snapshot(reference_flames, reference_embers))
	_check("enabling immediately applies current exposure and light", is_equal_approx(float(first_material.get_shader_parameter("exposure_value")), 2.5) and is_equal_approx(light.light_energy, reference_light.light_energy))
	reference.free()
	var counted := CountingCampfire.new()
	counted._build_nodes()
	counted.configure(false, environment, 1000.0)
	var before_disabled_frames: Array = counted.effect_updates.duplicate()
	for frame in 16:
		var clock := 25.0 if frame < 8 else 25.0 + float(frame - 7) * 0.125
		var wind := Vector3.ZERO if frame < 8 else Vector3(float(frame), 0.0, -float(frame))
		counted.update_visual(clock, wind)
	_check("disabled frames skip visual and light updates", counted.effect_updates == before_disabled_frames)
	counted.free()
	_check("on/off transition reuses nodes", fire.get_child_count() == saved_children)
	_check("helper has no autonomous process", not fire.is_processing())
	fire.free()
	_test_enabled_frame_cache()
	print("FW-67 campfire: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
