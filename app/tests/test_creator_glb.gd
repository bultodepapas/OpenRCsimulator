extends SceneTree
## AC-04: strict GLB 2.0 preflight before the engine importer.
## Every fixture is built here from code. `GlbPreflight.inspect` never calls `GLTFDocument`; the
## only importer call in this file is the final check on the accepted fixture.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const GlbPreflight := preload("res://workshop/creator/glb_preflight.gd")

const MAGIC := 0x46546C67
const CHUNK_JSON := 0x4E4F534A
const CHUNK_BIN := 0x004E4942
const HALF := 0.7071067811865476

var failures := 0
var checks := 0
var texture_png := PackedByteArray()


func _initialize() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.9, 0.5, 0.1, 1.0))
	texture_png = image.save_png_to_buffer()
	_test_valid()
	_test_container()
	_test_json_and_extensions()
	_test_unsupported_features()
	_test_graph()
	_test_transforms()
	_test_buffers_and_accessors()
	_test_meshes()
	_test_materials_and_images()
	_test_ceilings()
	_test_engine_accepts_the_subset()
	print("Creator GLB: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_valid() -> void:
	var fixture := base()
	var result: Dictionary = GlbPreflight.inspect(pack(fixture))
	check("valid fixture accepted " + str(R.texts(result)), result.ok)
	if not result.ok:
		return
	var value: Dictionary = result.value
	var counts: Dictionary = value.counts
	check("counts", counts.nodes == 3 and counts.meshes == 1 and counts.primitives == 2 and counts.materials == 2
		and counts.images == 1 and counts.accessors == 6 and counts.buffer_views == 7 and counts.textures == 1)
	# The mesh has 2 + 1 triangles and 4 + 3 vertices; two nodes instantiate it.
	check("instantiated triangles double", counts.triangles == 6 and counts.vertices == 14 and counts.mesh_instances == 2)
	check("scene roots", value.scene == 0 and value.scene_roots == [0])
	check("duplicate node names kept", value.node_names == ["Root", "Part", "Part"])
	# Node 1 moves the unit box to x 1..2; node 2 scales by 2, turns 90 degrees about Y, moves to x -1.
	check("bounds min", close(value.bounds_min, [-1.0, 0.0, -2.0]))
	check("bounds max", close(value.bounds_max, [2.0, 2.0, 1.0]))
	check("images", value.images.size() == 1 and value.images[0].index == 0 and value.images[0].width == 4
		and value.images[0].height == 4 and value.images[0].pixels == 16)
	check("uv flags", value.has_uv and not value.all_uv)
	check("materials", value.materials.size() == 2 and value.materials[0].name == "paint"
		and value.materials[0].has_base_color_texture and value.materials[0].base_color_image == 0
		and value.materials[1].name == "plain" and not value.materials[1].has_base_color_texture)
	check("extensions reported", value.extensions_used == ["KHR_materials_emissive_strength", "KHR_materials_ior"])
	check("json hash shape", str(value.json_sha256).length() == 64)
	check("allow-list is two material scalars", GlbPreflight.ALLOWED_EXTENSIONS
		== ["KHR_materials_emissive_strength", "KHR_materials_ior"])

	# A file without a BIN chunk cannot carry geometry; a node-only file has no mesh in its scene.
	var bare := {"json": {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "only"}]},
		"bin": PackedByteArray()}
	refuse("scene without a mesh", bare, R.SOURCE_INVALID)

	# Interleaved vertex data (byteStride) takes the element-by-element path.
	var woven := interleaved()
	var woven_result: Dictionary = GlbPreflight.inspect(pack(woven))
	check("interleaved accepted " + str(R.texts(woven_result)), woven_result.ok)
	if woven_result.ok:
		check("interleaved bounds", close(woven_result.value.bounds_min, [0.0, 0.0, 0.0])
			and close(woven_result.value.bounds_max, [1.0, 2.0, 0.0]) and woven_result.value.counts.triangles == 1)
	var woven_bin: PackedByteArray = woven.bin
	woven_bin.encode_float(24 + 4, NAN)
	woven.bin = woven_bin
	refuse("NaN in interleaved positions", woven, R.SOURCE_INVALID)

	# 32-bit and 8-bit indices.
	for component: int in [5121, 5125]:
		var wide := base()
		var bin: PackedByteArray = pad(wide.bin, 0)
		var at := bin.size()
		for index: int in [0, 1, 2, 0, 2, 3]:
			if component == 5125:
				bin.append_array(u32(index))
			else:
				bin.append(index)
		wide.bin = bin
		wide.json.bufferViews.append({"buffer": 0, "byteOffset": at, "byteLength": bin.size() - at})
		wide.json.accessors.append({"bufferView": 7, "componentType": component, "count": 6, "type": "SCALAR"})
		wide.json.meshes[0].primitives[0].indices = 6
		wide.json.buffers[0].byteLength = bin.size()
		check("index component %d accepted" % component, GlbPreflight.inspect(pack(wide)).ok)
		bin.encode_u8(at + (4 if component == 5125 else 1) * 5, 4)
		wide.bin = bin
		refuse("index component %d out of range" % component, wide, R.SOURCE_INVALID)
		if component == 5125:
			bin.encode_u32(at + 20, 0xFFFFFFFF)
			wide.bin = bin
			refuse("index 2^32 - 1", wide, R.SOURCE_INVALID)


func _test_container() -> void:
	var good := pack(base())
	var changed := good.duplicate()
	changed.encode_u32(0, 0x46546C68)
	expect("bad magic", changed, R.SOURCE_INVALID)
	changed = good.duplicate()
	changed.encode_u32(4, 1)
	expect("container version 1", changed, R.SOURCE_UNSUPPORTED)
	changed = good.duplicate()
	changed.encode_u32(4, 3)
	expect("container version 3", changed, R.SOURCE_UNSUPPORTED)
	changed = good.duplicate()
	changed.encode_u32(8, good.size() + 4)
	expect("declared length too long", changed, R.SOURCE_INVALID)
	changed = good.duplicate()
	changed.encode_u32(8, good.size() - 4)
	expect("declared length too short", changed, R.SOURCE_INVALID)
	expect("truncated file", good.slice(0, good.size() - 4), R.SOURCE_INVALID)
	expect("empty file", PackedByteArray(), R.SOURCE_INVALID)
	expect("header only", good.slice(0, 12), R.SOURCE_INVALID)
	var appended := good.duplicate()
	appended.append_array(PackedByteArray([0, 0, 0, 0]))
	expect("bytes after the declared length", appended, R.SOURCE_INVALID)

	var fixture := base()
	var text := json_bytes(fixture.json)
	var bin := pad(fixture.bin, 0)
	expect("reassembled baseline", container([[CHUNK_JSON, text], [CHUNK_BIN, bin]]), "ok")
	expect("JSON chunk missing", container([[CHUNK_BIN, bin]]), R.SOURCE_INVALID)
	expect("BIN chunk first", container([[CHUNK_BIN, bin], [CHUNK_JSON, text]]), R.SOURCE_INVALID)
	expect("second JSON chunk", container([[CHUNK_JSON, text], [CHUNK_JSON, text]]), R.SOURCE_INVALID)
	expect("JSON chunk after BIN", container([[CHUNK_JSON, text], [CHUNK_BIN, bin], [CHUNK_JSON, text]]), R.SOURCE_INVALID)
	expect("second BIN chunk", container([[CHUNK_JSON, text], [CHUNK_BIN, bin], [CHUNK_BIN, bin]]), R.SOURCE_INVALID)
	expect("unknown chunk instead of BIN", container([[CHUNK_JSON, text], [0x12345678, bin]]), R.SOURCE_UNSUPPORTED)
	expect("unknown third chunk", container([[CHUNK_JSON, text], [CHUNK_BIN, bin], [0x12345678, bin]]),
		R.SOURCE_UNSUPPORTED)
	expect("empty JSON chunk", container([[CHUNK_JSON, PackedByteArray()], [CHUNK_BIN, bin]]), R.SOURCE_INVALID)

	# Misaligned chunks: one padding byte removed, every length field still consistent.
	var odd_text := text.slice(0, text.size() - 1)
	expect("misaligned JSON chunk", container([[CHUNK_JSON, odd_text], [CHUNK_BIN, bin]]), R.SOURCE_INVALID)
	var odd_bin := bin.duplicate()
	odd_bin.append(0)
	expect("misaligned BIN chunk", container([[CHUNK_JSON, text], [CHUNK_BIN, odd_bin]]), R.SOURCE_INVALID)
	# A chunk length that runs past the file, and one that would wrap a 32-bit sum.
	for length: int in [good.size(), 0xFFFFFFFC]:
		changed = good.duplicate()
		changed.encode_u32(12, length)
		expect("JSON chunk length %d" % length, changed, R.SOURCE_LIMIT if length > Limits.GLB_JSON_BYTES else R.SOURCE_INVALID)
	changed = good.duplicate()
	changed.encode_u32(20 + text.size(), 0xFFFFFFFC)
	expect("BIN chunk length overruns", changed, R.SOURCE_INVALID)
	changed = good.duplicate()
	changed.resize(20 + text.size() + 4)
	changed.encode_u32(8, changed.size())
	expect("stray bytes after JSON", changed, R.SOURCE_INVALID)

	var padded := text.duplicate()
	padded.resize(Limits.GLB_JSON_BYTES + 4)
	padded.fill(0x20)
	expect("JSON chunk over its limit", container([[CHUNK_JSON, padded], [CHUNK_BIN, bin]]), R.SOURCE_LIMIT)
	var huge := PackedByteArray()
	huge.resize(Limits.MODEL_SOURCE_BYTES + 4)
	huge.encode_u32(0, MAGIC)
	huge.encode_u32(4, 2)
	huge.encode_u32(8, huge.size())
	expect("file over its limit", huge, R.SOURCE_LIMIT)


