extends RefCounted
## Seek-based ZIP/ZIP64 index for scenery archives.
## Keeps only the central directory in memory. Member payloads are read on demand.

const R := preload("res://workshop/creator/result.gd")
const Archive := preload("res://workshop/creator/clearview/archive.gd")
const Deflate := preload("res://workshop/creator/clearview/deflate.gd")
const MAX_ENTRIES := 20000
const MAX_DIRECTORY := 16 * 1024 * 1024
const MAX_MEMBER := 32 * 1024 * 1024
const MAX_NAME := 1024
const CP437 := "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ "

var _path := ""
var _file_size := 0
var _directory_offset := 0
var _directory_size := 0
var _directory_sha := ""
var _entries := {}
var _names: Array[String] = []
var _label := ""


static func capture(path: String, cancel := Callable()) -> Dictionary:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return _fail("The ZIP cannot be opened.")
	var archive := new()
	archive._path = path
	archive._file_size = handle.get_length()
	archive._label = path.get_file()
	var result := archive._index(handle, cancel)
	if not result.ok:
		return result
	return R.ok(archive)


func label() -> String:
	return _label


func names() -> Array:
	return _names.duplicate()


func member_info(name: String) -> Dictionary:
	return (_entries.get(name, {}) as Dictionary).duplicate(true)


func read_member(name: String, ceiling := MAX_MEMBER, cancel := Callable()) -> Dictionary:
	if _cancelled(cancel):
		return _fail("The import was cancelled.")
	if not _entries.has(name):
		return _fail("The ZIP member is missing.")
	var entry: Dictionary = _entries[name]
	if entry.directory or entry.size < 1 or entry.size > mini(ceiling, MAX_MEMBER) or entry.compressed > MAX_MEMBER:
		return _fail("The ZIP member exceeds the permitted size.")
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null or file.get_length() != _file_size:
		return _fail("The ZIP changed or can no longer be opened.")
	file.seek(_directory_offset)
	var directory := file.get_buffer(_directory_size)
	if directory.size() != _directory_size or _hash(directory) != _directory_sha:
		return _fail("The ZIP directory changed after scanning.")
	var local: int = entry.local
	var end_limit: int = entry.end_limit
	if local < 0 or local > end_limit - 30:
		return _fail("The ZIP local header is outside the data region.")
	file.seek(local)
	var header := file.get_buffer(30)
	if header.size() != 30 or header.decode_u32(0) != 0x04034b50:
		return _fail("The ZIP local header is invalid.")
	var name_length := header.decode_u16(26)
	var extra_length := header.decode_u16(28)
	if local + 30 + name_length + extra_length > end_limit:
		return _fail("The ZIP local name is truncated.")
	var local_name := file.get_buffer(name_length)
	if local_name != entry.raw_name or header.decode_u16(6) != entry.flags or header.decode_u16(8) != entry.method:
		return _fail("The ZIP directory and local header disagree.")
	var data_offset := local + 30 + name_length + extra_length
	if entry.compressed > end_limit - data_offset:
		return _fail("The ZIP member exceeds the data region.")
	var extra := file.get_buffer(extra_length)
	if extra.size() != extra_length:
		return _fail("The ZIP local extra fields are truncated.")
	var local_crc := header.decode_u32(14)
	var local_compressed := header.decode_u32(18)
	var local_size := header.decode_u32(22)
	var local_fields := _extra(extra, local_name, local_size == 0xffffffff, local_compressed == 0xffffffff, false)
	if not local_fields.ok:
		return local_fields
	if local_size == 0xffffffff:
		local_size = local_fields.size
	if local_compressed == 0xffffffff:
		local_compressed = local_fields.compressed
	if entry.flags & 8:
		if local_crc not in [0, entry.crc] or local_compressed not in [0, entry.compressed] or local_size not in [0, entry.size]:
			return _fail("The ZIP data descriptor conflicts with the local header.")
	else:
		if local_crc != entry.crc or local_compressed != entry.compressed or local_size != entry.size:
			return _fail("The ZIP directory and local sizes disagree.")
	var compressed := file.get_buffer(entry.compressed)
	if compressed.size() != entry.compressed:
		return _fail("The ZIP member is truncated.")
	if entry.flags & 8:
		var remaining := end_limit - file.get_position()
		if remaining < 12:
			return _fail("The ZIP data descriptor is truncated.")
		var trailer := file.get_buffer(mini(16, remaining))
		var plain: bool = trailer.decode_u32(0) == entry.crc and trailer.decode_u32(4) == entry.compressed and trailer.decode_u32(8) == entry.size
		var signed: bool = trailer.size() >= 16 and trailer.decode_u32(0) == 0x08074b50 and trailer.decode_u32(4) == entry.crc and trailer.decode_u32(8) == entry.compressed and trailer.decode_u32(12) == entry.size
		if plain == signed:
			return _fail("The ZIP data descriptor is invalid or ambiguous.")
	if _cancelled(cancel):
		return _fail("The import was cancelled.")
	var decoded: Dictionary = R.ok(compressed) if entry.method == 0 else Deflate.decode(compressed, entry.size, cancel)
	if not decoded.ok:
		return decoded
	var bytes: PackedByteArray = decoded.value
	if bytes.size() != entry.size:
		return _fail("The ZIP member decoded to an unexpected size.")
	var checksum: Dictionary = Archive.crc32(bytes, cancel)
	if not checksum.ok or checksum.value != entry.crc:
		return _fail("The ZIP member failed its checksum.")
	return R.ok(bytes)


