## SC-BIRD-03: species silhouettes built from the planform data (birds.json), true size, in the mesh's XZ plane:
## nose +Z, wings along +-X, up +Y; a keel and the arm's leading-edge strip give depth when seen edge-on.
## Every species of a MultiMesh shares one topology (the group's finger slots; a three-triangle tail whose notch is
## forward for a forked tail, on the end line for a square one and behind it for a wedge), so group_mesh() can store
## each species' shape in CUSTOM0..3 and a bird draws only its own triangles. CUSTOMn.w packs the rig weights as
## tail + 2 * hand (hand: outboard of the wrist; tail: 0 at its root, 1 at its end). UV.y is the feather shade.
extends RefCounted

const FINGER_FILL := 0.72 # share of each finger slot covered by the feather; the rest is the gap
const LEADING_EDGE_THICKNESS := 0.06 # arm depth at the root as a share of the root chord [est]
const WEDGE_POINT := 0.35 # a wedge tail's point lies this share of the tail length behind its corners [est]
const MAX_SPECIES := 4 # CUSTOM0..3
const PART_BODY := 0 # per-vertex part labels (build().parts), for the tests
const PART_WING := 1
const PART_TAIL := 2


## {vertices, weights, shades, parts, rig: Vector4(shoulder x, wrist x, tail root z, half span), triangles}.
## finger_slots: the group's finger count (a species with fewer fingers leaves the rest as zero-area triangles).
static func build(planform: Dictionary, span: float, finger_slots: int) -> Dictionary:
	var out := {vertices = PackedVector3Array(), weights = PackedFloat32Array(), shades = PackedFloat32Array(),
		parts = PackedByteArray()}
	var half: float = span * 0.5
	var length: float = planform.body_length
	var shoulder: float = planform.body_width * 0.5
	var le0: float = length * 0.12
	var root_te: float = le0 - float(planform.root_chord)
	var nose: float = length * 0.45
	var tail_root: float = minf(-length * 0.55, root_te + float(planform.root_chord) * 0.1)
	var wrist: float = shoulder + float(planform.wrist) * (half - shoulder)
	var wrist_le: float = le0 + float(planform.wrist_sweep)
	var wrist_te: float = wrist_le - float(planform.wrist_chord)
	var tip_le: float = le0 + float(planform.tip_sweep)
	var tip_te: float = tip_le - float(planform.tip_chord)
	var ctx := {out = out, wrist = wrist, tail_root = tail_root, tail_length = 0.0, part = PART_BODY}
	# Body: nose, shoulders and tail root.
	var n := _v(0.0, nose)
	var rl := _v(shoulder, le0)
	var ll := _v(-shoulder, le0)
	var rt := _v(shoulder, root_te)
	var lt := _v(-shoulder, root_te)
	var t := _v(0.0, tail_root)
	_tri(ctx, [n, rl, ll], [0.0, 0.0, 0.0])
	_tri(ctx, [ll, rl, rt], [0.0, 0.0, 0.0])
	_tri(ctx, [ll, rt, lt], [0.0, 0.0, 0.0])
	_tri(ctx, [lt, rt, t], [0.0, 0.0, 0.0])
	# Keel: the body's depth, so a bird seen edge-on (level wings at a low elevation) keeps a visible body.
	var depth: float = planform.body_width * 0.5
	var mid := (nose + tail_root) * 0.5
	_tri(ctx, [n, Vector3(0.0, depth, mid), t], [0.0, 0.0, 0.0])
	_tri(ctx, [n, t, Vector3(0.0, -depth, mid)], [0.0, 0.0, 0.0])
	_tail(ctx, planform, shoulder)
	var thickness: float = float(planform.root_chord) * LEADING_EDGE_THICKNESS
	var fingers: int = mini(int(planform.fingers), finger_slots)
	ctx.part = PART_WING
	for side: float in [1.0, -1.0]:
		var a_le := _v(side * shoulder, le0)
		var a_te := _v(side * shoulder, root_te)
		var w_le := _v(side * wrist, wrist_le)
		var w_te := _v(side * wrist, wrist_te)
		_quad(ctx, [a_le, a_te, w_te, w_le], [0.0, 0.55, 0.65, 0.3])
		# The arm's thick leading edge (coverts), a strip under the leading edge: visible when the wing is edge-on.
		var a_low := Vector3(side * shoulder, -thickness, le0 - thickness)
		var w_low := Vector3(side * wrist, -thickness * 0.6, wrist_le - thickness * 0.6)
		_quad(ctx, [a_le, a_low, w_low, w_le], [0.0, 0.2, 0.3, 0.3])
		var t_le := _v(side * half, tip_le)
		var t_te := _v(side * half, tip_te)
		if finger_slots == 0:
			# Pointed or square hand; with a zero tip chord the second triangle has no area.
			_quad(ctx, [w_le, w_te, t_te, t_le], [0.3, 0.65, 1.0, 1.0])
			continue
		var finger_length: float = float(planform.finger_length) if fingers > 0 else 0.0
		var base_x: float = wrist + (1.0 - finger_length) * (half - wrist)
		var f: float = (base_x - wrist) / maxf(half - wrist, 1e-6)
		var b_le := _v(side * base_x, lerpf(wrist_le, tip_le, f))
		var b_te := _v(side * base_x, lerpf(wrist_te, tip_te, f))
		_quad(ctx, [w_le, w_te, b_te, b_le], [0.3, 0.65, 0.85, 0.75])
		var nearest := INF # the longest finger reaches the wing tip exactly, so the silhouette keeps its span
		for i: int in fingers:
			nearest = minf(nearest, absf((float(i) + FINGER_FILL * 0.5) / fingers - 0.45))
		for i: int in finger_slots:
			if i >= fingers:
				_tri(ctx, [t_le, t_le, t_le], [1.0, 1.0, 1.0]) # unused slot: zero area at the tip
				continue
			var u0: float = float(i) / fingers
			var u1: float = u0 + FINGER_FILL / fingers
			var um: float = (u0 + u1) * 0.5
			# The leading primaries are a little shorter, so the hand is rounded rather than square.
			var reach: float = 1.0 - 0.3 * (absf(um - 0.45) - nearest)
			var tip := _v(side * (base_x + (half - base_x) * reach), lerpf(tip_le, tip_te, um))
			_tri(ctx, [b_le.lerp(b_te, u0), b_le.lerp(b_te, u1), tip], [0.85, 0.85, 1.0])
	out.rig = Vector4(shoulder, wrist, tail_root, half)
	out.triangles = out.vertices.size() / 3
	return out