func _test_json_and_extensions() -> void:
	expect("not JSON", json_text("{nodes}"), R.SOURCE_INVALID)
	expect("array root", json_text("[1]"), R.SOURCE_INVALID)
	expect("duplicate key", json_text('{"asset":{"version":"2.0"},"asset":{}}'), R.SOURCE_INVALID)
	expect("non-finite number", json_text('{"asset":{"version":"2.0"},"extras":1e999}'), R.SOURCE_INVALID)
	expect("NaN literal", json_text('{"asset":{"version":"2.0"},"extras":NaN}'), R.SOURCE_INVALID)
	# Number tokens the engine's float parser would warn about are refused before it runs.
	expect("tiny exponent", json_text('{"asset":{"version":"2.0"},"extras":1e-999}'), R.SOURCE_INVALID)
	expect("very long number", json_text('{"asset":{"version":"2.0"},"extras":%s}' % "9".repeat(65)), R.SOURCE_INVALID)
	check("digits inside text are not numbers", GlbPreflight.inspect(pack(with(["nodes", 0, "name"],
		'q"\\ 1e999 ' + "9".repeat(200)))).ok)
	expect("byte-order mark", json_text("﻿" + '{"asset":{"version":"2.0"}}'), R.SOURCE_INVALID)
	expect("trailing JSON value", json_text('{"asset":{"version":"2.0"}} {}'), R.SOURCE_INVALID)
	# Bytes the engine's UTF-8 decoder would complain about are refused before it runs.
	for bad: Array in [[0xFF, 0x20], [0xC0, 0xAF], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xE2, 0x82], [0x00], [0x1F]]:
		var text := '{"asset":{"version":"2.0"},"extras":"'.to_utf8_buffer()
		text.append_array(PackedByteArray(bad))
		text.append_array('"}'.to_utf8_buffer())
		while text.size() % 4 != 0:
			text.append(0x20)
		expect("bad UTF-8 or control byte %s" % str(bad), container([[CHUNK_JSON, text]]), R.SOURCE_INVALID)
	var accented := base()
	accented.json.nodes[0].name = "Ñandú 雪 🛩"
	check("valid multi-byte names", GlbPreflight.inspect(pack(accented)).ok)
	var deep: Variant = 1
	for _level: int in Limits.JSON_DEPTH + 4:
		deep = [deep]
	refuse("JSON nested too deeply", with(["extras"], deep), R.SOURCE_LIMIT)

	refuse("no asset", without(["asset"]), R.SOURCE_INVALID)
	refuse("asset version 1.0", with(["asset", "version"], "1.0"), R.SOURCE_UNSUPPORTED)
	refuse("asset version number", with(["asset", "version"], 2.0), R.SOURCE_INVALID)
	refuse("asset minVersion 2.1", with(["asset", "minVersion"], "2.1"), R.SOURCE_UNSUPPORTED)
	check("asset minVersion 2.0", GlbPreflight.inspect(pack(with(["asset", "minVersion"], "2.0"))).ok)
	refuse("unknown top-level property", with(["KHR_scripts"], [1]), R.SOURCE_UNSUPPORTED)

	for name: String in ["KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_texture_basisu", "EXT_texture_webp",
			"KHR_mesh_quantization", "KHR_lights_punctual", "KHR_materials_variants", "VENDOR_unknown"]:
		refuse("extension used " + name, with(["extensionsUsed"], [name]), R.SOURCE_UNSUPPORTED)
		refuse("extension required " + name, with(["extensionsRequired"], [name]), R.SOURCE_UNSUPPORTED)
	refuse("allowed extension made required", with(["extensionsRequired"], ["KHR_materials_ior"]), R.SOURCE_UNSUPPORTED)
	check("empty required list", GlbPreflight.inspect(pack(with(["extensionsRequired"], []))).ok)
	refuse("extension list repeats", with(["extensionsUsed"], ["KHR_materials_ior", "KHR_materials_ior"]), R.SOURCE_INVALID)
	refuse("extension list holds a number", with(["extensionsUsed"], [1]), R.SOURCE_INVALID)
	refuse("extension used but not declared", with(["extensionsUsed"], ["KHR_materials_ior"]), R.SOURCE_INVALID)
	refuse("undeclared extension object on a node", with(["nodes", 1, "extensions"], {"KHR_lights_punctual": {"light": 0}}),
		R.SOURCE_UNSUPPORTED)
	refuse("allowed extension outside a material", with(["nodes", 1, "extensions"], {"KHR_materials_ior": {"ior": 1.5}}),
		R.SOURCE_UNSUPPORTED)
	refuse("root extension object", with(["extensions"], {"KHR_lights_punctual": {"lights": []}}), R.SOURCE_UNSUPPORTED)
	refuse("texture transform", with(["materials", 0, "pbrMetallicRoughness", "baseColorTexture", "extensions"],
		{"KHR_texture_transform": {"scale": [2.0, 2.0]}}), R.SOURCE_UNSUPPORTED)
	refuse("extension with an index inside", with(["materials", 1, "extensions", "KHR_materials_ior", "iorTexture"],
		{"index": 0}), R.SOURCE_UNSUPPORTED)
	refuse("negative emissive strength", with(["materials", 0, "extensions", "KHR_materials_emissive_strength",
		"emissiveStrength"], -1.0), R.SOURCE_INVALID)
	refuse("ior below one", with(["materials", 1, "extensions", "KHR_materials_ior", "ior"], 0.5), R.SOURCE_INVALID)
	# `extras` are skipped, whatever they hold.
	check("extras ignored", GlbPreflight.inspect(pack(with(["meshes", 0, "extras"],
		{"extensions": {"KHR_draco_mesh_compression": {}}, "skins": [1], "uri": "http://example.invalid/x"}))).ok)