func _index(file: FileAccess, cancel: Callable) -> Dictionary:
	if _file_size < 22:
		return _fail("The ZIP is truncated.")
	var tail_size := mini(_file_size, 65557)
	file.seek(_file_size - tail_size)
	var tail := file.get_buffer(tail_size)
	var eocd := -1
	for at: int in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(at) == 0x06054b50 and at + 22 + tail.decode_u16(at + 20) == tail.size():
			eocd = at
			break
	if eocd < 0:
		return _fail("The ZIP end record is invalid.")
	if tail.decode_u16(eocd + 4) != 0 or tail.decode_u16(eocd + 6) != 0:
		return _fail("Split ZIP archives are not supported.")
	var count := tail.decode_u16(eocd + 10)
	var on_disk := tail.decode_u16(eocd + 8)
	var central_length := tail.decode_u32(eocd + 12)
	var central_offset := tail.decode_u32(eocd + 16)
	var eocd_absolute := _file_size - tail_size + eocd
	if count == 65535 or central_length == 0xffffffff or central_offset == 0xffffffff:
		if eocd_absolute < 20:
			return _fail("The ZIP64 locator is missing.")
		file.seek(eocd_absolute - 20)
		var locator := file.get_buffer(20)
		if locator.size() != 20 or locator.decode_u32(0) != 0x07064b50 or locator.decode_u32(4) != 0 or locator.decode_u32(16) != 1:
			return _fail("The ZIP64 locator is invalid.")
		var end_offset := locator.decode_u64(8)
		if end_offset < 0 or end_offset > eocd_absolute - 76:
			return _fail("The ZIP64 end record offset is invalid.")
		file.seek(end_offset)
		var end64 := file.get_buffer(56)
		if end64.size() != 56 or end64.decode_u32(0) != 0x06064b50 or end64.decode_u64(4) != 44:
			return _fail("The ZIP64 end record is unsupported.")
		if end64.decode_u32(16) != 0 or end64.decode_u32(20) != 0:
			return _fail("Split ZIP archives are not supported.")
		on_disk = end64.decode_u64(24)
		count = end64.decode_u64(32)
		central_length = end64.decode_u64(40)
		central_offset = end64.decode_u64(48)
		if central_offset < 0 or central_length < 0 or central_offset > end_offset or central_length != end_offset - central_offset:
			return _fail("The ZIP64 central directory boundaries are invalid.")
	elif central_offset > eocd_absolute or central_length != eocd_absolute - central_offset:
		return _fail("The ZIP central directory boundaries are invalid.")
	if count < 1 or count > MAX_ENTRIES or count != on_disk or central_length > MAX_DIRECTORY:
		return _fail("The ZIP directory exceeds supported limits.")
	_directory_offset = central_offset
	_directory_size = central_length
	file.seek(central_offset)
	var directory := file.get_buffer(central_length)
	if directory.size() != central_length:
		return _fail("The ZIP directory is truncated.")
	_directory_sha = _hash(directory)
	var cursor := 0
	var folded := {}
	var raw_names := {}
	var offsets := {}
	var ordered_offsets: Array[int] = []
	for i: int in count:
		if _cancelled(cancel):
			return _fail("The import was cancelled.")
		if cursor + 46 > directory.size() or directory.decode_u32(cursor) != 0x02014b50:
			return _fail("The ZIP directory entry is invalid.")
		var flags := directory.decode_u16(cursor + 8)
		var method := directory.decode_u16(cursor + 10)
		var crc := directory.decode_u32(cursor + 16)
		var compressed := directory.decode_u32(cursor + 20)
		var size := directory.decode_u32(cursor + 24)
		var name_length := directory.decode_u16(cursor + 28)
		var extra_length := directory.decode_u16(cursor + 30)
		var comment_length := directory.decode_u16(cursor + 32)
		var disk := directory.decode_u16(cursor + 34)
		var mode := (directory.decode_u32(cursor + 38) >> 16) & 0xf000
		var local := directory.decode_u32(cursor + 42)
		var end := cursor + 46 + name_length + extra_length + comment_length
		if end > directory.size() or name_length < 1 or name_length > MAX_NAME or flags & ~0x080e or method not in [0, 8] or disk != 0:
			return _fail("The ZIP entry uses an unsupported format.")
		var raw := directory.slice(cursor + 46, cursor + 46 + name_length)
		var raw_key := raw.hex_encode()
		if raw_names.has(raw_key):
			return _fail("The ZIP contains duplicate raw member names.")
		raw_names[raw_key] = true
		var extra := directory.slice(cursor + 46 + name_length, cursor + 46 + name_length + extra_length)
		var fields := _extra(extra, raw, size == 0xffffffff, compressed == 0xffffffff, local == 0xffffffff)
		if not fields.ok:
			return fields
		if size == 0xffffffff:
			size = fields.size
		if compressed == 0xffffffff:
			compressed = fields.compressed
		if local == 0xffffffff:
			local = fields.local
		if size < 0 or compressed < 0 or local < 0 or local >= central_offset or (method == 0 and size != compressed):
			return _fail("The ZIP entry has invalid sizes.")
		if offsets.has(local):
			return _fail("The ZIP contains overlapping local entries.")
		var name: String = fields.unicode if not fields.unicode.is_empty() else _decode_name(raw, bool(flags & 0x0800))
		var is_dir := name.ends_with("/")
		if not _safe_name(name) or folded.has(name.to_lower()) or mode not in [0, 0x4000, 0x8000]:
			return _fail("The ZIP has unsafe, duplicate or special entries.")
		if (mode == 0x4000 and not is_dir) or (mode == 0x8000 and is_dir):
			return _fail("The ZIP entry type is inconsistent.")
		folded[name.to_lower()] = true
		_names.append(name)
		_entries[name] = {directory = is_dir, size = size, compressed = compressed, local = local,
			flags = flags, method = method, crc = crc, raw_name = raw}
		offsets[local] = name
		ordered_offsets.append(local)
		cursor = end
	if cursor != directory.size():
		return _fail("The ZIP directory contains unexpected data.")
	ordered_offsets.sort()
	for i: int in ordered_offsets.size():
		var offset := ordered_offsets[i]
		var name: String = offsets[offset]
		_entries[name].end_limit = ordered_offsets[i + 1] if i + 1 < ordered_offsets.size() else central_offset
	return R.ok()