## One indexed ArrayMesh for a MultiMesh: VERTEX and UV from the first species, each species' shape and rig weights in
## CUSTOM0..3 (unused slots repeat the first species). All builds must share the topology (same corner count). Corners
## identical in every attribute (all species' shapes, weights and shade) become one vertex, so the vertex shader runs
## once per distinct vertex instead of once per triangle corner.
static func group_mesh(builds: Array) -> ArrayMesh:
	var first: Dictionary = builds[0]
	var count: int = (first.vertices as PackedVector3Array).size()
	var slots: Array = []
	for slot: int in MAX_SPECIES:
		var b: Dictionary = builds[slot] if slot < builds.size() else first
		assert((b.vertices as PackedVector3Array).size() == count, "bird species in one MultiMesh need one topology")
		slots.append(b)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var customs: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(),
		PackedFloat32Array()]
	var indices := PackedInt32Array()
	var seen: Dictionary = {}
	for i: int in count:
		var key: Array = [first.shades[i]]
		for b: Dictionary in slots:
			key.append(b.vertices[i])
			key.append(b.weights[i])
		var index: int = seen.get(key, -1)
		if index < 0:
			index = vertices.size()
			seen[key] = index
			vertices.append(first.vertices[i])
			normals.append(Vector3.UP)
			uvs.append(Vector2(0.0, first.shades[i]))
			for slot: int in MAX_SPECIES:
				var v: Vector3 = slots[slot].vertices[i]
				customs[slot].append_array([v.x, v.y, v.z, slots[slot].weights[i]])
		indices.append(index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags := 0
	for slot: int in MAX_SPECIES:
		arrays[Mesh.ARRAY_CUSTOM0 + slot] = customs[slot]
		flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + slot * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


## Unpacks a CUSTOMn.w rig weight into [hand, tail] (as sky_birds.gdshader does).
static func unpack_weight(w: float) -> Array[float]:
	var hand: float = 1.0 if w > 1.5 else 0.0
	return [hand, w - 2.0 * hand]


## Three triangles for every tail shape (the topology is shared): the notch is forward of the end line by the fork
## for a forked tail, on it for a square tail, and behind it for a wedge. A missing tail collapses to its root.
static func _tail(ctx: Dictionary, planform: Dictionary, shoulder: float) -> void:
	var length: float = planform.tail_length
	var root: float = ctx.tail_root
	var root_half: float = maxf(shoulder * 0.7, 1e-3)
	var end_half: float = maxf(float(planform.tail_width) * 0.5, root_half)
	var end_z: float = root - length
	var notch_z: float = end_z
	match str(planform.tail_shape):
		"forked":
			notch_z = end_z + float(planform.tail_fork)
		"wedge":
			notch_z = end_z - length * WEDGE_POINT
	if length <= 1e-4:
		end_half = root_half
		notch_z = root
	var rl := _v(-root_half, root)
	var rr := _v(root_half, root)
	var el := _v(-end_half, end_z)
	var er := _v(end_half, end_z)
	var notch := _v(0.0, notch_z)
	ctx.tail_length = maxf(length * (1.0 + WEDGE_POINT), 1e-4)
	ctx.part = PART_TAIL
	_tri(ctx, [rl, rr, notch], [0.0, 0.0, 0.4])
	_tri(ctx, [rr, er, notch], [0.0, 0.6, 0.4])
	_tri(ctx, [rl, notch, el], [0.0, 0.4, 0.6])
	ctx.tail_length = 0.0
	ctx.part = PART_BODY


static func _quad(ctx: Dictionary, p: Array, shade: Array) -> void:
	_tri(ctx, [p[0], p[1], p[2]], [shade[0], shade[1], shade[2]])
	_tri(ctx, [p[0], p[2], p[3]], [shade[0], shade[2], shade[3]])


## Appends one triangle; the rig weights follow from each vertex's position and part.
static func _tri(ctx: Dictionary, p: Array, shade: Array) -> void:
	var out: Dictionary = ctx.out
	for i: int in 3:
		var v: Vector3 = p[i]
		var hand: float = 1.0 if int(ctx.part) == PART_WING and absf(v.x) > float(ctx.wrist) + 1e-5 else 0.0
		var tail := 0.0
		if int(ctx.part) == PART_TAIL:
			# Vertices on the tail root edge stay with the body (rounding must not give them a tiny tail weight).
			tail = (float(ctx.tail_root) - v.z) / float(ctx.tail_length)
			tail = 0.0 if tail < 1e-4 else minf(tail, 1.0)
		out.vertices.append(v)
		out.weights.append(tail + 2.0 * hand)
		out.shades.append(float(shade[i]))
		out.parts.append(int(ctx.part))


static func _v(x: float, z: float) -> Vector3:
	return Vector3(x, 0.0, z)