func _test_unsupported_features() -> void:
	refuse("animations", with(["animations"], [{"channels": [], "samplers": []}]), R.SOURCE_UNSUPPORTED)
	refuse("skins", with(["skins"], [{"joints": [1]}]), R.SOURCE_UNSUPPORTED)
	refuse("cameras", with(["cameras"], [{"type": "perspective"}]), R.SOURCE_UNSUPPORTED)
	refuse("node camera", with(["nodes", 1, "camera"], 0), R.SOURCE_UNSUPPORTED)
	refuse("node skin", with(["nodes", 1, "skin"], 0), R.SOURCE_UNSUPPORTED)
	refuse("node weights", with(["nodes", 1, "weights"], [0.5]), R.SOURCE_UNSUPPORTED)
	refuse("mesh weights", with(["meshes", 0, "weights"], [0.5]), R.SOURCE_UNSUPPORTED)
	refuse("morph targets", with(["meshes", 0, "primitives", 0, "targets"], [{"POSITION": 0}]), R.SOURCE_UNSUPPORTED)
	refuse("sparse accessor", with(["accessors", 1, "sparse"], {"count": 1, "indices": {"bufferView": 3,
		"componentType": 5123}, "values": {"bufferView": 1}}), R.SOURCE_UNSUPPORTED)
	refuse("accessor without a buffer view", without(["accessors", 1, "bufferView"]), R.SOURCE_UNSUPPORTED)
	refuse("external buffer", with(["buffers", 0, "uri"], "model.bin"), R.SOURCE_UNSUPPORTED)
	refuse("data URI buffer", with(["buffers", 0, "uri"], "data:application/octet-stream;base64,AAAA"), R.SOURCE_UNSUPPORTED)
	refuse("external image", with(["images", 0, "uri"], "paint.png"), R.SOURCE_UNSUPPORTED)
	refuse("data URI image", with(["images", 0, "uri"], "data:image/png;base64,iVBORw0KGgo="), R.SOURCE_UNSUPPORTED)
	var external := without(["images", 0, "bufferView"])
	refuse("image with only a URI", with(["images", 0, "uri"], "../../secret.png", external), R.SOURCE_UNSUPPORTED)
	refuse("second buffer", with(["buffers", 1], {"byteLength": 4}), R.SOURCE_UNSUPPORTED)
	for mode: int in [0, 1, 2, 3, 5, 6]:
		refuse("primitive mode %d" % mode, with(["meshes", 0, "primitives", 1, "mode"], mode), R.SOURCE_UNSUPPORTED)
	refuse("primitive mode 7", with(["meshes", 0, "primitives", 1, "mode"], 7), R.SOURCE_INVALID)
	refuse("primitive mode 4.5", with(["meshes", 0, "primitives", 1, "mode"], 4.5), R.SOURCE_INVALID)
	refuse("matrix accessor", with(["accessors", 1, "type"], "MAT4"), R.SOURCE_UNSUPPORTED)
	refuse("unknown node property", with(["nodes", 1, "script"], "res://x.gd"), R.SOURCE_UNSUPPORTED)
	refuse("unknown material property", with(["materials", 0, "shader"], 1), R.SOURCE_UNSUPPORTED)


func _test_graph() -> void:
	# Cyclic graphs are refused here, so the engine importer is never called on them.
	refuse("self-cycle", with(["nodes", 1, "children"], [1]), R.SOURCE_INVALID)
	refuse("self-cycle on the root", with(["nodes", 0, "children"], [0, 1, 2]), R.SOURCE_INVALID)
	var loop := with(["nodes", 3], {"name": "a", "children": [4]})
	refuse("two-node cycle outside the scene", with(["nodes", 4], {"name": "b", "children": [3]}, loop), R.SOURCE_INVALID)
	var ring := with(["nodes", 3], {"children": [4]})
	ring = with(["nodes", 4], {"children": [5]}, ring)
	refuse("three-node cycle outside the scene", with(["nodes", 5], {"children": [3]}, ring), R.SOURCE_INVALID)
	refuse("cycle through the scene root", with(["nodes", 2, "children"], [0]), R.SOURCE_INVALID)
	var detached := with(["nodes", 3], {"name": "spare", "children": [4]})
	check("unreachable tree accepted", GlbPreflight.inspect(pack(with(["nodes", 4], {"name": "leaf"}, detached))).ok)

	refuse("child with two parents", with(["nodes", 1, "children"], [2]), R.SOURCE_INVALID)
	refuse("duplicate child", with(["nodes", 0, "children"], [1, 2, 1]), R.SOURCE_INVALID)
	refuse("repeated root", with(["scenes", 0, "nodes"], [0, 0]), R.SOURCE_INVALID)
	refuse("root that is a child", with(["scenes", 0, "nodes"], [0, 1]), R.SOURCE_INVALID)
	refuse("child out of range", with(["nodes", 0, "children"], [1, 3]), R.SOURCE_INVALID)
	refuse("root out of range", with(["scenes", 0, "nodes"], [3]), R.SOURCE_INVALID)
	refuse("children not a list", with(["nodes", 0, "children"], 1), R.SOURCE_INVALID)
	refuse("mesh out of range", with(["nodes", 1, "mesh"], 1), R.SOURCE_INVALID)
	refuse("scene out of range", with(["scene"], 1), R.SOURCE_INVALID)
	# The engine importer would choose a scene itself and log a warning on every build.
	refuse("no default scene", without(["scene"]), R.SOURCE_UNSUPPORTED)
	refuse("no scenes", without(["scenes"]), R.SOURCE_INVALID)
	refuse("empty scene", with(["scenes", 0, "nodes"], []), R.SOURCE_INVALID)
	refuse("nodes not a list", with(["nodes"], {"0": {}}), R.SOURCE_INVALID)
	refuse("node not an object", with(["nodes", 1], [1]), R.SOURCE_INVALID)
	refuse("node name not text", with(["nodes", 1, "name"], 7), R.SOURCE_INVALID)
	var second := with(["scenes", 1], {"nodes": [0]})
	check("second scene selectable", GlbPreflight.inspect(pack(with(["scene"], 1, second))).ok)
	refuse("other scene is validated too", with(["scenes", 1], {"nodes": [9]}), R.SOURCE_INVALID)

	# JSON numbers arrive as floats: fractions, negatives and out-of-range exponents are not indices.
	for index: Variant in [0.5, -1, 1.5, 1000.0, -0.25, 1e30, "0", true, null, [0]]:
		refuse("mesh index %s" % str(index), with(["nodes", 1, "mesh"], index), R.SOURCE_INVALID)
	refuse("fractional child", with(["nodes", 0, "children"], [1, 1.5]), R.SOURCE_INVALID)
	refuse("negative child", with(["nodes", 0, "children"], [1, -2]), R.SOURCE_INVALID)
	refuse("fractional accessor", with(["meshes", 0, "primitives", 0, "attributes", "POSITION"], 0.5), R.SOURCE_INVALID)
	refuse("exponent index", raw_json(pack(base()), '"scene":0', '"scene":1e3'), R.SOURCE_INVALID)
	refuse("fraction spelled with an exponent", raw_json(pack(base()), '"scene":0', '"scene":5e-1'), R.SOURCE_INVALID)
	check("whole exponent is the same number", GlbPreflight.inspect(raw_json(pack(base()), '"scene":0', '"scene":0e0')).ok)

	check("depth at the limit", GlbPreflight.inspect(pack(chain(Limits.GLB_DEPTH))).ok)
	refuse("depth over the limit", chain(Limits.GLB_DEPTH + 1), R.SOURCE_LIMIT)
	check("nodes at the limit", GlbPreflight.inspect(pack(fan(Limits.GLB_NODES))).ok)
	refuse("nodes over the limit", fan(Limits.GLB_NODES + 1), R.SOURCE_LIMIT)


