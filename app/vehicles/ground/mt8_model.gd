## Render boundary for the authorized, immutable MT8 author rig.
extends RefCounted

const Rig = preload("res://vehicles/ground/mt8_rig.gd")
const Frames = preload("res://render/frames.gd")
const SCENE := "res://assets/vehicles/mt8-bisonte/MT8_Bisonte.glb"
const CORNERS := ["FL", "FR", "RL", "RR"]

static func build() -> Dictionary:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		return {"ok": false, "error": "Bisonte visual resource is unavailable"}
	var imported := packed.instantiate() as Node3D
	var nodes := {}
	var error := _collect(imported, nodes)
	for required in ["MT8_Root", "Body", "Collision"]:
		if not nodes.has(required):
			error = "Missing MT8 binding: " + required
	for corner in CORNERS:
		for part in ["Suspension", "Spin", "WheelMesh", "ArmLower", "ArmUpper", "DriveshaftIn", "DriveshaftOut", "ShockA_Body", "ShockA_Spring", "ShockA_Shaft", "ShockB_Body", "ShockB_Spring", "ShockB_Shaft"]:
			if not nodes.has(corner + "_" + part):
				error = "Missing MT8 binding: " + corner + "_" + part
		if corner in ["FL", "FR"] and not nodes.has(corner + "_Steer"):
			error = "Missing MT8 binding: " + corner + "_Steer"
	if not error.is_empty():
		imported.free()
		return {"ok": false, "error": error}
	var rig: Node3D = Rig.new()
	rig.name = "BisonteMT8"
	rig.add_child(imported)
	rig.set("root_path", rig.get_path_to(nodes.MT8_Root))
	nodes.Collision.visible = false
	return {"ok": true, "error": "", "root": rig, "nodes": nodes, "travel_outside_art": false}

static func _collect(node: Node, nodes: Dictionary) -> String:
	if node is CollisionObject3D or node is CollisionShape3D or node is AnimationPlayer:
		return "Art must not own simulation: " + str(node.name)
	if node is Node3D:
		if nodes.has(str(node.name)):
			return "Duplicate MT8 binding: " + str(node.name)
		nodes[str(node.name)] = node
	for child in node.get_children():
		var error := _collect(child, nodes)
		if not error.is_empty():
			return error
	return ""

## State is read-only. Compliant physical stops can exceed the authored art envelope;
## only the drawn linkage is saturated, with an explicit diagnostic flag.
static func draw(visual: Dictionary, state: PackedFloat64Array, cg_height_m: float) -> bool:
	if state.size() != 31 or not visual.get("ok", false):
		return false
	for value in state:
		if not is_finite(value):
			return false
	var rotation := Frames.quat_to_render(state.slice(6, 10))
	var position := Frames.ned_to_render([state[0], state[1], state[2]])
	visual.root.transform = Frames.root_transform(rotation, position, Vector3(0, cg_height_m, 0))
	var travel := {}
	var spin := {}
	visual.travel_outside_art = false
	for i in 4:
		travel[CORNERS[i]] = clampf(state[13 + i], -0.07, 0.05)
		spin[CORNERS[i]] = -fmod(state[25 + i], TAU)
		visual.travel_outside_art = visual.travel_outside_art or absf(travel[CORNERS[i]] - state[13 + i]) > 0.001
	visual.root.set("travel", travel)
	visual.root.set("spin", spin)
	visual.root.set("steer", clampf(-state[29], -PI / 6.0, PI / 6.0))
	visual.root.call("_apply")
	return true
