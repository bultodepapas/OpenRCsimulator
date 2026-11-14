extends RefCounted
## Conservative identity helpers for the JETI DC/DS USB radio family.

const VENDOR_ID := 0x0483
const PRODUCT_ID := 0xA07C
const FAMILY_LABEL := "JETI DC/DS Radio"

const IDENTITY_TEXT_FIELDS := ["manufacturer", "name", "raw_name"]
const EMULATION_FLAGS := ["emulated", "is_emulated", "virtual", "is_virtual"]
const EMULATION_TEXT_FIELDS := ["manufacturer", "name", "raw_name", "backend", "transport"]
const EMULATION_MARKERS := ["emulat", "virtual", "synthetic", "mock device"]
const OTHER_FAMILY_MARKERS := ["xbox", "playstation", "logitech", "nintendo", "8bitdo", "generic gamepad"]


## Returns true when the complete USB pair and at least one JETI identity string agree.
static func matches(info: Dictionary) -> bool:
	if not _ids_match(info) or _is_ambiguous(info) or _is_emulated(info):
		return false
	return _has_corroborating_identity(info)


## Returns a stable family label after validation; otherwise leaves the observed name intact.
static func display_name(info: Dictionary) -> String:
	if matches(info):
		return FAMILY_LABEL
	return _observed_name(info)


## Parses integer, decimal-string, and hexadecimal-string USB identifiers.
static func normalize_usb_id(value: Variant) -> int:
	return _parse_id(value)


## True for an identity that claims JETI by name or the complete JETI USB pair.
## Callers use this to suppress generic automatic defaults when strict matching fails.
static func has_jeti_identity_claim(info: Dictionary) -> bool:
	return _has_jeti_text_claim(info) or _ids_match(info)


static func _ids_match(info: Dictionary) -> bool:
	return info.has("vendor_id") and info.has("product_id") \
		and _parse_id(info.vendor_id) == VENDOR_ID \
		and _parse_id(info.product_id) == PRODUCT_ID


static func _parse_id(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value) if value >= 0 and value <= 65535 else -1
	if typeof(value) != TYPE_STRING:
		return -1
	var text: String = value.strip_edges()
	if text.is_empty():
		return -1
	var parsed := -1
	if text.begins_with("0x") or text.begins_with("0X"):
		var digits: String = text.substr(2).to_lower()
		if digits.is_empty() or digits.length() > 4:
			return -1
		parsed = 0
		for index in digits.length():
			var digit := "0123456789abcdef".find(digits.substr(index, 1))
			if digit < 0:
				return -1
			parsed = parsed * 16 + digit
	elif text.is_valid_int():
		parsed = text.to_int()
	return parsed if parsed >= 0 and parsed <= 65535 else -1


static func _has_corroborating_identity(info: Dictionary) -> bool:
	var identity_fields := _present_text_fields(info, IDENTITY_TEXT_FIELDS)
	if not _any_jeti_text(info, identity_fields):
		return false
	# A populated USB manufacturer field is authoritative; a different manufacturer
	# cannot be rescued by a copied JETI-looking product name.
	if info.has("manufacturer") and typeof(info.manufacturer) == TYPE_STRING \
			and not info.manufacturer.strip_edges().is_empty() and not _contains_jeti_token(info.manufacturer):
		return false
	for field in ["name", "raw_name"]:
		var value: Variant = info.get(field, "")
		if typeof(value) == TYPE_STRING and _has_other_family_marker(value):
			return false
	return true


static func _is_ambiguous(info: Dictionary) -> bool:
	if not info.has("ambiguous"):
		return false
	return typeof(info["ambiguous"]) != TYPE_BOOL or bool(info["ambiguous"])


static func _is_emulated(info: Dictionary) -> bool:
	for field in EMULATION_FLAGS:
		if not info.has(field):
			continue
		if typeof(info[field]) != TYPE_BOOL or bool(info[field]):
			return true
	for field in EMULATION_TEXT_FIELDS:
		var value: Variant = info.get(field, "")
		if typeof(value) != TYPE_STRING:
			continue
		var lowered: String = value.to_lower()
		for marker in EMULATION_MARKERS:
			if marker in lowered:
				return true
	return false


static func _has_jeti_text_claim(info: Dictionary) -> bool:
	for field in IDENTITY_TEXT_FIELDS:
		var value: Variant = info.get(field, "")
		if typeof(value) == TYPE_STRING and _contains_jeti_token(value):
			return true
	return false


static func _present_text_fields(info: Dictionary, fields: Array) -> Array[String]:
	var result: Array[String] = []
	for field in fields:
		var value: Variant = info.get(field, "")
		if typeof(value) == TYPE_STRING and not value.strip_edges().is_empty():
			result.append(field)
	return result


static func _any_jeti_text(info: Dictionary, fields: Array) -> bool:
	for field in fields:
		if _contains_jeti_token(str(info[field])):
			return true
	return false


static func _contains_jeti_token(value: String) -> bool:
	var lowered := value.to_lower()
	if "not jeti" in lowered or "not-jeti" in lowered or "non-jeti" in lowered:
		return false
	var start := 0
	while true:
		var found := lowered.find("jeti", start)
		if found < 0:
			return false
		var before_ok := found == 0 or not _is_ascii_alphanumeric(lowered.substr(found - 1, 1))
		var after_index := found + 4
		var after_ok := after_index >= lowered.length() or not _is_ascii_alphanumeric(lowered.substr(after_index, 1))
		if before_ok and after_ok:
			return true
		start = found + 1
	return false


static func _is_ascii_alphanumeric(character: String) -> bool:
	return (character >= "a" and character <= "z") or (character >= "0" and character <= "9")


static func _has_other_family_marker(value: String) -> bool:
	var lowered := value.to_lower()
	for marker in OTHER_FAMILY_MARKERS:
		if marker in lowered:
			return true
	return false


static func _observed_name(info: Dictionary) -> String:
	for field in ["name", "raw_name"]:
		var value: Variant = info.get(field, "")
		if typeof(value) == TYPE_STRING and not value.strip_edges().is_empty():
			return value
	return "Controller"