func _test_transforms() -> void:
	var identity := [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
	refuse("matrix with translation", with(["nodes", 1, "matrix"], identity), R.SOURCE_INVALID)
	var mixed := without(["nodes", 1, "translation"])
	mixed = with(["nodes", 1, "matrix"], identity, mixed)
	refuse("matrix with scale", with(["nodes", 1, "scale"], [1.0, 1.0, 1.0], mixed), R.SOURCE_INVALID)

	# Column-major: scale 2, a quarter turn about Y, translation (-1, 0, 0) - the same as node 2's TRS.
	var turned := [0.0, 0.0, -2.0, 0.0, 0.0, 2.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 1.0]
	var by_matrix: Dictionary = GlbPreflight.inspect(pack(matrix_node(turned)))
	check("matrix accepted " + str(R.texts(by_matrix)), by_matrix.ok)
	if by_matrix.ok:
		check("matrix gives the TRS bounds", close(by_matrix.value.bounds_min, [-1.0, 0.0, -2.0])
			and close(by_matrix.value.bounds_max, [2.0, 2.0, 1.0]))
	var sheared := identity.duplicate()
	sheared[4] = 0.5
	refuse("sheared matrix", matrix_node(sheared), R.SOURCE_UNSUPPORTED)
	var slightly := identity.duplicate()
	slightly[4] = 0.00005
	check("shear inside the tolerance", GlbPreflight.inspect(pack(matrix_node(slightly))).ok)
	slightly[4] = 0.0002
	refuse("shear outside the tolerance", matrix_node(slightly), R.SOURCE_UNSUPPORTED)
	var mirrored := identity.duplicate()
	mirrored[0] = -1.0
	refuse("mirrored matrix", matrix_node(mirrored), R.SOURCE_UNSUPPORTED)
	var flat := identity.duplicate()
	flat[10] = 0.0
	refuse("flattened matrix", matrix_node(flat), R.SOURCE_UNSUPPORTED)
	var projective := identity.duplicate()
	projective[3] = 0.1
	refuse("projective matrix", matrix_node(projective), R.SOURCE_UNSUPPORTED)
	var weighted := identity.duplicate()
	weighted[15] = 2.0
	refuse("matrix with w = 2", matrix_node(weighted), R.SOURCE_UNSUPPORTED)
	refuse("matrix with 15 numbers", matrix_node(identity.slice(0, 15)), R.SOURCE_INVALID)
	var worded := identity.duplicate()
	worded[5] = "1"
	refuse("matrix with text", matrix_node(worded), R.SOURCE_INVALID)

	refuse("zero scale", with(["nodes", 2, "scale"], [1.0, 0.0, 1.0]), R.SOURCE_INVALID)
	refuse("negative scale", with(["nodes", 2, "scale"], [1.0, -1.0, 1.0]), R.SOURCE_UNSUPPORTED)
	refuse("all-negative scale", with(["nodes", 2, "scale"], [-1.0, -1.0, -1.0]), R.SOURCE_UNSUPPORTED)
	refuse("scale with two numbers", with(["nodes", 2, "scale"], [1.0, 1.0]), R.SOURCE_INVALID)
	refuse("non-finite scale", raw_json(pack(base()), '"scale":[2.0,2.0,2.0]', '"scale":[2.0,1e999,2]'), R.SOURCE_INVALID)
	refuse("scale beyond float32", with(["nodes", 2, "scale"], [1e39, 1.0, 1.0]), R.SOURCE_INVALID)
	refuse("translation beyond float32", with(["nodes", 1, "translation"], [0.0, 1e39, 0.0]), R.SOURCE_INVALID)
	refuse("translation with text", with(["nodes", 1, "translation"], [0.0, "1", 0.0]), R.SOURCE_INVALID)
	refuse("non-normalized quaternion", with(["nodes", 2, "rotation"], [0.0, 0.7, 0.0, 0.7]), R.SOURCE_INVALID)
	refuse("zero quaternion", with(["nodes", 2, "rotation"], [0.0, 0.0, 0.0, 0.0]), R.SOURCE_INVALID)
	refuse("quaternion with three numbers", with(["nodes", 2, "rotation"], [0.0, 0.0, 1.0]), R.SOURCE_INVALID)
	check("quaternion inside the tolerance", GlbPreflight.inspect(pack(with(["nodes", 2, "rotation"],
		[0.0, HALF * 1.00005, 0.0, HALF * 1.00005]))).ok)
	refuse("quaternion outside the tolerance", with(["nodes", 2, "rotation"], [0.0, HALF * 1.0002, 0.0, HALF * 1.0002]),
		R.SOURCE_INVALID)


func _test_buffers_and_accessors() -> void:
	refuse("buffer view overruns the buffer", with(["bufferViews", 5, "byteLength"], 36 + texture_png.size() + 64),
		R.SOURCE_INVALID)
	refuse("buffer view offset past the buffer", with(["bufferViews", 5, "byteOffset"], 1000000), R.SOURCE_INVALID)
	refuse("buffer view huge length", with(["bufferViews", 5, "byteLength"], 9007199254740991.0), R.SOURCE_INVALID)
	refuse("buffer view length 2^64", raw_json(pack(base()), '"byteLength":36,"byteOffset":176',
		'"byteLength":18446744073709551616,"byteOffset":176'), R.SOURCE_INVALID)
	refuse("buffer view zero length", with(["bufferViews", 5, "byteLength"], 0), R.SOURCE_INVALID)
	refuse("buffer view negative offset", with(["bufferViews", 5, "byteOffset"], -4), R.SOURCE_INVALID)
	refuse("buffer view on a missing buffer", with(["bufferViews", 5, "buffer"], 1), R.SOURCE_INVALID)
	refuse("buffer view without a buffer", without(["bufferViews", 5, "buffer"]), R.SOURCE_INVALID)
	refuse("buffer view target", with(["bufferViews", 5, "target"], 34964), R.SOURCE_INVALID)
	for stride: Variant in [0, 2, 3, 6, 13, 256, 1e9, -4, 4.5]:
		refuse("byte stride %s" % str(stride), with(["bufferViews", 0, "byteStride"], stride), R.SOURCE_INVALID)
	refuse("byte stride smaller than the element", with(["bufferViews", 0, "byteStride"], 8), R.SOURCE_INVALID)
	# A stride of 12 equals the element size and stays inside the view; 16 walks out of it.
	check("byte stride equal to the element", GlbPreflight.inspect(pack(with(["bufferViews", 0, "byteStride"], 12))).ok)
	refuse("byte stride walks out of the view", with(["bufferViews", 0, "byteStride"], 16), R.SOURCE_INVALID)
	# Three indices fit a 4-byte stride in the 12-byte view, so only the index rule refuses this.
	refuse("byte stride on index data", with(["accessors", 3, "count"], 3, with(["bufferViews", 3, "byteStride"], 4)),
		R.SOURCE_INVALID)

	refuse("buffer longer than the BIN chunk", with(["buffers", 0, "byteLength"], 100000), R.SOURCE_INVALID)
	refuse("buffer much shorter than the BIN chunk", with(["buffers", 0, "byteLength"], 8), R.SOURCE_INVALID)
	refuse("buffer without length", without(["buffers", 0, "byteLength"]), R.SOURCE_INVALID)
	var headless := base()
	headless.bin = PackedByteArray()
	refuse("buffer without a BIN chunk", headless, R.SOURCE_INVALID)
	refuse("BIN chunk without a buffer", without(["buffers"]), R.SOURCE_INVALID)

	refuse("accessor count overruns the view", with(["accessors", 1, "count"], 5), R.SOURCE_INVALID)
	refuse("accessor count 2^53", with(["accessors", 1, "count"], 9007199254740992.0), R.SOURCE_INVALID)
	refuse("accessor count 1e30", with(["accessors", 1, "count"], 1e30), R.SOURCE_INVALID)
	refuse("accessor count zero", with(["accessors", 1, "count"], 0), R.SOURCE_INVALID)
	refuse("accessor count fraction", with(["accessors", 1, "count"], 3.5), R.SOURCE_INVALID)
	refuse("accessor offset overruns the view", with(["accessors", 1, "byteOffset"], 12), R.SOURCE_INVALID)
	refuse("accessor offset misaligned", with(["accessors", 1, "byteOffset"], 2), R.SOURCE_INVALID)
	refuse("accessor view out of range", with(["accessors", 1, "bufferView"], 7), R.SOURCE_INVALID)
	refuse("accessor component type", with(["accessors", 1, "componentType"], 5124), R.SOURCE_INVALID)
	refuse("accessor type", with(["accessors", 1, "type"], "VEC5"), R.SOURCE_INVALID)
	refuse("accessor normalized float", with(["accessors", 1, "normalized"], true), R.SOURCE_INVALID)
	refuse("accessor normalized number", with(["accessors", 1, "normalized"], 1), R.SOURCE_INVALID)
	refuse("accessor min of the wrong size", with(["accessors", 1, "min"], [0.0, 0.0]), R.SOURCE_INVALID)
	# A view offset that leaves float data unaligned.
	var shifted := with(["bufferViews", 1, "byteOffset"], 50)
	refuse("view offset misaligns float data", with(["bufferViews", 1, "byteLength"], 46, shifted), R.SOURCE_INVALID)


func _test_meshes() -> void:
	refuse("POSITION without min and max", without(["accessors", 0, "max"]), R.SOURCE_INVALID)
	var no_min := without(["accessors", 0, "min"])
	refuse("POSITION without min", no_min, R.SOURCE_INVALID)
	refuse("POSITION min above max", with(["accessors", 0, "min"], [0.0, 2.0, 0.0]), R.SOURCE_INVALID)
	refuse("positions outside the declared max", with(["accessors", 0, "max"], [0.5, 1.0, 0.0]), R.SOURCE_INVALID)
	refuse("positions outside the declared min", with(["accessors", 0, "min"], [0.0, 0.25, 0.0]), R.SOURCE_INVALID)
	check("declared bounds may be wider", GlbPreflight.inspect(pack(with(["accessors", 0, "max"], [5.0, 5.0, 5.0]))).ok)
	check("bounds slack of one float32 step", GlbPreflight.inspect(pack(with(["accessors", 0, "max"],
		[0.9999999, 0.9999999, 0.0]))).ok)
	refuse("bounds off by more than the slack", with(["accessors", 0, "max"], [0.99999, 1.0, 0.0]), R.SOURCE_INVALID)

	for value: float in [NAN, INF, -INF]:
		refuse("position %s" % str(value), poke_float(0 + 12 + 4, value), R.SOURCE_INVALID)
		refuse("normal %s" % str(value), poke_float(48 + 8, value), R.SOURCE_INVALID)
		refuse("uv %s" % str(value), poke_float(96 + 4, value), R.SOURCE_INVALID)
		refuse("second surface position %s" % str(value), poke_float(140, value), R.SOURCE_INVALID)

	refuse("JOINTS_0", with(["meshes", 0, "primitives", 0, "attributes", "JOINTS_0"], 1), R.SOURCE_UNSUPPORTED)
	refuse("WEIGHTS_0", with(["meshes", 0, "primitives", 0, "attributes", "WEIGHTS_0"], 1), R.SOURCE_UNSUPPORTED)
	refuse("TEXCOORD_2", with(["meshes", 0, "primitives", 0, "attributes", "TEXCOORD_2"], 2), R.SOURCE_UNSUPPORTED)
	refuse("COLOR_1", with(["meshes", 0, "primitives", 0, "attributes", "COLOR_1"], 1), R.SOURCE_UNSUPPORTED)
	refuse("custom attribute", with(["meshes", 0, "primitives", 0, "attributes", "_BATCHID"], 1), R.SOURCE_UNSUPPORTED)
	check("TEXCOORD_1, TANGENT-free, COLOR_0 as float VEC3", GlbPreflight.inspect(pack(with(["meshes", 0, "primitives", 0,
		"attributes", "COLOR_0"], 1, with(["meshes", 0, "primitives", 0, "attributes", "TEXCOORD_1"], 2)))).ok)
	# COLOR_0 may be normalized bytes or shorts; other packed attributes are outside the subset.
	for entry: Array in [["VEC4", 5121, true, "COLOR_0", "ok"], ["VEC4", 5123, true, "COLOR_0", "ok"],
			["VEC3", 5121, true, "COLOR_0", R.SOURCE_INVALID], ["VEC4", 5121, false, "COLOR_0", R.SOURCE_INVALID],
			["VEC2", 5123, true, "TEXCOORD_0", R.SOURCE_UNSUPPORTED], ["VEC2", 5123, false, "TEXCOORD_0", R.SOURCE_INVALID],
			["VEC3", 5122, true, "NORMAL", R.SOURCE_INVALID]]:
		var packed := with(["accessors", 6], {"bufferView": 2, "componentType": entry[1], "normalized": entry[2],
			"count": 4, "type": entry[0]})
		refuse("%s as %s of %d normalized %s" % [entry[3], entry[0], entry[1], entry[2]],
			with(["meshes", 0, "primitives", 0, "attributes", entry[3]], 6, packed), entry[4])
	refuse("NORMAL as VEC2",with(["meshes", 0, "primitives", 0, "attributes", "NORMAL"], 2), R.SOURCE_INVALID)
	refuse("TEXCOORD_0 as VEC3", with(["meshes", 0, "primitives", 0, "attributes", "TEXCOORD_0"], 1), R.SOURCE_INVALID)
	refuse("POSITION as indices", with(["meshes", 0, "primitives", 0, "attributes", "POSITION"], 3), R.SOURCE_INVALID)
	refuse("TANGENT as VEC3", with(["meshes", 0, "primitives", 0, "attributes", "TANGENT"], 1), R.SOURCE_INVALID)
	refuse("attributes of different lengths", with(["meshes", 0, "primitives", 0, "attributes", "NORMAL"], 5), R.SOURCE_INVALID)
	refuse("no POSITION", without(["meshes", 0, "primitives", 0, "attributes", "POSITION"]), R.SOURCE_INVALID)
	refuse("no attributes", without(["meshes", 0, "primitives", 0, "attributes"]), R.SOURCE_INVALID)
	refuse("empty primitives", with(["meshes", 0, "primitives"], []), R.SOURCE_INVALID)
	refuse("attribute accessor out of range", with(["meshes", 0, "primitives", 0, "attributes", "NORMAL"], 6), R.SOURCE_INVALID)
	refuse("index accessor out of range", with(["meshes", 0, "primitives", 0, "indices"], 6), R.SOURCE_INVALID)
	refuse("material out of range", with(["meshes", 0, "primitives", 0, "material"], 2), R.SOURCE_INVALID)
	refuse("float indices", with(["meshes", 0, "primitives", 0, "indices"], 2), R.SOURCE_INVALID)
	refuse("vertex data from an index view", with(["bufferViews", 1, "target"], 34963), R.SOURCE_INVALID)
	refuse("indices from a vertex view", with(["bufferViews", 3, "target"], 34962), R.SOURCE_INVALID)

	# Indices: every value below the vertex count, and whole triangles only.
	refuse("index out of range", poke_u16(128 + 10, 4), R.SOURCE_INVALID)
	refuse("index 65535", poke_u16(128, 65535), R.SOURCE_INVALID)
	check("highest legal index", GlbPreflight.inspect(pack(poke_u16(128 + 10, 3))).ok)
	refuse("index count not a multiple of 3", with(["accessors", 3, "count"], 5), R.SOURCE_INVALID)
	refuse("index count 4", with(["accessors", 3, "count"], 4), R.SOURCE_INVALID)
	# Without indices the 4-vertex surface is not a whole number of triangles.
	refuse("non-indexed vertex count not a multiple of 3", without(["meshes", 0, "primitives", 0, "indices"]),
		R.SOURCE_INVALID)
	# The second surface indexed by the first one's indices: index 3 does not exist among 3 vertices.
	refuse("shared index accessor too large for a surface", with(["meshes", 0, "primitives", 1, "indices"], 3),
		R.SOURCE_INVALID)


func _test_materials_and_images() -> void:
	refuse("texture index out of range", with(["materials", 0, "pbrMetallicRoughness", "baseColorTexture", "index"], 1),
		R.SOURCE_INVALID)
	refuse("texture index fraction", with(["materials", 0, "pbrMetallicRoughness", "baseColorTexture", "index"], 0.5),
		R.SOURCE_INVALID)
	check("texCoord 1", GlbPreflight.inspect(pack(with(["materials", 0, "pbrMetallicRoughness", "baseColorTexture",
		"texCoord"], 1))).ok)
	refuse("texCoord 2", with(["materials", 0, "pbrMetallicRoughness", "baseColorTexture", "texCoord"], 2),
		R.SOURCE_UNSUPPORTED)
	refuse("texCoord -1", with(["materials", 0, "pbrMetallicRoughness", "baseColorTexture", "texCoord"], -1),
		R.SOURCE_INVALID)
	refuse("normal texture out of range", with(["materials", 1, "normalTexture"], {"index": 3, "scale": 1.0}),
		R.SOURCE_INVALID)
	check("normal, occlusion and emissive textures", GlbPreflight.inspect(pack(with(["materials", 1, "emissiveTexture"],
		{"index": 0}, with(["materials", 1, "occlusionTexture"], {"index": 0, "strength": 0.5},
		with(["materials", 1, "normalTexture"], {"index": 0, "scale": 1.0}))))).ok)
	refuse("base colour factor above one", with(["materials", 1, "pbrMetallicRoughness", "baseColorFactor"],
		[2.0, 0.0, 0.0, 1.0]), R.SOURCE_INVALID)
	refuse("base colour factor with three numbers", with(["materials", 1, "pbrMetallicRoughness", "baseColorFactor"],
		[1.0, 0.0, 0.0]), R.SOURCE_INVALID)
	refuse("roughness below zero", with(["materials", 0, "pbrMetallicRoughness", "roughnessFactor"], -0.1), R.SOURCE_INVALID)
	refuse("alpha mode", with(["materials", 0, "alphaMode"], "ADD"), R.SOURCE_INVALID)
	check("alpha blend", GlbPreflight.inspect(pack(with(["materials", 0, "alphaMode"], "BLEND"))).ok)
	refuse("double-sided number", with(["materials", 0, "doubleSided"], 1), R.SOURCE_INVALID)
	refuse("texture source out of range", with(["textures", 0, "source"], 1), R.SOURCE_INVALID)
	refuse("texture without a source", without(["textures", 0, "source"]), R.SOURCE_INVALID)
	refuse("sampler out of range", with(["textures", 0, "sampler"], 1), R.SOURCE_INVALID)
	refuse("sampler filter", with(["samplers", 0, "magFilter"], 9987), R.SOURCE_INVALID)
	refuse("sampler wrap", with(["samplers", 0, "wrapS"], 1), R.SOURCE_INVALID)

	# The declared type decides, and the bytes must then be a PNG the strict checker accepts.
	for mime: String in ["image/jpeg", "image/webp", "image/ktx2", "image/PNG", "application/octet-stream"]:
		refuse("image type " + mime, with(["images", 0, "mimeType"], mime), R.SOURCE_UNSUPPORTED)
	refuse("image without a type", without(["images", 0, "mimeType"]), R.SOURCE_INVALID)
	refuse("image type number", with(["images", 0, "mimeType"], 1), R.SOURCE_INVALID)
	refuse("image view out of range", with(["images", 0, "bufferView"], 7), R.SOURCE_INVALID)
	refuse("image without data", without(["images", 0, "bufferView"]), R.SOURCE_INVALID)
	refuse("image bytes are vertex data", with(["images", 0, "bufferView"], 0), R.SOURCE_INVALID)
	var jpeg := with_image(PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1,
		0, 0, 0xFF, 0xD9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	refuse("JPEG bytes labelled PNG", jpeg, R.SOURCE_INVALID)
	var damaged := texture_png.duplicate()
	damaged[damaged.size() - 14] ^= 0x10
	refuse("PNG with a damaged checksum", with_image(damaged), R.SOURCE_INVALID)
	refuse("truncated PNG", with_image(texture_png.slice(0, texture_png.size() - 12)), R.SOURCE_INVALID)
	# An iTXt chunk spliced in after IHDR: the PNG checker's refusal is passed on.
	var annotated := texture_png.slice(0, 33)
	annotated.append_array(png_chunk("iTXt", "Comment".to_ascii_buffer()))
	annotated.append_array(texture_png.slice(33))
	var forwarded: Dictionary = GlbPreflight.inspect(pack(with_image(annotated)))
	check("PNG with text metadata", not forwarded.ok and forwarded.diagnostics[0].code == R.SOURCE_UNSUPPORTED
		and forwarded.diagnostics[0].field == "images/0")

	# Aggregate budget: two 4096 x 2048 images fill it exactly; one more pixel is over.
	var half := blank_png(Limits.PNG_SIDE_PIXELS, Limits.PNG_SIDE_PIXELS / 2)
	var full := with_image(half)
	full.json.images.append({"bufferView": 6, "mimeType": "image/png"})
	var at_budget: Dictionary = GlbPreflight.inspect(pack(full))
	check("image pixels at the budget " + str(R.texts(at_budget)), at_budget.ok and at_budget.value.images.size() == 2
		and at_budget.value.images[0].pixels + at_budget.value.images[1].pixels == Limits.PNG_AGGREGATE_PIXELS)
	var bin: PackedByteArray = full.bin
	var dot_at := bin.size()
	var dot := blank_png(1, 1)
	bin.append_array(dot)
	full.bin = bin
	full.json.bufferViews.append({"buffer": 0, "byteOffset": dot_at, "byteLength": dot.size()})
	full.json.images.append({"bufferView": 7, "mimeType": "image/png"})
	full.json.buffers[0].byteLength = bin.size()
	refuse("image pixels over the budget", full, R.SOURCE_LIMIT)
	var only_dot := base()
	only_dot.json.images = []
	only_dot.json.textures = []
	only_dot.json.materials[0].pbrMetallicRoughness.erase("baseColorTexture")
	for _index: int in Limits.GLB_IMAGES:
		only_dot.json.images.append({"bufferView": 6, "mimeType": "image/png"})
	check("images at the limit", GlbPreflight.inspect(pack(only_dot)).ok)
	only_dot.json.images.append({"bufferView": 6, "mimeType": "image/png"})
	refuse("images over the limit", only_dot, R.SOURCE_LIMIT)


func _test_ceilings() -> void:
	# One mesh of 400 triangles on 3 vertices, instanced by many nodes.
	var single: Dictionary = GlbPreflight.inspect(pack(instanced(1, 400, 3)))
	check("400 triangles per instance", single.ok and single.value.counts.triangles == 400)
	var at_limit: Dictionary = GlbPreflight.inspect(pack(instanced(Limits.TRIANGLES / 400, 400, 3)))
	check("triangles at the ceiling", at_limit.ok and at_limit.value.counts.triangles == Limits.TRIANGLES
		and at_limit.value.counts.mesh_instances == Limits.TRIANGLES / 400)
	refuse("triangles over the ceiling by instancing", instanced(Limits.TRIANGLES / 400 + 1, 400, 3), R.SOURCE_LIMIT)
	# One triangle on 1500 vertices: the expanded vertex ceiling is reached by instancing too.
	var vertices_ok: Dictionary = GlbPreflight.inspect(pack(instanced(Limits.EXPANDED_VERTICES / 1500, 1, 1500)))
	check("vertices at the ceiling", vertices_ok.ok and vertices_ok.value.counts.vertices == Limits.EXPANDED_VERTICES)
	refuse("vertices over the ceiling by instancing", instanced(Limits.EXPANDED_VERTICES / 1500 + 1, 1, 1500), R.SOURCE_LIMIT)
	# A mesh no node uses is still built by the importer: it counts once.
	var spare := instanced(1, Limits.TRIANGLES / 2, 3)
	spare.json.meshes.append(spare.json.meshes[0].duplicate(true))
	var spare_ok: Dictionary = GlbPreflight.inspect(pack(spare))
	check("unused mesh inside the ceiling", spare_ok.ok and spare_ok.value.counts.triangles == Limits.TRIANGLES / 2)
	var spare_over := instanced(1, Limits.TRIANGLES / 2 + 1, 3)
	spare_over.json.meshes.append(spare_over.json.meshes[0].duplicate(true))
	refuse("unused mesh over the ceiling", spare_over, R.SOURCE_LIMIT)

	var surfaces := base()
	var surface: Dictionary = surfaces.json.meshes[0].primitives[1]
	surfaces.json.meshes[0].primitives = []
	for _index: int in Limits.GLB_PRIMITIVES:
		surfaces.json.meshes[0].primitives.append(surface.duplicate(true))
	var most: Dictionary = GlbPreflight.inspect(pack(surfaces))
	check("surfaces at the limit", most.ok and most.value.counts.primitives == Limits.GLB_PRIMITIVES
		and most.value.counts.triangles == 2 * Limits.GLB_PRIMITIVES)
	surfaces.json.meshes[0].primitives.append(surface.duplicate(true))
	refuse("surfaces over the limit", surfaces, R.SOURCE_LIMIT)

	for entry: Array in [["meshes", Limits.GLB_MESHES], ["materials", Limits.GLB_MATERIALS],
			["accessors", Limits.GLB_ACCESSORS], ["bufferViews", Limits.GLB_BUFFER_VIEWS]]:
		var grown := base()
		var list: Array = grown.json[entry[0]]
		while list.size() < int(entry[1]):
			list.append((list[list.size() - 1] as Dictionary).duplicate(true))
		check("%s at the limit" % entry[0], GlbPreflight.inspect(pack(grown)).ok)
		list.append((list[list.size() - 1] as Dictionary).duplicate(true))
		refuse("%s over the limit" % entry[0], grown, R.SOURCE_LIMIT)


## The admitted subset is something the pinned importer accepts without a warning.
func _test_engine_accepts_the_subset() -> void:
	var bytes := pack(base())
	var inspected: Dictionary = GlbPreflight.inspect(bytes)
	check("preflight passes before the importer runs", inspected.ok)
	if not inspected.ok:
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check("importer reads the fixture", document.append_from_buffer(bytes, "", state) == OK)
	var scene := document.generate_scene(state)
	check("importer builds a scene", scene != null)
	if scene == null:
		return
	var instances := 0
	var surfaces := 0
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			instances += 1
			surfaces += (node as MeshInstance3D).mesh.get_surface_count()
		pending.append_array(node.get_children())
	check("importer builds %d mesh instances (got %d)" % [inspected.value.counts.mesh_instances, instances],
		instances == int(inspected.value.counts.mesh_instances))
	check("importer builds two surfaces per instance (got %d)" % surfaces, surfaces == 4)
	scene.free()


# --- fixtures ---------------------------------------------------------------------------------

## A rigid tree: a root with two nodes sharing one two-surface mesh, a textured and a plain material.
func base() -> Dictionary:
	var bin := floats([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0])           # 0: quad positions
	bin.append_array(floats([0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]))     # 48: quad normals
	bin.append_array(floats([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0]))                         # 96: quad UVs
	bin.append_array(shorts([0, 1, 2, 0, 2, 3]))                                                 # 128: quad indices
	bin.append_array(floats([0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0]))                     # 140: triangle positions
	bin.append_array(floats([0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]))                     # 176: triangle normals
	bin.append_array(texture_png)                                                                # 212: PNG
	var json := {
		"asset": {"version": "2.0", "generator": "test_creator_glb"},
		"extensionsUsed": ["KHR_materials_emissive_strength", "KHR_materials_ior"],
		"scene": 0,
		"scenes": [{"name": "Scene", "nodes": [0]}],
		"nodes": [
			{"name": "Root", "children": [1, 2], "extras": {"note": [1, {"extensions": {"IGNORED": 1}}]}},
			{"name": "Part", "mesh": 0, "translation": [1.0, 0.0, 0.0]},
			{"name": "Part", "mesh": 0, "translation": [-1.0, 0.0, 0.0], "rotation": [0.0, HALF, 0.0, HALF],
				"scale": [2.0, 2.0, 2.0]}],
		"meshes": [{"name": "Body", "primitives": [
			{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0},
			{"attributes": {"POSITION": 4, "NORMAL": 5}, "material": 1, "mode": 4}]}],
		"materials": [
			{"name": "paint", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
				"roughnessFactor": 0.8}, "emissiveFactor": [0.1, 0.1, 0.1],
				"extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": 2.0}}},
			{"name": "plain", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.1, 0.1, 1.0]},
				"extensions": {"KHR_materials_ior": {"ior": 1.45}}}],
		"textures": [{"source": 0, "sampler": 0}],
		"samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
		"images": [{"name": "paint", "bufferView": 6, "mimeType": "image/png"}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [0.0, 0.0, 0.0], "max": [1.0, 1.0, 0.0]},
			{"bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC3"},
			{"bufferView": 2, "componentType": 5126, "count": 4, "type": "VEC2"},
			{"bufferView": 3, "componentType": 5123, "count": 6, "type": "SCALAR"},
			{"bufferView": 4, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0.0, 0.0, 1.0], "max": [1.0, 1.0, 1.0]},
			{"bufferView": 5, "componentType": 5126, "count": 3, "type": "VEC3"}],
		"bufferViews": [
			{"buffer": 0, "byteOffset": 0, "byteLength": 48, "target": 34962},
			{"buffer": 0, "byteOffset": 48, "byteLength": 48, "target": 34962},
			{"buffer": 0, "byteOffset": 96, "byteLength": 32, "target": 34962},
			{"buffer": 0, "byteOffset": 128, "byteLength": 12, "target": 34963},
			{"buffer": 0, "byteOffset": 140, "byteLength": 36, "target": 34962},
			{"buffer": 0, "byteLength": 36, "byteOffset": 176, "target": 34962},
			{"buffer": 0, "byteOffset": 212, "byteLength": texture_png.size()}],
		"buffers": [{"byteLength": bin.size()}],
	}
	return {"json": json, "bin": bin}


