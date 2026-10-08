## L10b: one low, rear-open pilot box; visual cue only, never a physical restraint.
## Field dimensions are estimates. Slats, galvanised frame and concrete colours are artistic.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const POST_M: float = 0.04
const PAD_M: float = 0.025
const STEEL: Color = Color("#969b99")
const ORANGE: Color = Color("#c87740")
const CONCRETE: Color = Color("#8e9186")


static func build(cue: Dictionary) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = str(cue.id)
	root.position = Frames.ned_to_render([cue.north, cue.east, 0.0])
	var width: float = float(cue.width)
	var depth: float = float(cue.depth)
	var height: float = float(cue.height)
	var kit: RefCounted = MeshKit.new()
	# Keep every fitting inside the field footprint. The rear (+Z/south) stays open.
	kit.block(Vector3(width, PAD_M, depth), Vector3.ZERO, CONCRETE)
	var x: float = (width - POST_M) * 0.5
	var z: float = (depth - POST_M) * 0.5
	var corners: Array[Vector3] = [Vector3(-x, 0, z), Vector3(-x, 0, -z), Vector3(x, 0, -z), Vector3(x, 0, z)]
	for corner: Vector3 in corners:
		kit.block(Vector3(POST_M, height, POST_M), corner, STEEL)
	for i: int in 3:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[i + 1]
		kit.beam(a + Vector3.UP * (height - POST_M * 0.5), b + Vector3.UP * (height - POST_M * 0.5), POST_M, STEEL)
		# Four broad opaque slats: open gaps without alpha sorting or subpixel wire grids.
		for row: int in 4:
			var y: float = lerpf(0.13, height - 0.13, float(row) / 3.0)
			var centre: Vector3 = (a + b) * 0.5 + Vector3.UP * y
			var size: Vector3 = Vector3(0.018, 0.07, depth - POST_M) if i != 1 else Vector3(width - POST_M, 0.07, 0.018)
			kit.box(size, centre, ORANGE, true)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Station"
	mesh.mesh = kit.to_mesh(material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	return root
