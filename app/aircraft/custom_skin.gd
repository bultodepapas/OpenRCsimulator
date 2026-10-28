# User-supplied paint only. The verified stock scene and its geometry remain authoritative.
extends RefCounted

const Registry := preload("res://aircraft/model_registry.gd")
const ModelManifest := preload("res://aircraft/model_manifest.gd")
const AIRCRAFT := "skywalker-x8"
const ROOT := "user://skins/"
const ARCHIVE_LIMIT := 32 * 1024 * 1024
const MANIFEST_LIMIT := 64 * 1024
const PNG_LIMIT := 16 * 1024 * 1024
const PIXEL_LIMIT := 4096 * 4096
const ENTRY_LIMIT := 10
const INSTALLED_LIMIT := 32
const DIRECTORY_SCAN_LIMIT := 128
const ID_PREFIX := "custom_"
const HASH_PREFIX_LENGTH := 24
const PNG_SIGNATURE := [137, 80, 78, 71, 13, 10, 26, 10]

static var _names_by_asset: Dictionary = {}
static var _temp_serial := 0
# Kept separate so the regression test can use a private user:// directory.
static var _root := ROOT


static func supports(aircraft_id: String) -> bool:
	return aircraft_id == AIRCRAFT


## The ID fits the existing livery preference contract; the stored file name uses a hyphen.
static func is_custom_id(value: String) -> bool:
	if not value.begins_with(ID_PREFIX) or value.length() != ID_PREFIX.length() + HASH_PREFIX_LENGTH:
		return false
	for character in value.substr(ID_PREFIX.length()):
		if not "0123456789abcdef".contains(character): return false
	return ModelManifest.is_livery_id(value)


## Validates an immutable snapshot before atomically publishing it in the user's skin directory.
static func import_file(path: String, aircraft_id: String) -> Dictionary:
	if not supports(aircraft_id): return _failure("Custom paint is not available for this aircraft.")
	if not path.to_lower().ends_with(".orskin"): return _failure("Choose an .orskin file.")
	var base := _base()
	if not base.ok: return base
	var snapshot := _read_snapshot(path)
	if not snapshot.ok: return snapshot
	var inspected := _inspect(snapshot.bytes, base)
	if not inspected.ok: return inspected
	var digest: String = inspected.sha256
	var id := ID_PREFIX + digest.substr(0, HASH_PREFIX_LENGTH)
	var directory := _root + aircraft_id
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK: return _failure("Could not create the custom paint directory.")
	var destination := _path_for(aircraft_id, id)
	if FileAccess.file_exists(destination):
		if FileAccess.get_sha256(destination) != digest:
			return _failure("A different custom paint already uses this identifier.")
		return {ok = true, errors = PackedStringArray(), id = id, label = inspected.manifest.label}
	var inventory := _inventory(aircraft_id)
	if not inventory.ok or inventory.files.size() >= INSTALLED_LIMIT or inventory.visited >= DIRECTORY_SCAN_LIMIT:
		return _failure("The custom paint directory is full; remove an installed paint before importing another.")
	_temp_serial += 1
	var temporary := directory + "/." + id + "-%d-%d.tmp" % [Time.get_ticks_usec(), _temp_serial]
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null: return _failure("Could not write custom paint.")
	output.store_buffer(snapshot.bytes)
	output.flush()
	var write_error := output.get_error()
	output.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _failure("Could not write the complete custom paint.")
	# Never deliberately replace an existing paint, even in the unlikely event of a hash-prefix collision.
	if FileAccess.file_exists(destination):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		if FileAccess.get_sha256(destination) != digest: return _failure("A different custom paint already uses this identifier.")
	else:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))
		if error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			return _failure("Could not save the custom paint.")
	return {ok = true, errors = PackedStringArray(), id = id, label = inspected.manifest.label}