## One triangle whose positions and normals share a buffer view with a 24-byte stride.
func interleaved() -> Dictionary:
	var bin := floats([0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 2.0, 0.0, 0.0, 0.0, 1.0])
	var json := {
		"asset": {"version": "2.0"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}}]}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0.0, 0.0, 0.0], "max": [1.0, 2.0, 0.0]},
			{"bufferView": 0, "byteOffset": 12, "componentType": 5126, "count": 3, "type": "VEC3"}],
		"bufferViews": [{"buffer": 0, "byteLength": 72, "byteStride": 24, "target": 34962}],
		"buffers": [{"byteLength": 72}],
	}
	return {"json": json, "bin": bin}


## `instances` nodes under one root, all using one indexed mesh of `triangles` on `vertices`.
func instanced(instances: int, triangles: int, vertices: int) -> Dictionary:
	var bin := PackedByteArray()
	bin.resize(vertices * 12)
	bin.encode_float(12, 1.0)
	bin.encode_float(28, 1.0)
	var index_at := bin.size()
	for _triangle: int in triangles:
		bin.append_array(PackedByteArray([0, 0, 1, 0, 2, 0]))
	var nodes: Array = [{"name": "root", "children": []}]
	for index: int in instances:
		nodes[0].children.append(index + 1)
		nodes.append({"mesh": 0, "translation": [float(index), 0.0, 0.0]})
	var json := {
		"asset": {"version": "2.0"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": nodes,
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": vertices, "type": "VEC3", "min": [0.0, 0.0, 0.0],
				"max": [1.0, 1.0, 0.0]},
			{"bufferView": 1, "componentType": 5123, "count": triangles * 3, "type": "SCALAR"}],
		"bufferViews": [{"buffer": 0, "byteLength": vertices * 12}, {"buffer": 0, "byteOffset": index_at,
			"byteLength": triangles * 6}],
		"buffers": [{"byteLength": bin.size()}],
	}
	return {"json": json, "bin": bin}


