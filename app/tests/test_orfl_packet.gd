## Independent framing, chain and boundary witnesses for all three ORFL recorders.
extends SceneTree

const Packet := preload("res://sim/orfl_packet.gd")
# Empty Dictionary: little-endian Variant tag 27, followed by a zero entry count.
# Prefix and chains computed independently with Python struct.pack and hashlib.sha256.
const FRAME := "080000004d159113222bfeb85fbe717cc2393ee8a6a85b7ce5ac1791c4eade5e3dd6de411b00000000000000"
const FIRST_CHAIN := "0e04b0668d67f81489d3f4add75db747b24e204e52a281695fe3736f23945d98"
const SECOND_CHAIN := "e6e8a4c39ffea30cd361b9f78d42b05bf4f20bc13114d225064790da607eb215"
const FILE_LIMIT := 512 * 1024 * 1024
const PAYLOAD_LIMIT := 16 * 1024 * 1024

var failures := 0


func _initialize() -> void:
	var path := "user://orfl-packet-%d-%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE_READ)
	if file == null:
		printerr("Cannot open ORFL packet test file: " + error_string(FileAccess.get_open_error()))
		quit(1)
		return
	_frames(file)
	_packed_values(file)
	_file_limits(file)
	_packet_limits(file)
	_corruption(file)
	file.close()
	_check("remove temporary file", DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	print("ORFL packet: %d failures" % failures)
	quit(1 if failures else 0)


func _frames(file: FileAccess) -> void:
	var frame := FRAME.hex_decode()
	var first := Packet.append_packet(file, {}, PackedByteArray(), FILE_LIMIT)
	_check("first chain from empty seed", first.ok and first.chain.hex_encode() == FIRST_CHAIN)
	var second := Packet.append_packet(file, {}, FIRST_CHAIN.hex_decode(), FILE_LIMIT)
	_check("second chain includes the previous hash", second.ok and second.chain.hex_encode() == SECOND_CHAIN)
	file.seek(0)
	_check("both complete frames match frozen bytes", file.get_buffer(file.get_length()) == frame + frame)
	file.seek(0)
	file.store_buffer(frame)
	file.seek(0)
	var readback := Packet.read_packet(file)
	_check("reader accepts a frozen frame", readback.ok and readback.value == {} and readback.digest == frame.slice(4, 36))


func _packed_values(file: FileAccess) -> void:
	file.seek_end()
	var offset := file.get_position()
	var values := {axes = PackedFloat64Array([-0.0, -1.25, 1.0 + 1.0e-15]),
		ticks = PackedInt64Array([-9007199254740993, 9007199254740993])}
	var append := Packet.append_packet(file, values, PackedByteArray(), FILE_LIMIT)
	_check("writes packed values", append.ok)
	file.seek(offset)
	var packet := Packet.read_packet(file)
	_check("packed floats retain signed zero and full precision", packet.ok and packet.value.axes is PackedFloat64Array
		and packet.value.axes.to_byte_array() == values.axes.to_byte_array())
	_check("packed integers retain full precision", packet.ok and packet.value.ticks is PackedInt64Array
		and packet.value.ticks.to_byte_array() == values.ticks.to_byte_array())


func _file_limits(file: FileAccess) -> void:
	var frame_size := FRAME.hex_decode().size()
	var chain := FIRST_CHAIN.hex_decode()
	var length := file.get_length()
	# This seek alone never allocates the 512 MiB prefix.
	var offset := FILE_LIMIT - frame_size + 1
	file.seek(offset)
	var refusal := Packet.append_packet(file, {}, chain, FILE_LIMIT)
	_check("one byte beyond file limit", not refusal.ok and refusal.code == ERR_FILE_CANT_WRITE
		and refusal.error == "Flight log byte limit exceeded; file is incomplete.")
	_check("refusal leaves cursor, bytes and chain intact", file.get_position() == offset and file.get_length() == length
		and not refusal.has("chain") and chain.hex_encode() == FIRST_CHAIN)
	# Use a small caller limit to exercise the allowed endpoint without extending a large file.
	file.seek_end()
	var limit := file.get_position() + frame_size
	var exact := Packet.append_packet(file, {}, chain, limit)
	_check("frame ending exactly at file limit is accepted", exact.ok and file.get_position() == limit)


func _packet_limits(file: FileAccess) -> void:
	var overhead := var_to_bytes({data = PackedByteArray()}).size()
	file.seek(0)
	var exact := Packet.append_packet(file, _padded_value(PAYLOAD_LIMIT - overhead), PackedByteArray(), FILE_LIMIT)
	_check("exactly 16 MiB payload accepted", exact.ok and file.get_position() == PAYLOAD_LIMIT + 36)
	var offset := file.get_position()
	var length := file.get_length()
	# Packed Variant data is padded to a multiple of four bytes. One extra byte exceeds the limit.
	var too_big := Packet.append_packet(file, _padded_value(PAYLOAD_LIMIT - overhead + 1), FIRST_CHAIN.hex_decode(), 0)
	_check("packet limit checked before file limit", not too_big.ok and too_big.code == ERR_INVALID_DATA
		and too_big.error == "Flight log packet exceeds bounded format.")
	_check("oversize refusal leaves file intact", file.get_position() == offset and file.get_length() == length and not too_big.has("chain"))


func _padded_value(size: int) -> Dictionary:
	var data := PackedByteArray()
	data.resize(size)
	return {data = data}


func _corruption(file: FileAccess) -> void:
	var frame := FRAME.hex_decode()
	# Only bytes after this position belong to each reader fixture.
	file.seek_end()
	var offset := file.get_position()
	file.store_buffer(frame.slice(0, 35))
	file.seek(offset)
	var header := Packet.read_packet(file)
	_check("truncated header refused", not header.ok and header.error == "Missing footer or truncated packet header.")
	file.seek(offset)
	file.store_buffer(frame.slice(0, frame.size() - 1))
	file.seek(offset)
	var payload := Packet.read_packet(file)
	_check("truncated payload refused", not payload.ok and payload.error == "Invalid or truncated packet length.")
	frame[4] ^= 1
	file.seek(offset)
	file.store_buffer(frame)
	file.seek(offset)
	var digest := Packet.read_packet(file)
	_check("bad checksum refused", not digest.ok and digest.error == "Packet checksum mismatch.")


func _check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		printerr("FAIL " + label)
