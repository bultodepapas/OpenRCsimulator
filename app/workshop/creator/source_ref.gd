extends RefCounted
## A published Creator selection, not a draft, candidate, path, or flight qualification.
## The record SHA names an exact revision-record object accepted by the Creator root index.
const R := preload("res://workshop/creator/result.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Limits := preload("res://workshop/creator/limits.gd")

const FORMAT := "openrc-creator-source v1"
const MAX_BYTES := 1024
const KEYS := ["format", "aircraft_uuid", "revision", "record_sha256"]


## Returns an R envelope containing a fresh, detached data-only reference.
static func make(aircraft_uuid: Variant, revision: Variant, record_sha256: Variant) -> Dictionary:
	return validate({"format": FORMAT, "aircraft_uuid": aircraft_uuid, "revision": revision,
		"record_sha256": record_sha256})


## Exact shape and scalar types. Revision zero/latest and floating-point revisions are refused.
static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != KEYS.size():
		return _invalid()
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in KEYS:
			return _invalid()
	if typeof(value.get("format")) != TYPE_STRING or value.format != FORMAT \
			or not _is_uuid(value.get("aircraft_uuid")) \
			or typeof(value.get("revision")) != TYPE_INT or value.revision < 1 \
			or value.revision > Limits.MAX_SAFE_INTEGER or not Bytes.is_sha256(value.get("record_sha256")):
		return _invalid()
	return R.ok({"format": FORMAT, "aircraft_uuid": value.aircraft_uuid,
		"revision": value.revision, "record_sha256": value.record_sha256})


## Use this instead of JSON.parse_string when reading a serialized reference: the exact integer
## token policy preserves revision as TYPE_INT and refuses fraction/exponent/negative spellings.
static func from_bytes(bytes: PackedByteArray) -> Dictionary:
	var read: Dictionary = Bytes.decode(bytes, PackedStringArray(["revision"]), MAX_BYTES)
	if not read.ok:
		return read
	return validate(read.value.data)


static func _is_uuid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 36:
		return false
	for index: int in 36:
		var character: String = value[index]
		if index in [8, 13, 18, 23]:
			if character != "-":
				return false
		elif character not in "0123456789abcdef":
			return false
	return value[14] == "4" and value[19] in "89ab"


static func _invalid() -> Dictionary:
	return R.fail(R.RECORD_INVALID, "This published aircraft reference is invalid.", "source_ref")
