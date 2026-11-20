extends RefCounted
## Local panorama previews. A directory becomes visible only after all six faces are written.

const Source = preload("res://landscapes/phoenix_source.gd")
const Images = preload("res://landscapes/phoenix_images.gd")
const ROOT := "user://landscapes/phoenix"
const PANEL_EDGE := 1024
const PANEL_LIMIT := 64 * 1024 * 1024
const PNG_LIMIT := 5 * 1024 * 1024
const SCHEMA := 1
const ID_LENGTH := 64
const META_LIMIT := 16384
const STAGING_MAX_AGE_SECONDS := 24 * 60 * 60
const CALIBRATIONS := "res://landscapes/phoenix/"
static var _library_lock := Mutex.new()


static func prepare(site: Dictionary, cancelled: Callable) -> Dictionary:
	var resolved_on_demand := bool(site.get("_pending", false))
	site = Source.resolve_site(site, cancelled)
	if not str(site.get("error", "")).is_empty():
		return {error = site.error}
	var panels: Array = site.get("panels", [])
	if panels.size() != 6:
		return {error = "Six panorama panels are required."}
	var descriptor_hash := str(site.descriptor_sha256)
	if not resolved_on_demand:
		var descriptor := Source.read_member(site, str(site.descriptor), 32 * 1024 * 1024, cancelled)
		if cancelled.call():
			return {error = "Cancelled."}
		if descriptor.is_empty():
			return {error = "The scenery descriptor could not be read."}
		if _digest(descriptor) != descriptor_hash:
			return {error = "The scenery changed. Choose the source again."}
	var hashes: Array[String] = [descriptor_hash]
	var faces: Array[Image] = []
	for index in panels.size():
		if cancelled.call():
			return {error = "Cancelled."}
		var data := Source.read_member(site, str(panels[index]), PANEL_LIMIT, cancelled)
		if cancelled.call():
			return {error = "Cancelled."}
		if data.is_empty():
			return {error = "Panorama panel %d is missing or exceeds the import limit.", panel = index + 1}
		var image := Images.decode_panel(data, PANEL_EDGE, cancelled)
		if cancelled.call():
			return {error = "Cancelled."}
		if image == null or image.is_empty():
			return {error = "Panorama panel %d could not be decoded.", panel = index + 1}
		if image.is_compressed() and image.decompress() != OK:
			return {error = "Panorama panel %d could not be decoded.", panel = index + 1}
		if image.get_width() != image.get_height():
			return {error = "The panorama panel dimensions are invalid."}
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
		if not faces.is_empty() and image.get_size() != faces[0].get_size():
			return {error = "The panorama panels have different dimensions."}
		faces.append(image)
		hashes.append(_digest(data))
	var id := ("phoenix-preview-%d:" % SCHEMA + ":".join(hashes)).sha256_text()
	return {id = id, title = str(site.title), images = faces, panorama = _joins_match(faces), error = ""}


static func entries(library_root: String = ROOT) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var folder := DirAccess.open(library_root)
	if folder == null:
		return found
	folder.include_hidden = true
	_reap_staging(folder, library_root)
	for id in folder.get_directories():
		var metadata := _metadata(library_root, id)
		if not metadata.is_empty():
			found.append(metadata)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order := str(a.title).naturalnocasecmp_to(str(b.title))
		return order < 0 if order != 0 else str(a.id) < str(b.id))
	return found


static func load_preview(id: String, cancelled: Callable, library_root: String = ROOT) -> Dictionary:
	var metadata := _metadata(library_root, id)
	if metadata.is_empty():
		return {error = "This installed scenery is incomplete."}
	var edge := int(metadata.edge)
	var faces: Array[Image] = []
	for index in 6:
		if cancelled.call():
			return {error = "Cancelled."}
		var payload := _read(library_root.path_join(id).path_join(_face_name(index)), PNG_LIMIT)
		if not _is_preview_png(payload, edge) or _digest(payload) != metadata.faces[index]:
			return {error = "This installed scenery is incomplete."}
		var image := Image.new()
		if image.load_png_from_buffer(payload) != OK or image.get_size() != Vector2i(edge, edge):
			return {error = "This installed scenery is incomplete."}
		image.convert(Image.FORMAT_RGBA8)
		faces.append(image)
	return {id = id, title = metadata.title, images = faces, panorama = metadata.panorama,
		calibration = _calibration(metadata), error = ""}


## Lightweight admission for the catalog. load_preview() verifies every face again at launch.
static func flight_calibration(id: String, library_root: String = ROOT) -> Dictionary:
	return _calibration(_metadata(library_root, id))


