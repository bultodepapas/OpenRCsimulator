extends "campaign.gd"
## No flights: freeze the 17 historical definitions and prove selector-only record changes.
const Bytes := preload("res://workshop/creator/bytes.gd")
const ServoLaw := preload("res://physics/slew_trajectory.gd")
const LEGACY_MAP := "res://tools/ac12_inputs/legacy-cases.json"


func _initialize() -> void:
	var directory: String = (get_script() as Script).resource_path.get_base_dir()
	var legacy := Bytes.decode(FileAccess.get_file_as_bytes(LEGACY_MAP))
	if not legacy.ok or typeof(legacy.value.data.get("format"))!=TYPE_STRING \
		or legacy.value.data.format!="openrc-ac12-legacy-case-map v1" or not legacy.value.data.get("cases") is Dictionary:
		printerr("Missing retained historical case map")
		quit(1)
		return
	Variants = load(directory.path_join("variants.gd"))
	var cases := {}
	var failures := 0
	for entry: Array in _cases():
		var id: String = entry[0]
		if id not in ["C01","C02","C03","C04","C05","C06","C07","C08","C09","C10","C11","C12","C13","C14","C15","C16","C17"]:
			continue
		var definition: Dictionary = entry[2]
		var original: Dictionary = Compiler.compile_candidate(definition)
		var selected := definition.duplicate(true)
		selected.format = Definition.SERVO_FORMAT
		selected.servo_integration = ServoLaw.LAW
		var candidate: Dictionary = Compiler.compile_candidate(selected)
		if not original.ok or not candidate.ok:
			failures += 1
			printerr("Case map refused: ",id)
			continue
		var previous: Variant = legacy.value.data.cases.get(id)
		if not previous is Dictionary or typeof(previous.get("definition_sha256"))!=TYPE_STRING \
			or typeof(previous.get("record_sha256"))!=TYPE_STRING \
			or previous.definition_sha256!=original.value.definition_sha256() or previous.record_sha256!=original.value.raw_sha256():
			failures += 1
			printerr("Historical case identity changed: ",id)
			continue
		var token := ",\"servo_integration\":"+JSON.stringify(ServoLaw.LAW)
		var text: String = candidate.value.raw_bytes().get_string_from_utf8()
		if text.count(token)!=1 or text.replace(token,"").to_utf8_buffer()!=original.value.raw_bytes():
			failures += 1
			printerr("Case map changed more than the physical selector: ",id)
			continue
		cases[id] = {legacy_definition_sha256=original.value.definition_sha256(),
			legacy_record_sha256=original.value.raw_sha256(),
			definition_sha256=candidate.value.definition_sha256(),record_sha256=candidate.value.raw_sha256()}
	if cases.size()!=17 or failures!=0:
		printerr("SERVO_ARRIVAL_CASES incomplete, ",failures," failures")
		quit(1)
		return
	var sources := {}
	for path: String in [directory.path_join("campaign.gd"),directory.path_join("variants.gd"),
		(get_script() as Script).resource_path,"res://workshop/creator/definition.gd",
		"res://workshop/creator/compiler.gd","res://workshop/creator/packages.gd",
		"res://data/creator/airframe-conventional-trainer-estimated-v1.json",
		"res://data/creator/power-electric-4s-800kv-apc12x6-estimated-v1.json"]:
		sources[path] = FileAccess.get_sha256(path)
	var encoded := Bytes.encode({format="openrc-ac12-servo-case-map v1",
		legacy_case_map_sha256=FileAccess.get_sha256(LEGACY_MAP),
		campaign_id="ac12-normalized-slew-arrivals-v1-20261116",servo_integration_law=ServoLaw.LAW,
		engine=Engine.get_version_info().string,engine_sha256=FileAccess.get_sha256(OS.get_executable_path()),
		source_hashes=sources,cases=cases})
	var output := ProjectSettings.globalize_path("user://ac12-arrival-cases/expected.json")
	if not encoded.ok or FileAccess.file_exists(output) or DirAccess.make_dir_recursive_absolute(output.get_base_dir())!=OK:
		printerr("Cannot retain fresh case map")
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
	print("SERVO_ARRIVAL_CASES 17 cases, 0 failures")
	print("SERVO_ARRIVAL_CASES_PATH ",output)
	print("SERVO_ARRIVAL_CASES_SHA256 ",encoded.value.sha256)
	quit(0)
