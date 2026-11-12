## DR-32: the local race course as an FPV pilot reads it, by day and at night.
##
## Solids: every gate is drawn from its collision boxes, one fabric panel per box at exactly the box's size and place
## (what is seen is what collides): striped side posts and bottom bar in woven vinyl mesh, a solid top banner with the
## gate number on a plate on both faces, rubber feet, and a checkered start/finish gate (the last gate closes the lap).
## The entry face's plate is dark with a white number; the exit face's is red, so a pilot who sees red is flying the
## gate the wrong way.
##
## Light (never a solid, never collides): an LED strip on the aperture edge with an additive neon halo into the
## opening, brighter as the sun sets; a start light bar on the start/finish gate (red per countdown second, green at
## GO, yellow on the last lap, blinking white at the finish); and race guidance: the next gate turns lime, its LEDs
## chase and a real light washes it, a chevron bobs above it, a dotted light path flows from the previous gate to it,
## and the gate after it turns amber. A gate flashes white when it is passed. Outside a race every gate is calm and
## gently breathing. Presentation only: nothing here feeds the session.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const Track = preload("res://sim/race/track.gd")
const GateShader = preload("res://vehicles/multirotor/race_gate.gdshader")
const GlowShader = preload("res://vehicles/multirotor/race_glow.gdshader")
const MarkerShader = preload("res://vehicles/multirotor/race_marker.gdshader")

## Panel colours, alternating by gate index, with the dark stripe between them.
const PANEL_COLORS := [Color(0.93, 0.16, 0.52), Color(0.16, 0.36, 0.98)]
const PANEL_NEXT := Color(0.5, 1.0, 0.08)
const PANEL_AFTER := Color(1.0, 0.68, 0.05)
const PLATE_DARK := Color(0.05, 0.05, 0.07)
const PLATE_BACK := Color(0.42, 0.03, 0.03)
const PLATE_MARGIN_M := 0.03
const STRIPE_DARK := Color(0.07, 0.07, 0.09)
const LED_CALM := Color(0.75, 0.92, 1.0)
const LED_NEXT := Color(0.3, 1.0, 0.2)
const LED_AFTER := Color(1.0, 0.72, 0.1)
const STRIPE_PERIOD_M := 0.6
const FOOT_SIZE := Vector3(0.32, 0.03, 0.6)
const PAD_SIZE_M := 1.4
const NUMBER_PIXEL_SIZE := 0.0032
const NUMBER_FONT_SIZE := 96
const NUMBER_PLATE_WIDTH_M := 0.62
const FINISH_PLATE_WIDTH_M := 1.6
## Neon halo depth into the aperture (m) and its energy per state, scaled up as the sun sets.
const HALO_DEPTH_M := 0.32
const HALO_ENERGY := [0.12, 0.45, 0.28]
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
## Seconds a passed gate flashes white.
const FLASH_S := 0.45

enum GateState { CALM, NEXT, AFTER }

var root: Node3D
## Per gate: the four panel MeshInstance3D nodes in the course's frame order (posts, top bar, bottom bar).
var gate_views: Array = []
## Per gate: its four panel materials.
var gate_materials: Array = []
## Per gate: its four halo materials.
var halo_materials: Array = []
var gate_states: Array[int] = []
## Per gate (render space): {centre, normal (the pass direction), up, across, w, h, top (top banner position)}.
var gate_frames: Array = []
var number_labels: Array[Label3D] = []
## Start light bar of the start/finish gate: lamp materials, index = lamp from the plate outward (both sides, both
## faces share a material per index).
var lamp_materials: Array[StandardMaterial3D] = []
var pad: MeshInstance3D
var chevron: MeshInstance3D
var gate_light: OmniLight3D
var path: MultiMeshInstance3D
var next_gate := -1
## 0 by day … 1 at night (from the scene's exposure); scales the light-only elements.
var night := 0.0
## 1 / the scene's tonemap exposure; every light-only element and LED emission is multiplied by it.
var exposure_comp := 1.0
## Response of light-only elements to the scene exposure: comp = exposure ^ -exposure_gamma. 0.5 measured on the
## default field at night (exposure 2497 under AgX): 1.0 left the neon nearly invisible, 0 burned it to white.
var exposure_gamma := 0.5
var _exposure_set := false
## Identity of the prepared course this visual draws.
var course_identity := ""
var _finish := -1
var _pad_render := Vector3.ZERO
var _pad_forward := Vector3.FORWARD
var _flash: Array[float] = []
var _lamp_state := ""


