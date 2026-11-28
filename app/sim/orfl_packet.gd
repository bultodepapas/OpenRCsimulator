## Checksummed Variant packets shared by the ORFL recorders.
extends RefCounted

const MAGIC := "ORFL0001"
const MAX_PACKET := 16 * 1024 * 1024
const HEADER_BYTES := 36 # Length followed by the SHA-256 digest.


static func append_packet(file: FileAccess, value: Dictionary, prior_chain: PackedByteArray, max_bytes: int) -> Dictionary:
	var payload := var_to_bytes(value)
	if payload.is_empty() or payload.size() > MAX_PACKET:
		return {ok = false, error = "Flight log packet exceeds bounded format.", code = ERR_INVALID_DATA}
	if file.get_position() + payload.size() + HEADER_BYTES > max_bytes:
		return {ok = false, error = "Flight log byte limit exceeded; file is incomplete.", code = ERR_FILE_CANT_WRITE}
	var digest := sha256(payload)
	file.store_32(payload.size())
	file.store_buffer(digest)
	file.store_buffer(payload)
	file.flush()
	if file.get_error() != OK:
		return {ok = false, error = "Flight log disk write failed; file is incomplete.", code = ERR_FILE_CANT_WRITE}
	return {ok = true, chain = sha256(prior_chain + digest)}


static func sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


## No object decoding. Bounds and checksum are checked before decoding a packet.
static func read_packet(file: FileAccess) -> Dictionary:
	var remaining := file.get_length() - file.get_position()
	if remaining < HEADER_BYTES:
		return {ok = false, error = "Missing footer or truncated packet header."}
	var size := file.get_32()
	if size <= 0 or size > MAX_PACKET or size > remaining - HEADER_BYTES:
		return {ok = false, error = "Invalid or truncated packet length."}
	var digest := file.get_buffer(32)
	var bytes := file.get_buffer(size)
	if sha256(bytes) != digest:
		return {ok = false, error = "Packet checksum mismatch."}
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary:
		return {ok = false, error = "Packet is not a dictionary."}
	return {ok = true, value = value, digest = digest}
