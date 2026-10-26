extends SceneTree

const Config := preload("res://physics/wind_spatial_config.gd")
const Field := preload("res://physics/wind_spatial_field.gd")
const Presets := preload("res://physics/wind_spatial_presets.gd")

func _initialize() -> void:
	var configs: Array[Dictionary] = []
	configs.append({"id": "calm", "config": Config.defaults()})
	for direction: float in [0.0, 90.0, 359.9]:
		var raw := Config.defaults()
		raw.identity.seed_u32 = 392731
		raw.identity.epoch_offset_s = 0.25
		raw.profile.reference_speed_mps = 3.125
		raw.profile.reference_from_deg = direction
		raw.profile.reference_height_agl_m = 15.0
		raw.profile.roughness_length_m = 0.05
		raw.profile.displacement_height_m = 0.08
		raw.profile.wall_join_height_agl_m = 0.6
		raw.profile.surface_layer_top_agl_m = 75.0
		raw.profile.free_air_join_height_m = 25.0
		raw.profile.free_air_wind_ned_mps = [-2.0, -1.0, 0.0]
		raw.profile.layers = [{"id": "layer", "center_agl_m": 42.0, "half_thickness_m": 7.0, "delta_wind_ned_mps": [0.23, -0.36, 0.0]}]
		raw.turbulence.rms_mps = 0.17 if direction != 0.0 else 0.0
		raw.turbulence.mode_count = 64 if direction == 359.9 else 24
		raw.gusts.events = [
			{"id": "tied-a", "start_s": 1.0, "duration_s": 4.0, "amplitude_ned_mps": [1.1, -0.7, 0.0]},
			{"id": "tied-b", "start_s": 1.0, "duration_s": 4.0, "amplitude_ned_mps": [-1.1, 0.7, 0.0]},
			{"id": "tied-c", "start_s": 1.0, "duration_s": 8.0, "amplitude_ned_mps": [0.01, -0.02, 0.0]},
			{"id": "overlap", "start_s": 3.0, "duration_s": 4.0, "amplitude_ned_mps": [-0.3, 0.2, 0.0]},
		]
		configs.append({"id": "direction-" + str(direction), "config": raw})
	var heights := [-0.25, 0.0, 0.000001, 0.3, 0.599999999, 0.6, 0.600000001, 2.999999999, 3.0, 35.0, 42.0, 49.0, 74.999999999, 75.0, 75.000000001, 99.999999999, 100.0, 100.000000001, 200.0]
	var times := [0.0, 0.749999999, 0.75, 0.750000001, 2.75, 4.749999999, 4.75, 6.75, 8.75, 86399.75]
	var queries: Array = []
	for height: float in heights:
		for time_s: float in times:
			queries.append({"position_ned_m": [17.25, -31.5, -height], "time_s": time_s})
	for item: Dictionary in configs:
		var built: Dictionary = Field.build(item.config)
		if not built.ok:
			push_error(str(built.errors))
			quit(1)
			return
		item["content_hash"] = built.field.content_hash()
		item["bound_bytes_hex"] = PackedFloat64Array([built.field.absolute_speed_bound_mps()]).to_byte_array().hex_encode()
		item["wind_bytes_hex"] = []
		for query: Dictionary in queries:
			var sample: Dictionary = built.field.sample_world(PackedFloat64Array(query.position_ned_m), float(query.time_s))
			if not sample.ok:
				push_error(str(sample.error))
				quit(1)
				return
			item.wind_bytes_hex.append(sample.wind_ned_mps.to_byte_array().hex_encode())
	var report := {
		"format": "openrc-spatial-boundary-parity v1",
		"baseline_solver_sha256": "cba4552d2749e19ace9483de73a6114adb7beb15ce7e70922b05a2a02fe27904",
		"baseline_field_sha256": "218908e722fa89347ccdd20423bedac9f0358f970b47661a4ec42cfa1bcf3130",
		"godot": Engine.get_version_info().string,
		"queries": queries, "cases": configs,
	}
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("recorded %d baseline boundary samples" % (configs.size() * queries.size()))
	quit()
