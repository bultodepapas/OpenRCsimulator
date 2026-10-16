# HELI-26a: read-only mechanical inspection of the advanced source rig.
# Does not drive Simulation or claim achieved flight actuator state.
extends RefCounted

const Model := preload("res://aircraft/hx700_articulated_model.gd")
const Equations := preload("res://render/rotor/hx700_motion_equations.gd")
const CLOSURE_TOLERANCE_M := 2.0e-6
const LIMITS := [13.0, 10.0, 10.0, 20.0, 1.0e6]

var bindings: Dictionary = {}
var pose: Dictionary = {}
var _rest: Dictionary = {}
var _parents: Dictionary = {}
var _rest_world: Dictionary = {}
var _linkages: Array = []


func configure(preview: Dictionary) -> bool:
	if not preview.get("ok", false) or Equations.SOURCE_SHA256 != Model.SOURCE_SHA256:
		return false
	if preview.get("bindings", {}).size() != 108:
		return false
	bindings = preview.bindings
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Model.PROFILE_PATH))
	for record: Dictionary in profile.bindings:
		_rest[record.id] = (bindings[record.id] as Node3D).transform
		_parents[record.id] = String(record.parent_id)
	_linkages = profile.linkages.duplicate(true)
	_rest_world = _world_frames(_rest)
	return apply(PackedFloat64Array([0, 0, 0, 0, 0])).ok


## Degrees: collective, lateral cyclic, longitudinal cyclic, tail; shaft phase in radians.
## Every candidate is checked before commit. Failure retains the last complete pose.
func apply(inputs: PackedFloat64Array) -> Dictionary:
	if bindings.is_empty() or inputs.size() != 5:
		return {"ok": false, "error": "Expected a configured rig and five mechanical inputs."}
	for i in inputs.size():
		if not is_finite(inputs[i]) or absf(inputs[i]) > float(LIMITS[i]):
			return {"ok": false, "error": "Mechanical input %d is outside the inspected range." % i}
	var calculated: Dictionary = Equations.evaluate(inputs[0], inputs[1], inputs[2], inputs[3], inputs[4])
	var local: Dictionary = _rest.duplicate()
	for id: String in calculated.poses:
		var frame: Transform3D = calculated.poses[id]
		if not _finite_transform(frame):
			return {"ok": false, "error": "Unreachable/nonfinite mechanism: " + id}
		local[id] = frame
	var world := _world_frames(local)
	var maximum_residual := 0.0
	for link: Dictionary in _linkages:
		var a: String = link.endpoint_a
		var b: String = link.endpoint_b
		var direction: Vector3 = world[b].origin - world[a].origin
		var residual := absf(direction.length() - float(link.length_m))
		if not is_finite(residual) or residual > CLOSURE_TOLERANCE_M:
			return {"ok": false, "error": "Rigid linkage does not close: " + String(link.id), "residual_m": residual}
		maximum_residual = maxf(maximum_residual, residual)
		# Orient ball links and their rods without scaling/stretching them.
		# A deterministic shortest rotation transports the neutral terminal frame.
		var rest_direction: Vector3 = _rest_world[b].origin - _rest_world[a].origin
		var turn := Basis(Quaternion(rest_direction.normalized(), direction.normalized()))
		for endpoint: String in [a, b]:
			var endpoint_world := Transform3D(turn * _rest_world[endpoint].basis, world[endpoint].origin)
			local[endpoint] = (world[_parents[endpoint]] as Transform3D).affine_inverse() * endpoint_world
	# Endpoint orientation also carries the authored rods and their thread anchors.
	for id: String in local:
		(bindings[id] as Node3D).transform = local[id]
	pose = {"ok": true, "inputs": inputs.duplicate(), "servos": calculated.servos,
		"blade_pitch": calculated.blade_pitch, "residual_m": maximum_residual}
	return pose.duplicate(true)


func _world_frames(local: Dictionary) -> Dictionary:
	var world: Dictionary = {}
	for id: String in local:
		_world_frame(id, local, world)
	return world


func _world_frame(id: String, local: Dictionary, world: Dictionary) -> Transform3D:
	if world.has(id):
		return world[id]
	var parent: String = _parents[id]
	var frame: Transform3D = local[id]
	if not parent.is_empty():
		frame = _world_frame(parent, local, world) * frame
	world[id] = frame
	return frame


static func _finite_transform(frame: Transform3D) -> bool:
	return frame.origin.is_finite() and frame.basis.x.is_finite() \
		and frame.basis.y.is_finite() and frame.basis.z.is_finite()
