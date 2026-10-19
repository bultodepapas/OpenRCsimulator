extends RefCounted
class_name WorkshopThumbnailCache
## Bounded LRU for copied thumbnail pixels. ViewportTexture is never accepted.

const MAX_ENTRIES := 16
const MAX_BYTES := 4 * 1024 * 1024
const MAX_DIMENSION := 512
const KEY_RE := "^[0-9a-f]{64}$"

var _entry_limit: int
var _byte_limit: int
var _dimension_limit: int
var _entries: Dictionary = {}
var _bytes := 0
var _clock := 0


func _init(entry_limit := MAX_ENTRIES, byte_limit := MAX_BYTES, dimension_limit := MAX_DIMENSION) -> void:
	_entry_limit = clampi(entry_limit, 1, MAX_ENTRIES)
	_byte_limit = clampi(byte_limit, 4, MAX_BYTES)
	_dimension_limit = clampi(dimension_limit, 1, MAX_DIMENSION)


func get_texture(key: String) -> ImageTexture:
	if not _entries.has(key):
		return null
	_clock += 1
	var entry: Dictionary = _entries[key]
	entry.last_used = _clock
	_entries[key] = entry
	return entry.texture as ImageTexture


func put_image(key: String, source: Image) -> Dictionary:
	if not _valid_key(key):
		return _failure("Thumbnail cache key must be a lowercase SHA-256 digest.")
	if source == null or source.is_empty():
		return _failure("Thumbnail image is empty.")
	var width := source.get_width()
	var height := source.get_height()
	if width < 1 or height < 1 or width > _dimension_limit or height > _dimension_limit:
		return _failure("Thumbnail dimensions exceed the cache limits.")
	var byte_count := width * height * 4
	if byte_count > _byte_limit:
		return _failure("Thumbnail image exceeds the cache byte limit.")
	var copy := source.duplicate() as Image
	if copy == null:
		return _failure("Thumbnail pixels could not be copied.")
	if copy.is_compressed() and copy.decompress() != OK:
		return _failure("Compressed thumbnail pixels could not be decoded.")
	copy.convert(Image.FORMAT_RGBA8)
	if copy.get_format() != Image.FORMAT_RGBA8:
		return _failure("Thumbnail pixels could not be normalized to RGBA8.")
	var texture := ImageTexture.create_from_image(copy)
	if texture == null:
		return _failure("Thumbnail ImageTexture could not be created.")
	if _entries.has(key):
		_remove_entry(key)
	_clock += 1
	_entries[key] = {texture = texture, bytes = byte_count, last_used = _clock}
	_bytes += byte_count
	_evict_to_limits()
	if not _entries.has(key):
		return _failure("Thumbnail was evicted before it could be retained.")
	return {ok = true, texture = texture, bytes = byte_count, errors = PackedStringArray()}


func clear() -> void:
	_entries.clear()
	_bytes = 0


func stats() -> Dictionary:
	return {entries = _entries.size(), bytes = _bytes, entry_limit = _entry_limit,
		byte_limit = _byte_limit, dimension_limit = _dimension_limit}


func _evict_to_limits() -> void:
	while _entries.size() > _entry_limit or _bytes > _byte_limit:
		var oldest_key := ""
		var oldest_clock := 9223372036854775807
		for key: String in _entries:
			var entry: Dictionary = _entries[key]
			if int(entry.last_used) < oldest_clock:
				oldest_clock = int(entry.last_used)
				oldest_key = key
		if oldest_key.is_empty():
			break
		_remove_entry(oldest_key)


func _remove_entry(key: String) -> void:
	if not _entries.has(key):
		return
	var entry: Dictionary = _entries[key]
	_bytes = maxi(0, _bytes - int(entry.get("bytes", 0)))
	_entries.erase(key)


func _valid_key(key: String) -> bool:
	if key.length() != 64:
		return false
	for index: int in key.length():
		if not "0123456789abcdef".contains(key.substr(index, 1)):
			return false
	return true


func _failure(message: String) -> Dictionary:
	return {ok = false, texture = null, errors = PackedStringArray([message])}