## The base model as a single chain of `depth` nodes with the mesh at the end.
func chain(depth: int) -> Dictionary:
	var fixture := base()
	var nodes: Array = []
	for index: int in depth:
		nodes.append({"name": "link", "children": [index + 1]} if index < depth - 1 else {"name": "tip", "mesh": 0})
	fixture.json.nodes = nodes
	return fixture


## The base model as one root with `count - 1` children; the first child carries the mesh.
func fan(count: int) -> Dictionary:
	var fixture := base()
	var nodes: Array = [{"name": "hub", "children": []}]
	for index: int in range(1, count):
		nodes[0].children.append(index)
		nodes.append({"mesh": 0} if index == 1 else {})
	fixture.json.nodes = nodes
	return fixture


## The base model with node 2's TRS replaced by a matrix.
func matrix_node(matrix: Array) -> Dictionary:
	var fixture := base()
	fixture.json.nodes[2] = {"name": "Part", "mesh": 0, "matrix": matrix}
	return fixture


## The base model with its embedded image bytes replaced.
func with_image(image: PackedByteArray) -> Dictionary:
	var fixture := base()
	var bin: PackedByteArray = (fixture.bin as PackedByteArray).slice(0, 212)
	bin.append_array(image)
	fixture.bin = bin
	fixture.json.bufferViews[6].byteLength = image.size()
	fixture.json.buffers[0].byteLength = bin.size()
	return fixture