## course: the session's prepared course ({gates[{frames, c, n, w, h, ...}], pad}); night_factor 0 (day) … 1.
func build(parent: Node3D, course: Dictionary, night_factor := 0.0) -> void:
	night = clampf(night_factor, 0.0, 1.0)
	root = Node3D.new()
	root.name = "RaceCourse"
	parent.add_child(root)
	course_identity = str(course.get("identity", ""))
	var gates: Array = course.get("gates", [])
	_finish = gates.size() - 1
	for index in gates.size():
		_build_gate(index, gates[index])
	_build_pad(course.get("pad", {}))
	_build_guidance()
	set_next(-1)


func _build_gate(index: int, gate: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Gate%d" % (index + 1)
	root.add_child(holder)
	var boxes: Array = gate.frames
	var c: PackedFloat64Array = gate.c
	var n: PackedFloat64Array = gate.n
	var centre := Frames.ned_to_render([c[0], c[1], c[2]])
	var bars: Array[MeshInstance3D] = []
	var materials: Array[ShaderMaterial] = []
	var panel: Color = PANEL_COLORS[index % PANEL_COLORS.size()]
	for k in boxes.size():
		var box: Dictionary = boxes[k]
		var mesh := BoxMesh.new()
		# Box axes: x across the aperture (render +X at heading 0), y up, z along the gate normal.
		mesh.size = Vector3(2.0 * float(box.half_z), 2.0 * float(box.half_down), 2.0 * float(box.half_x))
		var bar := MeshInstance3D.new()
		bar.name = "Panel%d" % k
		bar.mesh = mesh
		bar.position = Frames.ned_to_render([float(box.north), float(box.east), float(box.down)])
		bar.rotation.y = -deg_to_rad(float(box.heading_deg))
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var vertical: bool = mesh.size.y > mesh.size.x
		var to_centre: Vector3 = bar.basis.inverse() * (centre - bar.position)
		var material := ShaderMaterial.new()
		material.shader = GateShader
		material.set_shader_parameter("long_axis", Vector3(0, 1, 0) if vertical else Vector3(1, 0, 0))
		material.set_shader_parameter("across_axis", Vector3(1, 0, 0) if vertical else Vector3(0, 1, 0))
		material.set_shader_parameter("inner_sign", signf(to_centre.x if vertical else to_centre.y))
		material.set_shader_parameter("half_across", 0.5 * (mesh.size.x if vertical else mesh.size.y))
		material.set_shader_parameter("color_a", panel)
		material.set_shader_parameter("color_b", STRIPE_DARK)
		material.set_shader_parameter("stripe_period", STRIPE_PERIOD_M)
		material.set_shader_parameter("checker", index == _finish)
		material.set_shader_parameter("solid", k == 2)
		bar.material_override = material
		holder.add_child(bar)
		bars.append(bar)
		materials.append(material)
		if vertical:
			_add_foot(holder, bar, mesh.size)
	gate_views.append(bars)
	gate_materials.append(materials)
	gate_states.append(GateState.CALM)
	_flash.append(0.0)
	var basis: Basis = bars[2].basis if bars.size() >= 3 else Basis()
	var normal := Vector3(n[1], -n[2], -n[0]).normalized()
	gate_frames.append({centre = centre, normal = normal, up = basis.y, across = basis.x, w = float(gate.w),
		h = float(gate.h), top = bars[2].position if bars.size() >= 3 else centre})
	halo_materials.append(_add_halos(holder, centre, basis, float(gate.w), float(gate.h)))
	if bars.size() >= 3:
		_add_numbers(holder, index, bars[2], normal)


## A flat rubber foot under a post (visual ballast; it rises 3 cm above the ground the post stands on).
func _add_foot(holder: Node3D, post: MeshInstance3D, size: Vector3) -> void:
	var foot := MeshInstance3D.new()
	foot.name = "Foot"
	var mesh := BoxMesh.new()
	mesh.size = FOOT_SIZE
	foot.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.06, 0.06, 0.07)
	material.roughness = 0.9
	foot.material_override = material
	foot.transform = Transform3D(post.basis, post.position - post.basis.y * (0.5 * size.y - 0.5 * FOOT_SIZE.y))
	holder.add_child(foot)


