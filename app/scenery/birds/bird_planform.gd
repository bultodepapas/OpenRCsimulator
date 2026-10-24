## SC-BIRD-03: species silhouettes built from the planform data (birds.json), true size, flat in the mesh's XZ plane:
## nose +Z, wings along +-X, up +Y. Vertex COLOR carries the shader rig's weights: r = span fraction, g = hand
## (outboard of the wrist), b = tail (0 at the tail root, 1 at its end), a = 1. UV.y is the feather shade (0 body
## colour, 1 dark tips); UV.x is set by atlas() to the species' index in its MultiMesh, so several species share a draw.
extends RefCounted

const FINGER_FILL := 0.72 # share of each finger slot covered by the feather; the rest is the gap


## {vertices, colors, shades, rig: Vector4(shoulder x, wrist x, tail root z, half span), triangles}.
static func build(planform: Dictionary, span: float) -> Dictionary:
	var out := {vertices = PackedVector3Array(), colors = PackedColorArray(), shades = PackedFloat32Array()}
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
	var ctx := {out = out, half = half, wrist = wrist, tail_root = tail_root, tail_length = 0.0}
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
	_tail(ctx, planform, shoulder)
	for side: float in [1.0, -1.0]:
		var a_le := _v(side * shoulder, le0)
		var a_te := _v(side * shoulder, root_te)
		var w_le := _v(side * wrist, wrist_le)
		var w_te := _v(side * wrist, wrist_te)
		_quad(ctx, [a_le, a_te, w_te, w_le], [0.0, 0.55, 0.65, 0.3])
		var fingers: int = int(planform.fingers)
		if fingers == 0:
			var t_le := _v(side * half, tip_le)
			var t_te := _v(side * half, tip_te)
			if float(planform.tip_chord) <= 1e-4:
				_tri(ctx, [w_le, w_te, t_le], [0.3, 0.65, 1.0])
			else:
				_quad(ctx, [w_le, w_te, t_te, t_le], [0.3, 0.65, 1.0, 1.0])
			continue
		var base_x: float = wrist + (1.0 - float(planform.finger_length)) * (half - wrist)
		var f: float = (base_x - wrist) / maxf(half - wrist, 1e-6)
		var b_le := _v(side * base_x, lerpf(wrist_le, tip_le, f))
		var b_te := _v(side * base_x, lerpf(wrist_te, tip_te, f))
		_quad(ctx, [w_le, w_te, b_te, b_le], [0.3, 0.65, 0.85, 0.75])
		for i: int in fingers:
			var u0: float = float(i) / fingers
			var u1: float = u0 + FINGER_FILL / fingers
			var um: float = (u0 + u1) * 0.5
			# The leading primaries are a little shorter, so the hand is rounded rather than square.
			var reach: float = 1.0 - 0.3 * absf(um - 0.45)
			var tip := _v(side * (base_x + (half - base_x) * reach), lerpf(tip_le, tip_te, um))
			_tri(ctx, [b_le.lerp(b_te, u0), b_le.lerp(b_te, u1), tip], [0.85, 0.85, 1.0])
	out.rig = Vector4(shoulder, wrist, tail_root, half)
	out.triangles = out.vertices.size() / 3
	return out


## One ArrayMesh with every species of a MultiMesh; UV.x = species index (0, 1, ...).
static func atlas(builds: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for index: int in builds.size():
		var b: Dictionary = builds[index]
		vertices.append_array(b.vertices)
		colors.append_array(b.colors)
		for s: float in b.shades:
			uvs.append(Vector2(index, s))
			normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _tail(ctx: Dictionary, planform: Dictionary, shoulder: float) -> void:
	var length: float = planform.tail_length
	if length <= 1e-4:
		return
	var root: float = ctx.tail_root
	var root_half: float = maxf(shoulder * 0.7, 1e-3)
	var end_half: float = maxf(float(planform.tail_width) * 0.5, root_half)
	var end_z: float = root - length
	var rl := _v(-root_half, root)
	var rr := _v(root_half, root)
	var el := _v(-end_half, end_z)
	var er := _v(end_half, end_z)
	ctx.tail_length = length
	match str(planform.tail_shape):
		"forked":
			var notch := _v(0.0, end_z + float(planform.tail_fork))
			_tri(ctx, [rl, rr, notch], [0.0, 0.0, 0.4])
			_tri(ctx, [rr, er, notch], [0.0, 0.6, 0.4])
			_tri(ctx, [rl, notch, el], [0.0, 0.4, 0.6])
		"wedge":
			var ml := _v(-end_half, root - length * 0.6)
			var mr := _v(end_half, root - length * 0.6)
			_tri(ctx, [rl, rr, mr], [0.0, 0.0, 0.4])
			_tri(ctx, [rl, mr, ml], [0.0, 0.4, 0.4])
			_tri(ctx, [ml, mr, _v(0.0, end_z)], [0.4, 0.4, 0.6])
		_:
			_tri(ctx, [rl, rr, er], [0.0, 0.0, 0.5])
			_tri(ctx, [rl, er, el], [0.0, 0.5, 0.5])
	ctx.tail_length = 0.0


static func _quad(ctx: Dictionary, p: Array, shade: Array) -> void:
	_tri(ctx, [p[0], p[1], p[2]], [shade[0], shade[1], shade[2]])
	_tri(ctx, [p[0], p[2], p[3]], [shade[0], shade[2], shade[3]])


## Appends one triangle; the rig weights follow from each vertex's position.
static func _tri(ctx: Dictionary, p: Array, shade: Array) -> void:
	var out: Dictionary = ctx.out
	var tail_length: float = ctx.tail_length
	for i: int in 3:
		var v: Vector3 = p[i]
		var x: float = absf(v.x)
		var hand: float = 1.0 if x > float(ctx.wrist) + 1e-5 else 0.0
		var tail: float = clampf((float(ctx.tail_root) - v.z) / tail_length, 0.0, 1.0) if tail_length > 0.0 else 0.0
		out.vertices.append(v)
		out.colors.append(Color(clampf(x / float(ctx.half), 0.0, 1.0), hand, tail, 1.0))
		out.shades.append(float(shade[i]))


static func _v(x: float, z: float) -> Vector3:
	return Vector3(x, 0.0, z)