static func _calibration(metadata: Dictionary) -> Dictionary:
	if not bool(metadata.get("panorama", false)):
		return {}
	var registry: Variant = JSON.parse_string(FileAccess.get_file_as_string(CALIBRATIONS + "calibrations.json"))
	if not registry is Dictionary or registry.get("version") != 1:
		return {}
	var profile: Dictionary = registry.calibrations.get(metadata.id, {})
	if profile.is_empty() or profile.faces != metadata.faces:
		return {}
	return {name = metadata.title, field_path = CALIBRATIONS + str(profile.field),
		yaw_deg = float(profile.yaw_deg), version = int(registry.version),
		surface_path = CALIBRATIONS + "asphalt-surfaces.json" if profile.surface == "paved" else ""}


static func install(preview: Dictionary, cancelled: Callable, library_root: String = ROOT) -> Dictionary:
	var id := str(preview.get("id", ""))
	if not _valid_id(id) or not preview.get("images", []) is Array or preview.images.size() != 6:
		return {error = "A complete preview is required."}
	if not _metadata(library_root, id).is_empty():
		var existing := load_preview(id, cancelled, library_root)
		if str(existing.error).is_empty() or cancelled.call():
			return {error = existing.error, id = id}
	var stage := _temporary_path(library_root, "stage")
	if DirAccess.make_dir_recursive_absolute(library_root) != OK or DirAccess.make_dir_absolute(stage) != OK:
		return {error = "The scenery library could not be opened for writing."}
	var result := _write_stage(stage, preview, cancelled)
	if result.is_empty():
		_library_lock.lock()
		result = _publish(stage, library_root, id, cancelled)
		_library_lock.unlock()
	_discard(stage)
	return {error = result, id = id}


static func remove(id: String, library_root: String = ROOT) -> bool:
	_library_lock.lock()
	var removed := _remove(id, library_root)
	_library_lock.unlock()
	return removed


static func _remove(id: String, library_root: String) -> bool:
	if _metadata(library_root, id).is_empty():
		return false
	var target := library_root.path_join(id)
	var retired := _temporary_path(library_root, "removed")
	if DirAccess.rename_absolute(target, retired) != OK:
		return false
	_discard(retired)
	return true


static func _publish(stage: String, library_root: String, id: String, cancelled: Callable) -> String:
	if cancelled.call():
		return "Cancelled."
	var directory := DirAccess.open(library_root)
	var target := library_root.path_join(id)
	var backup := ""
	var error := "The scenery library could not publish this import."
	if directory == null or directory.is_link(id):
		return error
	if directory.dir_exists(id):
		var existing := load_preview(id, cancelled, library_root)
		if cancelled.call():
			return "Cancelled."
		if str(existing.error).is_empty():
			return ""
		backup = stage + "-damaged"
		if DirAccess.rename_absolute(target, backup) != OK:
			return error
	if DirAccess.rename_absolute(stage, target) == OK:
		_discard(backup)
		return ""
	if not backup.is_empty():
		DirAccess.rename_absolute(backup, target)
	return error


static func _write_stage(stage: String, preview: Dictionary, cancelled: Callable) -> String:
	var hashes: Array[String] = []
	var first: Image = preview.images[0]
	var side := first.get_width()
	if side < 1 or side > PANEL_EDGE:
		return "The panorama panel dimensions are invalid."
	for index in 6:
		if cancelled.call():
			return "Cancelled."
		var image: Image = preview.images[index]
		if image.get_size() != Vector2i(side, side):
			return "The panorama panels have different dimensions."
		var png := image.save_png_to_buffer()
		if png.is_empty() or png.size() > PNG_LIMIT or not _write(stage.path_join(_face_name(index)), png):
			return "A panorama panel could not be saved. Check the available disk space."
		hashes.append(_digest(png))
	var metadata := {version = SCHEMA, id = preview.id, title = preview.title, edge = side,
		faces = hashes, panorama = bool(preview.get("panorama", false))}
	var encoded := JSON.stringify(metadata).to_utf8_buffer()
	if encoded.size() > META_LIMIT or not _write(stage.path_join("site.json"), encoded):
		return "The scenery metadata could not be saved."
	return ""


