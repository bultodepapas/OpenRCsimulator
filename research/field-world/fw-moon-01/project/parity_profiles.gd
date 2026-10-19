# FW-MOON-01: cloud-occlusion parity of the mesh disc (candidate B) against the sky disc (candidate A) for every
# weather preset in app/data/sky/weather_presets.json. The layered arrays come from the app's own
# render/weather/sky_appearance.gd (resolve + shader_arrays, copied from SRC_REV by run.sh), offsets zero, seed 1253.
# Run: run.sh OUT profiles  (scene res://profiles.tscn, --mode=profiles). Method as bench.gd _run_parity part 2.
extends "res://bench.gd"

const SkyAppearance := preload("res://render/weather/sky_appearance.gd")
const PRESETS := "res://weather_presets.json"
const CLOUD_PARAMS := [&"layered_appearance", &"appearance_layer_count", &"appearance_layer_parameters",
	&"appearance_layer_motion", &"appearance_layer_seeds", &"appearance_cloud_density"]


func _ready() -> void:
	super._ready()
	_run_profiles.call_deferred()


func _set_both(name: StringName, value: Variant) -> void:
	sky_mat.set_shader_parameter(name, value)
	disc_mat.set_shader_parameter(name, value)


func _run_profiles() -> void:
	await _frames(30)
	cam.fov = 2.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	sky_mat.set_shader_parameter("cloud_lin", Vector3(0.08, 0.085, 0.09))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PRESETS))
	var rows := []
	var t_all := PackedFloat64Array()
	for preset: Dictionary in catalog.presets:
		var profile := SkyAppearance.resolve(preset, {seed = 1253})
		var layers: Array = profile.get("cloud_layers", [])
		var id := str(preset.get("id", ""))
		if profile.is_empty() or profile.get("legacy", false) or layers.is_empty():
			rows.append({preset = id, layers = layers.size(), note = "no layered decks (legacy or clear): see parity_mask"})
			continue
		var offsets := []
		for i in layers.size():
			offsets.append([0.0, 0.0])
		var arrays := SkyAppearance.shader_arrays(layers, offsets, float(profile.cloud_cover), float(profile.cloud_density))
		_set_both(&"layered_appearance", true)
		_set_both(&"appearance_layer_parameters", arrays.layer_parameters)
		_set_both(&"appearance_layer_motion", arrays.layer_motion)
		_set_both(&"appearance_layer_seeds", arrays.layer_seeds)
		_set_both(&"appearance_cloud_density", arrays.cloud_density)
		var per := []
		for k in 8:
			var el := 20.0 + 9.0 * float(k % 4)
			var p := [70.0 + 13.0 * k, el]
			_aim(p)
			var tag := "%s_az%03d_el%02d" % [id, int(p[0]), int(p[1])]
			_set_both(&"appearance_layer_count", arrays.layer_count)
			var cloudy := await _abc("profile_" + tag, k == 0)
			_set_both(&"appearance_layer_count", 0)
			var clear := await _abc("profile_" + tag + "_clear", false)
			per.append(_compare_mask(tag, cloudy, clear, t_all))
		var worst := 0.0
		var partial := 0
		var mean_dt := 0.0
		for r: Dictionary in per:
			worst = maxf(worst, float(r.max_abs_dt))
			mean_dt = maxf(mean_dt, absf(float(r.mean_t_a) - float(r.mean_t_b)))
			if float(r.mean_t_a) < 0.99 and float(r.mean_t_a) > 0.01:
				partial += 1
		rows.append({preset = id, layers = layers.size(), positions = per, partial_positions = partial,
			max_abs_dt = worst, max_abs_mean_dt = mean_dt})
	t_all.sort()
	_write({profiles = rows, mask_pixels = t_all.size(),
		mask_abs_dt_p50 = t_all[int(0.50 * (t_all.size() - 1))] if t_all.size() else -1.0,
		mask_abs_dt_p99 = t_all[int(0.99 * (t_all.size() - 1))] if t_all.size() else -1.0,
		mask_abs_dt_max = t_all[t_all.size() - 1] if t_all.size() else -1.0})
	get_tree().quit()
