extends SceneTree
## Focused checks of the Phoenix script container, GEO, texture and GLB writer (AC-PX).
## Every fixture is built here from the documented layout: no third-party bytes.
const R := preload("res://workshop/creator/result.gd")
const ScriptContainer := preload("res://workshop/creator/phoenix/script_container.gd")
const Geo := preload("res://workshop/creator/phoenix/geo.gd")
const PhoenixTexture := preload("res://workshop/creator/phoenix/texture.gd")
const GlbWriter := preload("res://workshop/creator/phoenix/glb_writer.gd")
const SourceImporter := preload("res://workshop/creator/source_importer.gd")
const Converter := preload("res://workshop/creator/phoenix/converter.gd")
const NO_MATERIAL := 0xFFFFFFFF
var failures := 0
var checks := 0


func _initialize() -> void:
	_script_container()
	_geo()
	_texture()
	_glb()
	_converter()
	print("Phoenix readers: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)


# ----------------------------------------------------------------------------------------- script

func _lua_string(buffer: StreamPeerBuffer, text: String) -> void:
	var raw := text.to_ascii_buffer()
	buffer.put_u32(raw.size() + 1)
	buffer.put_data(raw)
	buffer.put_u8(0)


func _abc(op: int, a: int, b: int, c: int) -> int:
	return op | (c << 6) | (b << 15) | (a << 24)


func _abx(op: int, a: int, bx: int) -> int:
	return op | (bx << 6) | (a << 24)


## modelTypes.demo = {name = "Demo", Size = 1.5}; plus a global table, a scalar, a sum and a symbol read.
func _demo_code() -> Array:
	return [_abx(5, 0, 0), _abx(10, 1, 0), _abc(9, 1, 252, 253), _abc(9, 1, 254, 255), _abc(9, 0, 251, 1),
		_abx(7, 1, 6), _abx(1, 2, 5), _abx(7, 2, 7), _abc(12, 3, 255, 255), _abx(7, 3, 8), _abc(6, 4, 0, 252),
		_abx(7, 4, 9), _abc(27, 0, 0, 0)]


func _lua_chunk(code: Array, number := 3.14159265358979323846E7, chosen: Array = []) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_data(PackedByteArray([0x1B, 0x4C, 0x75, 0x61, 0x50, 0x01, 0x04, 0x04, 0x04, 0x06, 0x08, 0x09, 0x09, 0x08]))
	buffer.put_double(number)
	_lua_string(buffer, "@demo.mod")
	buffer.put_32(0)
	for value: int in [0, 0, 0, 8]: # upvalues, parameters, vararg, stack
		buffer.put_u8(value)
	buffer.put_32(code.size())
	for _line: int in code.size():
		buffer.put_32(0)
	buffer.put_32(0) # locals
	buffer.put_32(0) # upvalue names
	var constants: Array = chosen if not chosen.is_empty() else ["modelTypes", "demo", "name", "Demo", "Size", 1.5,
		"demoTable", "scalar", "sum", "ref"]
	buffer.put_32(constants.size())
	for value: Variant in constants:
		if typeof(value) == TYPE_FLOAT:
			buffer.put_u8(3)
			buffer.put_double(value)
		else:
			buffer.put_u8(4)
			_lua_string(buffer, value)
	buffer.put_32(0) # nested functions
	buffer.put_32(code.size())
	for word: int in code:
		buffer.put_u32(word)
	return buffer.data_array


func _split(logical: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([0, 1, 2, 4, 8, 16, 32, 64])
	for index: int in logical.size():
		var first := (index * 37 + 11) & 0xFF
		out.append(first)
		out.append((logical[index] - first) & 0xFF)
	return out


func _script_container() -> void:
	var logical := _lua_chunk(_demo_code())
	var container := _split(logical)
	var unsplit := ScriptContainer.unsplit(container)
	check("unsplit restores the logical chunk", unsplit.ok and unsplit.value == logical)
	var parsed := ScriptContainer.read(container)
	check("demo script reads", parsed.ok)
	if parsed.ok:
		var value: Dictionary = parsed.value
		check("profile id", value.profile == ScriptContainer.PROFILE)
		check("source string", value.source == "@demo.mod")
		check("instruction and constant counts", value.instructions == 13 and value.constants == 10 and value.functions == 0)
		check("no diagnostics", value.diagnostics.is_empty())
		var assigned: Dictionary = value.assigned
		check("assignment into an unknown global", assigned.keys() == ["modelTypes.demo"])
		var demo: Dictionary = assigned.get("modelTypes.demo", {})
		check("assigned table content", demo.get("name") == "Demo" and demo.get("Size") == 1.5 and demo.size() == 2)
		var globals: Dictionary = value.globals
		check("global table", globals.get("demoTable") is Dictionary and globals.demoTable.get("name") == "Demo")
		check("global scalar", globals.get("scalar") == 1.5)
		check("whole number becomes int", typeof(globals.get("sum")) == TYPE_INT and globals.sum == 3)
		check("unknown global read is a symbol", globals.get("ref") == {"$symbol": "modelTypes.name"})
	var bad_magic := container.duplicate()
	bad_magic[0] = 1
	check("bad magic refused", not ScriptContainer.read(bad_magic).ok)
	check("short file refused", not ScriptContainer.read(PackedByteArray([0, 1, 2])).ok)
	var odd := container.duplicate()
	odd.append(0)
	var odd_result := ScriptContainer.read(odd)
	check("odd length refused", not odd_result.ok and odd_result.diagnostics[0].code == R.SOURCE_INVALID)
	var truncated := _split(logical.slice(0, logical.size() - 1))
	check("truncated chunk refused", not ScriptContainer.read(truncated).ok)
	check("trailing bytes refused", not ScriptContainer.read(_split(logical + PackedByteArray([0]))).ok)
	check("wrong test number refused", not ScriptContainer.read(_split(_lua_chunk(_demo_code(), 3.0))).ok)
	var wrong_header := logical.duplicate()
	wrong_header[4] = 0x51
	check("wrong Lua version refused", not ScriptContainer.read(_split(wrong_header)).ok)
	var jump := ScriptContainer.read(_split(_lua_chunk([_abx(5, 0, 0), _abx(20, 0, 5), _abc(27, 0, 0, 0)])))
	check("unsupported opcode is a diagnostic", jump.ok and jump.value.diagnostics == ["stopped at unsupported JMP (pc 1)"])
	var out_of_range := ScriptContainer.read(_split(_lua_chunk([_abx(1, 0, 9999)])))
	check("out-of-range constant refused", not out_of_range.ok)
	var table_misuse := ScriptContainer.read(_split(_lua_chunk([_abx(1, 0, 5), _abc(9, 0, 251, 251), _abc(27, 0, 0, 0)])))
	check("SETTABLE on a number is a diagnostic", table_misuse.ok and table_misuse.value.diagnostics.size() == 1)
	var unary := ScriptContainer.read(_split(_lua_chunk([_abx(5, 0, 0), _abc(17, 1, 0, 0), _abx(7, 1, 7), _abc(27, 0, 0, 0)])))
	check("symbol arithmetic stays an expression",
		unary.ok and unary.value.globals.get("scalar") == {"$expr": "-", "of": {"$symbol": "modelTypes"}})


# --------------------------------------------------------------------------------------------- geo

func _float_pad(buffer: StreamPeerBuffer, values: Array) -> void:
	for value: float in values:
		buffer.put_float(value)


func _fixed(text: String, length: int) -> PackedByteArray:
	var out := text.to_ascii_buffer()
	out.resize(length)
	return out


## nodes: [{name, material, triangles}] with one sub-mesh per node. Material 0 has a texture name.
func _geo_bytes(nodes: Array, material_count := 1, mutate := "") -> PackedByteArray:
	var triangles := 0
	for node: Dictionary in nodes:
		triangles += int(node.triangles)
	var buffer := StreamPeerBuffer.new()
	buffer.put_u32(1)
	buffer.put_u32(nodes.size())
	buffer.put_u32(0)
	buffer.put_u32(triangles)
	buffer.put_u8(0)
	_float_pad(buffer, [0.0, 0.0, 0.0, 1.0, 1.0, 2.0])
	buffer.put_u32(material_count)
	for index: int in material_count:
		var record := _fixed("Mat%d" % index, 128)
		record.resize(716)
		record.encode_u32(128, 2 if (mutate == "flag" and index == 0) else (1 if index == 0 else 0))
		if index == 0:
			record.encode_u8(132 + 0, 0)
			for at: int in "demo.bmp".length():
				record[132 + at] = "demo.bmp".unicode_at(at)
		record.encode_float(680, 0.25)
		record.encode_float(684, 0.5)
		record.encode_float(688, 0.75)
		buffer.put_data(record)
	buffer.put_u32(triangles * 3 + (1 if mutate == "vertices" else 0))
	var tri := 0
	for node: Dictionary in nodes:
		for _t: int in int(node.triangles):
			var ox := float(tri % 5)
			var oy := float(tri % 3)
			var oz := float(tri % 2) + 1.0
			var corners := [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]
			for corner: Array in corners:
				_float_pad(buffer, [ox + corner[0], oy + corner[1], oz + corner[2] * 0.5, 0.0, 0.0, 1.0, corner[0], corner[1]])
				_float_pad(buffer, [0.0, 0.0, 0.0, 0.0, 0.0])
			tri += 1
	buffer.put_u32(nodes.size())
	var cursor := 0
	for node: Dictionary in nodes:
		buffer.put_data(_fixed(str(node.name), 124))
		_float_pad(buffer, [0.0, 0.0])
		_float_pad(buffer, [0.0, 0.0, 0.0, 1.0, 1.0, 2.0])
		_float_pad(buffer, [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0])
		buffer.put_u32(1)
		_float_pad(buffer, [0.0, 0.0, 0.0, 1.0, 1.0, 1.0])
		buffer.put_u32(int(node.material))
		buffer.put_u32(0)
		buffer.put_u32(0)
		buffer.put_u16(0)
		buffer.put_u32(0xDEADBEEF) # heap pointer
		_float_pad(buffer, [0.0, 0.0, 0.0, 1.0, 1.0, 1.0])
		var end: int = cursor + int(node.triangles) * 3
		buffer.put_u32(cursor + (3 if mutate == "range" and node == nodes[1] else 0))
		buffer.put_u32(end)
		cursor = end
		buffer.put_u32(0)
	return buffer.data_array


func _demo_nodes() -> Array:
	return [{name = "wing", material = 0, triangles = 1}, {name = "fuse", material = NO_MATERIAL, triangles = 1},
		{name = "__col_" + "x".repeat(30), material = 0, triangles = 1}]


func _geo() -> void:
	var bytes := _geo_bytes(_demo_nodes())
	var parsed := Geo.parse(bytes)
	check("synthetic GEO parses", parsed.ok)
	if parsed.ok:
		var geo: Dictionary = parsed.value
		check("profile and header", geo.profile == Geo.PROFILE and geo.header.nodes == 3 and geo.header.triangles == 3
			and geo.header.version == 1)
		check("vertex count and offset", geo.vertex_count == 9 and geo.vertex_offset == 45 + 716 + 4)
		check("vertex data keeps the full stride", geo.vertex_data.size() == 9 * Geo.VERTEX_STRIDE_FLOATS)
		check("material name and texture", geo.materials.size() == 1 and geo.materials[0].name == "Mat0"
			and geo.materials[0].texture == "demo.bmp")
		check("material colour", geo.materials[0].diffuse == [0.25, 0.5, 0.75])
		var nodes: Array = geo.nodes
		check("roles", [nodes[0].role, nodes[1].role, nodes[2].role] == ["visual", "visual", "collision"])
		check("name overflow flagged", not nodes[0].name_overflow and nodes[2].name_overflow)
		check("contiguous sub ranges", nodes[0].subs[0].first == 0 and nodes[0].subs[0].end == 3
			and nodes[1].subs[0].first == 3 and nodes[2].subs[0].end == 9)
		check("no-material sentinel", nodes[0].subs[0].material == 0 and nodes[1].subs[0].material == -1)
		check("source identity", geo.sha256.length() == 64)
	var extra := bytes.duplicate()
	extra.append(0)
	check("one appended byte refused", not Geo.parse(extra).ok)
	check("truncated refused", not Geo.parse(bytes.slice(0, bytes.size() - 1)).ok)
	check("sub range gap refused", not Geo.parse(_geo_bytes(_demo_nodes(), 1, "range")).ok)
	check("bad material texture flag refused", not Geo.parse(_geo_bytes(_demo_nodes(), 1, "flag")).ok)
	check("vertex count mismatch refused", not Geo.parse(_geo_bytes(_demo_nodes(), 1, "vertices")).ok)
	var version := bytes.duplicate()
	version.encode_u32(0, 2)
	check("unknown version refused", not Geo.parse(version).ok)
	var material_index := bytes.duplicate()
	var first_node_at: int = Geo.parse(bytes).value.nodes[0].offset
	material_index.encode_u32(first_node_at + 224 + 24, 7)
	check("material index out of range refused", not Geo.parse(material_index).ok)
	var not_finite := bytes.duplicate()
	not_finite.encode_float(first_node_at + 132, INF)
	check("non-finite node bounds refused", not Geo.parse(not_finite).ok)
	var unresolved := bytes.duplicate()
	unresolved.encode_float(first_node_at + 124, NAN)
	check("unresolved writer floats are not checked", Geo.parse(unresolved).ok)
	var wrong_nodes := bytes.duplicate()
	wrong_nodes.encode_u32(4, 2)
	check("header node count mismatch refused", not Geo.parse(wrong_nodes).ok)
	check("empty file refused", not Geo.parse(PackedByteArray()).ok)


# ---------------------------------------------------------------------------------------- texture

## Magic, 53 filler bytes, 8 x 8 BGR rows stored bottom-up from byte 61 and one trailing byte.
func _texture_bytes() -> PackedByteArray:
	var out := PackedByteArray([0xFF, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02])
	for index: int in 53:
		out.append((index * 13 + 5) & 0xFF)
	for row: int in 8: # stored row 0 is the bottom row
		for x: int in 8:
			out.append(10 + x) # blue
			out.append(20 + row) # green
			out.append(30 + x + row * 8) # red
	out.append(99)
	return out


func _texture() -> void:
	var bytes := _texture_bytes()
	var profile := PhoenixTexture.texture_profile(bytes)
	check("texture profile", profile.ok and profile.value.kind == "phoenix raw" and profile.value.width == 8
		and profile.value.height == 8 and profile.value.channels == 3 and profile.value.pixel_offset == 61)
	check("candidate layouts counted", profile.ok and profile.value.candidates == 3)
	var decoded := PhoenixTexture.decode(bytes)
	check("texture decodes", decoded.ok)
	if decoded.ok:
		var image: Image = decoded.value.image
		check("image size and format", image.get_width() == 8 and image.get_height() == 8 and image.get_format() == Image.FORMAT_RGB8)
		var correct := true
		for y: int in 8:
			for x: int in 8:
				var pixel := image.get_pixel(x, y)
				# Top row of the image is the last stored row; channels are swapped to RGB.
				correct = correct and pixel.r8 == 30 + x + (7 - y) * 8 and pixel.g8 == 20 + (7 - y) and pixel.b8 == 10 + x
		check("pixel colours and bottom-up orientation", correct)
		check("texture identity", decoded.value.sha256.length() == 64)
	check("standard BMP is not converted", PhoenixTexture.texture_profile("BM".to_ascii_buffer() + PackedByteArray([0, 0])).ok
		and not PhoenixTexture.decode("BM".to_ascii_buffer() + PackedByteArray([0, 0])).ok)
	var wrong_magic := bytes.duplicate()
	wrong_magic[0] = 0
	check("unknown signature refused", not PhoenixTexture.decode(wrong_magic).ok)
	check("odd layout refused", not PhoenixTexture.decode(bytes.slice(0, bytes.size() - 1)).ok)
	# 4-channel: magic, 54 filler bytes, 4 x 4 BGRA rows stored bottom-up from byte 62, two trailing bytes.
	var four := PackedByteArray([0xFF, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02])
	for index: int in 54:
		four.append(7)
	for row: int in 4:
		for x: int in 4:
			four.append_array(PackedByteArray([40 + x, 50 + row, 60, 100 + row * 4 + x]))
	four.append_array(PackedByteArray([0, 0]))
	var four_result := PhoenixTexture.decode(four)
	check("four channel texture decodes as RGBA", four_result.ok and four_result.value.has_alpha
		and four_result.value.image.get_format() == Image.FORMAT_RGBA8 and four_result.value.profile.pixel_offset == 62)
	if four_result.ok:
		var top_left: Color = four_result.value.image.get_pixel(0, 0)
		check("BGRA order and bottom-up rows", top_left.r8 == 60 and top_left.g8 == 53 and top_left.b8 == 40
			and top_left.a8 == 112)
		check("mean alpha", is_equal_approx(float(four_result.value.mean[3]), (100.0 + 115.0) / 2.0 / 255.0))


# -------------------------------------------------------------------------------------------- glb

func _chunk_json(glb: PackedByteArray) -> Dictionary:
	var length := glb.decode_u32(12)
	var parsed: Variant = JSON.parse_string(glb.slice(20, 20 + length).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _glb() -> void:
	var geo: Dictionary = Geo.parse(_geo_bytes(_demo_nodes())).value
	var texture: Dictionary = PhoenixTexture.decode(_texture_bytes()).value
	var built := GlbWriter.build(geo, texture, 2.0)
	check("GLB builds", built.ok)
	if built.ok:
		var value: Dictionary = built.value
		check("visual nodes only", value.visual_nodes == 2 and value.meshes == 2 and value.triangles == 2 and not value.merged)
		var admitted := SourceImporter.inspect_bytes(value.bytes, "demo.glb")
		check("Creator admission accepts the textured GLB", admitted.ok)
		if admitted.ok:
			var source: Object = admitted.value
			check("admitted as GLB with embedded PNG", source.format() == "glb" and source.details().counts.images == 1
				and source.details().counts.triangles == 2)
			check("scale is applied", is_equal_approx(source.bounds_max()[0], 4.0))
		var json := _chunk_json(value.bytes)
		var receipt: Dictionary = json.get("asset", {}).get("extras", {}).get("openrc_phoenix", {})
		check("receipt", receipt.get("format") == "openrc-phoenix-visual-v1" and receipt.get("geo_sha256") == geo.sha256
			and receipt.get("texture_sha256") == texture.sha256 and receipt.get("scale") == 2.0
			and receipt.get("physics_imported") == false)
		var materials: Array = json.get("materials", [])
		check("textured material", materials.size() == 1 and materials[0].pbrMetallicRoughness.has("baseColorTexture"))
		check("collision node omitted", json.get("nodes", []).size() == 2)
	var untextured := GlbWriter.build(geo)
	check("GLB without a texture builds", untextured.ok and SourceImporter.inspect_bytes(untextured.value.bytes, "plain.glb").ok)
	if untextured.ok:
		var colors: Array = _chunk_json(untextured.value.bytes).materials[0].pbrMetallicRoughness.baseColorFactor
		check("diffuse colour used without a texture", colors == [0.25, 0.5, 0.75, 1.0])
	check("bad scale refused", not GlbWriter.build(geo, {}, 0.0).ok and not GlbWriter.build(geo, {}, NAN).ok)
	# More visual nodes than the mesh ceiling: merged per material and reported.
	var many: Array = []
	for index: int in 140:
		many.append({name = "part%d" % index, material = index % 2, triangles = 1})
	var wide := Geo.parse(_geo_bytes(many, 2))
	check("wide synthetic GEO parses", wide.ok)
	if wide.ok:
		var merged := GlbWriter.build(wide.value)
		check("over-limit part count is merged", merged.ok and merged.value.merged and merged.value.meshes == 2
			and merged.value.primitives == 2 and merged.value.triangles == 140)
		check("merge is reported", merged.ok and merged.diagnostics.size() == 1
			and merged.diagnostics[0].severity == R.SEVERITY_WARNING)
		check("merged GLB admitted", merged.ok and SourceImporter.inspect_bytes(merged.value.bytes, "merged.glb").ok)


# -------------------------------------------------------------------------------------- converter

## modelTypes.demo = {name = "Demo", attributes = {Physical = {Size = 1.5}},
##   airfoils = {{isMirrored = 1, attributes = {Position = {x = 0, y = 2, z = 3}, Length = 0.75}}}}
func _model_chunk(with_size := true, display := "Demo") -> PackedByteArray:
	var constants: Array = ["modelTypes", "demo", "name", display, "attributes", "Physical", "Size" if with_size else "Mass",
		1.5, "airfoils", "isMirrored", 1.0, "Position", "x", 0.0, "y", 2.0, "z", 3.0, "Length", 0.75]
	var k := func(index: int) -> int: return 250 + index
	var code: Array = [_abx(5, 0, 0), _abx(10, 1, 0), _abc(9, 1, k.call(2), k.call(3)),
		_abx(10, 2, 0), _abx(10, 3, 0), _abc(9, 3, k.call(6), k.call(7)), _abc(9, 2, k.call(5), 3),
		_abc(9, 1, k.call(4), 2), _abx(10, 2, 0), _abx(10, 3, 0), _abc(9, 3, k.call(9), k.call(10)),
		_abx(10, 4, 0), _abx(10, 5, 0), _abc(9, 5, k.call(12), k.call(13)), _abc(9, 5, k.call(14), k.call(15)),
		_abc(9, 5, k.call(16), k.call(17)), _abc(9, 4, k.call(11), 5), _abc(9, 4, k.call(18), k.call(19)),
		_abc(9, 3, k.call(4), 4), _abx(31, 2, 0), _abc(9, 1, k.call(8), 2), _abc(9, 0, k.call(1), 1), _abc(27, 0, 0, 0)]
	return _split(_lua_chunk(code, 3.14159265358979323846E7, constants))


func _write(folder: String, name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _converter() -> void:
	var folder := OS.get_user_data_dir().path_join("phoenix_converter_test")
	DirAccess.make_dir_recursive_absolute(folder)
	var nodes: Array = [{name = "wing", material = 0, triangles = 2}, {name = "fuse", material = 0, triangles = 2}]
	_write(folder, "demo.mod", _model_chunk())
	_write(folder, "demo.geo", _geo_bytes(nodes))
	_write(folder, "DEMO.BMP", _texture_bytes())
	var converted: Dictionary = Converter.convert(folder.path_join("demo.mod"))
	check("installed model converts", converted.ok)
	if converted.ok:
		var value: Dictionary = converted.value
		check("placement follows the Phoenix frame", value.placement.nose_axis == "+z" and value.placement.up_axis == "+y"
			and value.placement.units == "m")
		var datum: Array = value.placement.datum
		check("datum is the main-wing root leading edge in metres", datum.size() == 3 and is_equal_approx(datum[0], 0.0)
			and is_equal_approx(datum[1], 0.03) and is_equal_approx(datum[2], 0.045))
		check("decoded span", is_equal_approx(float(value.summary.wings[0].span_m), 1.5))
		check("texture resolved case-insensitively", value.receipt.textures.has("DEMO.BMP"))
		var document := _chunk_json(value.source.source_bytes())
		var receipt: Dictionary = document.asset.extras.openrc_phoenix
		check("receipt identifies the model and imports no physics", receipt.model_id == "demo"
			and receipt.physics_imported == false and receipt.format == GlbWriter.FORMAT_ID)
		check("textured material", document.has("images") and document.materials[0].pbrMetallicRoughness.has("baseColorTexture"))
		check("appearance-only note", converted.diagnostics.any(func(d: Dictionary) -> bool:
			return d.message == Converter.APPEARANCE_ONLY))
	_write(folder, "nosize.mod", _model_chunk(false))
	_write(folder, "nosize.geo", _geo_bytes(nodes))
	check("model without size refused", not Converter.convert(folder.path_join("nosize.mod")).ok)
	_write(folder, "lonely.mod", _model_chunk())
	var lonely: Dictionary = Converter.convert(folder.path_join("lonely.mod"))
	check("missing geometry refused", not lonely.ok and lonely.diagnostics[0].code == R.DEPENDENCY_MISSING)
	_write(folder, "plain.mod", "modelTypes.demo = {}".to_ascii_buffer())
	check("text that is not the container refused", not Converter.convert(folder.path_join("plain.mod")).ok)
	_write(folder, "slash.mod", _model_chunk(true, "F/A-18: \"X\""))
	_write(folder, "slash.geo", _geo_bytes(nodes))
	var slash: Dictionary = Converter.convert(folder.path_join("slash.mod"))
	check("path characters in the model name never reach the source file name", slash.ok
		and slash.value.source.file_name() == "slash.glb" and slash.value.summary.name == "F/A-18: \"X\"")
	var cyclic := _split(_lua_chunk([_abx(10, 0, 0), _abc(9, 0, 251, 0), _abc(9, 0, 252, 0), _abx(7, 0, 0),
		_abc(27, 0, 0, 0)], 3.14159265358979323846E7, ["t", "a", "b"]))
	var started := Time.get_ticks_msec()
	var refused: Dictionary = ScriptContainer.read(cyclic)
	check("self-referencing table is bounded and refused", not refused.ok
		and refused.diagnostics[0].code == R.SOURCE_LIMIT and Time.get_ticks_msec() - started < 10000)
	var stop := ScriptContainer.read(_split(_lua_chunk(_demo_code())), func() -> bool: return true)
	check("cancel callable accepted", stop.ok or stop.diagnostics[0].message == "The import was cancelled.")
	for name: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
