extends "campaign.gd"
## Run against the retained pre-selector source, before the new-law campaign. No flights.
const Bytes := preload("res://workshop/creator/bytes.gd")


func _initialize() -> void:
	var directory: String = (get_script() as Script).resource_path.get_base_dir()
	Variants = load(directory.path_join("variants.gd"))
	var expected := {}
	for index: int in range(1,18):expected["C%02d" % index]=true
	var cases := {}
	for entry: Array in _cases():
		var id: String = entry[0]
		if not expected.has(id):continue
		var candidate: Dictionary = Compiler.compile_candidate(entry[2])
		if not candidate.ok:
			printerr("Historical case refused: ",id)
			quit(1)
			return
		cases[id] = {definition_sha256=candidate.value.definition_sha256(),record_sha256=candidate.value.raw_sha256()}
	if cases.size()!=17:
		quit(1)
		return
	var sources := {}
	for path: String in [directory.path_join("campaign.gd"),directory.path_join("variants.gd"),
		"res://workshop/creator/definition.gd","res://workshop/creator/compiler.gd",
		"res://workshop/creator/packages.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var encoded := Bytes.encode({format="openrc-ac12-legacy-case-map v1",
		engine=Engine.get_version_info().string,engine_sha256=FileAccess.get_sha256(OS.get_executable_path()),
		source_hashes=sources,cases=cases})
	var output := ProjectSettings.globalize_path("user://ac12-legacy-cases/expected.json")
	if not encoded.ok or FileAccess.file_exists(output) or DirAccess.make_dir_recursive_absolute(output.get_base_dir())!=OK:
		quit(1)
		return
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		quit(1)
		return
	file.store_buffer(encoded.value.bytes)
	file.close()
	if FileAccess.get_sha256(output)!=encoded.value.sha256:
		quit(1)
		return
	print("LEGACY_SERVO_CASES 17 cases, 0 failures")
	print("LEGACY_SERVO_CASES_PATH ",output)
	print("LEGACY_SERVO_CASES_SHA256 ",encoded.value.sha256)
	quit(0)
