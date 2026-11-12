## DR-32: the local race course as an FPV pilot reads it, by day and at night.
##
## Solids: every gate is drawn from its collision boxes, each box a fabric panel at exactly the box's size and place
## (what is seen is what collides), built like a league gate: a woven sleeve between a white PVC tube outside and an
## LED diffuser tube on the aperture, moulded corner connectors, striped side posts and bottom bar, a solid top banner
## with eyelets and the gate number on a rimmed plate on both faces, and a checkered start/finish gate (the last gate
## closes the lap). On the ground each post stands on a foot tube held by two sandbags.
## The entry face's plate is dark with a white number; the exit face's is red, so a pilot who sees red is flying the
## gate the wrong way.
##
## Light (never a solid, never collides): an LED strip on the aperture edge with an additive neon halo into the
## opening, brighter as the sun sets; a start light bar on the start/finish gate (red per countdown second, green at
## GO, yellow on the last lap, blinking white at the finish); and race guidance: the next gate turns lime, its LEDs
## chase and a real light washes it (dusk and night), a chevron bobs above it, a dotted light path flows from the
## previous gate to it, and the gate after it turns amber. A gate flashes white when it is passed. Outside a race
## every gate is calm and gently breathing. Presentation only: nothing here feeds the session.
##
## Cost (DR-32 R1, 2026-11-12): the compatibility renderer pays per draw call, so each gate's four panels are one merged
## mesh (one draw, one shadow caster) and its four halo quads another; feet, sandbags, number plates and start lamps are
## MultiMeshes for the whole course; calm halos are not drawn by day; the exposure compensation is one global shader
## parameter set once per frame. A six-gate course drew 79 calls before, 21 after (with the detail pass). Detail is
## shaded, not modelled.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const Track = preload("res://sim/race/track.gd")
const GateShader = preload("res://vehicles/multirotor/race_gate.gdshader")
const GlowShader = preload("res://vehicles/multirotor/race_glow.gdshader")
const MarkerShader = preload("res://vehicles/multirotor/race_marker.gdshader")
const PlateShader = preload("res://vehicles/multirotor/race_plate.gdshader")

## Global shader parameter carrying exposure ^ -exposure_gamma to every gate, halo and marker material.
const EXPOSURE_PARAM := &"race_exposure_comp"
## Panel colours, alternating by gate index, with the dark stripe between them.
const PANEL_COLORS := [Color(0.93, 0.16, 0.52), Color(0.16, 0.36, 0.98)]
const PANEL_NEXT := Color(0.5, 1.0, 0.08)
const PANEL_AFTER := Color(1.0, 0.68, 0.05)
const PLATE_DARK := Color(0.05, 0.05, 0.07)
const PLATE_BACK := Color(0.42, 0.03, 0.03)
## Plate margin inside the banner: clear of the 0.04 m tubes on its edges.
const PLATE_MARGIN_M := 0.045
const STRIPE_DARK := Color(0.07, 0.07, 0.09)
const LED_CALM := Color(0.75, 0.92, 1.0)
const LED_NEXT := Color(0.3, 1.0, 0.2)
const LED_AFTER := Color(1.0, 0.72, 0.1)
const STRIPE_PERIOD_M := 0.6
## Feet: a PVC tube on the ground along the gate normal under each post, two sandbags across it (m).
const FOOT_TUBE_RADIUS_M := 0.02
const FOOT_TUBE_LENGTH_M := 0.7
## Sandbag size: along the foot tube, across it, height.
const SANDBAG_SIZE := Vector3(0.16, 0.3, 0.09)
const SANDBAG_OFFSET_M := 0.2
## Positions go through float32 transforms (about 1e-6 m of rounding tens of metres out): a post is cut by a bar
## that covers it within this tolerance, and no sliver thinner than it is kept.
const CUT_TOLERANCE_M := 1.0e-4
const PAD_SIZE_M := 1.4
const NUMBER_PIXEL_SIZE := 0.0032
const NUMBER_FONT_SIZE := 96
const NUMBER_PLATE_WIDTH_M := 0.62
const FINISH_PLATE_WIDTH_M := 1.6
## Neon halo depth into the aperture (m) and its energy per state, scaled up as the sun sets.
const HALO_DEPTH_M := 0.32
const HALO_ENERGY := [0.12, 0.45, 0.28]
## Below this night factor calm halos are not drawn (by day they add nothing visible).
const CALM_HALO_NIGHT := 0.25
## Below this night factor the next gate's light is off (by day it adds nothing visible, and costs a light pass).
const GATE_LIGHT_NIGHT := 0.25
## Start light bar: lamps per side of the finish plate, radius and spacing (m).
const LAMPS_PER_SIDE := 3
const LAMP_RADIUS_M := 0.065
const LAMP_SPACING_M := 0.19
const LAMP_OFF := Color(0.08, 0.08, 0.09)
const LAMP_RED := Color(1.0, 0.08, 0.05)
const LAMP_GREEN := Color(0.15, 1.0, 0.25)
const LAMP_YELLOW := Color(1.0, 0.8, 0.1)
## Guidance: path dot spacing and size (m), chevron size and its height above the banner (m), the gate light's range.
const PATH_SPACING_M := 0.9
const PATH_DOT_M := 0.26
const PATH_MAX_DOTS := 160
const CHEVRON_SIZE := Vector2(0.75, 0.55)
const CHEVRON_LIFT_M := 0.8
const GATE_LIGHT_RANGE_M := 7.0
const GATE_LIGHT_STANDOFF_M := 2.2
const GATE_LIGHT_ENERGY := 0.05
## Seconds a passed gate flashes white.
const FLASH_S := 0.45

enum GateState { CALM, NEXT, AFTER }

static var _pad_texture: ImageTexture
static var _exposure_param_added := false

var root: Node3D
## Per gate: [the merged panel MeshInstance3D] (one mesh, the four collision boxes).
var gate_views: Array = []
## Per gate: the collision boxes the panel mesh draws, in render space: [{position, size, basis}] in frame order.
var gate_boxes: Array = []
## Per gate: [its panel material].
var gate_materials: Array = []
## Per gate: [its halo material]; per gate its halo node.
var halo_materials: Array = []
var halo_nodes: Array[MeshInstance3D] = []
var gate_states: Array[int] = []
## Per gate (render space): {centre, normal (the pass direction), up, across, w, h, top (top banner position)}.
var gate_frames: Array = []
var number_labels: Array[Label3D] = []
var feet: MultiMeshInstance3D
var sandbags: MultiMeshInstance3D
var plates: Array[MultiMeshInstance3D] = []
## Start light bar of the start/finish gate (one MultiMesh; lamp k's instances share a colour).
var lamps: MultiMeshInstance3D
var pad: MeshInstance3D
var chevron: MeshInstance3D
var gate_light: OmniLight3D
var path: MultiMeshInstance3D
var next_gate := -1
## 0 by day … 1 at night (from the scene's exposure); scales the light-only elements.
var night := 0.0
## exposure ^ -exposure_gamma; light-only elements and LED emission are multiplied by it.
var exposure_comp := 1.0
## Response of light-only elements to the scene exposure. 0.5 measured on the default field at night (exposure 2497
## under AgX): 1.0 left the neon nearly invisible, 0 burned it to white.
var exposure_gamma := 0.5
## Identity of the prepared course this visual draws.
var course_identity := ""
var _finish := -1
var _pad_render := Vector3.ZERO
var _flash: Array[float] = []
var _lamp_lit := -1
var _lamp_colour := Color()
var _lamp_comp := -1.0
var _energy_night := -1.0
## Lamp k -> its instance indices in the lamp MultiMesh, and the colour it shows (kept here: the rendering server
## owns the instance buffer, and a headless one keeps none).
var _lamp_instances: Array = []
var _lamp_shown: Array[Color] = []


## course: the session's prepared course ({gates[{frames, c, n, w, h, ...}], pad}); night_factor 0 (day) … 1 (the
## exposure read each frame overrides it).
func build(parent: Node3D, course: Dictionary, night_factor := 0.0) -> void:
	_ensure_exposure_param()
	night = clampf(night_factor, 0.0, 1.0)
	root = Node3D.new()
	root.name = "RaceCourse"
	parent.add_child(root)
	course_identity = str(course.get("identity", ""))
	var gates: Array = course.get("gates", [])
	_finish = gates.size() - 1
	var foot_transforms: Array[Transform3D] = []
	var plate_rows: Array = [[], []] # entry, exit: [Transform3D]
	var lamp_transforms: Array[Transform3D] = []
	for index in gates.size():
		_build_gate(index, gates[index], foot_transforms, plate_rows, lamp_transforms)
	feet = _multimesh("Feet", _foot_mesh(), foot_transforms)
	# Two sandbags weigh down each foot, one either side of the post.
	var bag_transforms: Array[Transform3D] = []
	for foot: Transform3D in foot_transforms:
		var along: Vector3 = foot.basis.y
		# Pillow axes: x across the tube (its length), y up, z along the tube.
		var across: Vector3 = Vector3.UP.cross(along).normalized()
		var flat := Basis(across, Vector3.UP, along)
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = foot.origin + along * side * SANDBAG_OFFSET_M
			bag_transforms.append(Transform3D(flat, at + Vector3.UP * (0.5 * SANDBAG_SIZE.z - FOOT_TUBE_RADIUS_M)))
	sandbags = _multimesh("Sandbags", _sandbag_mesh(), bag_transforms)
	for exit in 2:
		var quad := QuadMesh.new()
		var material := ShaderMaterial.new()
		material.shader = PlateShader
		material.set_shader_parameter("plate_color", PLATE_BACK if exit == 1 else PLATE_DARK)
		quad.material = material
		plates.append(_multimesh("BackPlates" if exit == 1 else "NumberPlates", quad, plate_rows[exit]))
	_build_lamps(lamp_transforms)
	_build_pad(course.get("pad", {}))
	_build_guidance()
	set_next(-1)


## The global shader parameter exists once per process (materials compile against it). Outside the editor the
## server's parameter list reads empty (and logs an error), so this script remembers that it added it.
static func _ensure_exposure_param() -> void:
	if _exposure_param_added:
		return
	RenderingServer.global_shader_parameter_add(EXPOSURE_PARAM, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_exposure_param_added = true


func _build_gate(index: int, gate: Dictionary, foot_transforms: Array[Transform3D], plate_rows: Array,
		lamp_transforms: Array[Transform3D]) -> void:
	var boxes: Array = gate.frames
	var c: PackedFloat64Array = gate.c
	var n: PackedFloat64Array = gate.n
	var centre := Frames.ned_to_render([c[0], c[1], c[2]])
	# Gate frame: x across the aperture, y up, z along the normal (every box of a gate shares its heading).
	var basis := Basis(Vector3.UP, -deg_to_rad(float(boxes[0].heading_deg))) if not boxes.is_empty() else Basis()
	var holder := MeshInstance3D.new()
	holder.name = "Gate%d" % (index + 1)
	holder.transform = Transform3D(basis, centre)
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var drawn: Array = []
	var extent := {}
	holder.mesh = _panel_mesh(boxes, holder.transform, drawn, extent)
	var material := ShaderMaterial.new()
	material.shader = GateShader
	material.set_shader_parameter("color_a", PANEL_COLORS[index % PANEL_COLORS.size()])
	material.set_shader_parameter("color_b", STRIPE_DARK)
	material.set_shader_parameter("stripe_period", STRIPE_PERIOD_M)
	material.set_shader_parameter("checker", index == _finish)
	material.set_shader_parameter("frame_extent", Vector4(float(gate.w), float(gate.h), float(extent.get("x_out", 0.0)),
		float(extent.get("y_top", 0.0))))
	material.set_shader_parameter("frame_bottom", float(extent.get("y_bottom", 0.0)))
	material.set_shader_parameter("tube_m", Track.FRAME_THICKNESS_M)
	holder.material_override = material
	root.add_child(holder)
	gate_views.append([holder])
	gate_boxes.append(drawn)
	gate_materials.append([material])
	gate_states.append(GateState.CALM)
	_flash.append(0.0)
	for box: Dictionary in drawn:
		if (box.size as Vector3).y > (box.size as Vector3).x:
			# A foot tube lying on the ground along the gate normal under each post (its axis is the mesh's y).
			var ground: Vector3 = (box.position as Vector3) - Vector3.UP * (0.5 * (box.size as Vector3).y)
			foot_transforms.append(Transform3D(basis * Basis(Vector3.RIGHT, 0.5 * PI), ground + Vector3.UP * FOOT_TUBE_RADIUS_M))
	var normal := Vector3(n[1], -n[2], -n[0]).normalized()
	var top: Vector3 = drawn[2].position if drawn.size() >= 3 else centre
	gate_frames.append({centre = centre, normal = normal, up = basis.y, across = basis.x, w = float(gate.w),
		h = float(gate.h), top = top})
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = _halo_mesh(float(gate.w), float(gate.h))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo_material := ShaderMaterial.new()
	halo_material.shader = GlowShader
	halo.material_override = halo_material
	holder.add_child(halo)
	halo_nodes.append(halo)
	halo_materials.append([halo_material])
	if drawn.size() >= 3:
		_add_numbers(holder, index, drawn[2], normal, plate_rows, lamp_transforms)


## One mesh for a gate's collision boxes, in the gate frame `frame`. The posts are cut where the bars cross them, so
## no two faces share a plane (they flickered) while the union stays exactly the boxes'. UV.x is 1 on a post and 0 on
## a bar. `drawn` receives each box's render-space {position, size, basis}; `extent` the frame's {x_out (outer half
## width), y_top (top of the banner), y_bottom (underside of the bottom bar)} in the gate frame.
static func _panel_mesh(boxes: Array, frame: Transform3D, drawn: Array, extent := {}) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var to_gate := frame.affine_inverse()
	var parts: Array = [] # [local centre, size]
	var bars: Array = [] # [x min, x max, y min, y max]
	var x_out := 0.0
	var y_top := -INF
	var y_bottom := INF
	for box: Dictionary in boxes:
		var size := Vector3(2.0 * float(box.half_z), 2.0 * float(box.half_down), 2.0 * float(box.half_x))
		var world := Frames.ned_to_render([float(box.north), float(box.east), float(box.down)])
		drawn.append({position = world, size = size, basis = frame.basis})
		var local: Vector3 = to_gate * world
		parts.append([local, size])
		x_out = maxf(x_out, absf(local.x) + 0.5 * size.x)
		y_top = maxf(y_top, local.y + 0.5 * size.y)
		if size.y <= size.x:
			bars.append([local.x - 0.5 * size.x, local.x + 0.5 * size.x, local.y - 0.5 * size.y, local.y + 0.5 * size.y])
			y_bottom = minf(y_bottom, local.y - 0.5 * size.y)
	extent.x_out = x_out
	extent.y_top = y_top
	extent.y_bottom = y_bottom if is_finite(y_bottom) else y_top
	for part: Array in parts:
		var local: Vector3 = part[0]
		var size: Vector3 = part[1]
		var vertical: bool = size.y > size.x
		var segments: Array = [[local.y - 0.5 * size.y, local.y + 0.5 * size.y]]
		if vertical:
			for bar: Array in bars:
				var covers: bool = float(bar[0]) <= local.x - 0.5 * size.x + CUT_TOLERANCE_M \
					and float(bar[1]) >= local.x + 0.5 * size.x - CUT_TOLERANCE_M
				if covers:
					segments = _cut(segments, float(bar[2]), float(bar[3]))
		for segment: Array in segments:
			var shape := BoxMesh.new()
			shape.size = Vector3(size.x, float(segment[1]) - float(segment[0]), size.z)
			var centre := Vector3(local.x, 0.5 * (float(segment[0]) + float(segment[1])), local.z)
			var arrays: Array = shape.get_mesh_arrays()
			var base := vertices.size()
			for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				vertices.append(v + centre)
				uvs.append(Vector2(1.0 if vertical else 0.0, 0.0))
			normals.append_array(arrays[Mesh.ARRAY_NORMAL])
			for i: int in arrays[Mesh.ARRAY_INDEX]:
				indices.append(base + i)
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_TEX_UV] = uvs
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


## `segments` ([[lo, hi]]) without the interval lo..hi.
static func _cut(segments: Array, lo: float, hi: float) -> Array:
	var kept: Array = []
	for segment: Array in segments:
		var a: float = segment[0]
		var b: float = segment[1]
		if hi <= a or lo >= b:
			kept.append(segment)
			continue
		if lo > a + CUT_TOLERANCE_M:
			kept.append([a, lo])
		if hi < b - CUT_TOLERANCE_M:
			kept.append([hi, b])
	return kept


## One mesh for a gate's four neon halo quads in the gate plane, fading from each aperture edge inward. COLOR carries
## the LED edge direction in UV space (mapped to 0..1) and the chase segments / 64.
static func _halo_mesh(w: float, h: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	# [centre (across, up), size, LED edge direction in UV, edge length]
	var edges := [
		[Vector2(0.0, h - 0.5 * HALO_DEPTH_M), Vector2(2.0 * w, HALO_DEPTH_M), Vector2(0.0, -1.0), 2.0 * w],
		[Vector2(0.0, -h + 0.5 * HALO_DEPTH_M), Vector2(2.0 * w, HALO_DEPTH_M), Vector2(0.0, 1.0), 2.0 * w],
		[Vector2(-w + 0.5 * HALO_DEPTH_M, 0.0), Vector2(HALO_DEPTH_M, 2.0 * h), Vector2(-1.0, 0.0), 2.0 * h],
		[Vector2(w - 0.5 * HALO_DEPTH_M, 0.0), Vector2(HALO_DEPTH_M, 2.0 * h), Vector2(1.0, 0.0), 2.0 * h],
	]
	for edge: Array in edges:
		var c: Vector2 = edge[0]
		var half: Vector2 = 0.5 * (edge[1] as Vector2)
		var dir: Vector2 = edge[2]
		var colour := Color(0.5 * (dir.x + 1.0), 0.5 * (dir.y + 1.0), (float(edge[3]) / 0.35) / 64.0)
		var base := vertices.size()
		# QuadMesh convention: UV (0,0) at the top-left corner (-x, +y).
		for corner: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			vertices.append(Vector3(c.x + corner.x * half.x, c.y + corner.y * half.y, 0.0))
			normals.append(Vector3(0, 0, 1))
			uvs.append(Vector2(0.5 * (corner.x + 1.0), 0.5 * (1.0 - corner.y)))
			colours.append(colour)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_TEX_UV] = uvs
	surface[Mesh.ARRAY_COLOR] = colours
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


## The white PVC foot tube (axis y), the same tube as the frame's.
static func _foot_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = FOOT_TUBE_RADIUS_M
	mesh.bottom_radius = FOOT_TUBE_RADIUS_M
	mesh.height = FOOT_TUBE_LENGTH_M
	mesh.radial_segments = 10
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.91, 0.93)
	material.roughness = 0.32
	mesh.material = material
	return mesh


## A sandbag: a pillow (a superellipsoid, boxy in plan and rounded on top) of SANDBAG_SIZE, its length on x and the
## foot tube's direction on z, olive canvas. The size is baked in: instances stay rigid, so normals stay right.
static func _sandbag_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var arrays: Array = sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# p = sign(v) |v|^e per axis; the normal of that surface follows sign(v) |v|^(2 - e).
	var e := Vector3(0.35, 0.8, 0.35)
	for i in vertices.size():
		var v: Vector3 = vertices[i] * 2.0
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		for axis in 3:
			p[axis] = signf(v[axis]) * pow(absf(v[axis]), e[axis])
			n[axis] = signf(v[axis]) * pow(absf(v[axis]), 2.0 - e[axis])
		var scale := Vector3(SANDBAG_SIZE.y, SANDBAG_SIZE.z, SANDBAG_SIZE.x)
		vertices[i] = 0.5 * p * scale
		n /= scale
		normals[i] = n.normalized() if n.length_squared() > 1.0e-12 else normals[i]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.22, 0.14)
	material.roughness = 0.95
	mesh.surface_set_material(0, material)
	return mesh


## A course-wide MultiMesh of `mesh` at `transforms` under the root (one draw for all of them).
func _multimesh(node_name: String, mesh: Mesh, transforms: Array, colours := false) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colours
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	return instance


## The banner's plate on both faces (entry dark with a white number, exit red; collected into the plate MultiMeshes)
## and the number labels; the start/finish plate says so and carries the start light bar.
func _add_numbers(holder: Node3D, index: int, top: Dictionary, normal: Vector3, plate_rows: Array,
		lamp_transforms: Array[Transform3D]) -> void:
	var size: Vector3 = top.size
	var depth: float = 0.5 * size.z
	var finish: bool = index == _finish
	var plate_size := Vector2(FINISH_PLATE_WIDTH_M if finish else NUMBER_PLATE_WIDTH_M, size.y - 2.0 * PLATE_MARGIN_M)
	var basis: Basis = top.basis
	var text := str(index + 1) if not finish else "START / FINISH"
	for side: float in [1.0, -1.0]:
		var outward: Vector3 = basis.z * side
		# The entry face looks back along the pass direction.
		var entry: bool = outward.dot(normal) < 0.0
		# A QuadMesh and a Label3D face their +Z side: each turns that side away from the banner it stands on.
		var facing := basis if side > 0.0 else basis.rotated(Vector3.UP, PI)
		var at: Vector3 = (top.position as Vector3) + outward * (depth + 0.002)
		(plate_rows[0 if entry else 1] as Array).append(Transform3D(facing.scaled_local(Vector3(plate_size.x, plate_size.y, 1.0)), at))
		var label := Label3D.new()
		label.name = "Number"
		label.text = text
		label.font_size = NUMBER_FONT_SIZE if not finish else 64
		label.pixel_size = NUMBER_PIXEL_SIZE
		label.outline_size = 0
		if finish:
			label.modulate = Color(1.0, 0.86, 0.2)
		else:
			label.modulate = Color(1, 1, 1) if entry else Color(1.0, 0.75, 0.7)
		label.double_sided = false
		label.transform = holder.transform.affine_inverse() * Transform3D(facing, (top.position as Vector3) + outward * (depth + 0.004))
		holder.add_child(label)
		number_labels.append(label)
		if finish:
			# Each side's lamps sit in a dark rimmed housing.
			var housing := Vector2(LAMPS_PER_SIDE * LAMP_SPACING_M + 0.05, 2.0 * LAMP_RADIUS_M + 0.07)
			for sign_x: float in [-1.0, 1.0]:
				var mid: float = sign_x * (0.5 * plate_size.x + 0.14 + 0.5 * (LAMPS_PER_SIDE - 1) * LAMP_SPACING_M)
				(plate_rows[0] as Array).append(Transform3D(facing.scaled_local(Vector3(housing.x, housing.y, 1.0)),
					(top.position as Vector3) + facing.x * mid + outward * (depth + 0.002)))
			for k in LAMPS_PER_SIDE:
				for sign_x: float in [-1.0, 1.0]:
					var x: float = sign_x * (0.5 * plate_size.x + 0.14 + k * LAMP_SPACING_M)
					lamp_transforms.append(Transform3D(facing, (top.position as Vector3) + facing.x * x + outward * depth))
					while _lamp_instances.size() <= k:
						_lamp_instances.append([])
					(_lamp_instances[k] as Array).append(lamp_transforms.size() - 1)


## The start light bar as one MultiMesh of unshaded spheres coloured per instance.
func _build_lamps(transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mesh := SphereMesh.new()
	mesh.radius = LAMP_RADIUS_M
	mesh.height = 2.0 * LAMP_RADIUS_M
	mesh.radial_segments = 16
	mesh.rings = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	lamps = _multimesh("StartLamps", mesh, transforms, true)
	for i in transforms.size():
		lamps.multimesh.set_instance_color(i, LAMP_OFF)


## Colour of start lamp k (the same on both sides and faces); for tests and diagnostics.
func lamp_color(k: int) -> Color:
	return _lamp_shown[k] if k >= 0 and k < _lamp_shown.size() else Color()


## The start pad: a dark landing square with a checkered border, a hair above the ground (the pad itself is terrain).
func _build_pad(pad_data: Dictionary) -> void:
	if pad_data.is_empty():
		return
	pad = MeshInstance3D.new()
	pad.name = "StartPad"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(PAD_SIZE_M, PAD_SIZE_M)
	pad.mesh = mesh
	if _pad_texture == null:
		_pad_texture = ImageTexture.create_from_image(pad_image())
	var material := StandardMaterial3D.new()
	material.albedo_texture = _pad_texture
	material.roughness = 0.85
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pad.material_override = material
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.position = Frames.ned_to_render([float(pad_data.north), float(pad_data.east), float(pad_data.down) - 0.006])
	pad.rotation.y = -deg_to_rad(float(pad_data.get("heading_deg", 0.0)))
	_pad_render = pad.position
	root.add_child(pad)


## 64 px landing square: a checkered border two cells wide around a dark centre with two white launch chevrons
## pointing to the pad's heading (texture up is the pad's forward).
static func pad_image() -> Image:
	var image := Image.create(64, 64, true, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var colour := Color(0.13, 0.13, 0.14)
			if x < 8 or y < 8 or x >= 56 or y >= 56:
				colour = Color(0.95, 0.95, 0.95) if (x / 4 + y / 4) % 2 == 0 else Color(0.05, 0.05, 0.05)
			else:
				var dx := absi(x - 32)
				for apex: int in [17, 29]:
					if dx <= 13 and absi(y - apex - dx) <= 2:
						colour = Color(0.95, 0.95, 0.95)
			image.set_pixel(x, y, colour)
	image.generate_mipmaps()
	return image


## Race guidance nodes, shown only during a race: the bobbing chevron, the light on the next gate, the path dots.
func _build_guidance() -> void:
	var chevron_mesh := QuadMesh.new()
	chevron_mesh.size = CHEVRON_SIZE
	chevron = MeshInstance3D.new()
	chevron.name = "NextGateChevron"
	chevron.mesh = chevron_mesh
	chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var chevron_material := ShaderMaterial.new()
	chevron_material.shader = MarkerShader
	chevron_material.set_shader_parameter("shape", 1)
	chevron_material.set_shader_parameter("marker_color", LED_NEXT)
	chevron.material_override = chevron_material
	chevron.visible = false
	root.add_child(chevron)
	gate_light = OmniLight3D.new()
	gate_light.name = "NextGateLight"
	gate_light.light_color = LED_NEXT
	gate_light.omni_range = GATE_LIGHT_RANGE_M
	gate_light.shadow_enabled = false
	gate_light.visible = false
	root.add_child(gate_light)
	var dot := QuadMesh.new()
	dot.size = Vector2(PATH_DOT_M, PATH_DOT_M)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = dot
	multimesh.instance_count = PATH_MAX_DOTS
	multimesh.visible_instance_count = 0
	path = MultiMeshInstance3D.new()
	path.name = "PathToNextGate"
	path.multimesh = multimesh
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var path_material := ShaderMaterial.new()
	path_material.shader = MarkerShader
	path_material.set_shader_parameter("shape", 0)
	path_material.set_shader_parameter("marker_color", LED_NEXT)
	path.material_override = path_material
	path.visible = false
	root.add_child(path)


## Remove the drawn course from the scene (a course change).
func free_nodes() -> void:
	if root != null and is_instance_valid(root):
		# Out of the tree at once, so the next course's root takes the name RaceCourse.
		if root.get_parent() != null:
			root.get_parent().remove_child(root)
		root.queue_free()
	root = null
	gate_views = []
	gate_materials = []
	halo_materials = []
	halo_nodes = []


## Highlight the next required gate (-1 outside a race) and the one after it; move the guidance to it.
func set_next(next: int) -> void:
	next_gate = next
	var count := gate_views.size()
	for index in count:
		var state := GateState.CALM
		if next >= 0 and index == next:
			state = GateState.NEXT
		elif next >= 0 and count > 1 and index == (next + 1) % count:
			state = GateState.AFTER
		gate_states[index] = state
	_apply_energies()
	_place_guidance(next)


## State colours and night-scaled levels of every gate and the guidance (on a state change or a night-factor step).
func _apply_energies() -> void:
	_energy_night = night
	var light_scale := 0.35 + 2.6 * night
	for index in gate_views.size():
		var state: int = gate_states[index]
		# Calm LEDs carry the gate's own colour (a coloured outline at night); next and after keep theirs.
		var calm: Color = (PANEL_COLORS[index % PANEL_COLORS.size()] as Color).lerp(LED_CALM, 0.35)
		var led: Color = [calm, LED_NEXT, LED_AFTER][state]
		var panel: Color = [PANEL_COLORS[index % PANEL_COLORS.size()], PANEL_NEXT, PANEL_AFTER][state]
		# Daylight emission stays below saturation so the LED keeps its hue (white means overexposed).
		var material: ShaderMaterial = gate_materials[index][0]
		material.set_shader_parameter("led_color", led)
		material.set_shader_parameter("led_energy", [0.35, 1.0, 0.6][state] * (1.0 + 2.0 * night))
		# Panel glow keeps the colour readable by day; at night the LEDs and the light carry it (it would burn to white).
		material.set_shader_parameter("panel_glow", [0.0, 0.18, 0.05][state] * lerpf(1.0, 0.12, night))
		material.set_shader_parameter("led_width", [0.02, 0.06, 0.04][state])
		material.set_shader_parameter("color_a", panel)
		material.set_shader_parameter("chase", 1.0 if state == GateState.NEXT else 0.0)
		material.set_shader_parameter("breathe", 1.0 if state == GateState.CALM else 0.0)
		var halo: ShaderMaterial = halo_materials[index][0]
		halo.set_shader_parameter("glow_color", led)
		halo.set_shader_parameter("energy", float(HALO_ENERGY[state]) * light_scale)
		halo.set_shader_parameter("chase", 1.0 if state == GateState.NEXT else 0.0)
		halo_nodes[index].visible = state != GateState.CALM or night >= CALM_HALO_NIGHT or _flash[index] > 0.0
	(chevron.material_override as ShaderMaterial).set_shader_parameter("energy", 0.6 + 2.0 * night)
	(path.material_override as ShaderMaterial).set_shader_parameter("energy", 1.1 + 1.9 * night)
	_apply_light()


func _apply_light() -> void:
	# Lit surfaces take the full exposure (about 50x at night against the compensated 1 / sqrt): a small energy washes
	# the gate and pools on the ground without burning the fabric to white.
	gate_light.light_energy = GATE_LIGHT_ENERGY * exposure_comp
	gate_light.visible = next_gate >= 0 and next_gate < gate_frames.size() and night >= GATE_LIGHT_NIGHT


## The chevron above the next gate, the light in front of it, and the path dots from the previous gate (or the start
## pad for the first gate of a lap) to it, on a Hermite curve leaving and entering along the gates' pass directions.
func _place_guidance(next: int) -> void:
	var racing: bool = next >= 0 and next < gate_frames.size()
	chevron.visible = racing
	path.visible = racing
	_apply_light()
	if not racing:
		path.multimesh.visible_instance_count = 0
		return
	var target: Dictionary = gate_frames[next]
	chevron.position = (target.top as Vector3) + (target.up as Vector3) * CHEVRON_LIFT_M
	gate_light.position = (target.centre as Vector3) - (target.normal as Vector3) * GATE_LIGHT_STANDOFF_M
	var start: Vector3
	var start_dir: Vector3
	if next == 0:
		start = _pad_render + Vector3.UP * 0.4
		start_dir = ((target.centre as Vector3) - start).normalized()
	else:
		var previous: Dictionary = gate_frames[next - 1]
		start = (previous.centre as Vector3) + (previous.normal as Vector3) * 0.8
		start_dir = previous.normal
	var end: Vector3 = (target.centre as Vector3) - (target.normal as Vector3) * 0.8
	var span: float = start.distance_to(end)
	var m0: Vector3 = start_dir * span * 0.9
	var m1: Vector3 = (target.normal as Vector3) * span * 0.9
	var dots: int = clampi(int(span / PATH_SPACING_M), 2, PATH_MAX_DOTS)
	for i in dots:
		var t: float = float(i) / float(dots - 1)
		var t2 := t * t
		var t3 := t2 * t
		var p: Vector3 = (2.0 * t3 - 3.0 * t2 + 1.0) * start + (t3 - 2.0 * t2 + t) * m0 \
			+ (-2.0 * t3 + 3.0 * t2) * end + (t3 - t2) * m1
		path.multimesh.set_instance_transform(i, Transform3D(Basis(), p))
		path.multimesh.set_instance_color(i, Color(1, 1, 1, t))
	path.multimesh.visible_instance_count = dots


## Follow the scene's eye-adapted exposure (World's tonemap): the global parameter carries exposure ^ -gamma to every
## light-only material (one call); the night factor is read from it (exposure 1 by day, about 10^3 at night) and the
## night-scaled levels are reapplied only when it moves by a step.
func set_exposure(exposure: float) -> void:
	var value: float = exposure if is_finite(exposure) and exposure > 0.0 else 1.0
	var comp: float = pow(value, -exposure_gamma)
	if absf(comp / exposure_comp - 1.0) > 0.01 or _lamp_comp < 0.0:
		exposure_comp = comp
		RenderingServer.global_shader_parameter_set(EXPOSURE_PARAM, comp)
		_apply_light()
		_lamp_comp = -1.0 # lamps are unshaded vertex colours: they take the new level on their next update
	night = clampf(log(value) / log(10.0) / 3.0, 0.0, 1.0)
	if absf(night - _energy_night) > 0.05:
		_apply_energies()


## A gate the race director has just scored flashes white.
func gate_passed(index: int) -> void:
	if index >= 0 and index < _flash.size():
		_flash[index] = FLASH_S
		halo_nodes[index].visible = true


## Per frame (presentation time, never simulation time): flash decay and the start light bar.
func update(delta: float, race: Dictionary = {}) -> void:
	for index in _flash.size():
		if _flash[index] <= 0.0:
			continue
		_flash[index] = maxf(0.0, _flash[index] - maxf(delta, 0.0))
		var level: float = _flash[index] / FLASH_S
		(gate_materials[index][0] as ShaderMaterial).set_shader_parameter("flash", level)
		(halo_materials[index][0] as ShaderMaterial).set_shader_parameter("flash", level)
		if level == 0.0:
			halo_nodes[index].visible = gate_states[index] != GateState.CALM or night >= CALM_HALO_NIGHT
	_update_lamps(race)


## Start light bar from the race telemetry: off; red lamps filling during the countdown; green for the first 1.5 s of
## the race; yellow on the last lap; blinking white once finished. Instance colours change only when the state does.
func _update_lamps(race: Dictionary) -> void:
	if lamps == null:
		return
	var lit := 0
	var colour := LAMP_OFF
	match str(race.get("phase", "")):
		"COUNTDOWN":
			lit = clampi(4 - int(ceil(float(race.get("countdown_s_left", 3.0)))), 1, LAMPS_PER_SIDE)
			colour = LAMP_RED
		"RACING":
			var laps: int = (race.get("laps", []) as Array).size()
			if int(race.get("valid_laps", 0)) == 0 and int(race.get("next_gate", 0)) == 0 \
					and float(race.get("elapsed_lap_s", 0.0)) < 1.5:
				lit = LAMPS_PER_SIDE
				colour = LAMP_GREEN
			elif laps > 0 and int(race.get("valid_laps", 0)) == laps - 1:
				lit = LAMPS_PER_SIDE
				colour = LAMP_YELLOW
		"FINISHED":
			lit = LAMPS_PER_SIDE if int(Time.get_ticks_msec() / 250) % 2 == 0 else 0
			colour = Color(1, 1, 1)
	if lit == _lamp_lit and colour == _lamp_colour and _lamp_comp == exposure_comp:
		return
	_lamp_lit = lit
	_lamp_colour = colour
	_lamp_comp = exposure_comp
	var level := exposure_comp * (1.0 + 2.0 * night)
	_lamp_shown.resize(_lamp_instances.size())
	for k in _lamp_instances.size():
		# An unlit lens is a dark surface: compensated twice (exposure ^ -1 at the default gamma 0.5), so it stays dark.
		var shown: Color = colour * level if k < lit else LAMP_OFF * exposure_comp * exposure_comp
		_lamp_shown[k] = shown
		for i: int in _lamp_instances[k]:
			lamps.multimesh.set_instance_color(i, shown)
