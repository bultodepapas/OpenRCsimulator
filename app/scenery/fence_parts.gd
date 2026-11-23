## CR-17a: one fence recipe for visual beams, collision envelopes and local damage IDs.
extends RefCounted
const Palette := preload("res://scenery/palette.gd")
const MeshKit := preload("res://scenery/mesh_kit.gd")
const ClubSign := preload("res://scenery/club_sign.gd")
const GATE_HEIGHT := 1.86
const GATE_BOTTOM := 0.22
const GATE_TOP := 1.36
const GATE_PLATE_OFFSET := 0.20
const STOCK_GATE_HEIGHT := 1.48

## Points are render X/Z. Each post and each rail/wire bay can fail independently.
static func build(points: PackedVector2Array, style: String, seed: int) -> Array[Dictionary]:
	if style == "gate":
		return _gate(points)
	if style == "stock_gate":
		return _stock_gate(points, seed)
	var result: Array[Dictionary] = []
	var wire := style in ["wire", "barbed"]
	var spacing := 3.6 if style == "barbed" else (3.0 if wire else 2.5)
	var post := Palette.col("wood_grey") if wire else Palette.col("wood")
	for segment: int in points.size() - 1:
		var a := points[segment]
		var b := points[segment + 1]
		var length := a.distance_to(b)
		if length <= 1.0e-6:
			continue
		var bays := maxi(1, roundi(length / spacing))
		for at: int in bays + (1 if segment == points.size() - 2 else 0):
			var p := a.lerp(b, float(at) / bays)
			var lean := (Palette.hash01(seed, segment * 1000 + at) - 0.5) * 0.06
			var stake := {id = "%02d:post:%02d" % [segment, at], part = "post", profile = "wood",
				a = Vector3(p.x, 0, p.y), b = Vector3(p.x + lean, 1.25 if wire else 1.15, p.y),
				width = 0.10 if wire else 0.13, color = post.darkened(0.15 * Palette.hash01(seed, at, segment))}
			if style == "barbed":
				var grain := Palette.hash01(seed, segment * 1000 + at, 37)
				stake.stake_angle = grain * TAU
				stake.width = 0.17 if at == 0 or at == bays else lerpf(0.10, 0.135, grain)
				stake.b = Vector3(p.x + lean, 1.24 + grain * 0.15, p.y)
			result.append(stake)
		var levels: Array = [0.55, 0.85, 1.12] if wire else [0.45, 0.95]
		for bay: int in bays:
			var start := a.lerp(b, float(bay) / bays)
			var finish := a.lerp(b, float(bay + 1) / bays)
			for level: int in levels.size():
				var height: float = levels[level]
				var piece := {id = "%02d:bay:%02d:%d" % [segment, bay, level], part = "wire" if wire else style,
					profile = "wire" if wire else "wood", a = Vector3(start.x, height, start.y),
					b = Vector3(finish.x, height, finish.y), width = 0.012 if wire else 0.08,
					color = Palette.col("steel") if wire else post.lightened(0.05)}
				if style == "barbed" and level == levels.size() - 1:
					piece.barbs = true
				result.append(piece)
	return result


## Hinge and latch are authored across the road. Open the leaf 96 degrees left of hinge-to-latch.
static func gate_tip(hinge: Vector2, latch: Vector2) -> Vector2:
	return hinge + (latch - hinge).rotated(deg_to_rad(-96.0))


static func _gate(points: PackedVector2Array) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if points.size() != 2 or points[0].distance_to(points[1]) < 1.0:
		return parts
	var hinge := Vector3(points[0].x, 0, points[0].y)
	var latch := Vector3(points[1].x, 0, points[1].y)
	var span := hinge.distance_to(latch)
	var tip := gate_tip(points[0], points[1])
	var along := hinge.direction_to(Vector3(tip.x, 0.0, tip.y))
	for base: Vector3 in [hinge, latch]:
		parts.append({id = "hinge" if base == hinge else "latch", part = "post", profile = "masonry",
			a = base, b = base + Vector3.UP * GATE_HEIGHT, width = 0.36, color = Palette.col("wall_white")})
	parts[1].catch_direction = latch.direction_to(hinge)
	var mid_height := Vector3.UP * (GATE_TOP + GATE_BOTTOM) * 0.5
	var a := hinge + along * 0.14 + mid_height
	var b := hinge + along * (span - 0.14) + mid_height
	parts.append({id = "leaf", part = "gate", profile = "metal", width = 0.064,
		color = Palette.col("door_green"), a = a, b = b, members = gate_members(a, b, 0.064)})
	return parts


