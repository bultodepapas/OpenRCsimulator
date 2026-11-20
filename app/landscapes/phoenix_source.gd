extends RefCounted
## Discovery and bounded reads for player-selected Phoenix scenery sources.
## The returned positions retain their source coordinates and class codes.
## Their semantics require independent validation before use in flight.

const Archive := preload("res://workshop/creator/clearview/archive.gd")
const Objects := preload("res://landscapes/phoenix_objects.gd")
const Zip64 := preload("res://landscapes/phoenix_zip64.gd")
const MAX_DESCRIPTOR := 32 * 1024 * 1024
const MAX_MEMBER := 32 * 1024 * 1024
const MAX_ENTRIES := 20000
const MAX_DEPTH := 16
const MAX_POSITIONS := 4096
const SITE_MAGIC := "PHOENIXCREATOR FLYING SITE"
const INFINITY_MAGIC := "PHOENIX_INFINITYSCAPE_SITE"


## site.panels contains six member names from one complete tier, or is empty.
## Loose members are absolute paths; archive members use ZIP-relative paths.
static func scan(path: String, cancel := Callable()) -> Dictionary:
	if _cancelled(cancel):
		return {sites = [], error = "The scan was cancelled."}
	var source := ProjectSettings.globalize_path(path).simplify_path()
	if source.to_lower().ends_with(".zip") and FileAccess.file_exists(source):
		return _scan_zip(source, cancel)
	var root := source
	var selected := ""
	var defaults := ""
	if FileAccess.file_exists(source):
		root = source.get_base_dir()
		selected = source
	elif not DirAccess.dir_exists_absolute(source):
		return {sites = [], error = "The selected source could not be opened."}
	elif DirAccess.dir_exists_absolute(source.path_join("resources/environments")):
		root = source.path_join("resources/environments")
		defaults = source.path_join("resources/defaults/InfinityScape sites")
	var index := {}
	var counter := [0]
	var result := _index_folder(root, 0, index, counter, cancel)
	if not result.is_empty():
		return {sites = [], error = result}
	if not defaults.is_empty() and DirAccess.dir_exists_absolute(defaults):
		result = _index_folder(defaults, 0, index, counter, cancel)
		if not result.is_empty():
			return {sites = [], error = result}
	if not selected.is_empty():
		var matches := _lookup(index, selected)
		if matches.size() != 1:
			return {sites = [], error = "The selected descriptor is missing or its name is ambiguous."}
		selected = matches[0]
	var descriptors: Array[String] = []
	for names: Array in index.values():
		for name: String in names:
			if name.get_extension().to_lower() in ["pxf", "pxi"] and (selected.is_empty() or name == selected):
				descriptors.append(name)
	descriptors.sort()
	var sites: Array = []
	for descriptor: String in descriptors:
		if _cancelled(cancel):
			return {sites = [], error = "The scan was cancelled."}
		var data := _read_file(descriptor, MAX_DESCRIPTOR, cancel)
		var site := _site(data, source, descriptor, null, index)
		sites.append(site)
	return {sites = sites, error = "" if not sites.is_empty() else "No Phoenix scenery descriptors were found."}


static func _scan_zip(source: String, cancel: Callable) -> Dictionary:
	# Large collections and ZIP64 use the seek-based reader and lazy rows.
	var zip_file := FileAccess.open(source, FileAccess.READ)
	if zip_file == null:
		return {sites = [], error = "The selected source could not be opened."}
	var streaming := zip_file.get_length() > 64 * 1024 * 1024
	zip_file.close()
	var captured: Dictionary = Zip64.capture(source, cancel) if streaming else Archive.capture(source, cancel)
	if not captured.ok and not streaming and not _cancelled(cancel):
		captured = Zip64.capture(source, cancel)
		streaming = captured.ok
	if not captured.ok:
		if _cancelled(cancel):
			return {sites = [], error = "The scan was cancelled."}
		return {sites = [], error = "The ZIP is invalid or exceeds the supported archive limits."}
	var archive = captured.value
	var index := {}
	var descriptors: Array[String] = []
	for name: String in archive.names():
		if name.ends_with("/"):
			continue
		_add_index(index, name)
		if name.get_extension().to_lower() in ["pxf", "pxi"]:
			descriptors.append(name)
	descriptors.sort()
	var sites: Array = []
	for descriptor: String in descriptors:
		if _cancelled(cancel):
			return {sites = [], error = "The scan was cancelled."}
		if streaming:
			sites.append({
				"title": descriptor.get_file().get_basename(),
				"source": source,
				"descriptor": descriptor,
				"kind": "infinityscape" if descriptor.get_extension().to_lower() == "pxi" else "panorama",
				"panels": [],
				"positions": [],
				"error": "",
				"_archive": archive,
				"_index": index,
				"_pending": true,
				"_members": [descriptor],
			})
			continue
		var read: Dictionary = archive.read_member(descriptor, MAX_DESCRIPTOR, cancel)
		var data := PackedByteArray()
		if read.ok:
			data = read.value
		sites.append(_site(data, source, descriptor, archive, index))
	return {sites = sites, error = "" if not sites.is_empty() else "No Phoenix scenery descriptors were found."}


