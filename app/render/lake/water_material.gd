extends RefCounted
class_name LakeWaterMaterial

## Resource adapter for one finite lake surface. The basin renderer owns its
## mesh, positions it at -water_level_down_m, and supplies UV2.x as signed
## nearest-shore distance in metres. `config` is LakeLoader's normalized lake
## dictionary (`waves` and `wave_bounds` are top-level keys).
const WATER_SHADER: Shader = preload("res://render/lake/water.gdshader")
const ShaderClock = preload("res://render/shader_clock.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Spec = preload("res://spec.gd")
const HighGraphics = preload("res://render/high_graphics_profile.gd")

const MAX_WAVES := 2
const MAX_AMPLITUDE_M := 0.06
const DEFAULT_COLORS := {
	"shallow_color": Color(0.20, 0.43, 0.40, 1.0),
	"deep_color": Color(0.025, 0.115, 0.15, 1.0),
	"foam_color": Color(0.70, 0.82, 0.78, 1.0),
}
const PARAMETER_RANGES := {
	"absorption_per_m": Vector2(0.05, 2.0),
	"deep_reference_depth_m": Vector2(1.0, 12.0),
	"refraction_strength": Vector2(0.0, 0.025),
	"shore_fade_m": Vector2(0.1, 12.0),
	"shore_foam_start_m": Vector2(0.0, 1.0),
	"shore_foam_end_m": Vector2(0.1, 2.0),
	"water_roughness": Vector2(0.0, 1.0),
	"water_specular": Vector2(0.0, 1.0),
}


## `config` is the normalized lake definition; `lighting` is the same world
## snapshot passed to the existing Atmosphere helpers (or empty for active flow).
static func create(config: Dictionary, lighting: Dictionary = {}) -> ShaderMaterial:
	ShaderClock.register()
	var result := ShaderMaterial.new()
	result.shader = WATER_SHADER

	for parameter: String in DEFAULT_COLORS:
		var value: Variant = config.get(parameter, DEFAULT_COLORS[parameter])
		result.set_shader_parameter(parameter, _as_color(value, DEFAULT_COLORS[parameter]))

	var bounds: Dictionary = config.get("wave_bounds", {})
	for parameter: String in PARAMETER_RANGES:
		var fallback := _default_number(parameter)
		var value: Variant = config.get(parameter, fallback)
		if parameter == "shore_fade_m":
			value = bounds.get(parameter, value)
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			var limits: Vector2 = PARAMETER_RANGES[parameter]
			result.set_shader_parameter(parameter, clampf(float(value), limits.x, limits.y))
		else:
			result.set_shader_parameter(parameter, fallback)

	_set_wave_parameters(result, config, bounds)
	update_lighting(result, lighting)
	return result


## Keep custom surface haze aligned with the existing world environment, while
## standard spatial specular uses its DirectionalLight, sky, and reflection probes.
static func update_lighting(material: ShaderMaterial, lighting: Dictionary = {}) -> void:
	if material == null:
		return
	var effective_lighting := lighting
	if not lighting.is_empty():
		# Water-only overrides can be passed beside the world values. Fill missing
		# atmosphere fields from the canonical defaults exactly as the other render
		# adapters do for a scene snapshot.
		effective_lighting = Spec.ATMOSPHERE.duplicate(true)
		effective_lighting.merge(lighting, true)
	material.set_shader_parameter("haze_lin", Atmosphere.haze_linear(effective_lighting))
	material.set_shader_parameter("sun_dir", Atmosphere.sun_direction(effective_lighting))
	material.set_shader_parameter("sun_lin", Atmosphere.sun_linear(effective_lighting))
	material.set_shader_parameter("sun_scatter", Atmosphere.sun_scatter(effective_lighting))
	Atmosphere.track_shadow_material(material, effective_lighting)
	material.set_shader_parameter("beta", Atmosphere.beta())

	var flow_state: Dictionary = Atmosphere.state
	var lobe_lin: Vector3 = flow_state.lobe_lin if lighting.is_empty() and not flow_state.is_empty() \
		else effective_lighting.get("lobe_lin", Vector3.ZERO)
	var lobe_dir: Vector3 = flow_state.lobe_dir if lighting.is_empty() and not flow_state.is_empty() \
		else effective_lighting.get("lobe_dir", Vector3(1.0, 0.0, 0.0))
	material.set_shader_parameter("lobe_lin", lobe_lin)
	material.set_shader_parameter("lobe_dir", lobe_dir)
	material.set_shader_parameter("lobe_k", effective_lighting.get("lobe_k", 8.0))
	material.set_shader_parameter("lobe_height", effective_lighting.get("lobe_height", 1.5708))
	_set_lighting_override(material, lighting, "water_roughness", PARAMETER_RANGES.water_roughness)
	_set_lighting_override(material, lighting, "water_specular", PARAMETER_RANGES.water_specular)


static func _set_wave_parameters(material: ShaderMaterial, config: Dictionary, bounds: Dictionary) -> void:
	var packed_waves := PackedVector4Array()
	packed_waves.resize(MAX_WAVES)
	var packed_phases := PackedFloat32Array()
	packed_phases.resize(MAX_WAVES)
	var raw_waves: Variant = config.get("waves", [])
	if not raw_waves is Array:
		push_error("Normalized lake config `waves` must be an Array[Dictionary].")
		material.set_shader_parameter("wave_params", packed_waves)
		material.set_shader_parameter("wave_phase_rad", packed_phases)
		material.set_shader_parameter("wave_count", 0)
		return
	if raw_waves.size() > MAX_WAVES:
		push_error("Lake water supports at most %d analytic waves; no waves were applied." % MAX_WAVES)
		material.set_shader_parameter("wave_params", packed_waves)
		material.set_shader_parameter("wave_phase_rad", packed_phases)
		material.set_shader_parameter("wave_count", 0)
		return

	var amplitude_limit := MAX_AMPLITUDE_M
	var configured_limit: Variant = bounds.get("max_amplitude_m", MAX_AMPLITUDE_M)
	if (typeof(configured_limit) == TYPE_FLOAT or typeof(configured_limit) == TYPE_INT) \
		and is_finite(float(configured_limit)):
		amplitude_limit = clampf(float(configured_limit), 0.0, MAX_AMPLITUDE_M)

	var amplitude_sum := 0.0
	var valid_count := 0
	for raw_wave: Variant in raw_waves:
		if not raw_wave is Dictionary:
			push_error("Every normalized lake wave must be a Dictionary; no waves were applied.")
			material.set_shader_parameter("wave_params", packed_waves)
			material.set_shader_parameter("wave_phase_rad", packed_phases)
			material.set_shader_parameter("wave_count", 0)
			return
		var values: Array[float] = []
		for key: String in ["amplitude_m", "wavelength_m", "period_s", "heading_rad", "phase_rad"]:
			var value: Variant = raw_wave.get(key)
			if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)):
				push_error("Lake wave is missing a finite numeric `%s`; no waves were applied." % key)
				material.set_shader_parameter("wave_params", packed_waves)
				material.set_shader_parameter("wave_phase_rad", packed_phases)
				material.set_shader_parameter("wave_count", 0)
				return
			values.append(float(value))
		var amplitude := values[0]
		var wavelength := values[1]
		var period := values[2]
		if amplitude < 0.0 or wavelength <= 0.0 or period <= 0.0:
			push_error("Lake wave amplitude must be non-negative and wavelength/period positive; no waves were applied.")
			material.set_shader_parameter("wave_params", packed_waves)
			material.set_shader_parameter("wave_phase_rad", packed_phases)
			material.set_shader_parameter("wave_count", 0)
			return
		packed_waves[valid_count] = Vector4(amplitude, wavelength, period, values[3])
		packed_phases[valid_count] = values[4]
		amplitude_sum += amplitude
		valid_count += 1

	if amplitude_sum > amplitude_limit + 1e-6:
		push_error("Lake wave amplitudes sum to %.4f m, above the configured %.4f m limit; no waves were applied." \
			% [amplitude_sum, amplitude_limit])
		material.set_shader_parameter("wave_params", packed_waves)
		material.set_shader_parameter("wave_phase_rad", packed_phases)
		material.set_shader_parameter("wave_count", 0)
		return
	material.set_shader_parameter("wave_params", packed_waves)
	material.set_shader_parameter("wave_phase_rad", packed_phases)
	material.set_shader_parameter("wave_count", valid_count)


static func _set_lighting_override(material: ShaderMaterial, lighting: Dictionary, parameter: String, limits: Vector2) -> void:
	var value: Variant = lighting.get(parameter)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		material.set_shader_parameter(parameter, clampf(float(value), limits.x, limits.y))


static func _as_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is Array or value is PackedFloat64Array or value is PackedFloat32Array:
		if value.size() >= 3:
			var alpha := float(value[3]) if value.size() >= 4 else 1.0
			return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	return fallback


static func _default_number(parameter: String) -> float:
	match parameter:
		"absorption_per_m":
			return 0.46
		"deep_reference_depth_m":
			return 5.0
		"refraction_strength":
			return 0.006
		"shore_fade_m":
			return 5.5
		"shore_foam_start_m":
			return 0.02
		"shore_foam_end_m":
			return 0.48
		"water_roughness":
			# VQ-07: the native Forward+ probe filter erases the shoreline silhouettes
			# at the Compatibility default. Keep some blur; this is a visual calibration,
			# not a universal BRDF conversion. Explicit material/lighting values still win.
			return 0.06 if HighGraphics.active() else 0.22
		"water_specular":
			return 0.76
	return 0.0
