## DR-32: the local race course as an FPV pilot reads it. Every gate is drawn from its solid frame boxes, one fabric
## panel per box at exactly the box's size and place (what is seen is what collides): striped side posts and bottom
## bar, a solid top banner with a dark number plate and the gate number on both faces, an LED strip on the aperture
## edge, rubber feet at the posts, and a checkered start/finish gate (the last gate closes the lap). State colours
## follow the race: the next gate turns lime and pulses, the one after it amber, the others keep their calm
## alternating colours (magenta, blue) with a white LED; outside a race every gate is calm. The start pad gets a
## painted landing square. Presentation only: nothing here feeds the session.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const Track = preload("res://sim/race/track.gd")
const GateShader = preload("res://vehicles/multirotor/race_gate.gdshader")

## Panel colours, alternating by gate index, with the dark stripe between them.
const PANEL_COLORS := [Color(0.93, 0.16, 0.52), Color(0.16, 0.36, 0.98)]
const PANEL_NEXT := Color(0.5, 1.0, 0.08)
const PANEL_AFTER := Color(1.0, 0.68, 0.05)
const PLATE_DARK := Color(0.05, 0.05, 0.07)
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
const FINISH_PLATE_WIDTH_M := 2.3

enum GateState { CALM, NEXT, AFTER }

var root: Node3D
## Per gate: the four panel MeshInstance3D nodes in the course's frame order (posts, top bar, bottom bar).
var gate_views: Array = []
## Per gate: its four panel materials.
var gate_materials: Array = []
var gate_states: Array[int] = []
var number_labels: Array[Label3D] = []
var pad: MeshInstance3D
var next_gate := -1
## Identity of the prepared course this visual draws.
var course_identity := ""
var _finish := -1


## course: the session's prepared course ({gates[{frames, n, c, ...}], pad}).
func build(parent: Node3D, course: Dictionary) -> void:
	root = Node3D.new()
	root.name = "RaceCourse"
	parent.add_child(root)
	course_identity = str(course.get("identity", ""))
	var gates: Array = course.get("gates", [])
	_finish = gates.size() - 1
	for index in gates.size():
		_build_gate(index, gates[index])
	_build_pad(course.get("pad", {}))
	set_next(-1)


func _build_gate(index: int, gate: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "Gate%d" % (index + 1)
	root.add_child(holder)
	var boxes: Array = gate.frames
	var c: PackedFloat64Array = gate.c
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
	if bars.size() >= 3:
		_add_numbers(holder, index, bars[2])


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


## A dark plate on both faces of the top banner with the gate number; the start/finish gate's plate says so.
func _add_numbers(holder: Node3D, index: int, top: MeshInstance3D) -> void:
	var size: Vector3 = (top.mesh as BoxMesh).size
	var depth: float = 0.5 * size.z
	var finish: bool = index == _finish
	var plate_mesh := QuadMesh.new()
	plate_mesh.size = Vector2(FINISH_PLATE_WIDTH_M if finish else NUMBER_PLATE_WIDTH_M, size.y - 2.0 * PLATE_MARGIN_M)
	var plate_material := StandardMaterial3D.new()
	plate_material.albedo_color = PLATE_DARK
	plate_material.roughness = 0.6
	var text := str(index + 1) if not finish else "START / FINISH"
	for side: float in [1.0, -1.0]:
		# A QuadMesh and a Label3D face their +Z side: each turns that side away from the banner it stands on.
		var facing := top.basis if side > 0.0 else top.basis.rotated(Vector3.UP, PI)
		var plate := MeshInstance3D.new()
		plate.name = "NumberPlate"
		plate.mesh = plate_mesh
		plate.material_override = plate_material
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plate.transform = Transform3D(facing, top.position + top.basis.z * side * (depth + 0.002))
		holder.add_child(plate)
		var label := Label3D.new()
		label.name = "Number"
		label.text = text
		label.font_size = NUMBER_FONT_SIZE if not finish else 64
		label.pixel_size = NUMBER_PIXEL_SIZE
		label.outline_size = 0
		label.modulate = Color(1, 1, 1) if not finish else Color(1.0, 0.86, 0.2)
		label.double_sided = false
		label.transform = Transform3D(facing, top.position + top.basis.z * side * (depth + 0.004))
		holder.add_child(label)
		number_labels.append(label)


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


## Highlight the next required gate (-1 outside a race) and the one after it.
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
		# Calm LEDs carry the gate's own colour (a coloured outline at night); next and after keep theirs.
		var calm: Color = (PANEL_COLORS[index % PANEL_COLORS.size()] as Color).lerp(LED_CALM, 0.35)
		var led: Color = [calm, LED_NEXT, LED_AFTER][state]
		var panel: Color = [PANEL_COLORS[index % PANEL_COLORS.size()], PANEL_NEXT, PANEL_AFTER][state]
		# Daylight emission stays below saturation so the LED keeps its hue (white means overexposed).
		var energy: float = [0.35, 1.0, 0.6][state]
		var glow: float = [0.0, 0.18, 0.05][state]
		var width: float = [0.025, 0.045, 0.035][state]
		for material: ShaderMaterial in gate_materials[index]:
			material.set_shader_parameter("led_color", led)
			material.set_shader_parameter("led_energy", energy)
			material.set_shader_parameter("panel_glow", glow)
			material.set_shader_parameter("led_width", width)
			material.set_shader_parameter("color_a", panel)


## Per frame: the next gate's LED pulses (presentation time, never simulation time).
func update(time_s: float) -> void:
	if next_gate < 0 or next_gate >= gate_materials.size():
		return
	var energy := 1.0 + 0.35 * sin(time_s * TAU * 1.5)
	for material: ShaderMaterial in gate_materials[next_gate]:
		material.set_shader_parameter("led_energy", energy)
