## FW-67: downloaded campfire base stays present while clock-driven effects toggle without growing the scene.
extends SceneTree

const Campfire := preload("res://render/world/campfire.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


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
	fire.set_enabled(true)
	_check("on/off transition reuses nodes", fire.get_child_count() == saved_children)
	_check("helper has no autonomous process", not fire.is_processing())
	fire.free()
	print("FW-67 campfire: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
