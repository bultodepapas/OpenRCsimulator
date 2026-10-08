## L10a: calm visual windsock; no simulation state, collision, process callback or invented wind.
## Dimensions: field data. Rigid first 3/8 length: FAA AC 150/5345-27E §3.3.
## Five bands, bend, folded tail, fittings and colours are artistic estimates, not FAA certification.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const SIDES: int = 16
const SECTIONS: int = 40
const BANDS: int = 5
const ORANGE: Color = Color("#e47b35")
const WHITE: Color = Color("#e9e4d7")
const STEEL: Color = Color("#8d9296")
const ARM_M: float = 0.35


static func build(cue: Dictionary) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = str(cue.id)
	root.position = Frames.ned_to_render([cue.north, cue.east, 0.0])
	var length_m: float = float(cue.length)
	var height: float = float(cue.pole_height)
	var radius: float = float(cue.throat_diameter) * 0.5
	var mount: Vector3 = Vector3(ARM_M, height, 0.0)
	var cloth: RefCounted = MeshKit.new()
	var centres: PackedVector3Array = PackedVector3Array()
	for i: int in range(SECTIONS + 1):
		centres.append(mount + centreline(length_m * i / SECTIONS, length_m))
	for i: int in SECTIONS:
		var s0: float = length_m * i / SECTIONS
		var s1: float = length_m * (i + 1) / SECTIONS
		var colour: Color = ORANGE if (i / (SECTIONS / BANDS)) % 2 == 0 else WHITE
		for j: int in SIDES:
			var a: float = TAU * j / SIDES
			var b: float = TAU * (j + 1) / SIDES
			cloth.quad(mount + cloth_point(s0, a, cue), mount + cloth_point(s0, b, cue),
				mount + cloth_point(s1, b, cue), mount + cloth_point(s1, a, cue), colour)
	var fabric: MeshInstance3D = _instance("Fabric", cloth, true)
	fabric.set_meta("centreline", centres)
	root.add_child(fabric)
	var hardware: RefCounted = MeshKit.new()
	hardware.cylinder(0.035, 0.026, height, 12, Vector3.ZERO, STEEL)
	hardware.block(Vector3(0.28, 0.10, 0.28), Vector3.ZERO, Color("#a6a296"))
	hardware.beam(Vector3(0.0, height - radius, 0.0), mount - Vector3.UP * radius, 0.025, STEEL)
	# An open throat ring and a light basket keep the first section open even at zero wind.
	for s: float in [0.0, length_m * 0.375]:
		for j: int in SIDES:
			var a: float = TAU * j / SIDES
			var b: float = TAU * (j + 1) / SIDES
			hardware.beam(mount + cloth_point(s, a, cue), mount + cloth_point(s, b, cue), 0.009, STEEL)
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		hardware.beam(mount + cloth_point(0.0, a, cue), mount + cloth_point(length_m * 0.375, a, cue), 0.009, STEEL)
	root.add_child(_instance("Support", hardware, false))
	return root


## Arc-length parameterisation: straight basket, a smooth quarter bend, then a hanging tail.
static func centreline(s: float, length_m: float) -> Vector3:
	var rigid: float = length_m * 0.375
	var bend_radius: float = length_m * 0.10
	if s <= rigid:
		return Vector3(s, 0.0, 0.0)
	var angle: float = minf((s - rigid) / bend_radius, PI * 0.5)
	var drop: float = maxf(s - rigid - bend_radius * PI * 0.5, 0.0)
	return Vector3(rigid + bend_radius * sin(angle), -bend_radius * (1.0 - cos(angle)) - drop, 0.0)


static func cloth_point(s: float, angle: float, cue: Dictionary) -> Vector3:
	var length_m: float = float(cue.length)
	var rigid: float = length_m * 0.375
	var bend_angle: float = clampf((s - rigid) / (length_m * 0.10), 0.0, PI * 0.5)
	var up: Vector3 = Vector3(sin(bend_angle), cos(bend_angle), 0.0)
	var collapse: float = smoothstep(rigid, rigid + length_m * 0.25, s)
	var radius: float = lerpf(float(cue.throat_diameter), float(cue.tail_diameter), s / length_m) * 0.5
	var fold: float = 1.0 + 0.06 * sin(angle * 6.0) * collapse
	return centreline(s, length_m) + radius * fold * (up * cos(angle)
		+ Vector3.BACK * sin(angle) * lerpf(1.0, 0.16, collapse))


static func _instance(node_name: String, kit: RefCounted, double_sided: bool) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = kit.to_mesh(material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh
