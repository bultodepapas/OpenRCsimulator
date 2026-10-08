# E4b research-only adjacent-float transform; enabled after authentic checkpoint restore.
extends RefCounted
static var direction: int = 0


static func next_up(value: float) -> float:
	if is_nan(value) or value == INF:
		return value
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	if value == 0.0:
		bytes.encode_u64(0, 1)
	else:
		bytes.encode_double(0, value)
		var bits: int = bytes.decode_u64(0)
		bits += -1 if value < 0.0 else 1
		bytes.encode_u64(0, bits)
	return bytes.decode_double(0)


static func apply(value: float) -> float:
	if direction == 0:
		return value
	return next_up(value) if direction > 0 else -next_up(-value)