## Closed timber leaf. The broad planks are face-nailed to two stiles; a compression
## brace rises from the hinge end to the latch. Both jambs are part of this gate.
static func _stock_gate(points: PackedVector2Array, seed: int) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if points.size() != 2 or points[0].distance_to(points[1]) < 1.0:
		return parts
	var hinge := Vector3(points[0].x, 0, points[0].y)
	var latch := Vector3(points[1].x, 0, points[1].y)
	var along := hinge.direction_to(latch)
	var across := along.cross(Vector3.UP)
	var wood := Palette.col("wood").lerp(Palette.col("wood_grey"), 0.53)
	for base: Vector3 in [hinge, latch]:
		parts.append({id = "hinge" if base == hinge else "latch", part = "post", profile = "wood",
			a = base, b = base + Vector3.UP * STOCK_GATE_HEIGHT, width = 0.24,
			color = wood.darkened(0.20), stake_angle = TAU * Palette.hash01(seed, parts.size())})
	var a := hinge + along * 0.14
	var b := latch - along * 0.14
	var boards: Array[Dictionary] = []
	for height: float in [0.28, 0.57, 0.89, 1.23]:
		var level := Vector3.UP * height
		boards.append({a = a + level, b = b + level, width = 0.048, face = 0.14})
	var lower := Vector3.UP * 0.21
	var upper := Vector3.UP * 1.30
	var heel := a + along * 0.065 + across * 0.050
	var toe := b - along * 0.065 + across * 0.050
	for end: Vector3 in [heel, toe]:
		boards.append({a = end + lower, b = end + upper, width = 0.055, face = 0.13})
	boards.append({a = heel + along * 0.065 + Vector3.UP * 0.28,
		b = toe - along * 0.065 + Vector3.UP * 1.23, width = 0.055, face = 0.105})
	var centre := Vector3.UP * 0.755
	parts.append({id = "leaf", part = "gate", profile = "wood", width = 0.048,
		color = wood, a = a + centre, b = b + centre, members = boards})
	return parts


## Decorations enter the same damage range as their supporting piece.
static func draw(k: MeshKit, piece: Dictionary, club_entrance: bool = false) -> void:
	var a: Vector3 = piece.a
	var b: Vector3 = piece.b
	if piece.part == "gate":
		if piece.profile == "wood":
			_stock_gate_leaf(k, piece)
			return
		_gate_leaf(k, a, b, piece.members, piece.color)
		if club_entrance:
			var along := a.direction_to(b)
			var saved := k.xf
			k.xf *= Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)),
				a.lerp(b, 0.36) + Vector3.UP * GATE_PLATE_OFFSET)
			ClubSign.gate_plate(k, gate_plate_width(a, b))
			k.xf = saved
		return
	if piece.profile == "masonry":
		var span: float = piece.width
		k.block(Vector3(span, 0.38, span), a, Palette.col("wall_brick"))
		k.block(Vector3(span - 0.06, GATE_HEIGHT - 0.47, span - 0.06),
			a + Vector3.UP * 0.38, piece.color)
		k.block(Vector3(span, 0.09, span), b - Vector3.UP * 0.09, Palette.col("wall_brick").darkened(0.20))
	elif piece.has("stake_angle"):
		_split_stake(k, a, b, piece.width, piece.stake_angle, piece.color)
	elif piece.part in ["wire", "rail"]:
		_span(k, a, b, piece.width, piece.color, piece.part == "wire")
	else:
		k.beam(a, b, piece.width, piece.color)
	if piece.has("catch_direction"):
		# Receiver on the inside face of the latch post, aligned with the bolt on the closed leaf.
		var toward: Vector3 = piece.catch_direction
		var socket := a + toward * 0.19 + Vector3.UP * lerpf(GATE_BOTTOM, GATE_TOP, 0.70)
		k.beam(socket - toward * 0.08, socket + toward * 0.06, 0.085, Palette.col("steel"))
	if piece.get("barbs", false):
		# Small crossed twists on the top strand. Two triangles per tine keep long runs inexpensive.
		var along := a.direction_to(b)
		var across := along.cross(Vector3.UP)
		var count := maxi(1, roundi(a.distance_to(b) / 0.85))
		for index: int in count:
			var p := a.lerp(b, (index + 0.5) / count)
			for sign_: float in [-1.0, 1.0]:
				var tip := p + sign_ * (Vector3.UP * 0.045 + across * 0.027)
				k.tri(p - along * 0.025, tip, p + along * 0.017, piece.color)
				k.tri(p + along * 0.017, tip, p - along * 0.025 + across * 0.012, piece.color)


## Five split faces and an oblique saw cut, with weathered end grain.
static func _split_stake(k: MeshKit, a: Vector3, b: Vector3, width: float, yaw: float, wood: Color) -> void:
	var top := PackedVector3Array()
	var foot := PackedVector3Array()
	for i in 5:
		var angle := yaw + TAU * float(i) / 5.0
		var offset := Vector3(cos(angle), 0, sin(angle)) * width * 0.5
		foot.append(a + offset)
		top.append(b + offset * 0.84 - Vector3.UP * (width * 0.23 + offset.x * 0.42))
	for i in 5:
		var j := (i + 1) % 5
		k.quad(foot[i], top[i], top[j], foot[j], wood.darkened(0.035 * (i % 3)))
	# Ascending angles wind clockwise when seen from above.
	top.reverse()
	k.poly(top, wood.lightened(0.14))


