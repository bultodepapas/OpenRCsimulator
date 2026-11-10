## BL-09: RC blimp visual adapter. Loads one skin GLB and poses its articulated nodes only from accepted physical
## state: vector angles, fin deflections and propeller shaft phase. Rendering never feeds back into physics.
## Bindings (node names and local rotation axes) come from the generated `presentation` block of the airship data.
extends RefCounted

const Frames := preload("res://render/frames.gd")
const Catalog := preload("res://vehicles/airship/airship_catalog.gd")

const VECTOR_KEYS := ["vector_port", "vector_starboard", "vector_stern"]
const FIN_KEYS := ["fin_dorsal", "fin_port", "fin_starboard"]
const ROTOR_KEYS := ["rotor_port", "rotor_starboard", "rotor_stern_axial", "rotor_stern_lateral"]
## Visual shaft speed at full normalized motor speed (rev/s); motion blur is not simulated.
const FULL_SPEED_REV_S := 120.0

var root: Node3D
var model: Node3D
var error := ""
var _bindings := {}
var _phase := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _discs: Array[MeshInstance3D] = []


static func skins(_presentation: Dictionary = {}) -> Array:
	return Catalog.skins()


func build(presentation: Dictionary, skin_id: String) -> bool:
	var chosen: Dictionary = {}
	for skin: Dictionary in skins(presentation):
		if skin.id == skin_id:
			chosen = skin
	if chosen.is_empty():
		error = "Unknown blimp skin: " + skin_id
		return false
	var scene := load(str(chosen.model)) as PackedScene
	if scene == null:
		error = "Blimp model is unavailable: " + str(chosen.model)
		return false
	root = Node3D.new()
	root.name = "Airship"
	model = scene.instantiate() as Node3D
	if model == null:
		error = "Blimp model did not instantiate"
		return false
	model.name = "Model"
	root.add_child(model)
	var bindings: Dictionary = presentation.get("bindings", {})
	for key: String in VECTOR_KEYS + FIN_KEYS + ROTOR_KEYS:
		var binding: Variant = bindings.get(key)
		if typeof(binding) != TYPE_DICTIONARY:
			error = "Blimp binding missing: " + key
			return false
		var node := model.find_child(str(binding.node), true, false) as Node3D
		var axis_raw: Array = binding.get("local_axis", [])
		if node == null or axis_raw.size() != 3:
			error = "Blimp model node missing: " + str(binding.node)
			return false
		var axis := Vector3(axis_raw[0], axis_raw[1], axis_raw[2])
		if absf(axis.length() - 1.0) > 1e-3:
			error = "Blimp binding axis is not a unit vector: " + key
			return false
		_bindings[key] = {node = node, rest = node.transform, axis = axis.normalized(), sign = float(binding.get("sign", 1.0))}
	for key: String in ROTOR_KEYS:
		_discs.append(_make_disc(_bindings[key], presentation.get("disc_radius", {}).get(key, 0.09)))
	return true


## A faint translucent disc appears only at speed; at rest the real blades are visible.
func _make_disc(binding: Dictionary, radius: float) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.002
	mesh.radial_segments = 32
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.87, 0.9, 0.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var node: Node3D = binding.node
	var rest: Transform3D = binding.rest
	# Cylinder axis is local +Y; align it with the spin axis expressed in the rotor's parent frame.
	var spin: Vector3 = (rest.basis * Vector3(binding.axis)).normalized()
	var helper := Vector3.UP if absf(spin.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := spin.cross(helper).normalized()
	disc.transform = Transform3D(Basis(x, spin, x.cross(spin)), rest.origin)
	node.get_parent().add_child(disc)
	return disc


## body: 13-value accepted (or interpolated) state; continuous: motor speeds, vector/fin angles (CTRL sign).
func pose(body: PackedFloat64Array, continuous: PackedFloat64Array, frame_dt: float) -> void:
	if root == null:
		return
	root.transform = Transform3D(Frames.quat_to_render(body.slice(6, 10)), Frames.ned_to_render([body[0], body[1], body[2]]))
	for i in 3:
		_turn(VECTOR_KEYS[i], continuous[4 + i])
		_turn(FIN_KEYS[i], continuous[7 + i])
	for i in 4:
		var n := continuous[i]
		_phase[i] = fposmod(_phase[i] + TAU * FULL_SPEED_REV_S * n * frame_dt, TAU)
		_turn(ROTOR_KEYS[i], _phase[i])
		var material := _discs[i].material_override as StandardMaterial3D
		material.albedo_color.a = clampf((absf(n) - 0.25) * 0.35, 0.0, 0.22)


func _turn(key: String, angle: float) -> void:
	var binding: Dictionary = _bindings[key]
	var node: Node3D = binding.node
	var rest: Transform3D = binding.rest
	node.transform = Transform3D(rest.basis * Basis(binding.axis, angle * float(binding.sign)), rest.origin)
