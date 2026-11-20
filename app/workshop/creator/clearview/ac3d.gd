extends RefCounted
## Bounded AC3Db scene reader. Geometry, local hierarchy and material/UV semantics only.
const R := preload("res://workshop/creator/result.gd")
const MAX_BYTES := 32 * 1024 * 1024
const MAX_NODES := 512
const MAX_VERTICES := 200000
const MAX_SURFACES := 200000
const MAX_REFS := 600000
var _bytes := PackedByteArray()
var _at := 0
var _error := ""
var _nodes: Array = []
var _materials: Array = []
var _vertices := 0
var _surfaces := 0
var _refs := 0
var _degenerate := 0
var _number := RegEx.new()
var _cancel := Callable()

static func read(bytes: PackedByteArray, cancel := Callable()) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return R.fail(R.SOURCE_LIMIT, "The AC3D model is empty or exceeds 32 MiB.", "source", "import")
	var reader := new()
	reader._bytes = bytes
	reader._cancel = cancel
	reader._number.compile("^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]{1,3})?$")
	return reader._read()

func _read() -> Dictionary:
	if _line() != "AC3Db":
		return R.fail(R.SOURCE_UNSUPPORTED, "Only AC3Db (version 11) models are supported.", "source", "import")
	var roots: Array[int] = []
	while _at < _bytes.size() and _error.is_empty():
		var tokens := _tokens(_line())
		if tokens.is_empty():
			continue
		if tokens[0] == "MATERIAL":
			_material(tokens)
		elif tokens[0] == "OBJECT":
			var node := _object(tokens, -1, 0)
			if node >= 0:
				roots.append(node)
		else:
			_fail("An unknown AC3D record changes the scene format.")
	if not _error.is_empty():
		return R.fail(R.SOURCE_INVALID, _error, "source", "import")
	if _nodes.is_empty() or _materials.is_empty():
		return R.fail(R.SOURCE_INVALID, "The AC3D scene has no objects or material palette.", "source", "import")
	var notes: Array = []
	if _degenerate > 0:
		notes.append(R.diagnostic(R.SOURCE_INVALID, "%s legacy polygons have fewer than three references; their coordinates are retained as markers.", "source", "import", [str(_degenerate)], R.SEVERITY_INFO))
	return R.ok({nodes = _nodes, roots = roots, materials = _materials, degenerate_polygons = _degenerate}, notes)

func _line() -> String:
	var start := _at
	while _at < _bytes.size() and _bytes[_at] != 10:
		var value := _bytes[_at]
		if (value < 32 and value not in [9, 13]) or value > 126 or _at - start > 65536:
			_fail("An AC3D line contains unsupported text or is too long.")
			_at = _bytes.size()
			return ""
		_at += 1
	var text := _bytes.slice(start, _at).get_string_from_ascii().strip_edges()
	_at = mini(_at + 1, _bytes.size())
	return text

func _tokens(line: String) -> Array[String]:
	var result: Array[String] = []
	var at := 0
	while at < line.length():
		if line[at] in [" ", "\t"]:
			at += 1
			continue
		var value := ""
		if line[at] == "\"":
			at += 1
			while at < line.length() and line[at] != "\"":
				value += line[at]
				at += 1
			if at == line.length():
				_fail("An AC3D quoted string is not terminated.")
				return []
			at += 1
			if at < line.length() and line[at] not in [" ", "\t"]:
				_fail("An AC3D quoted string has unexpected trailing text.")
				return []
		else:
			var start := at
			while at < line.length() and line[at] not in [" ", "\t"]:
				at += 1
			value = line.substr(start, at - start)
		result.append(value)
		if result.size() > 32:
			_fail("An AC3D record has too many fields.")
			return []
	return result

func _material(t: Array[String]) -> void:
	if t.size() != 22 or t[2] != "rgb" or t[6] != "amb" or t[10] != "emis" or t[14] != "spec" or t[18] != "shi" or t[20] != "trans" or _materials.size() >= 128:
		_fail("The AC3D material palette is invalid or exceeds its limit.")
		return
	var rgb := _floats(t.slice(3, 6))
	var ambient := _floats(t.slice(7, 10))
	var emission := _floats(t.slice(11, 14))
	var specular := _floats(t.slice(15, 18))
	var shininess := _float(t[19])
	var transparent := _float(t[21])
	for values: Array in [rgb, ambient, emission, specular]:
		for value: float in values:
			if value < 0.0 or value > 1.0:
				_fail("An AC3D material colour is outside the supported range.")
	if shininess < 0.0 or shininess > 128.0 or transparent < 0.0 or transparent > 1.0:
		_fail("An AC3D material has an unsupported opacity or shininess.")
	_materials.append({name = t[1], rgb = rgb, ambient = ambient, specular = specular, emission = emission, shininess = shininess, opacity = 1.0 - transparent})

