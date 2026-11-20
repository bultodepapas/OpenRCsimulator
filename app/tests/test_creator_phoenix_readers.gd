extends SceneTree
## Focused checks of the Phoenix script container, GEO, texture and GLB writer (AC-PX).
## Every fixture is built here from the documented layout: no third-party bytes.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Session := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CreatorTrial := preload("res://workshop/creator/trial.gd")
const ScriptContainer := preload("res://workshop/creator/phoenix/script_container.gd")
const Geo := preload("res://workshop/creator/phoenix/geo.gd")
const PhoenixTexture := preload("res://workshop/creator/phoenix/texture.gd")
const GlbWriter := preload("res://workshop/creator/phoenix/glb_writer.gd")
const SourceImporter := preload("res://workshop/creator/source_importer.gd")
const Converter := preload("res://workshop/creator/phoenix/converter.gd")
const VisualBuilderRef := preload("res://workshop/creator/visual_builder.gd")
const PhoenixSetup := preload("res://workshop/creator/phoenix/setup.gd")
const PhoenixPhysics := preload("res://workshop/creator/phoenix/physics.gd")
const Packages := preload("res://workshop/creator/packages.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const ClearViewSetup := preload("res://workshop/creator/clearview/setup.gd")
const ClearViewDonor := preload("res://workshop/creator/clearview/donor.gd")
const NO_MATERIAL := 0xFFFFFFFF
var failures := 0
var checks := 0


func _initialize() -> void:
	_script_container()
	_geo()
	_texture()
	_glb()
	_converter()
	_articulation()
	_layout()
	_setup()
	_biplane()
	_physics()
	_physics_propulsion()
	_physics_untrusted()
	_import_hardening()
	_physics_tuning()
	_landing_gear()
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
		record.encode_u32(128, 2 if (mutate == "flag" and index == 0) else (1 if index == 0 or mutate == "textures" else 0))
		if index == 0 or mutate == "textures":
			var texture_name := "t%d.bmp" % index if mutate == "textures" else "demo.bmp"
			for at: int in texture_name.length():
				record[132 + at] = texture_name.unicode_at(at)
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


# ----------------------------------------------------------------------------------- articulation

## Decoded-definition shape (as the script container returns it) with a mirrored aileron pair, a
## one-piece elevator, a rudder and a propeller.
func _articulated_model() -> Dictionary:
	return {airfoils = [
		{isMirrored = 1, controlSurfaces = [{attributes = {Input = "Left Aileron"},
			root_pivot = {x = 1.0, y = 0.5, z = 1.0}, tip_pivot = {x = 4.0, y = 0.5, z = 1.0},
			sides = [["wing"], ["fuse"]]}]},
		{isMirrored = 1, controlSurfaces = [{attributes = {Input = "Left Elevator"},
			root_pivot = {x = -2.0, y = 0.0, z = -3.0}, tip_pivot = {x = 2.0, y = 0.0, z = -3.0}, sides = [["tail"], {}]}]},
		{isMirrored = 0, controlSurfaces = [{attributes = {Input = "Rudder"},
			root_pivot = {x = 0.0, y = 0.0, z = -3.0}, tip_pivot = {x = 0.0, y = 2.0, z = -3.0}, sides = [["fin"], {}]}]}],
		propulsion = [{type = "propeller", pivot = {x = 0.0, y = 0.5, z = 2.0}, spinDirection = 1,
			spinGeometry = ["hub"], blurGeometry = ["blades"]}]}


func _articulation() -> void:
	var groups: Array = Converter.articulation_groups(_articulated_model())
	var roles: Array = groups.map(func(g: Dictionary) -> String: return g.role)
	check("articulation roles", roles == ["aileron_left", "aileron_right", "elevator", "rudder", "propeller"])
	if groups.size() == 5:
		check("left aileron hinge points left with a positive sign", groups[0].hinge == [3.0, 0.0, 0.0] and groups[0].sign == 1)
		check("right aileron is the mirror image", groups[1].origin == [-1.0, 0.5, 1.0] and groups[1].hinge == [-3.0, 0.0, 0.0]
			and groups[1].sign == -1)
		check("rudder sign follows the up axis", groups[3].sign == 1 and groups[3].axis == "x")
		check("propeller groups spin and blur geometry", groups[4].nodes == ["hub", "blades"] and groups[4].axis == "z"
			and groups[4].hinge.is_empty())
	var nodes: Array = [{name = "wing", material = 0, triangles = 2}, {name = "fuse", material = 0, triangles = 2},
		{name = "body", material = 0, triangles = 2}]
	var geo: Dictionary = Geo.parse(_geo_bytes(nodes)).value
	var hinge := [{role = "aileron_left", nodes = ["wing"], origin = [1.0, 0.5, 1.0], hinge = [3.0, 0.0, 1.0],
		axis = "x", sign = 1}, {role = "propeller", nodes = ["fuse"], origin = [0.0, 0.5, 2.0], hinge = [], axis = "z",
		sign = 1}]
	var built := GlbWriter.build(geo, {}, 0.5, {}, hinge)
	check("articulated GLB builds", built.ok and built.value.pivots.size() == 2)
	if not built.ok:
		return
	var document := _chunk_json(built.value.bytes)
	var pivot: Dictionary = document.nodes[int(built.value.pivots[0].node)]
	check("pivot carries the part hint", pivot.extras.openrc_creator_part.axis == "x" and pivot.children.size() == 1)
	# Neutral pose: every child vertex mapped through the pivot matrix lands on the original scaled point.
	var m: Array = pivot.matrix
	var child: Dictionary = document.nodes[int(pivot.children[0])]
	var accessor: Dictionary = document.meshes[int(child.mesh)].primitives[0].attributes
	var positions := _accessor_floats(built.value.bytes, document, int(accessor.POSITION))
	var original: PackedFloat32Array = geo.vertex_data
	var first := Vector3(m[0] * positions[0] + m[4] * positions[1] + m[8] * positions[2] + m[12],
		m[1] * positions[0] + m[5] * positions[1] + m[9] * positions[2] + m[13],
		m[2] * positions[0] + m[6] * positions[1] + m[10] * positions[2] + m[14])
	check("neutral pose is unchanged", first.is_equal_approx(Vector3(original[0], original[1], original[2]) * 0.5))
	var admitted := SourceImporter.inspect_bytes(built.value.bytes, "pivots.glb")
	check("articulated GLB admitted", admitted.ok)
	if admitted.ok:
		var bindings := Converter.proposed_bindings(built.value.pivots)
		var checked: Dictionary = VisualBuilderRef.validate_bindings(admitted.value, bindings)
		check("proposed bindings validate", checked.ok and checked.value.controls.has("aileron_left")
			and checked.value.propeller.axis == "z")
	var glassy: Dictionary = Geo.parse(_geo_bytes(nodes)).value
	glassy.materials[0].name = "canopy_glass"
	glassy.materials[0].texture = null
	var glass_built := GlbWriter.build(glassy, {}, 1.0)
	var glass_doc: Dictionary = _chunk_json(glass_built.value.bytes) if glass_built.ok else {}
	check("untextured glass is translucent", glass_built.ok and glass_doc.materials[0].get("alphaMode") == "BLEND"
		and float(glass_doc.materials[0].pbrMetallicRoughness.baseColorFactor[3]) < 1.0)


func _accessor_floats(glb: PackedByteArray, document: Dictionary, index: int) -> PackedFloat32Array:
	var accessor: Dictionary = document.accessors[index]
	var view: Dictionary = document.bufferViews[int(accessor.bufferView)]
	var json_length := glb.decode_u32(12)
	var bin_start := 20 + json_length + 8
	var start := bin_start + int(view.get("byteOffset", 0))
	return glb.slice(start, start + int(view.byteLength)).to_float32_array()


func _layout() -> void:
	var model := {airfoils = [
		{isMirrored = 1, attributes = {Position = {x = 0.0, y = 2.0, z = 3.0}, Length = 0.75, Root_chord = 0.25,
			Tip_chord = 0.2, Dihedral = 3.0},
			controlSurfaces = [{attributes = {Input = "Left Aileron", Length = 0.3, Max_travel = 20.0}}]},
		{isMirrored = 1, attributes = {Position = {x = 0.0, y = 2.5, z = -40.0}, Length = 0.25, Root_chord = 0.12,
			Tip_chord = 0.1}, controlSurfaces = [{attributes = {Input = "Left Elevator", Length = 0.2, Max_travel = 15.0}}]},
		{isMirrored = 0, attributes = {Position = {x = 0.0, y = 3.0, z = -41.0}, Length = 0.2, Root_chord = 0.14,
			Tip_chord = 0.06}, controlSurfaces = [{attributes = {Input = "Rudder", Length = 0.1, Max_travel = 25.0}}]}],
		propulsion = [{type = "propeller", pivot = {x = 0.0, y = 2.0, z = 10.0}}]}
	var values: Dictionary = Converter.definition_values(model, 0.01, [0.0, 0.02, 0.03])
	var expected := {"wing/span": 1.5, "wing/root_chord": 0.25, "wing/tip_chord": 0.2, "wing/dihedral_deg": 3.0,
		"horizontal_tail/span": 0.5, "horizontal_tail/chord": 0.11, "horizontal_tail/position/0": 0.43,
		"horizontal_tail/position/2": 0.005, "vertical_tail/height": 0.2, "vertical_tail/chord": 0.1,
		"vertical_tail/position/0": 0.44, "vertical_tail/position/2": 0.01, "equipment/hub_position/0": -0.07,
		"equipment/hub_position/1": 0.0, "equipment/hub_position/2": 0.0, "fuselage/nose_x": -0.04,
		"fuselage/center_z": 0.0, "controls/aileron_deg": 20.0,
		"controls/elevator_deg": 15.0, "controls/rudder_deg": 25.0}
	var matching := values.size() == expected.size()
	for path: String in expected:
		matching = matching and values.has(path) and is_equal_approx(float(values[path]), float(expected[path]))
	check("Phoenix layout maps into the Creator structural frame", matching)
	check("no layout without a datum", Converter.definition_values(model, 0.01, []).is_empty())


# ------------------------------------------------------------------------------------------ setup

func _setup() -> void:
	var fit: Dictionary = PhoenixSetup.fit_planform(1.6, 0.4, 0.12)
	check("a planform outside the taper and aspect ranges is fitted", fit.changed
		and is_equal_approx(fit.tip / fit.root, 0.6 * 1.005) and 1.6 / (0.5 * (fit.root + fit.tip)) >= 4.0)
	check("an in-range planform is kept", not PhoenixSetup.fit_planform(1.5, 0.25, 0.2).changed)
	var nodes: Array = [{name = "wing", material = 0, triangles = 2}, {name = "fuse", material = 0, triangles = 2},
		{name = "body", material = 0, triangles = 2}]
	var geo: Dictionary = Geo.parse(_geo_bytes(nodes)).value
	var data := {datum = [0.0, 1.0, 1.5], half_span_m = 1.5, root_chord_m = 0.3, tip_chord_m = 0.25, dihedral_deg = 3.0,
		propeller_found = true, pusher = false, biplane = true,
		layout = {"horizontal_tail/span": 0.6, "controls/elevator_deg": 45.0, "equipment/hub_position/0": -0.2}}
	var plain := GlbWriter.build(geo, {}, 1.0, {creator_setup = data})
	var marked := GlbWriter.build(geo, {}, 1.0, {creator_setup = data}, [], [Installation.PHOENIX_NAMESPACE])
	var plain_source: Variant = SourceImporter.inspect_bytes(plain.value.bytes, "plain.glb").value
	var source: Variant = SourceImporter.inspect_bytes(marked.value.bytes, "marked.glb").value
	check("only the aeroplane marker makes a Phoenix provider source", Installation.provider(plain_source) == ""
		and Installation.provider(source) == "phoenix" and Installation.required(source))
	check("Phoenix sources get their own messages", Installation.flight_unavailable(source) == Installation.PHOENIX_FLIGHT_UNAVAILABLE
		and Installation.flight_unavailable(plain_source) == Installation.FLIGHT_UNAVAILABLE)
	check("ClearView setup and donors refuse a Phoenix source", not ClearViewSetup.propose(source, [[0.9, 2.2]]).ok
		and not ClearViewDonor.propose(source, true).ok)
	var proposed: Dictionary = PhoenixSetup.propose(source, Authoring.span_domain())
	check("Phoenix setup proposes from the receipt", proposed.ok)
	if not proposed.ok:
		return
	var value: Dictionary = proposed.value
	check("a 3 m model is scaled into the trainer class", value.scaled and value.range_index == 1
		and float(value.flown_span_m) < float(value.source_span_m) and value.units == "")
	check("throws are limited to the package range", value.throws_fitted and float(value.layout["controls/elevator_deg"]) == 30.0)
	check("biplane and propeller flags pass through", value.biplane and value.propeller_found and not value.pusher)
	check("the setup can resize metres set at import", value.owns_scale)
	check("ordinary sources get no Phoenix setup", not PhoenixSetup.propose(plain_source, Authoring.span_domain()).ok)
	var doc := Authoring.new()
	doc.set_source(source)
	doc.set_axis("nose_axis", "+z")
	doc.set_axis("up_axis", "+y")
	doc.set_units("m")
	doc.set_datum([0.0, 1.0, 1.5])
	check("a Phoenix source needs a declared configuration", doc.needs_source_installation())
	var applied: Dictionary = doc.apply_clearview_setup(value, doc.revision)
	check("the shared setup declares the estimated configuration", applied.ok and not doc.needs_source_installation())
	if applied.ok:
		check("the model was resized for the trainer class", float(doc.placement().unit_scale) < 1.0)
		check("the decoded tail span enters as an estimate", doc.is_estimated("horizontal_tail/span"))


func _biplane() -> void:
	# Ailerons only on the narrower lower wing: the reference wing is still the widest, and both wings'
	# area forms the equivalent wing at the main wing's span and taper.
	var model := {airfoils = [
		{isMirrored = 1, attributes = {Position = {x = 0.0, y = 20.0, z = 2.0}, Length = 0.8, Root_chord = 0.2,
			Tip_chord = 0.2, Dihedral = 0.0}},
		{isMirrored = 1, attributes = {Position = {x = 0.0, y = 0.0, z = 4.0}, Length = 0.7, Root_chord = 0.2,
			Tip_chord = 0.2, Dihedral = 4.0},
			controlSurfaces = [{attributes = {Input = "Left Aileron", Length = 0.3, Max_travel = 20.0}}]}]}
	var summary: Dictionary = Converter.summarize(model, 0.01)
	var lifting: Array = Converter.lifting_wings(summary)
	check("stacked wings are found, widest first", lifting.size() == 2 and is_equal_approx(float(lifting[0].span_m), 1.6))
	var values: Dictionary = Converter.definition_values(model, 0.01, [0.0, 0.1, 0.03], lifting)
	var area := 1.6 * 0.2 + 1.4 * 0.2
	check("equivalent wing keeps the widest span and adds the area", is_equal_approx(float(values["wing/span"]), 1.6)
		and is_equal_approx(float(values["wing/root_chord"]) * 1.6, area) and is_equal_approx(float(values["wing/dihedral_deg"]), 2.0))


# ---------------------------------------------------------------------------------------- physics

## A synthetic section polar with known answers: CL = 0.1 + 5.7·α (rad) to 12°,
## a 1.35 peak to 14°, then stalled; negative peak −1.0; CD 0.01 + 0.0005·α²(deg).
func _synthetic_polar() -> Array:
	var out: Array = []
	for step: int in range(-180, 181):
		var a := step * 0.5
		var cl := 0.1 + 5.7 * deg_to_rad(a)
		if a > 12.0:
			cl = 1.35 if a <= 14.0 else maxf(0.6, 1.35 - 0.05 * (a - 14.0))
		if cl < -1.0:
			cl = -1.0
		out.append_array([a, cl, 0.01 + 0.0005 * a * a])
	return out


func _physics_model(prop_diameter := 0.25, rpm := 9000.0) -> Dictionary:
	return {attributes = {Physical = {Weight = 1.5, Size = 1.5, Centre_of_gravity = {x = 0.0, y = 2.0, z = -5.0},
		Fuselage_drag_area = {frontal = 0.006}}},
		airfoils = [
			{isMirrored = 1, attributes = {Airfoil = "Synthetic", Position = {x = 0.0, y = 2.0, z = 3.0}, Length = 0.75,
				Root_chord = 0.25, Tip_chord = 0.2, Dihedral = 3.0, Incidence = 1.0},
				controlSurfaces = [{attributes = {Input = "Left Aileron", Length = 0.3, Tip_distance = 0.05,
					Root_chord = 0.06, Tip_chord = 0.05, Max_travel = 20.0}}]},
			{isMirrored = 1, attributes = {Airfoil = "Synthetic", Position = {x = 0.0, y = 2.5, z = -40.0}, Length = 0.25,
				Root_chord = 0.12, Tip_chord = 0.1},
				controlSurfaces = [{attributes = {Input = "Left Elevator", Length = 0.2, Root_chord = 0.04, Tip_chord = 0.04}}]}],
		propulsion = [{type = "propeller", attributes = {Diameter = prop_diameter, Pitch = 0.15, Max_RPM = rpm, Blade_count = 2}}]}


func _physics() -> void:
	var polar := PhoenixPhysics.reduce_polar(_synthetic_polar(), 1.0)
	check("polar slope, zero lift and incidence lift", is_equal_approx(snappedf(polar.slope, 0.01), 5.7)
		and is_equal_approx(snappedf(polar.cl_zero, 0.001), 0.1) and absf(polar.cl_at_incidence - (0.1 + 5.7 * deg_to_rad(1.0))) < 1e-3)
	check("polar peaks and minimum drag", is_equal_approx(polar.cl_max, 1.35) and is_equal_approx(polar.cl_min, -1.0)
		and is_equal_approx(polar.cd_min, 0.01) and polar.stall_width_deg >= 2.0 and polar.stall_width_deg <= 15.0)
	var theta := acos(2.0 * 0.25 - 1.0)
	check("plain-flap effectiveness", is_equal_approx(PhoenixPhysics.flap_tau(0.25), 0.85 * (1.0 - (theta - sin(theta)) / PI)))
	var model := _physics_model()
	var block := PhoenixPhysics.physics_block(model, 0.01, [0.0, 0.02, 0.03], {"Synthetic": _synthetic_polar()},
		model.airfoils[0], model.airfoils[1], null)
	check("physics block from the decoded model", block.get("format") == PhoenixPhysics.FORMAT and is_equal_approx(block.mass_kg, 1.5)
		and is_equal_approx(block.cg_aft_m, 0.08) and block.has("aileron_roll_power") and block.has("elevator_effectiveness")
		and is_equal_approx(block.propeller.max_rpm, 9000.0))
	var ids := PhoenixPhysics.derive(block, "conventional-trainer-estimated-v1", "electric-3s-1250kv-9x6-estimated-v1", 1.0)
	check("derived packages are registered", not ids.is_empty())
	if ids.is_empty():
		return
	var airframe: Dictionary = Packages.airframe(ids.airframe)
	var power: Dictionary = Packages.power(ids.power)
	check("derived packages resolve and pass the package checks", airframe.ok and power.ok)
	if airframe.ok and power.ok:
		check("Phoenix section efficiency and drag", is_equal_approx(float(airframe.value.wing.oswald_efficiency.value), 0.85)
			and float(airframe.value.wing.profile_drag.value) > 0.01 and str(airframe.value.wing.profile_drag.source).contains("Phoenix"))
		check("Phoenix propeller diameter and RPM", float(power.value.propeller.diameter.value) <= 0.25 + 1e-9
			and float(power.value.motor.kv_rpm_per_volt.value) > 0.0)
	check("a saved draft re-derives the same ids", PhoenixPhysics.restore(block, ids.airframe, ids.power))
	var altered := block.duplicate(true)
	altered.mass_kg = 2.0
	check("an altered physics block does not restore", not PhoenixPhysics.restore(altered, ids.airframe, ids.power))
	check("mixed ids do not restore", not PhoenixPhysics.restore(block, ids.power, ids.airframe))
	# A huge propeller: the runtime's static thrust is held at the cap by a smaller physical diameter.
	var big := _physics_model(0.45, 12000.0)
	var big_block := PhoenixPhysics.physics_block(big, 0.01, [0.0, 0.02, 0.03], {"Synthetic": _synthetic_polar()},
		big.airfoils[0], big.airfoils[1], null)
	var big_ids := PhoenixPhysics.derive(big_block, "conventional-trainer-estimated-v1", "electric-4s-800kv-apc12x6-estimated-v1", 1.0)
	if not big_ids.is_empty():
		var big_power: Dictionary = Packages.power(big_ids.power)
		var probe: Dictionary = big_power.value.duplicate(true)
		probe.id = "probe-big-thrust"
		var point: Dictionary = Packages.static_thrust(probe, 1.0)
		check("static thrust held at the cap", point.get("ok", false)
			and float(point.thrust_n) <= PhoenixPhysics.THRUST_CAP * 1.5 * Packages.GRAVITY * 1.03
			and float(big_power.value.propeller.diameter.value) < 0.45)
	else:
		check("static thrust held at the cap", false)


## Static thrust (N) of the derived power package for `model`, with its id prefix.
func _derived_static_thrust(model: Dictionary, power_base: String) -> Dictionary:
	var block := PhoenixPhysics.physics_block(model, 0.01, [0.0, 0.02, 0.03], {"Synthetic": _synthetic_polar()},
		model.airfoils[0], model.airfoils[1], null)
	var ids := PhoenixPhysics.derive(block, "conventional-trainer-estimated-v1", power_base, 1.0)
	if ids.is_empty():
		return {}
	var power: Dictionary = Packages.power(ids.power)
	if not power.ok:
		return {}
	var probe: Dictionary = power.value.duplicate(true)
	probe.id = "probe-%s" % ids.power.sha256_text().substr(0, 8)
	var point: Dictionary = Packages.static_thrust(probe, 1.0)
	return {block = block, power = power.value, thrust = float(point.get("thrust_n", NAN))}


func _physics_propulsion() -> void:
	var base := "electric-3s-1250kv-9x6-estimated-v1"
	var single := _derived_static_thrust(_physics_model(0.2, 8000.0), base)
	var twin_model := _physics_model(0.2, 8000.0)
	twin_model.propulsion.append(twin_model.propulsion[0].duplicate(true))
	var twin := _derived_static_thrust(twin_model, base)
	check("a twin records its propeller count", not twin.is_empty() and int(twin.block.propeller.get("count", 1)) == 2)
	check("a twin's equivalent propeller gives about twice the thrust", not single.is_empty() and not twin.is_empty()
		and twin.thrust > 1.6 * single.thrust and twin.thrust < 2.4 * single.thrust)
	# A ducted-fan jet: Phoenix Max_Thrust in newtons sets the equivalent propeller's static thrust.
	var jet_model := _physics_model()
	jet_model.propulsion = [{type = "turbine", attributes = {Max_Thrust = 20.0, Max_RPM = 25000}}]
	var jet := _derived_static_thrust(jet_model, base)
	check("a jet records its Phoenix thrust", not jet.is_empty() and is_equal_approx(float(jet.block.get("jet_thrust_n", 0.0)), 20.0))
	if not jet.is_empty():
		var motor: Dictionary = jet.power.motor
		var kt := 60.0 / (TAU * float(motor.kv_rpm_per_volt.value))
		var supply := float(motor.resistance_ohm.value) + float(jet.power.battery.resistance_ohm.value)
		check("a small fast rotor keeps the shaft time constant the runtime assumes",
			float(jet.power.propeller.rotating_inertia.value) * supply / (kt * kt) >= PhoenixPhysics.SHAFT_TIME_CONSTANT_S * 0.999)
	check("the jet's equivalent propeller delivers the Phoenix thrust", not jet.is_empty()
		and absf(jet.thrust - 20.0) <= 20.0 * 0.05 and str(jet.power.propeller.name).contains("jet"))
	# A glider without propulsion: an estimated launch motor of GLIDER_THRUST_SHARE × weight.
	var glider_model := _physics_model()
	glider_model.propulsion = []
	var glider := _derived_static_thrust(glider_model, base)
	var weight := 1.5 * Packages.GRAVITY
	check("a glider gets a labelled estimated launch motor", not glider.is_empty()
		and absf(glider.thrust - PhoenixPhysics.GLIDER_THRUST_SHARE * weight) <= 0.05 * PhoenixPhysics.GLIDER_THRUST_SHARE * weight
		and str(glider.power.propeller.diameter.kind) == "estimated")


func _physics_untrusted() -> void:
	var weightless := _physics_model()
	weightless.attributes.Physical.erase("Weight")
	check("a model without a weight has no physics block", PhoenixPhysics.physics_block(weightless, 0.01, [0.0, 0.02, 0.03],
		{"Synthetic": _synthetic_polar()}, weightless.airfoils[0], weightless.airfoils[1], null).is_empty())
	var model := _physics_model()
	var block := PhoenixPhysics.physics_block(model, 0.01, [0.0, 0.02, 0.03], {"Synthetic": _synthetic_polar()},
		model.airfoils[0], model.airfoils[1], null)
	check("a decoded block is valid", PhoenixPhysics.valid_block(block))
	var trainer := "conventional-trainer-estimated-v1"
	var power := "electric-3s-1250kv-9x6-estimated-v1"
	for broken: Array in [["section", null], ["wing_lift_slope", 40.0], ["mass_kg", -1.0], ["propeller", {diameter_m = 0.2}]]:
		var altered := block.duplicate(true)
		if broken[1] == null:
			altered.erase(broken[0])
		else:
			altered[broken[0]] = broken[1]
		check("an invalid block (%s) derives nothing" % broken[0], not PhoenixPhysics.valid_block(altered)
			and PhoenixPhysics.derive(altered, trainer, power, 1.0).is_empty())
	var ids := PhoenixPhysics.derive(block, trainer, power, 1.0)
	var other := PhoenixPhysics.derive(block, trainer, power, 1.25)
	check("another flown size derives other ids", not ids.is_empty() and not other.is_empty() and ids.airframe != other.airframe)
	check("a derived package cannot shadow an installed one",
		not Packages.register_derived(trainer, Packages.airframe(ids.airframe).value).ok
		and not Packages.register_derived("plain-id", Packages.airframe(ids.airframe).value).ok)
	# Setup and a reopened draft both parse the same stored receipt text: the parsed block restores its ids.
	var receipt := JSON.stringify(block)
	var applied := PhoenixPhysics.derive(JSON.parse_string(receipt), trainer, power, 1.0)
	check("a reopened receipt restores the same ids", not applied.is_empty()
		and PhoenixPhysics.restore(JSON.parse_string(receipt), applied.airframe, applied.power))
	# A heavier flying mass than the scaled source: the ids carry it, restore reproduces them, and a glider's
	# launch motor refers to the weight that flies.
	var glider_model := _physics_model()
	glider_model.propulsion = []
	var glider := PhoenixPhysics.physics_block(glider_model, 0.01, [0.0, 0.02, 0.03], {"Synthetic": _synthetic_polar()},
		glider_model.airfoils[0], glider_model.airfoils[1], null)
	var heavy := PhoenixPhysics.derive(glider, trainer, power, 1.0, 3.0)
	check("a flying mass is part of the ids", not heavy.is_empty() and str(heavy.power).contains("|3.0|")
		and PhoenixPhysics.restore(glider, heavy.airframe, heavy.power))
	if not heavy.is_empty():
		var probe: Dictionary = Packages.power(heavy.power).value.duplicate(true)
		probe.id = "probe-heavy-glider"
		var thrust := float(Packages.static_thrust(probe, 1.0).get("thrust_n", NAN))
		var wanted := PhoenixPhysics.GLIDER_THRUST_SHARE * 3.0 * Packages.GRAVITY
		check("the launch motor refers to the flying weight", absf(thrust - wanted) <= 0.05 * wanted)


# --------------------------------------------------------------------------- import hardening (IAQ-03c)

func _import_hardening() -> void:
	var folder := OS.get_user_data_dir().path_join("phoenix_hardening_test")
	DirAccess.make_dir_recursive_absolute(folder)
	# More textured materials than the GLB admits: the rest keep their colour, and a note says how many.
	var count := Limits.GLB_IMAGES + 2
	_write(folder, "many.mod", _model_chunk())
	_write(folder, "many.geo", _geo_bytes([{name = "wing", material = 0, triangles = 2}], count, "textures"))
	for index: int in count:
		_write(folder, "t%d.bmp" % index, _texture_bytes())
	var many: Dictionary = Converter.convert(folder.path_join("many.mod"))
	check("textures beyond the GLB limit are reported", many.ok and many.diagnostics.any(func(d: Dictionary) -> bool:
		return d.message == Converter.TEXTURES_LIMITED and d.arguments == [str(Limits.GLB_IMAGES), "2"]))
	if many.ok:
		check("a model without a type keeps the appearance-only note", many.diagnostics.any(func(d: Dictionary) -> bool:
			return d.message == Converter.APPEARANCE_ONLY) and not many.diagnostics.any(func(d: Dictionary) -> bool:
			return d.message == Converter.ROTORCRAFT))
		check("reopened Phoenix sources rebuild their notes", Converter.source_notes(many.value.source).any(
			func(d: Dictionary) -> bool: return d.message == Converter.APPEARANCE_ONLY))
	for name: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	# A copied installation whose folder names changed case still finds the shared textures.
	var install := OS.get_user_data_dir().path_join("phoenix_case_test")
	var model_dir := install.path_join("RESOURCES/Objects/demo")
	var shared_dir := install.path_join("RESOURCES/Textures/AIRCRAFT")
	DirAccess.make_dir_recursive_absolute(model_dir)
	DirAccess.make_dir_recursive_absolute(shared_dir)
	_write(model_dir, "demo.mod", _model_chunk())
	_write(model_dir, "demo.geo", _geo_bytes([{name = "wing", material = 0, triangles = 2}]))
	_write(shared_dir, "Demo.bmp", _texture_bytes())
	var copied: Dictionary = Converter.convert(model_dir.path_join("demo.mod"))
	check("shared textures are found in a copied installation with other folder case", copied.ok
		and copied.value.receipt.textures.has("Demo.bmp"))
	for dir: String in [shared_dir, model_dir]:
		for name: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(name))
	for dir: String in [shared_dir, install.path_join("RESOURCES/Textures"), model_dir, install.path_join("RESOURCES/Objects"),
			install.path_join("RESOURCES"), install]:
		DirAccess.remove_absolute(dir)
	var geo: Dictionary = Geo.parse(_geo_bytes([{name = "wing", material = 0, triangles = 2}])).value
	# A helicopter receipt: the rotorcraft note on import and on reopen, never the fixed-wing set-up note.
	var heli := GlbWriter.build(geo, {}, 1.0, {model_type = "Helicopter", name = "Heli", span_m = 1.2, mass_kg = 3.1})
	var heli_source: Variant = SourceImporter.inspect_bytes(heli.value.bytes, "heli.glb").value
	var heli_notes := Converter.source_notes(heli_source)
	check("Phoenix helicopters are told they import as appearance only", heli_notes.any(func(d: Dictionary) -> bool:
		return d.message == Converter.ROTORCRAFT) and not heli_notes.any(func(d: Dictionary) -> bool:
		return d.message == Converter.LAYOUT or d.message == Converter.APPEARANCE_ONLY))
	check("the reopened summary comes from the receipt", heli_notes.any(func(d: Dictionary) -> bool:
		return d.message == Converter.SUMMARY and d.arguments == ["Heli", "1.2", "3.1"]))
	check("other sources get no Phoenix notes", Converter.source_notes(null).is_empty())
	# An aeroplane with its own physics: a size change after set-up blocks flight until set-up runs again.
	var model := _physics_model()
	var block := PhoenixPhysics.physics_block(model, 0.01, [0.0, 0.02, 0.03], {"Synthetic": _synthetic_polar()},
		model.airfoils[0], model.airfoils[1], null)
	var data := {datum = [0.0, 0.02, 0.03], half_span_m = 0.75, root_chord_m = 0.25, tip_chord_m = 0.2,
		dihedral_deg = 3.0, propeller_found = true, pusher = false, biplane = false, physics = block,
		layout = {"horizontal_tail/span": 0.5, "horizontal_tail/position/0": 0.45}}
	var marked := GlbWriter.build(geo, {}, 1.0, {creator_setup = data}, [], [Installation.PHOENIX_NAMESPACE])
	var source: Variant = SourceImporter.inspect_bytes(marked.value.bytes, "physics.glb").value
	var proposed: Dictionary = PhoenixSetup.propose(source, Authoring.span_domain())
	var doc := Authoring.new()
	doc.set_source(source)
	doc.set_axis("nose_axis", "+z")
	doc.set_axis("up_axis", "+y")
	doc.set_units("m")
	doc.set_datum([0.0, 0.02, 0.03])
	var applied: Dictionary = doc.apply_clearview_setup(proposed.value, doc.revision) if proposed.ok else proposed
	var power := str(doc.definition().get("power_package", ""))
	check("set-up derives the Phoenix packages", applied.ok and PhoenixPhysics.is_derived(power))
	if not (applied.ok and PhoenixPhysics.is_derived(power)):
		return
	check("the flown size matches the derived packages", not doc.phoenix_size_changed()
		and not _has_message(doc.compile(), Authoring.PHOENIX_RESIZED))
	var snapshot: Dictionary = doc.snapshot()
	doc.set_units("cm")
	check("a size change after set-up blocks flight with a clear note", doc.phoenix_size_changed()
		and _has_message(doc.compile(), Authoring.PHOENIX_RESIZED))
	# A draft whose derivation an earlier version made reopens on its base packages and asks for set-up again.
	var stale: Dictionary = snapshot.duplicate(true)
	for key: String in ["power_package", "airframe_package"]:
		var parts := str(stale[key]).split("|")
		parts[parts.size() - 1] = "0000000000000000"
		stale[key] = "|".join(parts)
	var fresh := Authoring.new()
	var reopened: Dictionary = fresh.restore(stale, source)
	check("an outdated derivation reopens the draft on its base packages", reopened.ok
		and not PhoenixPhysics.is_derived(str(fresh.definition().get("power_package", "")))
		and fresh.needs_source_installation() and fresh.restore_notes.any(func(d: Dictionary) -> bool:
			return d.message == Authoring.PHOENIX_DERIVATION_RESET))
	var current := Authoring.new()
	check("a current derivation reopens unchanged", current.restore(snapshot, source).ok
		and str(current.definition().get("power_package", "")) == power and current.restore_notes.is_empty())