## Return only installed paints which still validate against the current stock model.
static func choices(aircraft_id: String) -> Array:
	if not supports(aircraft_id): return []
	var inventory := _inventory(aircraft_id)
	if not inventory.ok: return []
	var base := _base()
	if not base.ok: return []
	var result := []
	for filename: String in inventory.files:
		if result.size() >= INSTALLED_LIMIT: break
		var id := ID_PREFIX + filename.trim_prefix("custom-").trim_suffix(".orskin")
		if not is_custom_id(id): continue
		var inspected := _load_id(aircraft_id, id, base, false)
		if inspected.ok: result.append({id = id, label = str(inspected.manifest.label)})
	return result


static func _inventory(aircraft_id: String) -> Dictionary:
	var directory := DirAccess.open(_root + aircraft_id)
	if directory == null: return {ok = true, files = [], visited = 0}
	var names: Array[String] = []
	directory.list_dir_begin()
	var file := directory.get_next()
	var visited := 0
	while not file.is_empty():
		visited += 1
		if visited > DIRECTORY_SCAN_LIMIT:
			directory.list_dir_end()
			return {ok = false, files = [], visited = visited}
		if not directory.current_is_dir() and file.begins_with("custom-") and file.ends_with(".orskin"):
			var id := ID_PREFIX + file.trim_prefix("custom-").trim_suffix(".orskin")
			if is_custom_id(id): names.append(file)
		file = directory.get_next()
	directory.list_dir_end()
	names.sort()
	return {ok = true, files = names, visited = visited}


## Called only on a separately constructed and registry-validated stock scene.
static func apply(aircraft_id: String, id: String, stock_sha256: String, root: Node3D) -> Dictionary:
	if not supports(aircraft_id) or not is_custom_id(id): return _failure("Unknown custom paint.")
	var base := _base()
	if not base.ok: return base
	if stock_sha256 != base.sha256 or str(root.get_meta("asset_sha256", "")) != base.sha256:
		return _failure("Custom paint requires the verified default aircraft model.")
	var inspected := _load_id(aircraft_id, id, base)
	if not inspected.ok: return inspected
	var records := {}
	for record: Dictionary in inspected.manifest.materials:
		records[record.name] = record
	var seen := {}
	var changes := []
	var copies := {}
	var textures := {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null: continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface)
			if material == null or not records.has(material.resource_name): continue
			if not material is StandardMaterial3D or mesh_node.material_override != null:
				return _failure("A target material is not a supported stock surface.")
			var name := material.resource_name
			seen[name] = true
			var key := material.get_instance_id()
			if not copies.has(key):
				var painted := material.duplicate() as StandardMaterial3D
				if painted == null: return _failure("Could not copy a stock material.")
				var record: Dictionary = records[name]
				var color: Array = record.base_color
				# glTF/Blender base-color factors are linear; Godot material colors are sRGB.
				painted.albedo_color = Color(float(color[0]), float(color[1]), float(color[2]), float(color[3])).linear_to_srgb()
				if float(color[3]) < 1.0: painted.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				if record.has("texture"):
					var texture_name := str(record.texture)
					if not textures.has(texture_name):
						textures[texture_name] = ImageTexture.create_from_image(inspected.images[texture_name])
					if textures[texture_name] == null: return _failure("Could not create a custom paint texture.")
					painted.albedo_texture = textures[texture_name]
				else:
					painted.albedo_texture = null
				copies[key] = painted
			changes.append({node = mesh_node, surface = surface, material = copies[key]})
	for name in records:
		if not seen.has(name): return _failure("A target material is missing from the verified stock model: " + str(name))
	# Commit only after all surfaces and textures have been prepared successfully.
	for change: Dictionary in changes:
		change.node.set_surface_override_material(change.surface, change.material)
	return {ok = true, errors = PackedStringArray(), id = id, label = str(inspected.manifest.label), sha256 = inspected.sha256}


static func _path_for(aircraft_id: String, id: String) -> String:
	return _root + aircraft_id + "/custom-" + id.substr(ID_PREFIX.length()) + ".orskin"