## Four neon halo quads in the gate plane, one per aperture edge, fading from the LED line into the opening.
func _add_halos(holder: Node3D, centre: Vector3, basis: Basis, w: float, h: float) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	# [offset in (across, up), quad size, edge direction in UV, length for the chase segments]
	var edges := [
		[Vector2(0.0, h - 0.5 * HALO_DEPTH_M), Vector2(2.0 * w, HALO_DEPTH_M), Vector2(0.0, -1.0), 2.0 * w],
		[Vector2(0.0, -h + 0.5 * HALO_DEPTH_M), Vector2(2.0 * w, HALO_DEPTH_M), Vector2(0.0, 1.0), 2.0 * w],
		[Vector2(-w + 0.5 * HALO_DEPTH_M, 0.0), Vector2(HALO_DEPTH_M, 2.0 * h), Vector2(-1.0, 0.0), 2.0 * h],
		[Vector2(w - 0.5 * HALO_DEPTH_M, 0.0), Vector2(HALO_DEPTH_M, 2.0 * h), Vector2(1.0, 0.0), 2.0 * h],
	]
	for edge: Array in edges:
		var mesh := QuadMesh.new()
		mesh.size = edge[1]
		var halo := MeshInstance3D.new()
		halo.name = "Halo"
		halo.mesh = mesh
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var offset: Vector2 = edge[0]
		halo.transform = Transform3D(basis, centre + basis.x * offset.x + basis.y * offset.y)
		var material := ShaderMaterial.new()
		material.shader = GlowShader
		material.set_shader_parameter("edge_dir", edge[2])
		material.set_shader_parameter("segments", float(edge[3]) / 0.35)
		halo.material_override = material
		holder.add_child(halo)
		materials.append(material)
	return materials


## The banner's plate on both faces: the entry face (the one a pilot flying the gate the right way sees) is dark with
## a white number; the exit face is red. The start/finish plate says so and carries the start light bar.
func _add_numbers(holder: Node3D, index: int, top: MeshInstance3D, normal: Vector3) -> void:
	var size: Vector3 = (top.mesh as BoxMesh).size
	var depth: float = 0.5 * size.z
	var finish: bool = index == _finish
	var plate_mesh := QuadMesh.new()
	plate_mesh.size = Vector2(FINISH_PLATE_WIDTH_M if finish else NUMBER_PLATE_WIDTH_M, size.y - 2.0 * PLATE_MARGIN_M)
	var text := str(index + 1) if not finish else "START / FINISH"
	for side: float in [1.0, -1.0]:
		var outward: Vector3 = top.basis.z * side
		# The entry face looks back along the pass direction.
		var entry: bool = outward.dot(normal) < 0.0
		# A QuadMesh and a Label3D face their +Z side: each turns that side away from the banner it stands on.
		var facing := top.basis if side > 0.0 else top.basis.rotated(Vector3.UP, PI)
		var plate_material := StandardMaterial3D.new()
		plate_material.albedo_color = PLATE_DARK if entry else PLATE_BACK
		plate_material.roughness = 0.6
		var plate := MeshInstance3D.new()
		plate.name = "NumberPlate" if entry else "BackPlate"
		plate.mesh = plate_mesh
		plate.material_override = plate_material
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plate.transform = Transform3D(facing, top.position + outward * (depth + 0.002))
		holder.add_child(plate)
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
		label.transform = Transform3D(facing, top.position + outward * (depth + 0.004))
		holder.add_child(label)
		number_labels.append(label)
		if finish:
			_add_lamps(holder, top, facing, outward, depth, plate_mesh.size.x)


