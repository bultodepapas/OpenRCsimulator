extends SceneTree
const R := preload("res://workshop/creator/result.gd")
const Deflate := preload("res://workshop/creator/clearview/deflate.gd")
const Archive := preload("res://workshop/creator/clearview/archive.gd")
const Params := preload("res://workshop/creator/clearview/params.gd")
const Ac3d := preload("res://workshop/creator/clearview/ac3d.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_deflate()
	_zip()
	_params()
	_ac3d()
	print("ClearView readers: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)

func _deflate() -> void:
	var empty := Deflate.decode(PackedByteArray([3,0]), 0)
	check("RFC empty fixed block", empty.ok and empty.value.is_empty())
	var abc := PackedByteArray([1,3,0,252,255,65,66,67])
	var decoded := Deflate.decode(abc, 3)
	check("RFC stored ABC", decoded.ok and decoded.value == "ABC".to_ascii_buffer())
	check("stored nlen corruption", not Deflate.decode(PackedByteArray([1,3,0,253,255,65,66,67]), 3).ok)
	check("reserved block", not Deflate.decode(PackedByteArray([7]), 0).ok)
	for raw: PackedByteArray in [PackedByteArray(), "a".to_ascii_buffer(), "ABABABABABABABABABABABABABAB".to_ascii_buffer(), _payload(70000)]:
		var gzip := raw.compress(FileAccess.COMPRESSION_GZIP) if not raw.is_empty() else PackedByteArray()
		var stream := gzip.slice(10, gzip.size() - 8) if not raw.is_empty() else PackedByteArray([3,0])
		var result := Deflate.decode(stream, raw.size())
		check("independent native encoder %d" % raw.size(), result.ok and result.value == raw)
		var trailing := stream.duplicate()
		trailing.append(0)
		check("trailing compressed bytes refused", not Deflate.decode(trailing, raw.size()).ok)
		check("truncated compressed bytes refused", not Deflate.decode(stream.slice(0, stream.size() - 1), raw.size()).ok)
		check("short output refused", not Deflate.decode(stream, raw.size() + 1).ok)
		if not raw.is_empty():
			check("excess output refused", not Deflate.decode(stream, raw.size() - 1).ok)
	var zeros := PackedByteArray()
	zeros.resize(1024 * 1024)
	var bomb := zeros.compress(FileAccess.COMPRESSION_GZIP)
	check("expansion stops at stated output", not Deflate.decode(bomb.slice(10, bomb.size() - 8), 64).ok)
	var bits: Array[int] = []
	for block: int in Deflate.MAX_BLOCKS + 1:
		_put_bits(bits, 1 if block == Deflate.MAX_BLOCKS else 0, 1)
		_put_bits(bits, 1, 2) # fixed Huffman
		_put_bits(bits, 0, 7) # end-of-block symbol 256
	var limited := Deflate.decode(_pack_bits(bits), 0)
	check("empty-block CPU amplification refused", not limited.ok and limited.diagnostics[0].code == R.SOURCE_LIMIT)
	check("decompression cancellation", not Deflate.decode(abc, 3, func() -> bool: return true).ok)
	# An independent dynamic alphabet: CL symbols 0 and 1, one-bit literal EOB, no distance codes.
	bits = []
	_put_bits(bits, 1, 1)
	_put_bits(bits, 2, 2)
	_put_bits(bits, 0, 5)
	_put_bits(bits, 0, 5)
	_put_bits(bits, 14, 4)
	for index: int in 18:
		_put_bits(bits, 1 if index in [3,17] else 0, 3)
	for index: int in 258:
		_put_bits(bits, 1 if index == 256 else 0, 1)
	_put_bits(bits, 0, 1)
	check("single-EOB dynamic tree and empty distance alphabet", Deflate.decode(_pack_bits(bits), 0).ok)

func _zip() -> void:
	check("cancel before capture never opens a file", not Archive.capture("res://missing.zip",func() -> bool: return true).ok)
	check("cancel before inspection", not Archive.inspect(_zip_bytes([["a","x".to_ascii_buffer()]]),"x.zip",func() -> bool: return true).ok)
	var index_polls := [0]
	var cancelled := Archive.inspect(_zip_bytes([["a","x".to_ascii_buffer()],["b","y".to_ascii_buffer()]]),"x.zip",func() -> bool:
		index_polls[0] += 1
		return index_polls[0] > 2)
	check("cancel during archive indexing or hashing", not cancelled.ok and index_polls[0] > 2)
	check("independent CRC vector", Archive.crc32("123456789".to_ascii_buffer()).value == 0xCBF43926)
	check("empty CRC", Archive.crc32(PackedByteArray()).value == 0)
	var content := "123456789".to_ascii_buffer()
	for compressed: bool in [false, true]:
		var bytes := _zip_bytes([["Plane/params.txt", content]], compressed)
		var parsed := Archive.inspect(bytes)
		check("ZIP admission", parsed.ok)
		if parsed.ok:
			var got: Dictionary = parsed.value.read_member("Plane/params.txt")
			check("ZIP exact member bytes", got.ok and got.value == content)
			check("unique case lookup", parsed.value.resolve("Plane", "PARAMS.TXT").value.case_adjusted)
			check("missing member", not parsed.value.resolve("Plane", "absent.ac").ok)
			check("unsafe dependency", not parsed.value.resolve("Plane", "../elsewhere").ok)
		bytes[30 + "Plane/params.txt".length()] ^= 1
		parsed = Archive.inspect(bytes)
		check("corrupt data refused on read", parsed.ok and not parsed.value.read_member("Plane/params.txt").ok)
	for path: String in ["../bad", "/bad", "C:/bad", "a/../bad", "a//bad", "a\\bad", "a./bad"]:
		check("unsafe ZIP path " + path, not Archive.inspect(_zip_bytes([[path, content]])).ok)
	check("case collision refused", not Archive.inspect(_zip_bytes([["a", content],["A", content]])).ok)
	var hinted := _zip_bytes([["Plane/",PackedByteArray()],["Plane/a",content]])
	var directory := hinted.decode_u32(hinted.size() - 6)
	hinted.encode_u32(22,472)
	hinted.encode_u32(directory + 24,472)
	hinted.encode_u32(directory + 38,16)
	var legacy := Archive.inspect(hinted)
	check("empty legacy directory hint is reported", legacy.ok and legacy.diagnostics.size() == 1)
	if legacy.ok:
		check("directory cannot be read as payload", not legacy.value.read_member("Plane/").ok)
		check("file after directory stays intact", legacy.value.read_member("Plane/a").value == content)
	hinted.encode_u32(14,1)
	hinted.encode_u32(directory + 16,1)
	check("directory exception requires zero CRC", not Archive.inspect(hinted).ok)
	var cut := _zip_bytes([["a", content]])
	check("truncated end record", not Archive.inspect(cut.slice(0, cut.size() - 1)).ok)
	var polls := [0]
	var checksum := Archive.crc32(_payload(10000), func() -> bool:
		polls[0] += 1
		return polls[0] == 2)
	check("CRC cancellation during a stored member", not checksum.ok and polls[0] == 2)
	var v5 := "verNumber 5.0\nmodelType 1.0\nmodelName Body.ac\n".to_ascii_buffer()
	var pack := Package.inspect_bytes(_zip_bytes([["Plane/params.txt",v5],["Plane/data/body.ac",content],["Plane/wavdata/params.txt",v5]]))
	check("nested sound parameter file is not another model", pack.ok and pack.value.models().size() == 1)
	if pack.ok:
		check("model references resolve unique case", pack.value.models()[0].ok and pack.value.models()[0].case_adjusted)
	var two := Package.inspect_bytes(_zip_bytes([["One/params.txt",v5],["One/data/body.ac",content],["Two/params.txt",v5],["Two/data/body.ac",content]]))
	check("pack inventory has two distinct model roots", two.ok and two.value.models().size() == 2)

func _params() -> void:
	var v5 := "verNumber 5.0\nmodelType 1.0\nmodelName Plane with spaces.ac\nbreakPart Wing 1 2\nbreakPart Tail 3 4\nunknownField 100.0 >=0, description\n"
	var result := Params.read(v5.to_ascii_buffer())
	check("v5 metadata", result.ok and result.value.version == 5 and result.value.model_name == "Plane with spaces.ac")
	check("ordered repeated observations", result.ok and result.value.records.size() == 6 and result.value.records[3].key == "breakPart" and result.value.records[4].key == "breakPart")
	check("bare annotation kept", result.ok and result.value.records[5].raw_rhs == "100.0 >=0, description")
	check("physics is explicitly unimported", result.ok and result.diagnostics[0].code == R.UNSUPPORTED_CAPABILITY)
	var v6 := "#begin params\nverNumber 6.0\nmodelType 1\nmodelName body.ac\n#end params\n#begin motor.left\nmotorRotatingMassDiam 1.0\nmotorRotatingMassDiam 1.0\n#end motor.left\n"
	check("sectioned v6 with retained duplicate", Params.read(v6.to_ascii_buffer()).ok)
	for text: String in [v5 + "verNumber 6.0\n", v5.replace("5.0", "5.000000000000001"), v5.replace("modelName", "ModelName"), v5.replace("Plane with spaces.ac", "../bad.ac"), v6.replace("#end motor.left", "#end motor.right"), v6.replace("6.0", "7.0"), v6 + "outOfSection 1\n", v6.replace("#end params", "#begin nested\n#end params")]:
		check("ambiguous or unsupported parameters refused", not Params.read(text.to_ascii_buffer()).ok)
	check("NUL refused", not Params.read(v5.to_ascii_buffer() + PackedByteArray([0])).ok)
	check("empty params refused", not Params.read(PackedByteArray()).ok)

func _ac3d() -> void:
	var text := _ac_fixture()
	var result := Ac3d.read(text.to_ascii_buffer())
	check("AC3Db hierarchy and surface read", result.ok and result.value.nodes.size() == 2 and result.value.nodes[1].surfaces.size() == 1)
	if result.ok:
		check("material ambient/specular retained", result.value.materials[0].ambient == [0.2,0.2,0.2] and result.value.materials[0].specular == [0.5,0.5,0.5])
	for bad: String in [text.replace("AC3Db", "AC3Dc"), text.replace("refs 3", "refs 2"), text.replace("0 0 0\n1 0 0", "1e999 0 0\n1 0 0"), text.replace("SURF 0x30", "SURF 0xFF"), text.replace("2 0 1", "9 0 1"), text.replace("numvert 3", "numvert 9999999")]:
		check("malformed or unsupported AC scene refused", not Ac3d.read(bad.to_ascii_buffer()).ok)
	var observed := [0]
	check("AC cancellation", not Ac3d.read(text.to_ascii_buffer(), func() -> bool:
		observed[0] += 1
		return observed[0] == 2).ok)
	var point := text.replace("SURF 0x30", "SURF 0x32").replace("refs 3\n0 0 0\n1 1 0\n2 0 1", "refs 1\n0 0 0")
	check("deliberate point marker retained", Ac3d.read(point.to_ascii_buffer()).ok)
	var short_polygon := point.replace("SURF 0x32","SURF 0x30")
	var retained := Ac3d.read(short_polygon.to_ascii_buffer())
	check("legacy short polygon is reported and retained", retained.ok and retained.value.degenerate_polygons == 1 and retained.diagnostics.size() == 1)

static func _ac_fixture() -> String:
	return "AC3Db\nMATERIAL \"m\" rgb 1 1 1 amb 0.2 0.2 0.2 emis 0 0 0 spec 0.5 0.5 0.5 shi 10 trans 0\nOBJECT world\nkids 1\nOBJECT poly\nname \"wing\"\nloc 1 2 3\nnumvert 3\n0 0 0\n1 0 0\n0 1 1\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 0 1\nkids 0\n"

static func _payload(size: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size)
	for at: int in size:
		bytes[at] = (at * 17 + (at >> 8)) & 255
	return bytes

static func _put_bits(bits: Array[int], value: int, width: int) -> void:
	for at: int in width:
		bits.append((value >> at) & 1)

static func _pack_bits(bits: Array[int]) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize((bits.size() + 7) / 8)
	for at: int in bits.size():
		bytes[at / 8] |= bits[at] << (at & 7)
	return bytes

## ZIP fixture fields written directly; CRC oracle for the primary vector is independently known.
static func _zip_bytes(entries: Array, compressed := false) -> PackedByteArray:
	var bytes := PackedByteArray()
	var central := PackedByteArray()
	for entry: Array in entries:
		var name := str(entry[0]).to_ascii_buffer()
		var payload: PackedByteArray = entry[1]
		var checksum := 0xFFFFFFFF
		for value: int in payload:
			checksum ^= value
			for bit: int in 8:
				checksum = (checksum >> 1) ^ (0xEDB88320 if checksum & 1 else 0)
		checksum ^= 0xFFFFFFFF
		var data := payload
		if compressed:
			var gzip := payload.compress(FileAccess.COMPRESSION_GZIP)
			data = gzip.slice(10, gzip.size() - 8)
		var local := PackedByteArray()
		local.resize(30)
		local.encode_u32(0, 0x04034B50)
		local.encode_u16(4, 20)
		local.encode_u16(8, 8 if compressed else 0)
		local.encode_u32(14, checksum)
		local.encode_u32(18, data.size())
		local.encode_u32(22, payload.size())
		local.encode_u16(26, name.size())
		var record := PackedByteArray()
		record.resize(46)
		record.encode_u32(0, 0x02014B50)
		record.encode_u16(4, 20)
		record.encode_u16(6, 20)
		record.encode_u16(10, 8 if compressed else 0)
		record.encode_u32(16, checksum)
		record.encode_u32(20, data.size())
		record.encode_u32(24, payload.size())
		record.encode_u16(28, name.size())
		record.encode_u32(42, bytes.size())
		local.append_array(name)
		local.append_array(data)
		bytes.append_array(local)
		record.append_array(name)
		central.append_array(record)
	var end := PackedByteArray()
	end.resize(22)
	end.encode_u32(0, 0x06054B50)
	end.encode_u16(8, entries.size())
	end.encode_u16(10, entries.size())
	end.encode_u32(12, central.size())
	end.encode_u32(16, bytes.size())
	bytes.append_array(central)
	bytes.append_array(end)
	return bytes