## Expand one inventory row only when the player selects it.
static func resolve_site(site: Dictionary, cancel := Callable()) -> Dictionary:
	if not bool(site.get("_pending", false)):
		return site
	if _cancelled(cancel):
		var cancelled := site.duplicate()
		cancelled.error = "The scan was cancelled."
		return cancelled
	var archive = site.get("_archive")
	var read: Dictionary = archive.read_member(str(site.descriptor), MAX_DESCRIPTOR, cancel)
	if not read.ok:
		var failed := site.duplicate()
		failed.error = "The scenery descriptor could not be read."
		return failed
	return _site(read.value, str(site.source), str(site.descriptor), archive, site._index)


## The member must have been resolved during discovery for this site.
## An empty result means that the member is unavailable or exceeds the limit.
static func read_member(site: Dictionary, member: String, limit: int, cancel := Callable()) -> PackedByteArray:
	if _cancelled(cancel) or limit <= 0 or not (site.get("_members", []) as Array).has(member):
		return PackedByteArray()
	var archive = site.get("_archive")
	if archive != null:
		var result: Dictionary = archive.read_member(member, mini(limit, MAX_MEMBER), cancel)
		return result.value if result.ok else PackedByteArray()
	if _is_link(member) or _is_link(member.get_base_dir()):
		return PackedByteArray()
	return _read_file(member, mini(limit, MAX_MEMBER), cancel)


static func _site(data: PackedByteArray, source: String, descriptor: String, archive: Variant, index: Dictionary) -> Dictionary:
	var site := {
		"title": descriptor.get_file().get_basename(),
		"source": source,
		"descriptor": descriptor,
		"kind": "unknown",
		"panels": [],
		"high_panels": [],
		"positions": [],
		"error": "",
		"_archive": archive,
		"_members": [descriptor],
	}
	if data.is_empty():
		site.error = "The descriptor could not be read or exceeds its size limit."
		return site
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(data)
	site.descriptor_hash = digest.finish().hex_encode()
	site.descriptor_sha256 = site.descriptor_hash
	site.descriptor_size = data.size()
	if _starts_with(data, INFINITY_MAGIC):
		site.kind = "infinityscape"
		if data.size() < 580:
			site.error = "The InfinityScape descriptor is truncated."
			return site
		var preset_title: Variant = _text(data, 36, 256)
		if preset_title == null or str(preset_title).is_empty():
			site.error = "The InfinityScape title is invalid."
			return site
		site.title = preset_title
		site.description = _text(data, 292, 256)
		site.error = "InfinityScape terrain generation is not yet supported."
		return site
	if not _starts_with(data, SITE_MAGIC):
		site.error = "The file is not a recognized Phoenix scenery descriptor."
		return site
	site.kind = "panorama"
	if data.size() < 2485:
		site.error = "The site does not contain a complete panoramic descriptor."
		return site
	var profile := data.decode_u32(32)
	if profile < 1 or profile > 4:
		site.error = "This Phoenix scenery profile is not supported."
		return site
	site.profile = profile
	var title: Variant = _text(data, 36, 256)
	if title == null or str(title).is_empty():
		site.error = "The scenery title is invalid."
		return site
	site.title = title
	site.description = _text(data, 292, 256)
	var names: Array[String] = []
	for i: int in 6:
		var name = _text(data, 553 + 256 * i, 256)
		if name == null or not _safe_filename(str(name)):
			site.error = "The panorama contains an invalid panel filename."
			return site
		names.append(name)
	var count := data.decode_u32(2481)
	if count > MAX_POSITIONS or 2485 + 92 * count + 4 > data.size():
		site.error = "The position records are truncated or exceed the supported limit."
		return site
	var positions: Array = []
	for i: int in count:
		var offset := 2485 + 92 * i
		var label = _text(data, offset, 64)
		if label == null:
			site.error = "A position label is missing its terminator."
			return site
		var values: Array[float] = []
		for j: int in 6:
			var value := data.decode_float(offset + 68 + 4 * j)
			if not is_finite(value):
				site.error = "A position contains an invalid coordinate."
				return site
			values.append(value)
		positions.append({ordinal = i, label = label, source_class = data.decode_u32(offset + 64), values = values})
	site.positions = positions
	site.object_count = data.decode_u32(2485 + 92 * count)
	site.objects = Objects.inspect(data, 2485 + 92 * count, profile)
	var matrix: Array[float] = []
	for i: int in 16:
		var value := data.decode_float(2101 + 4 * i)
		if not is_finite(value):
			site.error = "The panorama transform is invalid."
			return site
		matrix.append(value)
	site.panorama_matrix = matrix
	var shift: Array[float] = []
	for i: int in 3:
		var value := data.decode_float(2089 + 4 * i)
		if not is_finite(value):
			site.error = "The panorama shift is invalid."
			return site
		shift.append(value)
	site.panorama_shift = shift
	var base := descriptor.get_base_dir()
	# High-resolution names are a verified stock naming convention.
	var high_names: Array[String] = []
	for name: String in names:
		var stem := name.get_basename()
		if stem.is_empty() or not stem.right(1).is_valid_int():
			high_names.clear()
			break
		high_names.append(stem.left(stem.length() - 1) + "#high" + stem.right(1) + "." + name.get_extension())
	var high: Array[String] = []
	if high_names.size() == 6:
		high = _resolve_in_directory(index, base.path_join("high"), high_names)
	if high.size() == 6:
		site.high_panels = high
		site._members.append_array(high)
	var resolved := _resolve_panels(index, base, names)
	if not resolved.error.is_empty():
		if high.size() != 6:
			site.error = resolved.error
			return site
		site.panels = high
		site.tier = "high"
	else:
		site.panels = resolved.panels
		site.tier = resolved.tier
	site._members.append_array(site.panels)
	var cube = _text(data, 2165, 256)
	if cube != null and _safe_filename(str(cube)):
		var cube_result := _lookup(index, base.path_join(str(cube)))
		if cube_result.size() == 1:
			site.cubemap = cube_result[0]
			site._members.append(cube_result[0])
	return site


