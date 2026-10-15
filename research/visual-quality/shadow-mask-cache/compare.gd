extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var directory := ""
	var output := ""
	var reverse := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--directory="): directory = arg.trim_prefix("--directory=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--reverse": reverse = true
	if directory.is_empty() or output.is_empty() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	var scripts := {reference = load(directory.path_join("reference.gd")), candidate = load(directory.path_join("candidate.gd"))}
	var samples := []
	var failures := []
	for workload: String in ["silhouette", "create"]:
		for pair in range(10):
			var signatures := {}
			for variant: String in (["reference", "candidate"] if (pair % 2 == 0) != reverse else ["candidate", "reference"]):
				var host := Node3D.new()
				var begin := Time.get_ticks_usec()
				var result: Variant = scripts[variant].silhouette() if workload == "silhouette" else scripts[variant].create(host)
				samples.append({workload = workload, pair = pair, variant = variant, usec = Time.get_ticks_usec() - begin})
				if workload == "silhouette":
					signatures[variant] = _image_signature(result)
				else:
					var material: StandardMaterial3D = result.material_override
					signatures[variant] = {image = _image_signature(material.albedo_texture.get_image()),
						arrays = result.mesh.surface_get_arrays(0), transform = result.transform, shadow = result.cast_shadow,
						shading = material.shading_mode, transparency = material.transparency, color = material.albedo_color, cull = material.cull_mode}
				host.free()
			if var_to_bytes(signatures.reference) != var_to_bytes(signatures.candidate): failures.append(workload + ":" + str(pair))
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({complete = failures.is_empty(), failures = failures, exact_pairs = 20, samples = samples,
		engine = Engine.get_version_info(), adapter = RenderingServer.get_video_adapter_name(),
		scope = "native construction; parity/readback outside timing; first calls retained separately; shared host, not startup or FPS"}, "\t"))
	file.close()
	print("shadow blur: 20 exact image/carrier pairs; failures=", failures)
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _image_signature(img: Image) -> Array:
	return [img.get_size(), img.get_format(), img.has_mipmaps(), img.get_mipmap_count(), img.get_data()]