static func _base() -> Dictionary:
	var described: Dictionary = Registry.describe(AIRCRAFT)
	if not described.get("ok", false): return _failure("The stock aircraft model could not be verified.")
	var asset: Dictionary = described.manifest.get("asset", {})
	var sha := str(asset.get("sha256", ""))
	if asset.get("kind") != "imported_glb" or sha.is_empty(): return _failure("The stock aircraft asset is unavailable.")
	if not _names_by_asset.has(sha):
		var scene := load(str(asset.get("path", ""))) as PackedScene
		if scene == null: return _failure("The stock aircraft scene could not be loaded.")
		var instance := scene.instantiate()
		var names := {}
		for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null: continue
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface)
				if material is StandardMaterial3D and not material.resource_name.is_empty(): names[material.resource_name] = true
		instance.free()
		if names.is_empty(): return _failure("The stock aircraft has no paintable materials.")
		_names_by_asset[sha] = names
	return {ok = true, sha256 = sha, names = _names_by_asset[sha]}


static func _load_id(aircraft_id: String, id: String, base: Dictionary, decode_textures := true) -> Dictionary:
	if not is_custom_id(id): return _failure("Unknown custom paint.")
	var snapshot := _read_snapshot(_path_for(aircraft_id, id))
	if not snapshot.ok: return snapshot
	var inspected := _inspect(snapshot.bytes, base, decode_textures)
	if inspected.ok and not str(inspected.sha256).begins_with(id.substr(ID_PREFIX.length())):
		return _failure("The stored custom paint has changed.")
	return inspected