## Start light bar: LAMPS_PER_SIDE lamps on each side of the finish plate, on both faces; one material per lamp index.
func _add_lamps(holder: Node3D, top: MeshInstance3D, facing: Basis, outward: Vector3, depth: float, plate_w: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = LAMP_RADIUS_M
	mesh.height = 2.0 * LAMP_RADIUS_M
	mesh.radial_segments = 16
	mesh.rings = 8
	var first: bool = lamp_materials.is_empty()
	for k in LAMPS_PER_SIDE:
		if first:
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = LAMP_OFF
			lamp_materials.append(material)
		for sign_x: float in [-1.0, 1.0]:
			var lamp := MeshInstance3D.new()
			lamp.name = "StartLamp"
			lamp.mesh = mesh
			lamp.material_override = lamp_materials[k]
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var x: float = sign_x * (0.5 * plate_w + 0.14 + k * LAMP_SPACING_M)
			lamp.transform = Transform3D(facing, top.position + facing.x * x + outward * depth)
			holder.add_child(lamp)


## The start pad: a dark landing square with a checkered border, a hair above the ground (the pad itself is terrain).
func _build_pad(pad_data: Dictionary) -> void:
	if pad_data.is_empty():
		return
	pad = MeshInstance3D.new()
	pad.name = "StartPad"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(PAD_SIZE_M, PAD_SIZE_M)
	pad.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(pad_image())
	material.roughness = 0.85
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pad.material_override = material
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.position = Frames.ned_to_render([float(pad_data.north), float(pad_data.east), float(pad_data.down) - 0.006])
	pad.rotation.y = -deg_to_rad(float(pad_data.get("heading_deg", 0.0)))
	_pad_render = pad.position
	_pad_forward = -pad.basis.z
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
	chevron_material.set_shader_parameter("energy", 0.6 + 1.0 * night)
	chevron.material_override = chevron_material
	chevron.visible = false
	root.add_child(chevron)
	gate_light = OmniLight3D.new()
	gate_light.name = "NextGateLight"
	gate_light.light_color = LED_NEXT
	gate_light.omni_range = GATE_LIGHT_RANGE_M
	gate_light.light_energy = (0.25 + 0.45 * night) * exposure_comp
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
	path_material.set_shader_parameter("energy", 1.1 + 0.6 * night)
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


## Highlight the next required gate (-1 outside a race) and the one after it; move the guidance to it.
func set_next(next: int) -> void:
	next_gate = next
	var count := gate_views.size()
	var light_scale := 0.35 + 2.6 * night
	for index in count:
		var state := GateState.CALM
		if next >= 0 and index == next:
			state = GateState.NEXT
		elif next >= 0 and count > 1 and index == (next + 1) % count:
			state = GateState.AFTER
		gate_states[index] = state
		# Calm LEDs carry the gate's own colour (a coloured outline at night); next and after keep theirs.
		var calm: Color = (PANEL_COLORS[index % PANEL_COLORS.size()] as Color).lerp(LED_CALM, 0.35)
		var led: Color = [calm, LED_NEXT, LED_AFTER][state]
		var panel: Color = [PANEL_COLORS[index % PANEL_COLORS.size()], PANEL_NEXT, PANEL_AFTER][state]
		# Daylight emission stays below saturation so the LED keeps its hue (white means overexposed).
		var energy: float = [0.35, 1.0, 0.6][state] * (1.0 + 2.0 * night)
		var glow: float = [0.0, 0.18, 0.05][state]
		var width: float = [0.025, 0.045, 0.035][state]
		for material: ShaderMaterial in gate_materials[index]:
			material.set_shader_parameter("led_color", led)
			material.set_shader_parameter("led_energy", energy)
			material.set_shader_parameter("panel_glow", glow)
			material.set_shader_parameter("led_width", width)
			material.set_shader_parameter("color_a", panel)
			material.set_shader_parameter("chase", 1.0 if state == GateState.NEXT else 0.0)
			material.set_shader_parameter("breathe", 1.0 if state == GateState.CALM else 0.0)
		for material: ShaderMaterial in halo_materials[index]:
			material.set_shader_parameter("glow_color", led)
			material.set_shader_parameter("energy", float(HALO_ENERGY[state]) * light_scale)
			material.set_shader_parameter("chase", 1.0 if state == GateState.NEXT else 0.0)
	gate_light.light_energy = (0.25 + 0.45 * night) * exposure_comp
	_place_guidance(next)


## The chevron above the next gate, the light in front of it, and the path dots from the previous gate (or the start
## pad for the first gate of a lap) to it, on a Hermite curve leaving and entering along the gates' pass directions.
func _place_guidance(next: int) -> void:
	var racing: bool = next >= 0 and next < gate_frames.size()
	chevron.visible = racing
	gate_light.visible = racing
	path.visible = racing
	if not racing:
		path.multimesh.visible_instance_count = 0
		return
	var target: Dictionary = gate_frames[next]
	chevron.position = (target.top as Vector3) + (target.up as Vector3) * CHEVRON_LIFT_M
	gate_light.position = (target.centre as Vector3) - (target.normal as Vector3) * 1.2
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


## Follow the scene's eye-adapted exposure (World's tonemap): light-only elements are scaled by its inverse so they
## keep their colour on screen, and the night factor is read from it (exposure 1 by day, about 10^3 at night).
func set_exposure(exposure: float) -> void:
	var value: float = exposure if is_finite(exposure) and exposure > 0.0 else 1.0
	var comp: float = pow(value, -exposure_gamma)
	if _exposure_set and absf(comp / exposure_comp - 1.0) < 0.03:
		return
	_exposure_set = true
	exposure_comp = comp
	night = clampf(log(value) / log(10.0) / 3.0, 0.0, 1.0)
	var all: Array = []
	for group: Array in gate_materials:
		all.append_array(group)
	for group: Array in halo_materials:
		all.append_array(group)
	all.append(chevron.material_override)
	all.append(path.material_override)
	for material: ShaderMaterial in all:
		material.set_shader_parameter("exposure_comp", comp)
	(chevron.material_override as ShaderMaterial).set_shader_parameter("energy", 0.6 + 2.0 * night)
	(path.material_override as ShaderMaterial).set_shader_parameter("energy", 1.1 + 1.9 * night)
	_lamp_state = ""
	set_next(next_gate)


## A gate the race director has just scored flashes white.
func gate_passed(index: int) -> void:
	if index >= 0 and index < _flash.size():
		_flash[index] = FLASH_S


## Per frame (presentation time, never simulation time): flash decay and the start light bar.
func update(delta: float, race: Dictionary = {}) -> void:
	for index in _flash.size():
		if _flash[index] <= 0.0:
			continue
		_flash[index] = maxf(0.0, _flash[index] - maxf(delta, 0.0))
		var level: float = _flash[index] / FLASH_S
		for material: ShaderMaterial in gate_materials[index]:
			material.set_shader_parameter("flash", level)
		for material: ShaderMaterial in halo_materials[index]:
			material.set_shader_parameter("flash", level)
	_update_lamps(race)


## Start light bar from the race telemetry: off; red lamps filling during the countdown; green for the first 1.5 s of
## the race; yellow on the last lap; blinking white once finished.
func _update_lamps(race: Dictionary) -> void:
	if lamp_materials.is_empty():
		return
	var phase := str(race.get("phase", ""))
	var lit := 0
	var colour := LAMP_OFF
	match phase:
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
	var state := "%s:%d:%s" % [phase, lit, colour.to_html()]
	if state == _lamp_state:
		return
	_lamp_state = state
	for k in LAMPS_PER_SIDE:
		lamp_materials[k].albedo_color = (colour if k < lit else LAMP_OFF) * exposure_comp * (1.0 + 2.0 * night)