func poke_float(at: int, value: float) -> Dictionary:
	var fixture := base()
	var bin: PackedByteArray = fixture.bin
	bin.encode_float(at, value)
	fixture.bin = bin
	return fixture


func poke_u16(at: int, value: int) -> Dictionary:
	var fixture := base()
	var bin: PackedByteArray = fixture.bin
	bin.encode_u16(at, value)
	fixture.bin = bin
	return fixture


## Sets `value` at `path` in the JSON of `fixture` (a fresh base model by default). An index
## equal to an array's size appends.
func with(path: Array, value: Variant, fixture: Dictionary = {}) -> Dictionary:
	var target := base() if fixture.is_empty() else fixture
	var node: Variant = target.json
	for index: int in path.size() - 1:
		node = node[path[index]]
	var last: Variant = path[path.size() - 1]
	if node is Array and int(last) == (node as Array).size():
		(node as Array).append(value)
	else:
		node[last] = value
	return target


func without(path: Array, fixture: Dictionary = {}) -> Dictionary:
	var target := base() if fixture.is_empty() else fixture
	var node: Variant = target.json
	for index: int in path.size() - 1:
		node = node[path[index]]
	(node as Dictionary).erase(path[path.size() - 1])
	return target


## Rewrites one spot of the JSON text of a packed model, to spell numbers `JSON.stringify` cannot.
func raw_json(glb: PackedByteArray, find: String, replace: String) -> PackedByteArray:
	var size := glb.decode_u32(12)
	var text := glb.slice(20, 20 + size).get_string_from_utf8()
	check("raw JSON edit finds its text: " + find, text.count(find) == 1)
	var edited := text.replace(find, replace).strip_edges().to_utf8_buffer()
	var chunks: Array = [[CHUNK_JSON, pad(edited, 0x20)]]
	if glb.size() > 20 + size:
		chunks.append([CHUNK_BIN, glb.slice(28 + size)])
	return container(chunks)