## The strand/rail ends sit inside posts. Omit their caps and use a triangular
## cross-section on the 12 mm wire; keep broad square faces on the timber rails.
static func _span(k: MeshKit, a: Vector3, b: Vector3, width: float, color: Color, wire: bool) -> void:
	var lateral := a.direction_to(b).cross(Vector3.UP) * (width * 0.5)
	var up := Vector3.UP * (width * 0.5)
	var section := PackedVector3Array([-up - lateral, -up + lateral])
	if wire:
		section.append(up)
	else:
		section.append(up + lateral)
		section.append(up - lateral)
	for i in section.size():
		var c := section[i]
		var d := section[(i + 1) % section.size()]
		k.quad(a + c, b + c, b + d, a + d, color)


static func gate_plate_width(a: Vector3, b: Vector3) -> float:
	return minf(1.55, a.distance_to(b) * 0.64)


static func gate_members(a: Vector3, b: Vector3, diameter: float) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	var top := Vector3.UP * (GATE_TOP - GATE_BOTTOM) * 0.5
	var mid := (a + b) * 0.5
	for upright: Vector3 in [a, mid, b]:
		members.append({a = upright - top, b = upright + top, width = diameter})
	for fraction: float in [-1.0, -0.34, 0.34, 1.0]:
		members.append({a = a + top * fraction, b = b + top * fraction, width = diameter})
	members.append({a = a - top, b = mid + top, width = 0.042})
	members.append({a = mid + top, b = b - top, width = 0.042})
	return members


static func _gate_leaf(k: MeshKit, a: Vector3, b: Vector3, members: Array, paint: Color) -> void:
	for tube: Dictionary in members:
		_tube(k, tube.a, tube.b, tube.width, paint)
	var top := Vector3.UP * (GATE_TOP - GATE_BOTTOM) * 0.5
	var along := a.direction_to(b)
	for level: float in [-0.78, 0.78]:
		var pin := a + level * top
		k.beam(pin - along * 0.14, pin, 0.07, Palette.col("steel"))
		_tube(k, pin - Vector3.UP * 0.07, pin + Vector3.UP * 0.07, 0.09, Palette.col("steel"))
	k.beam(b + along * 0.12 + top * 0.40, b - along * 0.22 + top * 0.40, 0.045, Palette.col("steel"))


static func _stock_gate_leaf(k: MeshKit, piece: Dictionary) -> void:
	var saved := k.xf
	var a: Vector3 = piece.a
	var b: Vector3 = piece.b
	var along := a.direction_to(b)
	var across := along.cross(Vector3.UP)
	var wood: Color = piece.color
	for i in piece.members.size():
		var board: Dictionary = piece.members[i]
		var start: Vector3 = board.a
		var end: Vector3 = board.b
		var axis := start.direction_to(end)
		k.xf = saved * Transform3D(Basis(axis, across.cross(axis), across), (start + end) * 0.5)
		var grain := wood.darkened(Palette.hash01(i, 73) * 0.19)
		k.box(Vector3(start.distance_to(end), board.face, board.width), Vector3.ZERO, grain, true, grain.lightened(0.06))
	# Dark strap hinges over two boards; exposed bolt heads and a sliding bolt at the latch.
	k.xf = saved * Transform3D(Basis(along, Vector3.UP, across), Vector3(a.x, 0.0, a.z))
	var iron := Palette.col("steel_dark").darkened(0.30)
	for level: float in [0.28, 1.23]:
		k.box(Vector3(0.45, 0.056, 0.016), Vector3(0.165, level, -0.032), iron, true)
		k.beam(Vector3(-0.06, level - 0.064, -0.035), Vector3(-0.06, level + 0.064, -0.035), 0.044, iron)
		for x: float in [0.067, 0.31]:
			k.box(Vector3(0.025, 0.025, 0.009), Vector3(x, level, -0.043), Palette.col("steel"), true)
	var extent := a.distance_to(b)
	k.box(Vector3(0.23, 0.035, 0.030), Vector3(extent - 0.045, 0.89, -0.039), iron, true)
	k.xf = saved


static func _tube(k: MeshKit, a: Vector3, b: Vector3, diameter: float, color: Color) -> void:
	var axis := a.direction_to(b)
	var across := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.UP).normalized()
	var saved := k.xf
	k.xf *= Transform3D(Basis(across, axis, across.cross(axis)), a)
	k.cylinder(diameter * 0.5, diameter * 0.5, a.distance_to(b), 8, Vector3.ZERO, color, true, null, true)
	k.xf = saved