static func _extra(extra: PackedByteArray, raw_name: PackedByteArray, need_size: bool, need_compressed: bool, need_local: bool) -> Dictionary:
	var result := {ok = true, unicode = "", size = -1, compressed = -1, local = -1}
	var at := 0
	var found64 := false
	var found_unicode := false
	while at < extra.size():
		if at + 4 > extra.size():
			return _fail("A ZIP extra field is truncated.")
		var kind := extra.decode_u16(at)
		var length := extra.decode_u16(at + 2)
		at += 4
		var end := at + length
		if end > extra.size():
			return _fail("A ZIP extra field is truncated.")
		if kind == 1:
			if found64:
				return _fail("A ZIP64 extra field is duplicated.")
			found64 = true
			for key: String in ["size", "compressed", "local"]:
				var needed: bool = need_size if key == "size" else (need_compressed if key == "compressed" else need_local)
				if needed:
					if at + 8 > end:
						return _fail("A ZIP64 extra field is incomplete.")
					result[key] = extra.decode_u64(at)
					at += 8
		elif kind == 0x7075:
			if found_unicode or length < 5 or extra[at] != 1:
				return _fail("A ZIP Unicode path field is invalid.")
			found_unicode = true
			var checksum: Dictionary = Archive.crc32(raw_name)
			if not checksum.ok or checksum.value != extra.decode_u32(at + 1):
				return _fail("A ZIP Unicode path checksum is invalid.")
			var bytes := extra.slice(at + 5, end)
			result.unicode = bytes.get_string_from_utf8()
			if str(result.unicode).to_utf8_buffer() != bytes:
				return _fail("A ZIP Unicode path is invalid.")
		at = end
	if (need_size and result.size < 0) or (need_compressed and result.compressed < 0) or (need_local and result.local < 0):
		return _fail("A ZIP64 extra field is missing.")
	return result


static func _decode_name(bytes: PackedByteArray, utf8: bool) -> String:
	if utf8:
		var value := bytes.get_string_from_utf8()
		return value if value.to_utf8_buffer() == bytes else ""
	var result := ""
	for b: int in bytes:
		result += String.chr(b) if b < 128 else CP437.substr(b - 128, 1)
	return result


static func _safe_name(name: String) -> bool:
	if name.is_empty() or name.begins_with("/") or "\\" in name or ":" in name:
		return false
	var parts := name.trim_suffix("/").split("/", true)
	if parts.size() > 16:
		return false
	for part: String in parts:
		if part.is_empty() or part in [".", ".."] or part.ends_with(".") or part.ends_with(" "):
			return false
	for code: int in name.to_utf32_buffer().size() / 4:
		var c := name.unicode_at(code)
		if c < 32 or c == 127:
			return false
	return true


static func _hash(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


static func _cancelled(cancel: Callable) -> bool:
	return cancel.is_valid() and bool(cancel.call())


static func _fail(message: String) -> Dictionary:
	return R.fail(R.SOURCE_INVALID, message, "source", "import")
