extends SceneTree
## Read-only audit of locally downloaded packages through the production adapter.
const Package := preload("res://workshop/creator/clearview/package.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Supply corpus directory and report path.")
		quit(2)
		return
	var rows: Array = []
	var archives: Array = []
	var names := DirAccess.get_files_at(args[0])
	names.sort()
	for name: String in names:
		if not name.ends_with(".zip"):
			continue
		var path := args[0].path_join(name)
		var captured: Dictionary = Package.capture(path)
		var archive := {file = name, sha256 = Bytes.sha256(FileAccess.get_file_as_bytes(path)), ok = captured.ok}
		if not captured.ok:
			archive.diagnostics = captured.diagnostics
			archives.append(archive)
			continue
		archive.models = captured.value.models().size()
		archives.append(archive)
		for model: Dictionary in captured.value.models():
			var result: Dictionary = Converter.convert(captured.value, model.root)
			var row := {archive = name, model_root = model.root, ok = result.ok, diagnostics = result.diagnostics}
			if result.ok:
				row.source_sha256 = result.value.source.sha256()
				row.triangles = result.value.source.triangle_count()
				row.physics_imported = result.value.receipt.physics_imported
				row.members = result.value.receipt.members
				row.coordinate_frames = result.value.receipt.coordinate_frames
			rows.append(row)
			print("AUDIT_CORPUS_MODEL: ", JSON.stringify({archive = name, root = model.root, ok = result.ok}))
	var report := {base_commit = "2a3cf04dbbdaf486b9c9c8e983463d828f90c64a", engine = Engine.get_version_info(), platform = OS.get_name(),
		archives = archives, models = rows, converted = rows.filter(func(row: Dictionary) -> bool: return row.ok).size()}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		printerr("Cannot write audit report.")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"  ",true,true)+"\n")
	file.close()
	print("AUDIT_CORPUS_COMPLETE: %d models; %d converted; %d refused" % [rows.size(),report.converted,rows.size()-report.converted])
	quit(0)
