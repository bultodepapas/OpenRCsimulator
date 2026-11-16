extends RefCounted
## Strict single-disk ZIP32 envelope. ASCII member paths, stored/raw-DEFLATE data, optional
## data descriptors. Captured bytes never leave this object; members are decoded on demand.
const R := preload("res://workshop/creator/result.gd")
const Deflate := preload("deflate.gd")
const MAX_ARCHIVE := 64 * 1024 * 1024
const MAX_EXPANDED := 256 * 1024 * 1024
const MAX_MEMBER := 32 * 1024 * 1024
const MAX_ENTRIES := 4096
const MAX_NAME := 512
const POLICY := "openrc-clearview-zip32-v1"
var _bytes := PackedByteArray()
var _entries := {}
var _folded := {}
var _sha256 := ""
var _label := ""
var _notes: Array = []
var _directory_hints := 0

static func capture(path: String, cancel := Callable()) -> Dictionary:
	if _cancelled(cancel):
		return _invalid("The import was cancelled.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return R.fail(R.SOURCE_MISSING, "The ClearView ZIP cannot be opened.", "source", "import")
	var size := file.get_length()
	if size < 22 or size > MAX_ARCHIVE:
		return R.fail(R.SOURCE_LIMIT, "The ClearView ZIP must be between 22 bytes and 64 MiB.", "source", "import")
	var bytes := PackedByteArray()
	while bytes.size() < size:
		if _cancelled(cancel):
			return _invalid("The import was cancelled.")
		var chunk := file.get_buffer(mini(1024 * 1024, size - bytes.size()))
		if chunk.is_empty() or file.get_error() != OK:
			return _invalid("The ClearView ZIP could not be read completely.")
		bytes.append_array(chunk)
	return inspect(bytes, path.get_file(), cancel)

static func inspect(bytes: PackedByteArray, label := "models.zip", cancel := Callable()) -> Dictionary:
	if _cancelled(cancel):
		return _invalid("The import was cancelled.")
	if bytes.size() < 22 or bytes.size() > MAX_ARCHIVE:
		return R.fail(R.SOURCE_LIMIT, "The ClearView ZIP must be between 22 bytes and 64 MiB.", "source", "import")
	var archive := new()
	archive._bytes = bytes.duplicate()
	archive._label = label.get_file()
	var checked := archive._index(cancel)
	if not checked.ok:
		return checked
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	for at: int in range(0, bytes.size(), 1024 * 1024):
		if _cancelled(cancel):
			return _invalid("The import was cancelled.")
		hasher.update(bytes.slice(at, mini(at + 1024 * 1024, bytes.size())))
	archive._sha256 = hasher.finish().hex_encode()
	return R.ok(archive, archive.diagnostics())

static func _cancelled(cancel: Callable) -> bool:
	return cancel.is_valid() and bool(cancel.call())

func sha256() -> String:
	return _sha256

func label() -> String:
	return _label

func names() -> Array:
	return _entries.keys()

func diagnostics() -> Array:
	var notes := _notes.duplicate(true)
	if _directory_hints > 32:
		notes.append(R.diagnostic(R.SOURCE_INVALID, "Ignored size hints for %s additional empty legacy directories.", "source", "import", [str(_directory_hints - 32)], R.SEVERITY_INFO))
	return notes

func member_info(name: String) -> Dictionary:
	return (_entries.get(name, {}) as Dictionary).duplicate(true)

## Exact path first, then a unique case-insensitive match. Cross-model/host lookup is impossible.
func resolve(root: String, relative: String) -> Dictionary:
	var relative_path := relative.replace("\\", "/")
	if not safe_name(relative_path, false):
		return _invalid("A model references an unsafe or unsupported member path.")
	var path := root + "/" + relative_path if not root.is_empty() else relative_path
	if _entries.has(path):
		return R.ok({name = path, case_adjusted = false})
	var found: String = _folded.get(path.to_lower(), "")
	if found.is_empty():
		return R.fail(R.DEPENDENCY_MISSING, "The ZIP is missing the model file or texture \"%s\".", "source", "import", [path])
	return R.ok({name = found, case_adjusted = true})

func read_member(name: String, ceiling := MAX_MEMBER, cancel := Callable()) -> Dictionary:
	if not _entries.has(name):
		return R.fail(R.DEPENDENCY_MISSING, "The selected ZIP member is missing.", "source", "import")
	var entry: Dictionary = _entries[name]
	if entry.directory or entry.expanded > mini(ceiling, MAX_MEMBER):
		return R.fail(R.SOURCE_LIMIT, "A selected ZIP member exceeds its import limit.", "source", "import")
	var compressed := _bytes.slice(entry.data, entry.data + entry.compressed)
	var decoded: Dictionary = R.ok(compressed) if entry.method == 0 else Deflate.decode(compressed, entry.expanded, cancel)
	if not decoded.ok:
		return decoded
	var output: PackedByteArray = decoded.value
	var checksum := crc32(output, cancel)
	if not checksum.ok:
		return checksum
	if output.size() != entry.expanded or checksum.value != entry.crc:
		return _invalid("A ZIP member failed its size or CRC check.")
	return R.ok(output)

## IEEE CRC-32 with bounded batches and cancellation, including uncompressed members.
static func crc32(bytes: PackedByteArray, cancel := Callable()) -> Dictionary:
	var table := PackedInt64Array()
	table.resize(256)
	for index: int in 256:
		var value := index
		for bit: int in 8:
			value = (value >> 1) ^ (0xEDB88320 if value & 1 else 0)
		table[index] = value
	var crc := 0xFFFFFFFF
	for at: int in bytes.size():
		if at % 4096 == 0 and cancel.is_valid() and bool(cancel.call()):
			return _invalid("The import was cancelled.")
		crc = (crc >> 8) ^ table[(crc ^ bytes[at]) & 255]
	return R.ok(crc ^ 0xFFFFFFFF)

static func safe_name(name: String, directory := true) -> bool:
	if name.is_empty() or name.length() > MAX_NAME or name.begins_with("/") or "\\" in name or ":" in name:
		return false
	for code: int in name.to_ascii_buffer():
		if code < 32 or code > 126:
			return false
	# to_ascii_buffer replaces non-ASCII characters; require a lossless round trip.
	if name.to_ascii_buffer().get_string_from_ascii() != name:
		return false
	var parts := name.split("/", true)
	if parts.size() > 16:
		return false
	for index: int in parts.size():
		var part := parts[index]
		if part.is_empty() and directory and index == parts.size() - 1:
			continue
		if part.is_empty() or part in [".", ".."] or part.ends_with(".") or part.ends_with(" "):
			return false
	return true

func _index(cancel := Callable()) -> Dictionary:
	var eocd := -1
	for at: int in range(_bytes.size() - 22, maxi(-1, _bytes.size() - 65558), -1):
		if at % 4096 == 0 and _cancelled(cancel):
			return _invalid("The import was cancelled.")
		if _u32(at) == 0x06054B50 and at + 22 + _u16(at + 20) == _bytes.size():
			eocd = at
			break
	if eocd < 0:
		return _invalid("The ZIP end record is missing or truncated.")
	var count := _u16(eocd + 10)
	var length := _u32(eocd + 12)
	var start := _u32(eocd + 16)
	if _u16(eocd + 4) != 0 or _u16(eocd + 6) != 0 or _u16(eocd + 8) != count or count == 65535 or length == 0xFFFFFFFF or start == 0xFFFFFFFF:
		return _invalid("Use a single-disk ZIP32 archive; split and ZIP64 archives are unsupported.")
	if count < 1 or count > MAX_ENTRIES or start + length != eocd:
		return _invalid("The ZIP directory is inconsistent or exceeds the entry limit.")
	var at := start
	var expanded := 0
	var ranges: Array = []
	for index: int in count:
		if _cancelled(cancel):
			return _invalid("The import was cancelled.")
		if at + 46 > eocd or _u32(at) != 0x02014B50:
			return _invalid("The ZIP directory is truncated or malformed.")
		var flags := _u16(at + 8)
		var method := _u16(at + 10)
		var crc := _u32(at + 16)
		var compressed := _u32(at + 20)
		var size := _u32(at + 24)
		var nl := _u16(at + 28)
		var extra := _u16(at + 30)
		var comment := _u16(at + 32)
		var local := _u32(at + 42)
		var next := at + 46 + nl + extra + comment
		if flags & ~0x080E or method not in [0, 8] or (method == 0 and flags & 6) or _u16(at + 34) != 0:
			return _invalid("The ZIP uses encryption, split disks or an unsupported compression method.")
		if nl < 1 or nl > MAX_NAME or next > eocd or local + 30 > start or compressed > MAX_ARCHIVE or size > MAX_EXPANDED:
			return _invalid("The ZIP contains an invalid member size or offset.")
		var name_bytes := _bytes.slice(at + 46, at + 46 + nl)
		for value: int in name_bytes:
			if value < 32 or value > 126:
				return R.fail(R.SOURCE_UNSUPPORTED, "Use ASCII filenames inside the ClearView ZIP.", "source", "import")
		var name := name_bytes.get_string_from_ascii()
		if not safe_name(name) or _folded.has(name.to_lower()):
			return _invalid("The ZIP contains unsafe, duplicate or case-colliding member paths.")
		var directory := name.ends_with("/")
		var mode := (_u32(at + 38) >> 16) & 0xF000
		if mode not in [0, 0x8000, 0x4000] or (mode == 0x4000 and not directory) or (mode == 0x8000 and directory):
			return _invalid("Links and special files are not allowed in a model ZIP.")
		if not _extra_ok(at + 46 + nl, extra) or _u32(local) != 0x04034B50 or _u16(local + 6) != flags or _u16(local + 8) != method:
			return _invalid("The ZIP local and directory records disagree.")
		var local_nl := _u16(local + 26)
		var local_extra := _u16(local + 28)
		var data := local + 30 + local_nl + local_extra
		if data > start or local_nl != nl or _bytes.slice(local + 30, local + 30 + local_nl) != name_bytes or not _extra_ok(local + 30 + local_nl, local_extra):
			return _invalid("The ZIP local member name or extra data is invalid.")
		var empty_directory_hint := directory and (mode == 0x4000 or bool(_u32(at + 38) & 16)) and method == 0 and compressed == 0 and crc == 0
		if (method == 0 and compressed != size and not empty_directory_hint) or (directory and size != 0 and not empty_directory_hint):
			return _invalid("The ZIP stored size or directory payload is invalid.")
		if empty_directory_hint and size != 0:
			_directory_hints += 1
			if _directory_hints <= 32:
				_notes.append(R.diagnostic(R.SOURCE_INVALID, "An empty legacy directory size hint was ignored: %s.", "source", "import", [name], R.SEVERITY_INFO))
		var end := data + compressed
		if end > start:
			return _invalid("A ZIP member overlaps the directory.")
		if flags & 8:
			for pair: Array in [[14, crc], [18, compressed], [22, size]]:
				if _u32(local + pair[0]) not in [0, pair[1]]:
					return _invalid("A ZIP data descriptor conflicts with its local record.")
			var descriptor := end
			var plain := descriptor + 12 <= start and _u32(descriptor) == crc and _u32(descriptor + 4) == compressed and _u32(descriptor + 8) == size
			var signed := descriptor + 16 <= start and _u32(descriptor) == 0x08074B50 and _u32(descriptor + 4) == crc and _u32(descriptor + 8) == compressed and _u32(descriptor + 12) == size
			if plain == signed:
				return _invalid("The ZIP data descriptor is missing or inconsistent.")
			end = descriptor + (16 if signed else 12)
		elif _u32(local + 14) != crc or _u32(local + 18) != compressed or _u32(local + 22) != size:
			return _invalid("The ZIP member sizes or CRC disagree between headers.")
		expanded += size
		if expanded > MAX_EXPANDED:
			return R.fail(R.SOURCE_LIMIT, "The ZIP expands beyond the 256 MiB import limit.", "source", "import")
		_entries[name] = {directory = directory, method = method, compressed = compressed, expanded = size, data = data, crc = crc}
		_folded[name.to_lower()] = name
		ranges.append([local, end])
		at = next
	if at != eocd:
		return _invalid("The ZIP directory has unexpected trailing data.")
	ranges.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var expected := 0
	for span: Array in ranges:
		if span[0] != expected:
			return _invalid("ZIP member records overlap or contain unsupported hidden data.")
		expected = span[1]
	if expected != start:
		return _invalid("Unexpected data precedes the ZIP directory.")
	return R.ok()

func _extra_ok(at: int, length: int) -> bool:
	var end := at + length
	if end > _bytes.size():
		return false
	while at < end:
		if at + 4 > end:
			return false
		var kind := _u16(at)
		var size := _u16(at + 2)
		if kind in [1, 0x0017, 0x7075] or at + 4 + size > end:
			return false
		at += 4 + size
	return at == end

func _u16(at: int) -> int:
	return _bytes.decode_u16(at)

func _u32(at: int) -> int:
	return _bytes.decode_u32(at)

static func _invalid(message: String) -> Dictionary:
	return R.fail(R.SOURCE_INVALID, message, "source", "import")
