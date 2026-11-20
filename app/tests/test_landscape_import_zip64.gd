extends SceneTree

const Zip64 := preload("res://landscapes/phoenix_zip64.gd")
const Archive := preload("res://workshop/creator/clearview/archive.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "user://test-scenery-zip64-%d.zip" % OS.get_process_id()
	var payload := "A synthetic stored ZIP64 member.".to_utf8_buffer()
	var name := "synthetic/synthetic.pxf"
	# POSIX fixtures can create a sparse offset beyond 4 GiB. Exercise the same ZIP64
	# fields at a small offset on Windows, where creating a hole can allocate disk space.
	var offset := 0x100000000 + 257 if OS.get_name() in ["Linux", "macOS"] else 257
	var created := _fixture(path, offset, name, payload)
	var archive := Zip64.capture(path) if created else {}
	var faults := 0
	if not archive.get("ok", false):
		printerr("FAIL sparse archive: ", archive)
		faults += 1
	else:
		var reader: RefCounted = archive.value
		var result: Dictionary = reader.read_member(name, 1024)
		if not result.get("ok", false) or result.value != payload:
			printerr("FAIL 64-bit offset member read: ", result)
			faults += 1
		if reader.read_member(name, 1).get("ok", true):
			printerr("FAIL expansion ceiling")
			faults += 1
		if reader.read_member(name, 1024, func() -> bool: return true).get("ok", true):
			printerr("FAIL cancellation")
			faults += 1
	DirAccess.remove_absolute(path)
	print("Landscape ZIP64: offset %d, %d failed" % [offset, faults])
	quit(1 if faults else 0)


func _fixture(path: String, offset: int, name: String, payload: PackedByteArray) -> bool:
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		return false
	var name_bytes := name.to_utf8_buffer()
	var crc: int = Archive.crc32(payload).value
	var local := _bytes(30, 0x04034b50)
	local.encode_u16(4, 45)
	local.encode_u32(14, crc)
	local.encode_u32(18, payload.size())
	local.encode_u32(22, payload.size())
	local.encode_u16(26, name_bytes.size())
	output.seek(offset)
	output.store_buffer(local)
	output.store_buffer(name_bytes)
	output.store_buffer(payload)

	var directory_offset := output.get_position()
	var central := _bytes(46, 0x02014b50)
	central.encode_u16(4, 45)
	central.encode_u16(6, 45)
	central.encode_u32(16, crc)
	central.encode_u32(20, payload.size())
	central.encode_u32(24, payload.size())
	central.encode_u16(28, name_bytes.size())
	central.encode_u16(30, 12)
	central.encode_u32(42, 0xffffffff)
	var extra := _bytes(12, 0x00080001)
	extra.encode_u64(4, offset)
	output.store_buffer(central)
	output.store_buffer(name_bytes)
	output.store_buffer(extra)
	var end64_offset := output.get_position()

	var end64 := _bytes(56, 0x06064b50)
	end64.encode_u64(4, 44)
	end64.encode_u16(12, 45)
	end64.encode_u16(14, 45)
	end64.encode_u64(24, 1)
	end64.encode_u64(32, 1)
	end64.encode_u64(40, end64_offset - directory_offset)
	end64.encode_u64(48, directory_offset)
	var locator := _bytes(20, 0x07064b50)
	locator.encode_u64(8, end64_offset)
	locator.encode_u32(16, 1)
	var end := _bytes(22, 0x06054b50)
	end.encode_u16(8, 0xffff)
	end.encode_u16(10, 0xffff)
	end.encode_u32(12, 0xffffffff)
	end.encode_u32(16, 0xffffffff)
	output.store_buffer(end64)
	output.store_buffer(locator)
	output.store_buffer(end)
	output.flush()
	return output.get_error() == OK


func _bytes(length: int, magic: int) -> PackedByteArray:
	var value := PackedByteArray()
	value.resize(length)
	value.encode_u32(0, magic)
	return value
