extends RefCounted
## Captures one model file and admits it as an `InspectedSource` (AC-07).
##
## The file is size-checked, read once into an immutable buffer and hashed. The format is chosen
## from the captured content, never from the file extension. Everything here is pure data with no
## scene-tree access, so `inspect_bytes` may run on a worker thread. Admission means only that the
## bytes are a supported, bounded model: it implies nothing about aircraft physics.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const StlReader := preload("res://workshop/creator/stl_reader.gd")
const GlbPreflight := preload("res://workshop/creator/glb_preflight.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")

const STEP := "import"
## File-dialog filters for the formats this importer admits.
const FILE_FILTERS: PackedStringArray = ["*.stl ; STL model", "*.glb ; Self-contained GLB model"]
const _GLB_MAGIC: PackedByteArray = [0x67, 0x6C, 0x54, 0x46]
const _IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "bmp", "gif", "tga", "svg"]
const _OTHER_MODEL_EXTENSIONS: PackedStringArray = ["gltf", "obj", "fbx", "blend", "dae", "3mf", "ply", "step", "stp", "iges", "igs"]


static func capture_and_inspect(path: String) -> Dictionary:
	var captured: Dictionary = read_bounded(path)
	if not captured.ok:
		return captured
	return inspect_bytes(captured.value, path.get_file())


## Reads a player-chosen file once. The length is checked before the content is read.
static func read_bounded(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return R.fail(R.SOURCE_MISSING, "The file \"%s\" cannot be opened.", "source", STEP, [path.get_file()])
	var length: int = file.get_length()
	if length <= 0:
		return R.fail(R.SOURCE_INVALID, "The file \"%s\" is empty.", "source", STEP, [path.get_file()])
	if length > Limits.MODEL_SOURCE_BYTES:
		return R.fail(R.SOURCE_LIMIT, "The file \"%s\" is larger than the %s MiB model limit. Reduce its detail and export it again.",
			"source", STEP, [path.get_file(), str(Limits.MODEL_SOURCE_BYTES / Limits.MIB)])
	var bytes: PackedByteArray = file.get_buffer(length)
	if bytes.size() != length or file.get_error() != OK:
		return R.fail(R.SOURCE_INVALID, "The file \"%s\" could not be read completely.", "source", STEP, [path.get_file()])
	return R.ok(bytes)


## Admits already captured bytes. `file_name` is a display label and a hint for messages only.
static func inspect_bytes(bytes: PackedByteArray, file_name: String) -> Dictionary:
	if bytes.is_empty():
		return R.fail(R.SOURCE_INVALID, "The file \"%s\" is empty.", "source", STEP, [file_name])
	if bytes.size() > Limits.MODEL_SOURCE_BYTES:
		return R.fail(R.SOURCE_LIMIT, "The file \"%s\" is larger than the %s MiB model limit. Reduce its detail and export it again.",
			"source", STEP, [file_name, str(Limits.MODEL_SOURCE_BYTES / Limits.MIB)])
	var extension := file_name.get_extension().to_lower()
	if extension in _IMAGE_EXTENSIONS:
		return R.fail(R.SOURCE_UNSUPPORTED, "\"%s\" is a picture, not a 3D model. Export the model as STL or as a self-contained GLB.",
			"source", STEP, [file_name])
	var fields := {bytes = bytes, sha256 = CreatorBytes.sha256(bytes), file_name = file_name}
	var notes: Array = []
	if bytes.size() >= 4 and bytes.slice(0, 4) == _GLB_MAGIC:
		var glb: Dictionary = GlbPreflight.inspect(bytes)
		if not glb.ok:
			return _located(glb)
		var info: Dictionary = glb.value
		fields.format = InspectedSource.FORMAT_GLB
		fields.triangles = int(info.counts.triangles)
		fields.bounds_min = info.bounds_min
		fields.bounds_max = info.bounds_max
		fields.details = info
		notes = glb.diagnostics
	else:
		var stl: Dictionary = StlReader.read(bytes)
		if not stl.ok:
			if extension in _OTHER_MODEL_EXTENSIONS:
				return R.fail(R.SOURCE_UNSUPPORTED, "\"%s\" is not a supported model format. Export the model as STL or as a self-contained GLB.",
					"source", STEP, [file_name])
			return _located(stl)
		var mesh: Dictionary = stl.value
		fields.format = str(mesh.format)
		fields.triangles = int(mesh.triangle_count)
		fields.bounds_min = mesh.bounds_min
		fields.bounds_max = mesh.bounds_max
		fields.positions = mesh.positions
		fields.details = {name = str(mesh.name), dropped_degenerate = int(mesh.dropped_degenerate),
			inconsistent_normals = int(mesh.inconsistent_normals), nonzero_attributes = int(mesh.nonzero_attributes)}
		notes = stl.diagnostics
	for axis: int in 3:
		if not (fields.bounds_max[axis] > fields.bounds_min[axis]):
			return R.fail(R.SOURCE_INVALID, "The model in \"%s\" is flat or empty along one axis.", "source", STEP, [file_name])
	fields.notes = _stamped(notes)
	var source := InspectedSource.new()
	source.adopt(fields)
	return R.ok(source, fields.notes)


## Reader diagnostics do not know the wizard: attach its step and field so the UI can route them.
static func _located(result: Dictionary) -> Dictionary:
	return R.fail_all(_stamped(result.get("diagnostics", [])))


static func _stamped(diagnostics: Array) -> Array:
	var stamped: Array = []
	for entry: Variant in diagnostics:
		if entry is Dictionary:
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			if str(copy.get("step", "")).is_empty():
				copy["step"] = STEP
			if str(copy.get("field", "")).is_empty():
				copy["field"] = "source"
			stamped.append(copy)
	return stamped