static func _read_snapshot(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure("Could not open the custom paint file.")
	var size := file.get_length()
	if size <= 0 or size > ARCHIVE_LIMIT:
		file.close()
		return _failure("Custom paint archive must be at most 32 MiB.")
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size: return _failure("Could not read the complete custom paint file.")
	return {ok = true, bytes = bytes}


static func _inspect(bytes: PackedByteArray, base: Dictionary, decode_textures := true) -> Dictionary:
	var directory := _zip_directory(bytes)
	if not directory.ok: return directory
	var temp := FileAccess.create_temp(FileAccess.WRITE_READ, "openrc-skin", "orskin")
	if temp == null: return _failure("Could not prepare the custom paint archive.")
	temp.store_buffer(bytes)
	temp.flush()
	if temp.get_error() != OK: return _failure("Could not prepare the custom paint archive.")
	var reader := ZIPReader.new()
	if reader.open(temp.get_path_absolute()) != OK: return _failure("Custom paint is not a readable ZIP archive.")
	var files := reader.get_files()
	if files.size() != directory.entries.size():
		reader.close()
		return _failure("ZIP directory does not match its entries.")
	for filename in files:
		if not directory.entries.has(filename):
			reader.close()
			return _failure("ZIP directory contains an unexpected entry.")
	var manifest_bytes := reader.read_file("manifest.json")
	if manifest_bytes.size() != int(directory.entries["manifest.json"].size):
		reader.close()
		return _failure("Could not read the complete paint manifest.")
	var source := manifest_bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != manifest_bytes or not _unique_json_keys(source):
		reader.close()
		return _failure("The paint manifest must be UTF-8 JSON without duplicate fields.")
	var manifest: Variant = JSON.parse_string(source)
	var validated := _validate_manifest(manifest, base, directory.entries)
	if not validated.ok:
		reader.close()
		return validated
	var images := {}
	var pixels := 0
	for filename: String in validated.textures:
		var png := reader.read_file(filename)
		if png.size() != int(directory.entries[filename].size):
			reader.close()
			return _failure("Could not read the complete PNG: " + filename)
		var dimensions := _png_dimensions(png)
		if dimensions == Vector2i.ZERO:
			reader.close()
			return _failure("Invalid PNG or image dimensions exceed 4096 pixels: " + filename)
		pixels += dimensions.x * dimensions.y
		if pixels > PIXEL_LIMIT:
			reader.close()
			return _failure("The combined custom paint textures exceed the pixel limit.")
		if decode_textures:
			var image := Image.new()
			if image.load_png_from_buffer(png) != OK or image.get_width() != dimensions.x or image.get_height() != dimensions.y:
				reader.close()
				return _failure("Could not decode PNG: " + filename)
			if image.generate_mipmaps() != OK:
				reader.close()
				return _failure("Could not prepare PNG mipmaps: " + filename)
			images[filename] = image
	reader.close()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return {ok = true, errors = PackedStringArray(), manifest = manifest, images = images, sha256 = hash.finish().hex_encode()}


static func _validate_manifest(value: Variant, base: Dictionary, entries: Dictionary) -> Dictionary:
	if not value is Dictionary or not _exact_fields(value, ["format", "version", "aircraft_id", "base_asset_sha256", "label", "materials"]):
		return _failure("The paint manifest has missing or unsupported fields.")
	if value.format != "openrc-skin" or typeof(value.version) not in [TYPE_INT, TYPE_FLOAT] or value.version != 1:
		return _failure("Unsupported custom paint format or version.")
	if value.aircraft_id != AIRCRAFT or value.base_asset_sha256 != base.sha256:
		return _failure("This paint is for a different aircraft or stock model version.")
	if not value.label is String or value.label.strip_edges().is_empty() or value.label.length() > 48:
		return _failure("Paint label must contain 1 to 48 printable characters.")
	for character in value.label:
		if character.unicode_at(0) < 32 or character.unicode_at(0) == 127:
			return _failure("Paint label must contain 1 to 48 printable characters.")
	if not value.materials is Array or value.materials.is_empty() or value.materials.size() > 9:
		return _failure("Paint must list between one and nine materials.")
	var names := {}
	var textures := {}
	for record: Variant in value.materials:
		if not record is Dictionary or not _exact_fields(record, ["name", "base_color"], ["texture"]):
			return _failure("Each material needs a name, base_color and optional PNG texture.")
		if not record.name is String or not base.names.has(record.name) or names.has(record.name):
			return _failure("Paint contains an unknown or duplicate material.")
		names[record.name] = true
		if not record.base_color is Array or record.base_color.size() != 4:
			return _failure("Each base color must contain four numbers from 0 to 1.")
		for component in record.base_color:
			if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)) or float(component) < 0.0 or float(component) > 1.0:
				return _failure("Each base color must contain four numbers from 0 to 1.")
		if record.has("texture"):
			if not record.texture is String or not _png_name(record.texture) or not entries.has(record.texture):
				return _failure("A material references a missing or unsafe PNG filename.")
			textures[record.texture] = true
	for filename in entries:
		if filename != "manifest.json" and not textures.has(filename): return _failure("The archive contains an unreferenced file.")
	return {ok = true, textures = textures.keys()}


static func _exact_fields(value: Dictionary, required: Array, optional: Array = []) -> bool:
	for key in required:
		if not value.has(key): return false
	for key in value:
		if not required.has(key) and not optional.has(key): return false
	return true


static func _png_name(name: String) -> bool:
	if name.is_empty() or name.length() > 96 or name.begins_with(".") or not name.ends_with(".png"): return false
	for character in name:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-".contains(character): return false
	return true


