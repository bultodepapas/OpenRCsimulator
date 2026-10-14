# VQ-02a: run outside app/ against an imported, immutable source snapshot.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ""
	var source_commit := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		elif arg.begins_with("--source-commit="):
			source_commit = arg.trim_prefix("--source-commit=")
		else:
			_fail("Unknown option: " + arg)
			return
	if output.is_empty() or FileAccess.file_exists(output) or source_commit.length() != 40 or not source_commit.is_valid_hex_number():
		_fail("Supply a new --output and the snapshot --source-commit")
		return
	if DisplayServer.get_name() == "headless":
		_fail("Native renderer required for texture image inspection")
		return
	var collector: RefCounted = load(get_script().resource_path.get_base_dir().path_join("texture_runtime_inventory.gd")).new()
	var loader: Script = load("res://data/field_loader.gd")
	var loaded: Dictionary = loader.load_from()
	if not loaded.ok:
		_fail("Default field failed validation")
		return
	var cases: Array[Dictionary] = []
	var world: Script = load("res://render/world/world.gd")
	var scene := Node3D.new()
	scene.name = "DefaultDayWorld"
	# Build off-tree: no audio, particle processing or simulation is started.
	world.build(scene, loaded.field, Callable(), {time_of_day = false}, {}, {field_lighting = "club", campfire = false})
	cases.append({id = "default-day-world", inventory = collector.scan(scene)})
	scene.free()
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	var airplane: Script = load("res://render/airplane.gd")
	for family: String in catalog.airplane_visual_families():
		var built: Dictionary = airplane.build(family)
		if not built.get("root") is Node3D:
			_fail("Aircraft visual build failed: " + family)
			return
		var aircraft_root: Node3D = built.root
		cases.append({id = family, inventory = collector.scan(aircraft_root)})
		aircraft_root.free()
	var report := {
		schema_version = 1, source_commit = source_commit,
		source_identity_note = "Caller-supplied commit; verify archive and imported-input hashes separately",
		engine = Engine.get_version_info(), renderer = RenderingServer.get_current_rendering_method(),
		adapter = RenderingServer.get_video_adapter_name(), cases = cases,
		build_options = {
			field = loaded.field.id,
			scenery = load("res://scenery/scenery.gd").options(),
			landscape_upgrade = load("res://render/landscape_upgrade/options.gd").enabled(),
			night_options = {field_lighting = "club", campfire = false},
		},
		scope = {
			read_only = true, assigned_resources_not_effective_draws = true,
			image_bytes_are_cpu_readback_not_vram = true, resource_ids_are_case_local = true,
			build_mode = "off-tree, default fixed daylight world and fixed-wing visual families",
			exclusions = ["Home/UI", "aircraft night kit", "conditional weather", "flight-only effects",
				"rotorcraft/ground vehicles", "GPU residency", "pixel/color/provenance qualification",
				"sampler arrays and shader-global textures", "containers deeper than eight levels"],
			filter_note = "BaseMaterial3D filter enums recorded; shader hints remain in the static inventory",
			readback_note = "One complete CPU image at a time; no per-image allocation cap",
			disabled_effects_note = "Persistent campfire and club-lighting resources are included even when disabled",
		},
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Cannot create output")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("TEXTURE_RUNTIME_INVENTORY_OK cases=", cases.size())
	_finish.call_deferred()


func _finish() -> void:
	# Let local builder references and queued render-resource deletions retire.
	await process_frame
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(2)
