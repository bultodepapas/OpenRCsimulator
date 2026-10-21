extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const HighGraphics := preload("res://render/high_graphics_profile.gd")
const Spec := preload("res://spec.gd")

const PROFILE_ENV := "OPENRC_GRAPHICS_PROFILE"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var had_profile_env := OS.has_environment(PROFILE_ENV)
	var saved_profile_env := OS.get_environment(PROFILE_ENV)
	var saved_configured: bool = HighGraphics._configured
	var saved_reported: bool = HighGraphics._reported
	var saved_atmosphere_state: Dictionary = Atmosphere.state.duplicate(true)
	var saved_engine_shadows: bool = Atmosphere.engine_shadows
	var saved_spec: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	var native_forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus" \
		and DisplayServer.get_name() != "headless"

	HighGraphics._configured = false
	HighGraphics._reported = false
	Atmosphere.state = {}
	OS.unset_environment(PROFILE_ENV)
	_check("no request selects standard", not HighGraphics.active() and HighGraphics.requested().is_empty())
	_test_standard_integration()

	OS.set_environment(PROFILE_ENV, "  ultra  ")
	_check("invalid request is normalized but inactive", HighGraphics.requested() == "ultra" and not HighGraphics.active())
	_test_direct_fallback("invalid request")

	OS.set_environment(PROFILE_ENV, "high")
	_check("high requires the actual native Forward+ display gate", HighGraphics.active() == native_forward_plus,
		"renderer=%s display=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_name()])
	if native_forward_plus:
		_test_high_native_values()
	else:
		_test_direct_fallback("high request with unavailable native Forward+")
		print("SKIP high native values: renderer=%s display=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_name()])

	_test_protected_environment_and_physics()
	_test_atmosphere_reapplication(native_forward_plus)

	if had_profile_env:
		OS.set_environment(PROFILE_ENV, saved_profile_env)
	else:
		OS.unset_environment(PROFILE_ENV)
	HighGraphics._configured = saved_configured
	HighGraphics._reported = saved_reported
	Atmosphere.state = saved_atmosphere_state
	Atmosphere.engine_shadows = saved_engine_shadows
	_check("atmosphere specification remains unchanged", Spec.ATMOSPHERE == saved_spec)
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(actual: float, expected: float, tolerance := 1.0e-5) -> bool:
	return absf(actual - expected) <= tolerance


func _test_standard_integration() -> void:
	var env := Atmosphere.environment(Spec.ATMOSPHERE)
	_check("standard environment keeps SSAO off", not env.ssao_enabled)
	_check("standard environment uses sky reflections", env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY)
	var holder := Node3D.new()
	root.add_child(holder)
	var sun := Atmosphere.create_sun(holder, Spec.ATMOSPHERE)
	_check("standard sun keeps two shadow splits", sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	_check("standard sun keeps default angular size", _near(sun.light_angular_distance, 0.0))
	holder.free()


func _test_direct_fallback(label: String) -> void:
	var env := Environment.new()
	env.ssao_enabled = false
	env.ssao_radius = 0.37
	env.ssao_intensity = 0.61
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var sun := DirectionalLight3D.new()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = false
	sun.light_angular_distance = 0.0
	HighGraphics.configure()
	HighGraphics.apply_environment(env)
	HighGraphics.apply_sun(sun)
	_check("%s leaves SSAO disabled" % label, not env.ssao_enabled)
	_check("%s preserves sentinel SSAO radius" % label, _near(env.ssao_radius, 0.37))
	_check("%s preserves sentinel SSAO intensity" % label, _near(env.ssao_intensity, 0.61))
	_check("%s preserves reflection source" % label, env.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED)
	_check("%s preserves standard shadow mode" % label,
		sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	_check("%s preserves standard shadow blending" % label, not sun.directional_shadow_blend_splits)
	_check("%s preserves standard angular size" % label, _near(sun.light_angular_distance, 0.0))
	sun.free()


func _test_high_native_values() -> void:
	HighGraphics.configure()
	_check("native high request latches renderer setup", HighGraphics._configured)
	var env := Environment.new()
	env.ssao_enabled = false
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	HighGraphics.apply_environment(env)
	_check("native high enables SSAO", env.ssao_enabled)
	_check("native high SSAO radius", _near(env.ssao_radius, 0.8))
	_check("native high SSAO intensity", _near(env.ssao_intensity, 1.2))
	_check("native high SSAO power", _near(env.ssao_power, 1.3))
	_check("native high SSAO detail", _near(env.ssao_detail, 0.5))
	_check("native high SSAO light affect", _near(env.ssao_light_affect, 0.0))
	_check("native high enables sky reflections", env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.4, 0.5, 0.6)
	sun.light_energy = 1.7
	HighGraphics.apply_sun(sun)
	_check("native high uses four shadow splits", sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_check("native high blends shadow splits", sun.directional_shadow_blend_splits)
	_check("native high first split", _near(sun.directional_shadow_split_1, 0.06))
	_check("native high second split", _near(sun.directional_shadow_split_2, 0.20))
	_check("native high third split", _near(sun.directional_shadow_split_3, 0.50))
	_check("native high uses solar angular size", _near(sun.light_angular_distance, 0.53))
	_check("native high preserves direct light colour", sun.light_color == Color(0.4, 0.5, 0.6))
	_check("native high preserves direct light energy", _near(sun.light_energy, 1.7))
	sun.free()


func _test_protected_environment_and_physics() -> void:
	var env := Atmosphere.environment(Spec.ATMOSPHERE)
	var exposure := env.tonemap_exposure
	var fog_enabled := env.fog_enabled
	var fog_mode := env.fog_mode
	var fog_density := env.fog_density
	var fog_height_density := env.fog_height_density
	var fog_scatter := env.fog_sun_scatter
	var beta_before := Atmosphere.beta()
	var transmittance_before := Atmosphere.transmittance(321.0)
	var scatter_before := Atmosphere.sun_scatter(Spec.ATMOSPHERE)
	var spec_before: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	HighGraphics.apply_environment(env)
	_check("high profile leaves exposure unchanged", _near(env.tonemap_exposure, exposure))
	_check("high profile leaves fog enablement unchanged", env.fog_enabled == fog_enabled)
	_check("high profile leaves fog mode unchanged", env.fog_mode == fog_mode)
	_check("high profile leaves fog density unchanged", _near(env.fog_density, fog_density))
	_check("high profile leaves height fog unchanged", _near(env.fog_height_density, fog_height_density))
	_check("high profile leaves fog scatter unchanged", _near(env.fog_sun_scatter, fog_scatter))
	_check("high profile leaves atmosphere extinction unchanged", _near(Atmosphere.beta(), beta_before))
	_check("high profile leaves atmospheric transmission unchanged", _near(Atmosphere.transmittance(321.0), transmittance_before))
	_check("high profile leaves sun scatter law unchanged", _near(Atmosphere.sun_scatter(Spec.ATMOSPHERE), scatter_before))
	_check("high profile leaves atmosphere configuration unchanged", Spec.ATMOSPHERE == spec_before)


func _test_atmosphere_reapplication(native_forward_plus: bool) -> void:
	var lighting: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	Atmosphere.state = {}
	var env := Atmosphere.environment(lighting)
	env.ssao_enabled = false
	env.ssao_radius = 0.13
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	Atmosphere.update_environment(env, lighting)
	_check("update_environment restores profile SSAO state", env.ssao_enabled == native_forward_plus)
	_check("update_environment preserves sky reflections in standard and high", env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY)
	if native_forward_plus:
		_check("update_environment reapplies high SSAO radius", _near(env.ssao_radius, 0.8))
	_check("update_environment leaves exposure at atmosphere setting", _near(env.tonemap_exposure, float(lighting.exposure)))
	_check("update_environment leaves fog density at atmosphere setting", _near(env.fog_density, Atmosphere.beta()))

	var flow_state := {
		"haze_lin": Vector3(0.12, 0.18, 0.24),
		"ambient_lin": Vector3(0.28, 0.31, 0.37),
		"tonemapper": "agx",
		"exposure": 0.73,
		"light_dir": Vector3(0.1, 0.98, -0.15).normalized(),
		"light_color": Color(1.0, 0.93, 0.81),
		"light_energy": 1.25,
		"shadow_strength": 0.7,
	}
	Atmosphere.state = flow_state.duplicate(true)
	var state_env := Environment.new()
	state_env.tonemap_exposure = 0.46
	state_env.fog_enabled = true
	state_env.fog_density = 0.004
	state_env.fog_height_density = 0.0
	Atmosphere.apply_state_to_environment(state_env)
	_check("apply_state_to_environment restores profile SSAO state", state_env.ssao_enabled == native_forward_plus)
	_check("apply_state_to_environment keeps sky reflection when high", state_env.reflected_light_source ==
		(Environment.REFLECTION_SOURCE_SKY if native_forward_plus else Environment.REFLECTION_SOURCE_DISABLED))
	_check("apply_state_to_environment preserves exposure", _near(state_env.tonemap_exposure, 0.46))
	_check("apply_state_to_environment preserves fog density", _near(state_env.fog_density, 0.004))
	_check("apply_state_to_environment preserves fog mode", state_env.fog_enabled and state_env.fog_height_density == 0.0)
	_check("apply_state_to_environment does not mutate flow state", Atmosphere.state == flow_state)

	Atmosphere.state = {}
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = false
	sun.light_angular_distance = 0.0
	Atmosphere.update_sun(sun, lighting)
	_check("update_sun reapplies high four-split shadows", sun.directional_shadow_mode ==
		(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if native_forward_plus else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS))
	if native_forward_plus:
		_check("update_sun reapplies high split blending", sun.directional_shadow_blend_splits)
		_check("update_sun reapplies high angular size", _near(sun.light_angular_distance, 0.53))
	else:
		_check("standard update_sun leaves high angular size disabled", _near(sun.light_angular_distance, 0.0))
	sun.free()