static func _metadata(library_root: String, id: String) -> Dictionary:
	if not _valid_id(id):
		return {}
	var path := library_root.path_join(id)
	var root_dir := DirAccess.open(library_root)
	if root_dir == null or root_dir.is_link(id):
		return {}
	var folder := DirAccess.open(path)
	if folder == null or folder.is_link("site.json"):
		return {}
	var raw := _read(path.path_join("site.json"), META_LIMIT)
	if raw.is_empty():
		return {}
	var parser := JSON.new()
	if parser.parse(raw.get_string_from_utf8()) != OK:
		return {}
	var value: Variant = parser.data
	if not value is Dictionary or value.get("version") != SCHEMA or value.get("id") != id \
			or not value.get("title") is String or not value.get("faces") is Array or not value.get("panorama") is bool:
		return {}
	var edge: Variant = value.get("edge")
	if not (edge is float or edge is int) or edge < 1 or edge > PANEL_EDGE or int(edge) != edge \
			or value.faces.size() != 6:
		return {}
	for index in 6:
		var name := _face_name(index)
		if not value.faces[index] is String or not _valid_id(value.faces[index]) \
				or folder.is_link(name) or not folder.file_exists(name):
			return {}
	return value


static func _read(path: String, limit: int) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > limit:
		return PackedByteArray()
	return file.get_buffer(file.get_length())


static func _write(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	return file.get_error() == OK


static func _digest(bytes: PackedByteArray) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return hasher.finish().hex_encode()


static func _valid_id(id: String) -> bool:
	return id.length() == ID_LENGTH and id.is_valid_hex_number(false)


static func _face_name(index: int) -> String:
	return "face-%d.png" % index


static func _temporary_path(library_root: String, purpose: String) -> String:
	return library_root.path_join(".%s-%d-%d-%d" % [
		purpose, int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()])


static func _reap_staging(folder: DirAccess, library_root: String) -> void:
	var cutoff := int(Time.get_unix_time_from_system()) - STAGING_MAX_AGE_SECONDS
	for name in folder.get_directories():
		var parts := name.trim_suffix("-damaged").split("-")
		if parts.size() != 4 or parts[0] not in [".stage", ".removed"] or folder.is_link(name):
			continue
		if not parts[1].is_valid_int() or not parts[2].is_valid_int() or not parts[3].is_valid_int():
			continue
		var created := int(parts[1])
		if created > 0 and created <= cutoff:
			_discard(library_root.path_join(name))


static func _is_preview_png(bytes: PackedByteArray, edge: int) -> bool:
	if bytes.size() < 33 or bytes.slice(0, 8).hex_encode() != "89504e470d0a1a0a" \
			or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return false
	return _u32_be(bytes, 16) == edge and _u32_be(bytes, 20) == edge


static func _u32_be(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]


## Screen out scrambled or differently projected panels. This check concerns local joins,
## so a positive result says nothing about the absolute bearing, eye or ground.
static func _joins_match(faces: Array[Image]) -> bool:
	if faces[0].get_width() < 16:
		return false
	# Each entry gives the edge (top, right, bottom, left) on the pole and traversal sign.
	const TOP := [Vector2i(2, 1), Vector2i(1, -1), Vector2i(0, -1), Vector2i(3, 1)]
	const BOTTOM := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, -1), Vector2i(3, -1)]
	var worst := 0.0
	var sum := 0.0
	for index in 4:
		var lateral := _edge_difference(faces[index], 1, faces[(index + 1) % 4], 3, 1)
		var top := _edge_difference(faces[index], 0, faces[4], TOP[index].x, TOP[index].y)
		var bottom := _edge_difference(faces[index], 2, faces[5], BOTTOM[index].x, BOTTOM[index].y)
		worst = maxf(worst, maxf(lateral, maxf(top, bottom)))
		sum += lateral + top + bottom
	return worst < 0.23 and sum / 12.0 < 0.08


static func _edge_difference(a: Image, edge_a: int, b: Image, edge_b: int, direction: int) -> float:
	const SAMPLE_COUNT := 128
	var end := a.get_width() - 1
	var sum := 0.0
	for index in SAMPLE_COUNT:
		var coordinate := roundi((index + 0.5) * end / SAMPLE_COUNT)
		var point_a := _edge_point(edge_a, coordinate, end)
		var point_b := _edge_point(edge_b, coordinate if direction == 1 else end - coordinate, end)
		var diff := a.get_pixelv(point_a) - b.get_pixelv(point_b)
		sum += absf(diff.r) + absf(diff.g) + absf(diff.b)
	return sum / (3 * SAMPLE_COUNT)


static func _edge_point(edge: int, coordinate: int, end: int) -> Vector2i:
	match edge:
		0: return Vector2i(coordinate, 0)
		1: return Vector2i(end, coordinate)
		2: return Vector2i(coordinate, end)
		_: return Vector2i(0, coordinate)


static func _discard(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	for index in 6:
		DirAccess.remove_absolute(path.path_join(_face_name(index)))
	DirAccess.remove_absolute(path.path_join("site.json"))
	DirAccess.remove_absolute(path)
