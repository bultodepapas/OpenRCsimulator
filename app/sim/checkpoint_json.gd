## Lossless JSON carrier for the existing native checkpoint; never serializes objects.
extends RefCounted
const FORMAT := "openrc-checkpoint-json v1"
const MAX_PAYLOAD_BYTES := 16 * 1024 * 1024
const MAX_TEXT_BYTES := MAX_PAYLOAD_BYTES * 4 / 3 + 2048

static func encode(snapshot: Dictionary) -> String:
	if snapshot.is_empty(): return ""
	var payload: PackedByteArray = var_to_bytes(snapshot)
	if payload.size() > MAX_PAYLOAD_BYTES: return ""
	return JSON.stringify({format=FORMAT, payload_base64=Marshalls.raw_to_base64(payload), sha256=_hash(payload)})

static func decode(text: String) -> Dictionary:
	if text.length() > MAX_TEXT_BYTES or text.to_utf8_buffer().size() > MAX_TEXT_BYTES:
		return {ok=false}
	var value: Variant = JSON.parse_string(text)
	if not value is Dictionary or value.size() != 3 or value.get("format") != FORMAT \
			or not value.get("payload_base64") is String or not value.get("sha256") is String:
		return {ok=false}
	var encoded: String = value.payload_base64
	if encoded.is_empty() or encoded.length() > MAX_TEXT_BYTES: return {ok=false}
	var payload: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if payload.is_empty() or payload.size() > MAX_PAYLOAD_BYTES \
			or Marshalls.raw_to_base64(payload) != encoded or _hash(payload) != value.sha256:
		return {ok=false}
	# bytes_to_var disallows objects; the separate with_objects decoder is deliberately never used.
	var snapshot: Variant = bytes_to_var(payload)
	if not snapshot is Dictionary or snapshot.is_empty(): return {ok=false}
	return {ok=true, snapshot=snapshot}

static func _hash(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