func _object(header: Array[String], parent: int, depth: int) -> int:
	if depth > 32 or _nodes.size() >= MAX_NODES or header.size() != 2 or header[1] not in ["world", "group", "poly"]:
		_fail("The AC3D object type, hierarchy or object count is unsupported.")
		return -1
	var index := _nodes.size()
	var node := {name = "Object %d" % index, type = header[1], parent = parent, children = [], loc = [0.0,0.0,0.0],
		rot = [1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0], texture = "", texrep = [1.0,1.0], texoff = [0.0,0.0],
		crease = 45.0, vertices = [], surfaces = [], has_data = false}
	_nodes.append(node)
	var seen := {}
	while _at < _bytes.size() and _error.is_empty():
		if _cancel.is_valid() and bool(_cancel.call()):
			_fail("The import was cancelled.")
			return -1
		var t := _tokens(_line())
		if t.is_empty():
			continue
		var key := t[0]
		if seen.has(key):
			_fail("An AC3D object repeats a structural field.")
			return -1
		seen[key] = true
		match key:
			"name", "texture", "url":
				if t.size() != 2 or t[1].length() > 512:
					_fail("An AC3D name or texture reference is invalid.")
				elif key != "url":
					node[key] = t[1]
			"loc", "rot", "texrep", "texoff":
				var count := 9 if key == "rot" else (3 if key == "loc" else 2)
				if t.size() != count + 1:
					_fail("An AC3D transform has the wrong number of components.")
				else:
					node[key] = _floats(t.slice(1))
			"crease":
				if t.size() != 2:
					_fail("An AC3D crease angle is invalid.")
				else:
					node.crease = _float(t[1])
					if node.crease < 0.0 or node.crease > 180.0:
						_fail("An AC3D crease angle is outside the supported range.")
			"data":
				node.has_data = true
				var count := _count(t, 65536)
				if _at + count > _bytes.size():
					_fail("An AC3D object data block is truncated.")
				else:
					_at += count
			"subdiv":
				# The control shape is imported unsmoothed; the converter reports it.
				var levels := _count(t, 8)
				if levels > 0:
					node.subdiv = levels
			"numvert":
				var count := _count(t, MAX_VERTICES - _vertices)
				_vertices += count
				for vertex: int in count:
					if vertex % 256 == 0 and _cancelled():
						break
					var v := _tokens(_line())
					if v.size() != 3:
						_fail("An AC3D vertex must contain three finite coordinates.")
						break
					node.vertices.append(_floats(v))
					if not _error.is_empty():
						break
			"numsurf":
				var count := _count(t, MAX_SURFACES - _surfaces)
				_surfaces += count
				for face: int in count:
					if face % 256 == 0 and _cancelled():
						break
					var surface := _surface(node.vertices.size())
					if not _error.is_empty():
						break
					node.surfaces.append(surface)
			"kids":
				var count := _count(t, MAX_NODES - _nodes.size())
				for child: int in count:
					var h := _tokens(_line())
					while h.is_empty() and _at < _bytes.size() and _error.is_empty():
						h = _tokens(_line())
					if h.is_empty() or h[0] != "OBJECT":
						_fail("An AC3D child object is missing.")
						break
					var child_index := _object(h, index, depth + 1)
					if child_index < 0:
						break
					node.children.append(child_index)
				return index
			_:
				_fail("The AC3D model uses an unsupported object property: %s." % key)
	_fail("An AC3D object is missing its kids terminator.")
	return -1

func _surface(vertex_count: int) -> Dictionary:
	var t := _tokens(_line())
	if t.size() != 2 or t[0] != "SURF":
		_fail("An AC3D surface header is missing.")
		return {}
	var raw := t[1]
	var flags := -1
	if raw.begins_with("0x") and raw.length() <= 6 and raw.is_valid_hex_number(true):
		flags = raw.hex_to_int()
	elif raw.is_valid_int() and raw.length() <= 4:
		flags = raw.to_int()
	if flags < 0 or flags & ~0x33 or (flags & 15) not in [0,1,2]:
		_fail("An AC3D surface uses unsupported flags.")
		return {}
	var material := 0
	t = _tokens(_line())
	if not t.is_empty() and t[0] == "mat":
		material = _count(t, _materials.size() - 1)
		t = _tokens(_line())
	if t.is_empty() or t[0] != "refs":
		_fail("An AC3D surface is missing its vertex references.")
		return {}
	var count := _count(t, mini(256, MAX_REFS - _refs))
	if (flags & 15) == 0 and count < 3:
		_degenerate += 1
	_refs += count
	var refs: Array = []
	for index: int in count:
		if index % 64 == 0 and _cancelled():
			break
		t = _tokens(_line())
		if t.size() != 3:
			_fail("An AC3D surface reference is invalid.")
			break
		var vertex := _count(["index", t[0]], vertex_count - 1)
		refs.append({vertex = vertex, uv = [_float(t[1]), _float(t[2])]})
	return {flags = flags, material = material, refs = refs}

func _count(t: Array, maximum: int) -> int:
	if t.size() != 2 or not str(t[1]).is_valid_int() or str(t[1]).length() > 9:
		_fail("An AC3D count or index is invalid.")
		return 0
	var value := int(t[1])
	if value < 0 or value > maximum:
		_fail("An AC3D count or index exceeds its allowed range.")
		return 0
	return value

func _float(token: String) -> float:
	if not _error.is_empty():
		return 0.0
	if token.length() > 32 or _number.search(token) == null:
		_fail("An AC3D number is malformed.")
		return 0.0
	var exponent := token.to_lower().split("e")
	if exponent.size() == 2 and absi(exponent[1].to_int()) > 38:
		_fail("An AC3D numeric exponent is outside the supported range.")
		return 0.0
	var value := token.to_float()
	if not is_finite(value) or absf(value) > 1.0e9:
		_fail("An AC3D number is non-finite or outside the supported range.")
		return 0.0
	return value

func _floats(tokens: Array) -> Array:
	var result: Array = []
	for token: String in tokens:
		result.append(_float(token))
	return result

func _cancelled() -> bool:
	if _cancel.is_valid() and bool(_cancel.call()):
		_fail("The import was cancelled.")
	return not _error.is_empty()

func _fail(message: String) -> void:
	if _error.is_empty():
		_error = message