func _has_message(result: Dictionary, message: String) -> bool:
	return not result.get("ok", false) and (result.get("diagnostics", []) as Array).any(func(d: Dictionary) -> bool:
		return d.message == message)


# ------------------------------------------------------------------------------- Phoenix tuning (IAQ-03d)

func _derived_airframe(model: Dictionary) -> Dictionary:
	var block := PhoenixPhysics.physics_block(model, 0.01, [0.0, 0.02, 0.03], {"Synthetic": _synthetic_polar()},
		model.airfoils[0], model.airfoils[1], null)
	var ids := PhoenixPhysics.derive(block, "conventional-trainer-estimated-v1", "electric-3s-1250kv-9x6-estimated-v1", 1.0)
	return {block = block, airframe = Packages.airframe(ids.airframe).value if not ids.is_empty() else {},
		power = Packages.power(ids.power).value if not ids.is_empty() else {}}


func _physics_tuning() -> void:
	var plain := _derived_airframe(_physics_model())
	var tuned_model := _physics_model()
	tuned_model.attributes.Fine_tuning = {Lift = 150, Elevator = 120, Aileron = 80, Thrust = 100, Stall = {severity = 100}}
	var tuned := _derived_airframe(tuned_model)
	check("Phoenix tuning is recorded", (tuned.block.get("tuning", {}) as Dictionary) == {lift = 1.5, elevator = 1.2, aileron = 0.8})
	if plain.airframe.is_empty() or tuned.airframe.is_empty():
		check("tuned packages derive", false)
		return
	check("lift tuning scales the zero-angle lift", is_equal_approx(float(tuned.airframe.wing.zero_alpha_lift.value),
		1.5 * float(plain.airframe.wing.zero_alpha_lift.value)))
	check("lift tuning raises the lift limit", float(tuned.airframe.envelope.CL_max.value) > float(plain.airframe.envelope.CL_max.value))
	check("elevator tuning scales its effectiveness", is_equal_approx(float(tuned.airframe.tail.elevator_effectiveness.value),
		minf(1.2 * float(plain.airframe.tail.elevator_effectiveness.value), PhoenixPhysics.MAX_SURFACE_EFFECTIVENESS)))
	check("aileron tuning scales the roll power", is_equal_approx(float(tuned.airframe.borrowed_coefficients.Clda_left.value),
		0.8 * float(plain.airframe.borrowed_coefficients.Clda_left.value)))
	var thrusty_model := _physics_model()
	thrusty_model.attributes.Fine_tuning = {Thrust = 50}
	var thrusty := _derived_airframe(thrusty_model)
	check("thrust tuning shrinks the propeller", float(thrusty.power.propeller.diameter.value)
		< float(plain.power.propeller.diameter.value))
	var broken: Dictionary = (tuned.block as Dictionary).duplicate(true)
	broken.tuning = {lift = 9.0}
	check("out-of-range tuning is refused", not PhoenixPhysics.valid_block(broken))
	# Zero-length ailerons are inactive: a rudder-steered model keeps only a token roll power.
	var rudder_model := _physics_model()
	rudder_model.airfoils[0].controlSurfaces[0].attributes.Length = 0.0
	var rudder := _derived_airframe(rudder_model)
	check("inactive ailerons leave a token roll power", float(rudder.block.get("aileron_roll_power", -1.0)) == 0.0
		and not rudder.airframe.is_empty() and absf(float(rudder.airframe.borrowed_coefficients.Clda_left.value))
		<= 0.11 * absf(float(plain.airframe.borrowed_coefficients.Clda_left.value)))
	# A chordless aileron is unknown data, not an inactive one: the base set stays.
	var chordless_model := _physics_model()
	chordless_model.airfoils[0].controlSurfaces[0].attributes.erase("Root_chord")
	chordless_model.airfoils[0].controlSurfaces[0].attributes.erase("Tip_chord")
	var chordless := _derived_airframe(chordless_model)
	check("a chordless aileron does not disable rolling", not chordless.block.has("aileron_roll_power"))
	# A disabled entry before a working aileron: the working one sets the roll power.
	var second_model := _physics_model()
	var working: Dictionary = (second_model.airfoils[0].controlSurfaces[0] as Dictionary).duplicate(true)
	second_model.airfoils[0].controlSurfaces[0].attributes.Length = 0.0
	second_model.airfoils[0].controlSurfaces.append(working)
	var second := _derived_airframe(second_model)
	check("a disabled aileron entry before a working one is skipped", float(second.block.get("aileron_roll_power", 0.0)) > 0.0
		and is_equal_approx(float(second.block.aileron_roll_power), float(plain.block.aileron_roll_power)))
	# Thrust-line angles come from the decoded propeller and are limited like the throws.
	var model := {airfoils = [{isMirrored = 1, attributes = {Position = {x = 0.0, y = 0.0, z = 0.0}, Length = 0.75,
		Root_chord = 0.25, Tip_chord = 0.2}}],
		propulsion = [{type = "propeller", pivot = {x = 0.0, y = 0.0, z = 30.0}, attributes = {Down_thrust = 8.0, Right_thrust = -0.5}}]}
	var values := Converter.definition_values(model, 0.01, [0.0, 0.0, 0.0], [0])
	check("thrust angles come from the propeller", float(values.get("equipment/thrust_angles_deg/0", 0.0)) == 8.0
		and float(values.get("equipment/thrust_angles_deg/1", 0.0)) == -0.5)
	check("thrust angles are limited to the installation range",
		PhoenixSetup.THROW_RANGES.has("equipment/thrust_angles_deg/0") and PhoenixSetup.THROW_RANGES["equipment/thrust_angles_deg/0"] == [-5.0, 5.0])