static func _png_dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 33: return Vector2i.ZERO
	for i in PNG_SIGNATURE.size():
		if bytes[i] != PNG_SIGNATURE[i]: return Vector2i.ZERO
	if _be32(bytes, 8) != 13 or bytes.slice(12, 16).get_string_from_ascii() != "IHDR": return Vector2i.ZERO
	var width := _be32(bytes, 16)
	var height := _be32(bytes, 20)
	if width < 1 or height < 1 or width > 4096 or height > 4096: return Vector2i.ZERO
	var depth := int(bytes[24])
	var color_type := int(bytes[25])
	var allowed_depths := {0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]}
	if not allowed_depths.has(color_type) or not allowed_depths[color_type].has(depth) or bytes[26] != 0 or bytes[27] != 0 or bytes[28] > 1:
		return Vector2i.ZERO
	# libpng can inflate compressed ancillary metadata independently of image dimensions.
	# Reject those metadata chunks, while accepting normal Blender/painting-tool PNGs.
	var offset := 8
	var saw_data := false
	var chunks := 0
	while offset + 12 <= bytes.size():
		chunks += 1
		if chunks > 65536: return Vector2i.ZERO
		var length := _be32(bytes, offset)
		if length < 0 or length > PNG_LIMIT or offset + 12 + length > bytes.size(): return Vector2i.ZERO
		var kind := bytes.slice(offset + 4, offset + 8).get_string_from_ascii()
		if kind in ["iCCP", "zTXt", "iTXt"]: return Vector2i.ZERO
		if offset != 8 and kind == "IHDR": return Vector2i.ZERO
		if kind == "IDAT": saw_data = true
		if kind == "IEND":
			if length != 0 or not saw_data or offset + 12 != bytes.size(): return Vector2i.ZERO
			return Vector2i(width, height)
		offset += 12 + length
	return Vector2i.ZERO


static func _be32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])


## JSON.parse_string accepts duplicate object fields. Scan the valid JSON token stream as well.
static func _unique_json_keys(source: String) -> bool:
	var stack := []
	var i := 0
	while i < source.length():
		var c := source.substr(i, 1)
		if c == '"':
			var start := i
			i += 1
			var closed := false
			while i < source.length():
				var current := source.substr(i, 1)
				if current == "\\":
					i += 2
					continue
				if current == '"':
					closed = true
					break
				i += 1
			if not closed: return false
			if not stack.is_empty() and stack.back().kind == "object" and stack.back().expect_key:
				var key: Variant = JSON.parse_string(source.substr(start, i - start + 1))
				if not key is String or stack.back().keys.has(key): return false
				stack.back().keys[key] = true
				stack.back().expect_key = false
		elif c == "{": stack.append({kind = "object", keys = {}, expect_key = true})
		elif c == "[": stack.append({kind = "array"})
		elif c == "}" or c == "]":
			if stack.is_empty(): return false
			stack.pop_back()
		elif c == "," and not stack.is_empty() and stack.back().kind == "object": stack.back().expect_key = true
		i += 1
	return stack.is_empty()


