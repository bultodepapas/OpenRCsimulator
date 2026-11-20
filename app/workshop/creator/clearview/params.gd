extends RefCounted
## Structural v5/v6 parameter observations only. Never constructs OpenRC physical data.
const R := preload("res://workshop/creator/result.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const Archive := preload("archive.gd")
const MAX_BYTES := 1024 * 1024
const MAX_LINES := 8192
const MAX_LINE := 4096
const MAX_RECORDS := 4096
const MAX_SECTIONS := 256
const IDENTITY := ["verNumber", "modelType", "modelName"]
const DEFAULT_MODEL := "body.ac"
const MODEL_DEFAULTED := "This model does not name its render file; the ClearView default body.ac is used."

static func read(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return R.fail(R.SOURCE_LIMIT, "The model parameter file is empty or too large.", "source", "import")
	for value: int in bytes:
		if (value < 32 and value not in [9, 10, 13]) or value > 126:
			return _invalid("Use an ASCII ClearView parameter file without control characters.")
	var text := bytes.get_string_from_ascii().replace("\r\n", "\n")
	if "\r" in text:
		return _invalid("The model parameter file has unsupported line endings.")
	var lines := text.split("\n", true)
	if lines.size() > MAX_LINES:
		return R.fail(R.SOURCE_LIMIT, "The model parameter file contains too many lines.", "source", "import")
	var records: Array = []
	var sections: Array[String] = []
	var section := ""
	var sectioned := false
	var flat := false
	var identities := {}
	for index: int in lines.size():
		if lines[index].length() > MAX_LINE:
			return R.fail(R.SOURCE_LIMIT, "A model parameter line is too long.", "source", "import")
		var line := lines[index].strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("#"):
			var marker := line.replace("\t", " ").split(" ", false)
			if marker.size() != 2 or marker[0] not in ["#begin", "#end"] or not _identifier(marker[1]):
				return _invalid("The model parameter file contains an unsupported section marker.")
			sectioned = true
			if marker[0] == "#begin":
				if not section.is_empty() or marker[1] in sections or sections.size() >= MAX_SECTIONS:
					return _invalid("The model parameter sections are nested, repeated or exceed the limit.")
				section = marker[1]
				sections.append(section)
			else:
				if section.is_empty() or section != marker[1]:
					return _invalid("The model parameter section endings do not match.")
				section = ""
			continue
		var split := -1
		for at: int in line.length():
			if line[at] in [" ", "\t"]:
				split = at
				break
		if split < 1 or not _identifier(line.left(split)) or records.size() >= MAX_RECORDS:
			return _invalid("The model parameter file contains an invalid field or too many records.")
		var key := line.left(split)
		var raw := line.substr(split).strip_edges()
		if raw.is_empty():
			return _invalid("A model parameter field has no value.")
		if section.is_empty():
			flat = true
		records.append({section = section, key = key, raw_rhs = raw, line = index + 1})
		for name: String in IDENTITY:
			if key.to_lower() == name.to_lower() and key != name:
				return _invalid("A model identity key has ambiguous letter case.")
		if key in IDENTITY and (section.is_empty() or section == "params"):
			var value := _without_comment(raw)
			if identities.has(key) and identities[key] != value:
				return _invalid("The model parameter file contains conflicting identity values.")
			identities[key] = value
	if not section.is_empty() or (sectioned and (flat or "params" not in sections)):
		return _invalid("The model parameter sections are incomplete or mixed with flat fields.")
	# Old flat dialects (v0-v4, mostly helicopters) may omit modelName: ClearView then renders the
	# conventional data/body.ac. The default is applied only there and reported as a note.
	var defaulted := false
	if not sectioned and identities.has("verNumber") and identities.has("modelType") and not identities.has("modelName") 			and _integer_identity(identities.verNumber) in [0, 1, 2, 3, 4]:
		identities["modelName"] = DEFAULT_MODEL
		defaulted = true
	for key: String in IDENTITY:
		if not identities.has(key):
			return _invalid("The model parameters must declare verNumber, modelType and modelName.")
	var version := _integer_identity(identities.verNumber)
	var model_type := _integer_identity(identities.modelType)
	if (version <= 5 and sectioned) or (version == 6 and not sectioned) or version < 0 or version > 6:
		return R.fail(R.SOURCE_UNSUPPORTED, "Only flat ClearView v0 to v5 and sectioned v6 model parameters are supported.", "source", "import")
	if model_type not in [0, 1]:
		return R.fail(R.SOURCE_UNSUPPORTED, "The ClearView model type is unsupported.", "source", "import")
	var model_name: String = identities.modelName
	if model_name.begins_with("\"") and model_name.ends_with("\"") and model_name.length() >= 2:
		model_name = model_name.substr(1, model_name.length() - 2)
	if not Archive.safe_name(model_name, false) or "/" in model_name or model_name.get_extension().to_lower() != "ac":
		return _invalid("The modelName parameter must be a safe AC3D filename.")
	var note := R.diagnostic(R.UNSUPPORTED_CAPABILITY,
		"Only the ClearView appearance is imported. Define and validate its OpenRC flight configuration separately.",
		"source", "import", [], R.SEVERITY_WARNING)
	return R.ok({version = version, model_type = model_type, model_name = model_name, records = records,
		sections = sections, sha256 = CreatorBytes.sha256(bytes)},
		[note, R.diagnostic(R.SOURCE_UNSUPPORTED, MODEL_DEFAULTED, "source", "import", [], R.SEVERITY_INFO)] if defaulted else [note])

static func _identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for at: int in value.length():
		var c := value.unicode_at(at)
		if not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c in [95, 46, 45]):
			return false
	return true

static func _without_comment(value: String) -> String:
	for at: int in range(1, value.length() - 1):
		if value.substr(at, 2) == "//" and value[at - 1] in [" ", "\t"]:
			return value.left(at).strip_edges()
	return value

static func _integer_identity(value: String) -> int:
	if value.begins_with("+"):
		value = value.substr(1)
	var parts := value.split(".", true)
	if parts.size() > 2 or parts[0].is_empty() or parts[0].length() > 8:
		return -1
	for c: int in parts[0].to_ascii_buffer():
		if c < 48 or c > 57:
			return -1
	if parts.size() == 2:
		if parts[1].is_empty():
			return -1
		for c: int in parts[1].to_ascii_buffer():
			if c != 48:
				return -1
	return parts[0].to_int()

static func _invalid(message: String) -> Dictionary:
	return R.fail(R.SOURCE_INVALID, message, "source", "import")
