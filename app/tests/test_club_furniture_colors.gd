extends SceneTree

const Kit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const Wood = preload("res://assets/landscape/flightline/Wood049_1K-JPG_Color.jpg")
var _checks := 0
var _failures := 0


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var builder_path := "res://scenery/club_furniture.gd"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--builder="): builder_path = arg.trim_prefix("--builder=")
	var builder: Script = load(builder_path)
	var wood: Image = Wood.get_image()
	wood.resize(96, 64, Image.INTERPOLATE_LANCZOS)
	var transforms: Array[Transform3D] = [Transform3D.IDENTITY,
		Transform3D(Basis(Vector3.UP, 0.71), Vector3(4, 2, -3)),
		Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3(-2, 1, 5)),
		Transform3D(Basis(Vector3.FORWARD, -0.43).scaled(Vector3(2, 0.8, 1.3)), Vector3(2, -1, 3))]
	for fixture in 6:
		var segments: int = [-2, 1, 4, 6, 14, 16][fixture]
		var seed: int = [-19, -1, 0, 7, 23, 193][fixture]
		var length_m := 0.7 + fixture * 0.23
		var width := 0.08 + fixture * 0.015
		var thickness := 0.025 + fixture * 0.005
		var tone := Color(0.3 + fixture * 0.08, 0.24, 0.13, 0.4)
		var local := Kit.new()
		builder.board(local, length_m, width, thickness, Vector3.ZERO, Basis.IDENTITY, seed, tone, segments)
		var side_count := 48 * (maxi(1, segments) + 2)
		_check("fixture %d triangle count" % fixture, local.cols.size() == side_count + 36)
		var expected := PackedColorArray()
		# Independent scalar oracle samples emitted local vertices, not cached rings.
		for index in side_count:
			expected.append(_sample(wood, local.verts[index], seed, tone))
		for index in 36:
			expected.append(tone.darkened(0.08))
		_check("fixture %d source grain and cap colors" % fixture, local.cols == expected)
		for transform: Transform3D in transforms:
			var kit := Kit.new()
			kit.box(Vector3.ONE, Vector3.ZERO, Color.MAGENTA)
			kit.tag_damage(0, "prefix")
			var first := kit.verts.size()
			var prefix := var_to_bytes([kit.verts, kit.norms, kit.cols, kit.damage_ranges])
			kit.xf = transform
			builder.board(kit, length_m, width, thickness, Vector3(0.3, 0.5, -0.2),
				Basis(Vector3.RIGHT, 0.47), seed, tone, segments)
			_check("fixture %d transformed colors" % fixture, kit.cols.slice(first) == expected)
			_check("fixture %d restored transform" % fixture, kit.xf == transform)
			_check("fixture %d preserved prefix and damage ranges" % fixture,
				var_to_bytes([kit.verts.slice(0, first), kit.norms.slice(0, first),
					kit.cols.slice(0, first), kit.damage_ranges]) == prefix)
	_check_furniture_plank(builder, "picnic", 16, 0.142, Vector3(0, 0.735, -0.304), 0, 3228)
	_check_furniture_plank(builder, "bench", 14, 0.13, Vector3(0, 0.455, -0.145), 12, 2116)
	print("club furniture colors: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## Inspect the first painted plank in each production prefab against its full-detail timber.
func _check_furniture_plank(builder: Script, id: String, segments: int, width: float, centre: Vector3,
		seed: int, triangles: int) -> void:
	var actual := Kit.new()
	builder.call(id, actual)
	_check(id + " retains its furniture within the fitted triangle count", actual.triangle_count() == triangles)
	var reference := Kit.new()
	builder.board(reference, 1.8, width, 0.05, centre, Basis.IDENTITY, seed, Palette.col("wood_light"), segments)
	var cursor := 0
	var valid := true
	for ring in segments + 2:
		for face in 8:
			var narrow := face % 2 == 0 and ring >= 1 and ring <= segments
			if narrow and ring % 2 == 0:
				continue
			var first := 6 * (8 * ring + face)
			var last := first + 48 if narrow else first
			# Adjacent strips retain the four outer corners of the two source quads.
			for source: int in [first, last + 1, last + 2, first + 3, first + 4, last + 5]:
				valid = valid and actual.verts[cursor] == reference.verts[source] \
					and actual.cols[cursor] == reference.cols[source] \
					and actual.norms[cursor].is_equal_approx(reference.norms[source])
				cursor += 1
	var caps := reference.verts.size() - 36
	_check(id + " preserves plank broad faces, chamfer corners, normals and sampled grain", valid)
	_check(id + " retains both original plank end caps", actual.verts.slice(cursor, cursor + 36) == reference.verts.slice(caps)
		and actual.cols.slice(cursor, cursor + 36) == reference.cols.slice(caps))


func _sample(wood: Image, point: Vector3, seed: int, tone: Color) -> Color:
	var u := fposmod(point.x / 0.8 + float(seed) * 0.173, 1.0)
	var v := fposmod((point.z + point.y * 2.0) / 0.8 + float(seed) * 0.319, 1.0)
	var pixel := wood.get_pixel(int(u * 95), int(v * 63))
	var light := (pixel.r + pixel.g + pixel.b) / 3.0
	var shade := clampf(1.0 + (light - 0.39) * 3.0, 0.78, 1.18)
	shade *= 0.91 + 0.13 * float(seed % 5) / 4.0
	return Color(tone.r * shade, tone.g * shade, tone.b * shade, 1.0)
