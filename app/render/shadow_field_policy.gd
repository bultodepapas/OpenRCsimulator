## Owns the field's existing planar receivers without touching native caster settings.
## Batch references are captured once after construction; a revision check is constant work per frame.
extends Node

const ShadowSettings = preload("res://render/shadow_settings.gd")

var _manager: Node
var _planes: Array[MeshInstance3D] = []
var _prior_visibility: Array[bool] = []
var _enabled := true
var _revision := -1


static func attach(field: Node3D) -> void:
	var policy := new()
	policy.name = "ShadowFieldPolicy"
	policy._manager = field.get_node_or_null("ProjectedFieldShadows")
	var cues := field.get_node_or_null("FlightCueShadows") as MeshInstance3D
	if cues != null:
		policy._planes.append(cues)
	var scenery := field.get_node_or_null("Scenery")
	if scenery != null:
		for child: Node in scenery.get_children():
			if child is MeshInstance3D and (str(child.name).begins_with("shadows_") or child.name == "PopulationContacts"):
				policy._planes.append(child as MeshInstance3D)
	field.add_child(policy)
	policy.apply_shadow_policy()


func _ready() -> void:
	add_to_group("shadow_policy_consumers")
	process_priority = -100
	# The manager's own _ready may have reapplied lighting when this detached field entered the tree.
	apply_shadow_policy(true)


func _process(_delta: float) -> void:
	if _revision != ShadowSettings.revision:
		apply_shadow_policy()


func apply_shadow_policy(force: bool = false) -> void:
	var enabled := ShadowSettings.projected_enabled()
	if not force and _revision == ShadowSettings.revision:
		return
	_revision = ShadowSettings.revision
	if not enabled:
		if _enabled:
			_prior_visibility.clear()
			for plane in _planes:
				_prior_visibility.append(plane.visible if is_instance_valid(plane) else false)
		for plane in _planes:
			if is_instance_valid(plane):
				plane.visible = false
		_disable_projectors()
	elif not _enabled:
		for index in _planes.size():
			if is_instance_valid(_planes[index]):
				_planes[index].visible = _prior_visibility[index]
		if is_instance_valid(_manager):
			_manager.apply(_manager.snapshot)
	_enabled = enabled


## Lighting snapshots still advance while projection is off, so restoring uses the latest one.
func apply_lighting(lighting: Dictionary) -> void:
	apply_shadow_policy()
	if not is_instance_valid(_manager):
		return
	if _enabled:
		_manager.apply(lighting)
	else:
		_manager.snapshot = lighting.duplicate(true)


func _disable_projectors() -> void:
	if not is_instance_valid(_manager):
		return
	_manager.set_process(false)
	for projector: Node in _manager.projectors:
		var request: Array = projector.get("_last_request")
		if request.size() == 4:
			projector.refresh(request[0], request[1], request[2], false)
		else:
			projector.refresh(float(projector.get_meta("soft_height", 0.0)), Vector3.UP, 0.0, false)