# ------------------------------------------------------------------------------- landing gear (AC-21)

## A decoded gear: mirrored mains and a steerable wheel, GEO units (radius 1.5, Size 1.5 -> 0.015 m/unit).
func _gear_model(steered_z: float) -> Dictionary:
	return {gear = [
		{mirrored = 1, isGuide = 0, isRetractable = 1, attributes = {Guide_travel = 20},
			wheels = [{pivot = {x = 10.0, y = 1.5, z = 0.0 if steered_z > 0.0 else 10.0}, radius = 1.5}]},
		{mirrored = 0, isGuide = 1, attributes = {Guide_travel = 30},
			wheels = [{pivot = {x = 0.0, y = 1.5, z = steered_z}, radius = 1.5}]}]}


func _landing_gear() -> void:
	var datum := [0.0, 0.3, 0.2]
	var tricycle := Converter.gear_layout(_gear_model(20.0), 0.015, datum)
	check("a nose-steered gear is a tricycle", tricycle.get("layout") == "tricycle" and (tricycle.contacts as Array).size() == 3
		and bool(tricycle.retractable))
	if tricycle.get("layout") == "tricycle":
		var by_id := {}
		for contact: Dictionary in tricycle.contacts:
			by_id[contact.id] = contact
		check("wheel bottoms in the leading-edge frame", by_id.has("nose") and by_id.has("main_left") and by_id.has("main_right")
			and is_equal_approx(float(by_id.nose.position[2]), -0.3) and is_equal_approx(float(by_id.main_right.position[1]), 0.15)
			and is_equal_approx(float(by_id.main_left.position[1]), -0.15) and float(by_id.nose.position[0]) < 0.0)
		check("the nose wheel steers with its travel", is_equal_approx(float(by_id.nose.steering_deg), 30.0)
			and float(by_id.main_left.steering_deg) == 0.0)
	var taildragger := Converter.gear_layout(_gear_model(-40.0), 0.015, datum)
	check("a tail-steered gear is a taildragger with negative steering", taildragger.get("layout") == "taildragger"
		and (taildragger.contacts as Array).any(func(c: Dictionary) -> bool: return c.id == "tail" and float(c.steering_deg) == -30.0))
	check("floats or skids without wheels give no gear", Converter.gear_layout({gear = [{mirrored = 1}]}, 0.015, datum).is_empty())
	# The definition accepts a closed gear member and refuses malformed ones.
	var good := {"landing_gear": {"layout": "tricycle", "contacts": [
		{"id": "nose", "position": [-0.2, 0.0, -0.2], "steering_deg": 20.0},
		{"id": "main_left", "position": [0.2, -0.15, -0.2], "steering_deg": 0.0},
		{"id": "main_right", "position": [0.2, 0.15, -0.2], "steering_deg": 0.0}]}}
	var problems: Array = []
	Definition._landing_gear(problems, good)
	check("a valid gear passes the definition rules", problems.is_empty())
	for broken: Dictionary in [{"landing_gear": {"layout": "quad", "contacts": good.landing_gear.contacts}},
			{"landing_gear": {"layout": "tricycle", "contacts": (good.landing_gear.contacts as Array).slice(0, 2)}},
			{"landing_gear": {"layout": "tricycle", "contacts": good.landing_gear.contacts, "extra": 1}}]:
		var found: Array = []
		Definition._landing_gear(found, broken)
		check("a malformed gear is refused", not found.is_empty())
	# Set-up carries the decoded gear into the definition; the record gets fixed gear and a runway start.
	var geo: Dictionary = Geo.parse(_geo_bytes([{name = "wing", material = 0, triangles = 2}])).value
	var model := _physics_model()
	var block := PhoenixPhysics.physics_block(model, 0.01, [0.0, 0.02, 0.03], {"Synthetic": _synthetic_polar()},
		model.airfoils[0], model.airfoils[1], null)
	var data := {datum = [0.0, 0.02, 0.03], half_span_m = 0.75, root_chord_m = 0.25, tip_chord_m = 0.2,
		dihedral_deg = 3.0, propeller_found = true, pusher = false, biplane = false, physics = block,
		layout = {"horizontal_tail/span": 0.5, "horizontal_tail/position/0": 0.45},
		gear = {layout = "tricycle", retractable = false, contacts = [
			{id = "nose", position = [-0.15, 0.0, -0.16], steering_deg = 25.0},
			{id = "main_left", position = [0.12, -0.12, -0.16], steering_deg = 0.0},
			{id = "main_right", position = [0.12, 0.12, -0.16], steering_deg = 0.0}]}}
	var marked := GlbWriter.build(geo, {}, 1.0, {creator_setup = data}, [], [Installation.PHOENIX_NAMESPACE])
	var source: Variant = SourceImporter.inspect_bytes(marked.value.bytes, "geared.glb").value
	var proposed: Dictionary = PhoenixSetup.propose(source, Authoring.span_domain())
	var doc := Authoring.new()
	doc.set_source(source)
	doc.set_axis("nose_axis", "+z")
	doc.set_axis("up_axis", "+y")
	doc.set_units("m")
	doc.set_datum([0.0, 0.02, 0.03])
	var applied: Dictionary = doc.apply_clearview_setup(proposed.value, doc.revision) if proposed.ok else proposed
	check("set-up brings the decoded gear as an estimate", applied.ok and doc.landing_gear().get("layout") == "tricycle"
		and (doc.definition().get("evidence", {}) as Dictionary).get("landing_gear") == "estimated")
	var built: Dictionary = doc.compile()
	check("a geared definition compiles", built.ok)
	if not built.ok:
		print("  compile: ", built.diagnostics.slice(0, 2))
		return
	var record: Variant = JSON.parse_string((built.value.raw_bytes() as PackedByteArray).get_string_from_utf8())
	check("the record carries fixed tricycle gear", record is Dictionary and record.capabilities.gear == "fixed_tricycle"
		and (record.landing_gear.contacts as Array).size() == 3 and record.landing_gear.has("breakaway_factor"))
	if record is Dictionary:
		var lowest_wheel := INF
		for contact: Dictionary in record.landing_gear.contacts:
			lowest_wheel = minf(lowest_wheel, float(contact.position.value[2]))
		var lowest_hull := INF
		for point: Array in record.crash_hull.value:
			lowest_hull = minf(lowest_hull, float(point[2]))
		check("the hull stays above the wheels", lowest_hull > lowest_wheel)
	var snapshot: Dictionary = doc.snapshot()
	var reopened := Authoring.new()
	check("a saved draft keeps its gear", reopened.restore(snapshot, source).ok and reopened.landing_gear() == doc.landing_gear())
	var payload := {creator_candidate = built.value, creator_source = source, creator_placement = doc.placement(),
		creator_name = "geared", start_choice = "runway", creator_bindings = doc.bindings(), creator_appearance = doc.appearance()}
	var trial: Dictionary = CreatorTrial.freeze(payload)
	var field: Dictionary = FieldLoader.load_from().field
	var runway: Dictionary = CreatorTrial.check_start(trial, field, Weather.defaults(), Session.START_RUNWAY) if trial.get("ok", false) else {}
	check("a geared Creator aircraft starts on the runway", runway.get("ok", false) and runway.get("available", false))
	var hand: Dictionary = CreatorTrial.check_start(trial, field, Weather.defaults(), Session.START_HAND_LAUNCH) if trial.get("ok", false) else {}
	check("a geared Creator aircraft is not hand launched", hand.get("ok", false) and not hand.get("available", true))
