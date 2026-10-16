## L10a: calm visual windsock; no simulation state, collision, process callback or invented wind.
## Dimensions: field data. Rigid first 3/8 length: FAA AC 150/5345-27E §3.3.
## Five bands, bend, folded tail, fittings and colours are artistic estimates, not FAA certification.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const SIDES: int = 32
const SECTIONS: int = 60
const BANDS: int = 5
const ORANGE: Color = Color("#e47b35")
const WHITE: Color = Color("#e9e4d7")
const STEEL: Color = Color("#8d9296")
const ARM_M: float = 0.35
const FabricFinish = preload("res://render/windsock_fabric.gdshader")
const SupportFinish = preload("res://render/windsock_support.gdshader")
const FABRIC_MAPS := {
	"fabric_color": preload("res://assets/landscape/windsock/Fabric001_1K-JPG_Color.jpg"),
	"fabric_normal": preload("res://assets/landscape/windsock/Fabric001_1K-JPG_NormalGL.jpg"),
	"fabric_roughness": preload("res://assets/landscape/windsock/Fabric001_1K-JPG_Roughness.jpg"),
}
const SUPPORT_MAPS := {
	"metal_normal": preload("res://assets/landscape/pilot-station/Metal032_1K-JPG_NormalGL.jpg"),
	"metal_roughness": preload("res://assets/landscape/pilot-station/Metal032_1K-JPG_Roughness.jpg"),
	"concrete_color": preload("res://assets/landscape/pilot-station/Concrete034_1K-JPG_Color.jpg"),
	"concrete_normal": preload("res://assets/landscape/pilot-station/Concrete034_1K-JPG_NormalGL.jpg"),
}


static func build(cue: Dictionary) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = str(cue.id)
	root.position = Frames.ned_to_render([cue.north, cue.east, 0.0])
	var length_m: float = float(cue.length)
	var height: float = float(cue.pole_height)
	var radius: float = float(cue.throat_diameter) * 0.5
	var mount: Vector3 = Vector3(ARM_M, height, 0.0)
	var cloth: RefCounted = MeshKit.new()
	var uvs := PackedVector2Array()
	var smooth_normals := PackedVector3Array()
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
			# MeshKit emits a,c,b / a,d,c. Store matching sleeve-space coordinates.
			for uv: Vector2 in [Vector2(s0,a), Vector2(s1,b), Vector2(s0,b), Vector2(s0,a), Vector2(s1,a), Vector2(s1,b)]:
				uvs.append(Vector2(uv.x / length_m, uv.y / TAU))
				smooth_normals.append(_cloth_normal(uv.x, uv.y, cue))
	var fabric: MeshInstance3D = _instance("Fabric", cloth, true)
	var arrays := fabric.mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = smooth_normals
	var mapped := ArrayMesh.new()
	mapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mapped, 0)
	surface.generate_tangents()
	fabric.mesh = surface.commit()
	var cloth_material := _material(FabricFinish, FABRIC_MAPS)
	cloth_material.set_shader_parameter("length_m", length_m)
	cloth_material.set_shader_parameter("circumference_m", TAU * radius)
	fabric.mesh.surface_set_material(0, cloth_material)
	fabric.set_meta("centreline", centres)
	root.add_child(fabric)
	var hardware: RefCounted = MeshKit.new()
	hardware.cylinder(0.035, 0.026, height, 24, Vector3.ZERO, STEEL)
	hardware.block(Vector3(0.28, 0.10, 0.28), Vector3.ZERO, Color(0, 0, 1))
	hardware.beam(Vector3(0.0, height - radius, 0.0), mount - Vector3.UP * radius, 0.025, STEEL)
	# Flange and four bolt anchors remain inside the original 0.28 m pad.
	hardware.box(Vector3(0.22, 0.012, 0.22), Vector3(0, 0.106, 0), STEEL, true)
	for x: float in [-0.085, 0.085]:
		for z: float in [-0.085, 0.085]:
			hardware.cylinder(0.014, 0.014, 0.003, 12, Vector3(x, 0.112, z), STEEL)
			hardware.cylinder(0.009, 0.009, 0.012, 6, Vector3(x, 0.115, z), STEEL.darkened(0.15))
	# Pole splice and bearing collars give the support a readable construction.
	for y: float in [height * 0.53, height - radius - 0.045]:
		hardware.cylinder(0.042, 0.042, 0.075, 24, Vector3(0, y, 0), STEEL)
		hardware.cylinder(0.044, 0.044, 0.008, 24, Vector3(0, y + 0.008, 0), STEEL.darkened(0.2))
	hardware.beam(Vector3(0, height - radius - 0.30, 0), mount - Vector3.UP * radius, 0.018, STEEL)
	# An open throat ring and a light basket keep the first section open even at zero wind.
	for s: float in [0.0, length_m * 0.375]:
		for j: int in SIDES:
			var a: float = TAU * j / SIDES
			var b: float = TAU * (j + 1) / SIDES
			hardware.beam(mount + cloth_point(s, a, cue), mount + cloth_point(s, b, cue), 0.009, STEEL)
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		hardware.beam(mount + cloth_point(0.0, a, cue), mount + cloth_point(length_m * 0.375, a, cue), 0.009, STEEL)
	var support := _instance("Support", hardware, false)
	support.mesh.surface_set_material(0, _material(SupportFinish, SUPPORT_MAPS))
	root.add_child(support)
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
	# Supported mouth stays circular; slack develops soft folds down the sleeve.
	var fold: float = 1.0 + collapse * (0.10 * sin(angle * 6.0)
		+ 0.055 * sin(s / length_m * TAU * 7.0 + angle * 3.0))
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


static func _cloth_normal(s: float, angle: float, cue: Dictionary) -> Vector3:
	var step_m := float(cue.length) * 0.0001
	var along := cloth_point(minf(s + step_m, cue.length), angle, cue) - cloth_point(maxf(s - step_m, 0.0), angle, cue)
	var around := cloth_point(s, angle + 0.001, cue) - cloth_point(s, angle - 0.001, cue)
	return around.cross(along).normalized()


static func _material(shader: Shader, maps: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = shader
	for channel: String in maps:
		result.set_shader_parameter(channel, maps[channel])
	return result
