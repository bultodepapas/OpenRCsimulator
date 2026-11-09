## Fixed-roster turbulence seed provenance. Does not consume any flight RNG.
extends RefCounted

const FORMAT := "openrc-companion-seeds v1"
const DOMAIN := "openrc/companions/turbulence/v1"
const UINT32_MAX := 4294967295
const MAX_COUNT := 3
const MAX_NONCES := 64


func resolve(player_seed: Variant, traffic_seed: Variant, count: Variant) -> Dictionary:
	if not _uint32(player_seed) or not _uint32(traffic_seed):
		return _failure("Player and traffic seeds must be uint32 integers.")
	if typeof(count) != TYPE_INT or count < 1 or count > MAX_COUNT:
		return _failure("Seed allocation requires a fixed roster of 1..3 companions.")
	var used_seeds := {int(player_seed): true}
	var used_states := {initial_state_hex(int(player_seed)): true}
	var allocations: Array[Dictionary] = []
	for slot: int in int(count):
		var allocated := false
		for nonce: int in MAX_NONCES:
			var candidate: int = _candidate_seed(int(player_seed), int(traffic_seed), slot, nonce)
			if not _uint32(candidate):
				return _failure("Seed derivation returned an invalid uint32.")
			var state_hex: String = initial_state_hex(candidate)
			if used_seeds.has(candidate) or used_states.has(state_hex):
				continue
			used_seeds[candidate] = true
			used_states[state_hex] = true
			allocations.append({actor_id = "companion-%d" % slot, slot = slot,
				seed = candidate, nonce = nonce, initial_rng_state_hex = state_hex})
			allocated = true
			break
		if not allocated:
			return _failure("Seed collision retries were exhausted.")
	return {ok = true, errors = PackedStringArray(), record = {
		format = FORMAT, domain = DOMAIN, player_seed = int(player_seed),
		traffic_seed = int(traffic_seed), count = int(count), allocations = allocations}}


## Re-derive the whole roster so wrong actors, nonces or resolved seeds refuse.
func validate_record(record: Variant, player_seed: int, traffic_seed: int, count: int) -> Dictionary:
	var expected: Dictionary = resolve(player_seed, traffic_seed, count)
	if not expected.ok:
		return expected
	if not _same_record(record, expected.record):
		return _failure("Seed allocation does not match the versioned fixed roster.")
	return expected


## JSON numbers arrive as float64. Every numeric field here is an exact uint32
## or smaller; accept integral JSON values, while retaining exact keys and types.
static func _same_record(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size():
			return false
		for key: String in expected:
			if not actual.has(key) or not _same_record(actual[key], expected[key]):
				return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size():
			return false
		for index in expected.size():
			if not _same_record(actual[index], expected[index]):
				return false
		return true
	if typeof(expected) == TYPE_INT:
		return typeof(actual) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(actual)) \
			and actual >= 0 and actual <= UINT32_MAX and actual == floor(float(actual)) and int(actual) == expected
	return typeof(actual) == typeof(expected) and actual == expected


func _candidate_seed(player_seed: int, traffic_seed: int, slot: int, nonce: int) -> int:
	var payload: String = "%s|player=%d|traffic=%d|actor=companion-%d|nonce=%d" % [
		DOMAIN, player_seed, traffic_seed, slot, nonce]
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(payload.to_utf8_buffer())
	return digest.finish().decode_u32(0)


## The actual engine mapping is checked, including any seed aliases. Encode the
## signed int64 bits as hex so JSON metadata never rounds a PCG state to float64.
static func initial_state_hex(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bits := PackedByteArray()
	bits.resize(8)
	bits.encode_s64(0, rng.state)
	return bits.hex_encode()


static func _uint32(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= UINT32_MAX


static func _failure(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}