## Inspect central and local ZIP records before ZIPReader can allocate an entry. ZIP64,
## encryption, paths, overlapping entries, and oversized advertised outputs are refused.
static func _zip_directory(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 22: return _failure("Custom paint is not a complete ZIP archive.")
	var eocd := -1
	var start := maxi(0, bytes.size() - 65557)
	for offset in range(bytes.size() - 22, start - 1, -1):
		if bytes.decode_u32(offset) == 0x06054b50 and offset + 22 + bytes.decode_u16(offset + 20) == bytes.size():
			eocd = offset
			break
	if eocd < 0: return _failure("Custom paint is not a complete ZIP archive.")
	var count := bytes.decode_u16(eocd + 10)
	var central_size := bytes.decode_u32(eocd + 12)
	var central_offset := bytes.decode_u32(eocd + 16)
	if bytes.decode_u16(eocd + 4) != 0 or bytes.decode_u16(eocd + 6) != 0 or bytes.decode_u16(eocd + 8) != count \
			or count < 1 or count > ENTRY_LIMIT or central_offset + central_size != eocd:
		return _failure("Unsupported or oversized ZIP directory.")
	var position := central_offset
	var entries := {}
	var folded := {}
	var intervals := []
	var total := 0
	for ignored in count:
		if position + 46 > eocd or bytes.decode_u32(position) != 0x02014b50: return _failure("Invalid ZIP directory entry.")
		var flags := bytes.decode_u16(position + 8)
		var method := bytes.decode_u16(position + 10)
		var crc := bytes.decode_u32(position + 16)
		var compressed := bytes.decode_u32(position + 20)
		var size := bytes.decode_u32(position + 24)
		var name_length := bytes.decode_u16(position + 28)
		var extra_length := bytes.decode_u16(position + 30)
		var comment_length := bytes.decode_u16(position + 32)
		var local := bytes.decode_u32(position + 42)
		var next := position + 46 + name_length + extra_length + comment_length
		if next > eocd or name_length == 0 or name_length > 96 or (flags & ~0x080e) != 0 or method not in [0, 8] \
				or bytes.decode_u16(position + 34) != 0 or compressed > ARCHIVE_LIMIT or size > PNG_LIMIT \
				or (method == 0 and compressed != size) or not _safe_zip_extra(bytes, position + 46 + name_length, extra_length):
			return _failure("Unsupported or oversized ZIP entry.")
		var name_bytes := bytes.slice(position + 46, position + 46 + name_length)
		var name := name_bytes.get_string_from_ascii()
		if name.to_ascii_buffer() != name_bytes or (name != "manifest.json" and not _png_name(name)) or folded.has(name.to_lower()):
			return _failure("ZIP filenames must be unique root-level manifest or PNG files.")
		if name == "manifest.json" and size > MANIFEST_LIMIT: return _failure("Paint manifest exceeds 64 KiB.")
		if size == 0: return _failure("ZIP entries must not be empty.")
		folded[name.to_lower()] = true
		total += size
		if total > ARCHIVE_LIMIT: return _failure("The expanded paint archive exceeds 32 MiB.")
		if local + 30 > central_offset or bytes.decode_u32(local) != 0x04034b50: return _failure("Invalid local ZIP entry.")
		var local_name_length := bytes.decode_u16(local + 26)
		var local_extra := bytes.decode_u16(local + 28)
		var data_start := local + 30 + local_name_length + local_extra
		var end := data_start + compressed
		if data_start > central_offset or end > central_offset or bytes.decode_u16(local + 6) != flags or bytes.decode_u16(local + 8) != method \
				or local_name_length != name_length or bytes.slice(local + 30, local + 30 + local_name_length) != name_bytes \
				or not _safe_zip_extra(bytes, local + 30 + local_name_length, local_extra):
			return _failure("ZIP local and directory records do not match.")
		if (flags & 8) == 0:
			if bytes.decode_u32(local + 14) != crc or bytes.decode_u32(local + 18) != compressed or bytes.decode_u32(local + 22) != size:
				return _failure("ZIP local and directory sizes do not match.")
		else:
			if bytes.decode_u32(local + 14) not in [0, crc] or bytes.decode_u32(local + 18) not in [0, compressed] \
					or bytes.decode_u32(local + 22) not in [0, size]:
				return _failure("ZIP local and directory sizes do not match.")
			if end + 12 > central_offset: return _failure("Incomplete ZIP data descriptor.")
			if bytes.decode_u32(end) == 0x08074b50: end += 4
			if end + 12 > central_offset or bytes.decode_u32(end) != crc or bytes.decode_u32(end + 4) != compressed or bytes.decode_u32(end + 8) != size:
				return _failure("ZIP data descriptor does not match its directory.")
			end += 12
		for interval: Vector2i in intervals:
			if local < interval.y and end > interval.x: return _failure("Overlapping ZIP entries are not supported.")
		intervals.append(Vector2i(local, end))
		entries[name] = {size = size}
		position = next
	if position != eocd or not entries.has("manifest.json"): return _failure("ZIP must contain one manifest.json.")
	return {ok = true, entries = entries}


static func _safe_zip_extra(bytes: PackedByteArray, offset: int, length: int) -> bool:
	var end := offset + length
	if offset < 0 or end > bytes.size(): return false
	while offset < end:
		if offset + 4 > end: return false
		var tag := bytes.decode_u16(offset)
		var size := bytes.decode_u16(offset + 2)
		offset += 4
		if tag == 0x0001 or offset + size > end: return false
		offset += size
	return true


static func _failure(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}

