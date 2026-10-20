extends SceneTree

const BeforeLights := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/landscape-perf-r2/baseline_airfield_lighting.gd")
const BeforeBank := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/landscape-perf-r2/baseline_storm_bank.gd")
const AfterLights := preload("res://render/landscape_upgrade/airfield_lighting.gd")
const AfterBank := preload("res://render/weather/storm_bank.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const SkyAppearance := preload("res://render/weather/sky_appearance.gd")
const PAIRS := 11
const ITERATIONS := 20000

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var field: Dictionary = FieldLoader.load_from().field
	var scenery: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field).scenery
	var fixtures: Dictionary = FieldLights.load_from().lights
	var selection: Dictionary = SkyConfig.for_preset("distant_storm")
	var profile: Dictionary = SkyConfig.validate(selection).profile
	var resolved: Dictionary = SkyAppearance.resolve(profile, selection)
	var scene := {"cloud_layers": resolved.cloud_layers.duplicate(true)}
	for layer: Dictionary in scene.cloud_layers:
		layer.offset = Vector2.ZERO
	var before := _make(BeforeLights, BeforeBank, field, scenery, fixtures, profile)
	var after := _make(AfterLights, AfterBank, field, scenery, fixtures, profile)
	var rows: Array = []
	for mode: String in ["lights_fixed", "lights_changing", "storm_fixed", "storm_changing", "flash_clear", "flash_changing"]:
		_measure(before, scene, mode, 1000)
		_measure(after, scene, mode, 1000)
		var old_samples: Array = []
		var new_samples: Array = []
		for pair in PAIRS:
			if pair % 2 == 0:
				old_samples.append(_measure(before, scene, mode, ITERATIONS))
				new_samples.append(_measure(after, scene, mode, ITERATIONS))
			else:
				new_samples.append(_measure(after, scene, mode, ITERATIONS))
				old_samples.append(_measure(before, scene, mode, ITERATIONS))
		var old_sorted := old_samples.duplicate()
		var new_sorted := new_samples.duplicate()
		old_sorted.sort()
		new_sorted.sort()
		var row := {"mode": mode, "before_us": old_sorted[PAIRS / 2], "after_us": new_sorted[PAIRS / 2],
			"before_samples_us": old_samples, "after_samples_us": new_samples}
		rows.append(row)
		print(JSON.stringify(row))
	var result := {"pairs": PAIRS, "iterations_per_sample": ITERATIONS,
		"renderer": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info(), "rows": rows}
	var file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/landscape-perf-r2/performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	for fixture: Dictionary in [before, after]:
		fixture.helper.free()
		fixture.lights.free()
		fixture.bank.free()
	before.clear()
	after.clear()
	await process_frame
	await process_frame
	quit()

func _make(light_script: Script, bank_script: Script, field: Dictionary, scenery: Dictionary,
		fixtures: Dictionary, profile: Dictionary) -> Dictionary:
	var environment := Atmosphere.environment()
	var lights := FieldLights.build(fixtures)
	var helper: Node3D = light_script.build(field, fixtures, scenery, true)
	helper.bind_environment(environment, lights)
	var bank: Node3D = bank_script.new()
	bank.configure(profile, 147)
	return {"environment": environment, "sky": environment.sky.sky_material, "lights": lights, "helper": helper, "bank": bank}

func _measure(fixture: Dictionary, scene: Dictionary, mode: String, count: int) -> float:
	var helper: Node3D = fixture.helper
	var bank: Node3D = fixture.bank
	var environment: Environment = fixture.environment
	var sky: ShaderMaterial = fixture.sky
	var event := {"event_id": "bench", "source_world": [10.0, 20.0, 30.0]}
	var start := Time.get_ticks_usec()
	match mode:
		"lights_fixed":
			for i in count:
				helper._update_from_environment()
		"lights_changing":
			for i in count:
				sky.set_shader_parameter("disc_dir", Vector3(0, -0.1 - float(i % 100) * 0.00001, -1))
				helper._update_from_environment()
		"storm_fixed":
			for i in count:
				bank.update_visual(scene, environment, null, float(i))
		"storm_changing":
			for i in count:
				sky.set_shader_parameter("cloud_lin", Vector3.ONE * (0.5 + float(i % 100) * 0.0001))
				bank.update_visual(scene, environment, null, float(i))
		"flash_clear":
			for i in count:
				bank.apply_flash({}, 0.0, 1.0)
		"flash_changing":
			for i in count:
				bank.apply_flash(event, float(i % 100) / 100.0, 1.0)
	return float(Time.get_ticks_usec() - start) / count
