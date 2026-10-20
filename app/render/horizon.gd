## L7: visual-only distant relief. One contiguous mesh replaces the default 40 km rough plane.
## The flight area stays flat; this is deliberately not the L12/L13 physical terrain sampler.
extends RefCounted

const PATH: String = "res://data/fields/horizon.json"
const SAMPLES: int = 1440
const ROWS: int = 25
const INNER_RADII: Array[float] = [50.0, 150.0, 400.0, 800.0]
const HALF_SIZE: float = 20000.0


## Strict committed-profile contract. No random generation or unverified data at runtime.
static func profile(path: String = PATH) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary:
		return {}
	var data: Dictionary = raw
	if data.get("format") != "openrc-horizon-profile v1" or data.get("azimuth_samples") != SAMPLES \
		or data.get("radial_rows") != ROWS or data.get("height_scale") != 256 \
		or data.get("dtype") != "int16_le" or data.get("layout") != "radial_major" \
		or data.get("azimuth_origin") != "north" or data.get("azimuth_direction") != "clockwise" \
		or data.get("azimuth_periodic") != true or data.get("outer_flat_radius_mm") != 20000000:
		return {}
	var radii: Variant = data.get("radii_mm")
	var heights: Variant = data.get("heights_q")
	if not radii is Array or radii.size() != ROWS or not heights is Array or heights.size() != ROWS:
		return {}
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(ROWS * SAMPLES * 2)
	for row: int in ROWS:
		if radii[row] != 1500000 + row * 187500 or not heights[row] is Array or heights[row].size() != SAMPLES:
			return {}
		for col: int in SAMPLES:
			var h: Variant = heights[row][col]
			if not (h is float or h is int) or not is_finite(float(h)) or h != floor(float(h)) or h < 0 or h > 30720:
				return {}
			if (row == 0 or row == ROWS - 1) and h != 0:
				return {}
			payload.encode_s16(2 * (row * SAMPLES + col), int(h))
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(payload)
	if digest.finish().hex_encode() != data.get("sha256"):
		return {}
	return data


static func mesh() -> ArrayMesh:
	var data: Dictionary = profile()
	if data.is_empty():
		push_error("L7 horizon profile missing or invalid: " + PATH)
		return null
	var radii: Array[float] = INNER_RADII.duplicate()
	for r: float in data.radii_mm:
		radii.append(r / 1000.0)
	radii.append(HALF_SIZE)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	vertices.resize(1 + radii.size() * SAMPLES)
	normals.resize(vertices.size())
	vertices[0] = Vector3.ZERO
	# Each ring uses the same azimuths. Keep scalar float64 precision until the vertex boundary.
	var east := PackedFloat64Array()
	var south := PackedFloat64Array()
	east.resize(SAMPLES)
	south.resize(SAMPLES)
	for col: int in SAMPLES:
		var angle: float = TAU * float(col) / SAMPLES
		east[col] = sin(angle)
		south[col] = -cos(angle)
	for row: int in radii.size():
		# Radius, profile row and destination offset are shared by the whole ring.
		var ring_radius: float = radii[row]
		var outer_ring: bool = row == radii.size() - 1
		var height_row: Array = []
		if row >= INNER_RADII.size() and row < INNER_RADII.size() + ROWS:
			height_row = data.heights_q[row - INNER_RADII.size()]
		var has_heights: bool = not height_row.is_empty()
		var vertex_offset: int = 1 + row * SAMPLES
		for col: int in SAMPLES:
			var x: float = east[col]
			var z: float = south[col]
			var radius: float = ring_radius
			# Last row reaches the original square boundary; all other rows are circular.
			if outer_ring:
				radius /= maxf(absf(x), absf(z))
			var h: float = 0.0
			if has_heights:
				h = float(height_row[col]) / 256.0
			vertices[vertex_offset + col] = Vector3(radius * x, h, radius * z)
	# Allocate the fan and ring triangles once, preserving winding and accumulation order.
	indices.resize(SAMPLES * (3 + (radii.size() - 1) * 6))
	var cursor: int = 0
	for col: int in SAMPLES:
		indices[cursor] = 0
		indices[cursor + 1] = 1 + col
		indices[cursor + 2] = 1 + (col + 1) % SAMPLES
		cursor += 3
	for row: int in radii.size() - 1:
		for col: int in SAMPLES:
			var a: int = 1 + row * SAMPLES + col
			var b: int = 1 + row * SAMPLES + (col + 1) % SAMPLES
			indices[cursor] = a
			indices[cursor + 1] = a + SAMPLES
			indices[cursor + 2] = b
			indices[cursor + 3] = b
			indices[cursor + 4] = a + SAMPLES
			indices[cursor + 5] = b + SAMPLES
			cursor += 6
	for i: int in range(0, indices.size(), 3):
		var a: int = indices[i]
		var b: int = indices[i + 1]
		var c: int = indices[i + 2]
		# Godot faces are clockwise; geometric cross product points away from the visible face.
		var normal: Vector3 = (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i: int in normals.size():
		normals[i] = normals[i].normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
