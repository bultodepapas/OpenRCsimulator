## Replays frozen typed checkpoint bytes through a narrowly defined identity migration.
extends RefCounted

const FIXTURE_PATH := "res://tests/fixtures/publication_fixture_bridge.json"
const FIXTURE_SHA256 := "5493c5c96964c1a94de2509dada739345980407dc22c8b71069338c883063e19"
const CURRENT_ENGINE := "cafc17a192acf67903910a68aeb3c076c0907a4b"
const OLD_AERO := "section-plane-source-weighted-wake-velocity-v2"
const CURRENT_AERO := "section-plane-source-weighted-wake-velocity-v4"
const CASES := {"shaft": ["coupled-rk4", "split"],
	"weather": ["calm", "cool-dense", "gusty", "turbulent"]}
const MAX_UNPACKED_BYTES := 1048576


static func _error(message: String) -> Dictionary:
	return {ok = false, error = message}


static func _sha256(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


static func _hex256(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.length() == 64 and value.is_valid_hex_number()


static func _sources_match(pins: Variant) -> bool:
	if not pins is Dictionary or pins.size() != 19:
		return false
	for path: String in pins:
		var pin: Variant = pins[path]
		var full := "res://" + path
		if not pin is Dictionary or not _hex256(pin.get("sha256")) or not FileAccess.file_exists(full):
			return false
		var bytes := FileAccess.get_file_as_bytes(full)
		if pin.get("mode") == "script-lf":
			var source := bytes.get_string_from_utf8()
			if source.to_utf8_buffer() != bytes:
				return false
			bytes = source.replace("\r\n", "\n").to_utf8_buffer()
		elif pin.get("mode") != "exact":
			return false
		if _sha256(bytes) != pin.sha256:
			return false
	return true


static func _overlays_match(overlays: Variant, pins: Variant) -> bool:
	if not overlays is Dictionary or not pins is Dictionary or overlays.size() != 2:
		return false
	for path: String in ["sim/flight_session.gd", "sim/electric_contact_step.gd"]:
		if not _hex256(overlays.get(path)) or not pins.get(path) is Dictionary \
				or pins[path].get("mode") != "script-lf" or pins[path].get("sha256") != overlays[path]:
			return false
	return true


static func load_family(family: String) -> Dictionary:
	if not CASES.has(family) or Engine.get_version_info().get("hash") != CURRENT_ENGINE:
		return _error("unsupported fixture family or engine")
	if not FileAccess.file_exists(FIXTURE_PATH):
		return _error("missing typed fixture")
	var text := FileAccess.get_file_as_string(FIXTURE_PATH).replace("\r\n", "\n")
	if text.sha256_text() != FIXTURE_SHA256:
		return _error("typed fixture identity differs")
	var manifest: Variant = JSON.parse_string(text)
	if not manifest is Dictionary or manifest.get("format") != "openrc-publication-bridge-v1" \
			or manifest.get("current_engine") != CURRENT_ENGINE \
			or not _overlays_match(manifest.get("candidate_overlays"), manifest.get("source_pins")) \
			or not _sources_match(manifest.get("source_pins")):
		return _error("fixture manifest or source identity differs")
	var families: Variant = manifest.get("families")
	if not families is Dictionary or not families.has(family) or not families[family] is Dictionary \
			or not families[family].has(OS.get_name()) or not families[family][OS.get_name()] is Dictionary:
		return _error("no fixture for this platform")
	var encoded_cases: Dictionary = families[family][OS.get_name()]
	if encoded_cases.size() != CASES[family].size():
		return _error("fixture case count differs")
	var result := {}
	for name: String in CASES[family]:
		if not encoded_cases.has(name) or not encoded_cases[name] is Dictionary:
			return _error("fixture case missing: " + name)
		var row: Dictionary = encoded_cases[name]
		for field: String in ["original_sha256", "reference_sha256", "current_sha256", "events_sha256",
				"original_configuration", "reference_configuration", "current_configuration"]:
			if not _hex256(row.get(field)):
				return _error("invalid " + name + " " + field)
		var encoded: Variant = row.get("frames_gzip_base64")
		if typeof(encoded) != TYPE_STRING or encoded.is_empty() or encoded.length() > MAX_UNPACKED_BYTES:
			return _error("invalid compressed frame data: " + name)
		var compressed := Marshalls.base64_to_raw(encoded)
		if Marshalls.raw_to_base64(compressed) != encoded:
			return _error("invalid base64 frame data: " + name)
		var bytes := compressed.decompress_dynamic(MAX_UNPACKED_BYTES, FileAccess.COMPRESSION_GZIP)
		if bytes.is_empty():
			return _error("invalid compressed frame data: " + name)
		var old_hash := HashingContext.new()
		var reference_hash := HashingContext.new()
		old_hash.start(HashingContext.HASH_SHA256)
		reference_hash.start(HashingContext.HASH_SHA256)
		var snapshots: Array = []
		var offset := 0
		for tick: int in 25:
			if offset + 4 > bytes.size():
				return _error("truncated frame length: " + name)
			var length: int = bytes.decode_u32(offset)
			offset += 4
			if length <= 0 or length > MAX_UNPACKED_BYTES or offset + length > bytes.size():
				return _error("invalid frame length: " + name)
			var frame := bytes.slice(offset, offset + length)
			offset += length
			var snapshot: Variant = bytes_to_var(frame)
			if not snapshot is Dictionary or var_to_bytes(snapshot) != frame \
					or snapshot.get("configuration") != row.original_configuration \
					or snapshot.get("aero_loads_law") != OLD_AERO:
				return _error("invalid typed historical frame: " + name)
			old_hash.update(frame)
			var reference: Dictionary = snapshot.duplicate(true)
			reference.configuration = row.reference_configuration
			reference_hash.update(var_to_bytes(reference))
			snapshots.append(snapshot)
		if offset != bytes.size() or old_hash.finish().hex_encode() != row.original_sha256 \
				or reference_hash.finish().hex_encode() != row.reference_sha256:
			return _error("historical or same-engine reference digest differs: " + name)
		var event_encoded: Variant = row.get("events_gzip_base64")
		if typeof(event_encoded) != TYPE_STRING or event_encoded.is_empty() or event_encoded.length() > MAX_UNPACKED_BYTES:
			return _error("invalid event data: " + name)
		var event_compressed := Marshalls.base64_to_raw(event_encoded)
		if Marshalls.raw_to_base64(event_compressed) != event_encoded:
			return _error("invalid base64 event data: " + name)
		var event_bytes := event_compressed.decompress_dynamic(MAX_UNPACKED_BYTES, FileAccess.COMPRESSION_GZIP)
		var event_hash := HashingContext.new()
		event_hash.start(HashingContext.HASH_SHA256)
		var events: Array = []
		offset = 0
		for tick: int in 25:
			if offset + 4 > event_bytes.size():
				return _error("truncated event length: " + name)
			var length: int = event_bytes.decode_u32(offset)
			offset += 4
			if length <= 0 or length > MAX_UNPACKED_BYTES or offset + length > event_bytes.size():
				return _error("invalid event length: " + name)
			var event_frame := event_bytes.slice(offset, offset + length)
			offset += length
			var event: Variant = bytes_to_var(event_frame)
			if not event is Array or var_to_bytes(event) != event_frame:
				return _error("invalid typed event frame: " + name)
			event_hash.update(event_frame)
			events.append(event)
		if offset != event_bytes.size() or event_hash.finish().hex_encode() != row.events_sha256:
			return _error("event digest differs: " + name)
		result[name] = {snapshots = snapshots, events = events, original_sha256 = row.original_sha256,
			reference_sha256 = row.reference_sha256, current_sha256 = row.current_sha256,
			original_configuration = row.original_configuration, current_configuration = row.current_configuration}
	return {ok = true, cases = result}


static func matches(row: Dictionary, tick: int, current: Dictionary, events: Array) -> bool:
	if tick < 0 or tick >= 25 or not row.get("snapshots") is Array or row.snapshots.size() != 25 \
			or not row.get("events") is Array or row.events.size() != 25 \
			or current.get("configuration") != row.get("current_configuration") \
			or current.get("aero_loads_law") != CURRENT_AERO:
		return false
	var expected: Dictionary = row.snapshots[tick].duplicate(true)
	if expected.get("configuration") != row.get("original_configuration") or expected.get("aero_loads_law") != OLD_AERO:
		return false
	expected.configuration = row.current_configuration
	expected.aero_loads_law = CURRENT_AERO
	return var_to_bytes(expected) == var_to_bytes(current) and var_to_bytes(row.events[tick]) == var_to_bytes(events)