## A GLB whose only chunk is this JSON text.
func json_text(text: String) -> PackedByteArray:
	return container([[CHUNK_JSON, pad(text.to_utf8_buffer(), 0x20)]])


func json_bytes(json: Dictionary) -> PackedByteArray:
	return pad(JSON.stringify(json, "", false).to_utf8_buffer(), 0x20)


func pack(fixture: Dictionary) -> PackedByteArray:
	var chunks: Array = [[CHUNK_JSON, json_bytes(fixture.json)]]
	if not (fixture.bin as PackedByteArray).is_empty():
		chunks.append([CHUNK_BIN, pad(fixture.bin, 0)])
	return container(chunks)


## A GLB container from `[type, payload]` pairs, written exactly as given.
func container(chunks: Array) -> PackedByteArray:
	var out := u32(MAGIC)
	out.append_array(u32(2))
	out.append_array(u32(0))
	for entry: Array in chunks:
		var payload: PackedByteArray = entry[1]
		out.append_array(u32(payload.size()))
		out.append_array(u32(int(entry[0])))
		out.append_array(payload)
	out.encode_u32(8, out.size())
	return out


func pad(bytes: PackedByteArray, filler: int) -> PackedByteArray:
	var out := bytes.duplicate()
	while out.size() % 4 != 0:
		out.append(filler)
	return out


func u32(value: int) -> PackedByteArray:
	var out := PackedByteArray([0, 0, 0, 0])
	out.encode_u32(0, value)
	return out


func floats(values: Array) -> PackedByteArray:
	return PackedFloat32Array(values).to_byte_array()


func shorts(values: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(values.size() * 2)
	for index: int in values.size():
		out.encode_u16(index * 2, int(values[index]))
	return out


## Bitwise CRC-32, independent of the module under test.
func crc(bytes: PackedByteArray) -> int:
	var value := 0xFFFFFFFF
	for byte: int in bytes:
		value ^= byte
		for _bit: int in 8:
			value = (value >> 1) ^ (0xEDB88320 * (value & 1))
	return value ^ 0xFFFFFFFF


func png_chunk(kind: String, data: PackedByteArray) -> PackedByteArray:
	var body := kind.to_ascii_buffer()
	body.append_array(data)
	var out := PackedByteArray([(data.size() >> 24) & 0xFF, (data.size() >> 16) & 0xFF, (data.size() >> 8) & 0xFF,
		data.size() & 0xFF])
	out.append_array(body)
	var sum := crc(body)
	out.append_array(PackedByteArray([(sum >> 24) & 0xFF, (sum >> 16) & 0xFF, (sum >> 8) & 0xFF, sum & 0xFF]))
	return out


## An all-zero 1-bit greyscale PNG, hand-assembled: large in pixels, tiny in bytes.
func blank_png(width: int, height: int) -> PackedByteArray:
	var header := PackedByteArray([(width >> 24) & 0xFF, (width >> 16) & 0xFF, (width >> 8) & 0xFF, width & 0xFF,
		(height >> 24) & 0xFF, (height >> 16) & 0xFF, (height >> 8) & 0xFF, height & 0xFF, 1, 0, 0, 0, 0])
	var raw := PackedByteArray()
	raw.resize(height * (1 + (width + 7) / 8))
	var out := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	out.append_array(png_chunk("IHDR", header))
	out.append_array(png_chunk("IDAT", raw.compress(FileAccess.COMPRESSION_DEFLATE)))
	out.append_array(png_chunk("IEND", PackedByteArray()))
	return out


func close(actual: PackedFloat64Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in expected.size():
		if absf(actual[index] - float(expected[index])) > 1.0e-9:
			return false
	return true


func refuse(label: String, fixture: Variant, code: String) -> void:
	expect(label, fixture if fixture is PackedByteArray else pack(fixture), code)


func expect(label: String, bytes: PackedByteArray, code: String) -> void:
	var result: Dictionary = GlbPreflight.inspect(bytes)
	var got := "ok"
	if not result.ok:
		got = str(result.diagnostics[0].code)
	check("%s -> %s (got %s%s)" % [label, code, got, "" if result.ok else ": " + R.texts(result)[0]], got == code
		and result.has("value") == result.ok)


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: " + label)