static func _resolve_panels(index: Dictionary, base: String, names: Array[String]) -> Dictionary:
	for tier: String in ["medium", "", "high"]:
		var directory := base if tier.is_empty() else base.path_join(tier)
		var panels := _resolve_in_directory(index, directory, names)
		if panels.size() == 6:
			return {panels = panels, tier = "root" if tier.is_empty() else tier, error = ""}
	return {panels = [], error = "A complete set of six panorama panels was not found, or names are ambiguous."}


static func _resolve_in_directory(index: Dictionary, directory: String, names: Array[String]) -> Array[String]:
	var panels: Array[String] = []
	for name: String in names:
		var matches := _lookup(index, directory.path_join(name))
		if matches.size() != 1:
			return []
		panels.append(matches[0])
	var unique := {}
	for panel: String in panels:
		unique[panel] = true
	if unique.size() != 6:
		return []
	return panels


static func _lookup(index: Dictionary, path: String) -> Array:
	return index.get(path.replace("\\", "/").simplify_path().to_lower(), [])


static func _add_index(index: Dictionary, path: String) -> void:
	var key := path.replace("\\", "/").simplify_path().to_lower()
	if not index.has(key):
		index[key] = []
	index[key].append(path)


static func _index_folder(directory: String, depth: int, index: Dictionary, counter: Array, cancel: Callable) -> String:
	if depth > MAX_DEPTH:
		return "The selected folder exceeds the maximum directory depth."
	if _is_link(directory):
		return "The selected folder contains a linked directory."
	var dir := DirAccess.open(directory)
	if dir == null:
		return "A source folder could not be opened."
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if _cancelled(cancel):
			dir.list_dir_end()
			return "The scan was cancelled."
		counter[0] += 1
		if counter[0] > MAX_ENTRIES:
			dir.list_dir_end()
			return "The selected folder exceeds the entry limit."
		var item := directory.path_join(name)
		if dir.is_link(name):
			name = dir.get_next()
			continue
		if dir.current_is_dir():
			var error := _index_folder(item, depth + 1, index, counter, cancel)
			if not error.is_empty():
				dir.list_dir_end()
				return error
		else:
			_add_index(index, item)
		name = dir.get_next()
	dir.list_dir_end()
	return ""


static func _is_link(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path.get_file())


static func _cancelled(cancel: Callable) -> bool:
	return cancel.is_valid() and bool(cancel.call())


static func _read_file(path: String, limit: int, cancel := Callable()) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > limit:
		return PackedByteArray()
	var length := file.get_length()
	var data := PackedByteArray()
	while data.size() < length:
		if _cancelled(cancel):
			return PackedByteArray()
		var chunk := file.get_buffer(mini(1024 * 1024, length - data.size()))
		if chunk.is_empty():
			return PackedByteArray()
		data.append_array(chunk)
	return data


static func _starts_with(data: PackedByteArray, value: String) -> bool:
	var bytes := value.to_ascii_buffer()
	return data.size() >= bytes.size() and data.slice(0, bytes.size()) == bytes


static func _text(data: PackedByteArray, offset: int, length: int) -> Variant:
	if offset < 0 or offset + length > data.size():
		return null
	var result := ""
	var windows_chars := [0x20ac, 0x81, 0x201a, 0x192, 0x201e, 0x2026, 0x2020, 0x2021,
		0x2c6, 0x2030, 0x160, 0x2039, 0x152, 0x8d, 0x17d, 0x8f,
		0x90, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
		0x2dc, 0x2122, 0x161, 0x203a, 0x153, 0x9d, 0x17e, 0x178]
	for i: int in range(offset, offset + length):
		var value := int(data[i])
		if value == 0:
			return result
		result += String.chr(windows_chars[value - 0x80] if value >= 0x80 and value <= 0x9f else value)
	return null


static func _safe_filename(name: String) -> bool:
	return not name.is_empty() and name not in [".", ".."] and not ("/" in name or "\\" in name or ":" in name)
