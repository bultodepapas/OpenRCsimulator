extends SceneTree
## Focused software checks; this headless script does not establish rendered quality.

const PlumeView = preload("res://visual/afterburner_visual.gd")

var _checks: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		push_error("FAIL: " + description)


func _run() -> void:
	var first := PlumeView.new()
	var second := PlumeView.new()
	root.add_child(first)
	root.add_child(second)
	first.set_snapshot(0.8, 4.25)
	second.set_snapshot(0.2, 1.0)
	var first_material := first.get_node("OuterPlume").material_override as ShaderMaterial
	var second_material := second.get_node("OuterPlume").material_override as ShaderMaterial
	_check(first_material != second_material, "separate engines own separate materials")
	_check(is_equal_approx(float(first_material.get_shader_parameter("burner_actual")), 0.8), "second engine cannot overwrite first intensity")
	var original_phase: Vector4 = first_material.get_shader_parameter("animation_phase_rad")
	first.set_snapshot(0.8, 4.25)
	_check(first_material.get_shader_parameter("animation_phase_rad") == original_phase, "same accepted time freezes animation")
	first.set_snapshot(0.8, 7.0)
	first.set_snapshot(0.8, 4.25)
	_check(first_material.get_shader_parameter("animation_phase_rad") == original_phase, "restored time restores animation phase")
	_check(PlumeView.phase_for_time(4.25).is_equal_approx(PlumeView.phase_for_time(1028.25)), "phase repeats over 1024-second boundary")
	var before := PlumeView.phase_for_time(1024.0 - 0.000001)
	var after := PlumeView.phase_for_time(1024.0 + 0.000001)
	var maximum_sine_jump := 0.0
	for index in 4:
		maximum_sine_jump = maxf(maximum_sine_jump, absf(sin(before[index]) - sin(after[index])))
	_check(maximum_sine_jump < 0.001, "clock wrap does not create a visible oscillator jump")
	var huge := PlumeView.phase_for_time(1.0e300)
	_check(huge.is_finite() and huge.x >= 0.0 and huge.x <= TAU and huge.w >= 0.0 and huge.w <= TAU, "large finite time produces bounded finite phases")
	first.set_snapshot(1.5, 8.0)
	_check(first.burner_actual == 1.0, "presentation level clamps at one")
	first.set_snapshot(-1.0, 8.0)
	_check(not first.visible and first.burner_actual == 0.0, "negative level hides the effect")
	first.set_snapshot(NAN, 8.0)
	_check(not first.visible, "non-finite level fails closed")
	first.set_snapshot(1.0, INF)
	_check(not first.visible, "non-finite time fails closed")
	first.set_snapshot(0.8, 5.0)
	first.clear()
	_check(not first.visible and first.accepted_sim_time_s == 0.0, "clear resets visibility and phase")
	var shell := second.get_node("OuterPlume") as MeshInstance3D
	_check(shell.custom_aabb.size.z >= second.max_length_m and shell.custom_aabb.size.x >= 2.0 * second.nozzle_radius_m, "finite bounds cover configured plume extent")
	_check(shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "flame does not cast a solid shadow")
	first.free()
	second.free()
	print("AFTERBURNER_VISUAL_CHECKS %d checks, %d failed" % [_checks, _failed])
	quit(0 if _failed == 0 else 1)
