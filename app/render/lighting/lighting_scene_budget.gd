extends RefCounted
class_name LightingSceneBudget
## Deterministic scene-local limits for decorative aircraft lighting.
## This class owns requests and grants only; rig owners own their rendering resources.

const DEFAULT_QUALITY := "standard"
const VALID_QUALITIES := ["low", "standard", "high"]
const MAX_REGISTERED_OWNERS := 128
const MAX_PER_OWNER_REQUEST := 2
const MAX_PRIORITY := 1000
const MAX_DISTANCE_M := 1000000.0
const MAX_REENTRANT_RESOLVES := 4
const PUBLISH_METHOD := &"apply_scene_budget"

static var _world_registry: Dictionary = {}

var _world_ref: WeakRef
var _world_id := 0
var _quality := DEFAULT_QUALITY
var _owners: Dictionary = {}
var _resolving := false
var _resolve_pending := false
var _last_receipt: Dictionary = {}


## Returns one coordinator per World3D resource. Viewports sharing that resource share grants.
## The registry holds weak references, so it does not keep an abandoned scene alive.
static func for_world(world: World3D):
	if world == null or not is_instance_valid(world):
		return null
	_prune_world_registry()
	var world_id := world.get_instance_id()
	if _world_registry.has(world_id):
		var record: Dictionary = _world_registry[world_id]
		var tracked_world: Variant = (record.get("world") as WeakRef).get_ref()
		var tracked_budget: Variant = (record.get("budget") as WeakRef).get_ref()
		if tracked_world == world and is_instance_valid(tracked_budget):
			return tracked_budget
		_world_registry.erase(world_id)
	var budget: RefCounted = load("res://render/lighting/lighting_scene_budget.gd").new()
	budget._world_ref = weakref(world)
	budget._world_id = world_id
	_world_registry[world_id] = {"world": weakref(world), "budget": weakref(budget)}
	return budget


## Register a weak owner identity and its StringName callback. Stable IDs must be unique per World3D.
func register_owner(owner: Object, stable_id: String, publish_method: StringName = PUBLISH_METHOD) -> bool:
	if not _world_is_live() or owner == null or not is_instance_valid(owner):
		return false
	var normalized_id := stable_id.strip_edges()
	if normalized_id.is_empty() or normalized_id.length() > 80 or publish_method.is_empty():
		return false
	var pruned := _prune_dead_owners()
	var owner_key := owner.get_instance_id()
	var existing: Dictionary = _owners.get(owner_key, {})
	if not existing.is_empty():
		var existing_owner: Variant = (existing.get("owner") as WeakRef).get_ref()
		if existing_owner == owner:
			if str(existing.get("stable_id", "")) != normalized_id \
					or StringName(existing.get("publish_method", PUBLISH_METHOD)) != publish_method:
				if pruned: _resolve_and_publish()
				return false
			if pruned:
				_resolve_and_publish()
			return true
		_owners.erase(owner_key)
	for other_key: Variant in _owners:
		var other: Dictionary = _owners[other_key]
		if str(other.get("stable_id", "")) == normalized_id:
			if pruned: _resolve_and_publish()
			return false
	if _owners.size() >= MAX_REGISTERED_OWNERS:
		if pruned: _resolve_and_publish()
		return false
	_owners[owner_key] = {
		"owner": weakref(owner),
		"stable_id": normalized_id,
		"publish_method": publish_method,
		"priority": 0,
		"distance_m": MAX_DISTANCE_M,
		"requested_spill": 0,
		"requested_vfx": 0,
		"grant": _empty_grant(),
	}
	_resolve_and_publish()
	return true


## Replace the owner's latest observation and resolve every owner's grant synchronously.
## Distance is expected to come from the displayed camera pose and may lag by one presentation frame.
func submit(owner: Object, request: Dictionary) -> Dictionary:
	if not _world_is_live() or owner == null or not is_instance_valid(owner):
		return _empty_grant()
	var pruned := _prune_dead_owners()
	var owner_key := owner.get_instance_id()
	if not _owners.has(owner_key):
		if pruned: _resolve_and_publish()
		return _empty_grant()
	var entry: Dictionary = _owners[owner_key]
	if (entry.get("owner") as WeakRef).get_ref() != owner:
		_owners.erase(owner_key)
		_resolve_and_publish()
		return _empty_grant()
	var checked := _normalize_request(request)
	if not bool(checked.get("ok", false)):
		entry["requested_spill"] = 0
		entry["requested_vfx"] = 0
		_owners[owner_key] = entry
		_resolve_and_publish()
		return _empty_grant()
	entry["priority"] = checked.priority
	entry["distance_m"] = checked.distance_m
	entry["requested_spill"] = checked.spill_lights
	entry["requested_vfx"] = checked.vfx_anchors
	_owners[owner_key] = entry
	_resolve_and_publish()
	return grant_for(owner)


## Change the scene's quality ceiling and synchronously publish any resulting revocations/grants.
func set_quality(value: String) -> bool:
	if value not in VALID_QUALITIES:
		return false
	if _quality == value:
		return true
	_quality = value
	_resolve_and_publish()
	return true


## Remove an owner and its grant before publishing the newly available capacity to others.
func unregister_owner(owner: Object) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var owner_key := owner.get_instance_id()
	if not _owners.has(owner_key):
		return
	var entry: Dictionary = _owners[owner_key]
	if (entry.get("owner") as WeakRef).get_ref() != owner:
		_owners.erase(owner_key)
		_resolve_and_publish()
		return
	var old_grant: Dictionary = entry.get("grant", _empty_grant())
	_owners.erase(owner_key)
	if int(old_grant.get("spill_lights", 0)) > 0 or int(old_grant.get("vfx_anchors", 0)) > 0:
		_publish(entry, _empty_grant())
	_resolve_and_publish()


## Read a detached grant. Unknown, dead, or not-yet-registered owners receive zero.
func grant_for(owner: Object) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return _empty_grant()
	_reconcile_dead_owners()
	var owner_key := owner.get_instance_id()
	if not _owners.has(owner_key):
		return _empty_grant()
	var entry: Dictionary = _owners[owner_key]
	if (entry.get("owner") as WeakRef).get_ref() != owner:
		return _empty_grant()
	return (entry.get("grant", _empty_grant()) as Dictionary).duplicate(true)


## Bounded diagnostic snapshot; it contains no owner references.
func receipt() -> Dictionary:
	_reconcile_dead_owners()
	if not _last_receipt.is_empty():
		return _last_receipt.duplicate(true)
	return _make_receipt([])


func registered_owner_count() -> int:
	_reconcile_dead_owners()
	return _owners.size()


func quality() -> String:
	return _quality


func _resolve_and_publish() -> void:
	if _resolving:
		_resolve_pending = true
		return
	_resolving = true
	var pass_count := 0
	while true:
		_resolve_pending = false
		_resolve_once()
		pass_count += 1
		if not _resolve_pending or pass_count >= MAX_REENTRANT_RESOLVES:
			break
	if _resolve_pending:
		# A pathological callback loop fails closed; the next external request can retry.
		_resolve_pending = false
		_revoke_all()
	_resolving = false


func _resolve_once() -> void:
	_prune_dead_owners()
	var ranked := _ranked_entries()
	var spill_left := _limit_for_quality()
	var vfx_left := _limit_for_quality()
	var targets: Dictionary = {}
	for entry: Dictionary in ranked:
		var spill := mini(int(entry.get("requested_spill", 0)), spill_left)
		var vfx := mini(int(entry.get("requested_vfx", 0)), vfx_left)
		spill_left -= spill
		vfx_left -= vfx
		targets[int(entry.get("owner_id", 0))] = {"spill_lights": spill, "vfx_anchors": vfx}

	# Publish all decreases first. A category increase is deferred until every owner's
	# old grant has been reduced, so sequential owner updates cannot exceed the scene cap.
	for entry: Dictionary in ranked:
		var owner_id := int(entry.get("owner_id", 0))
		var old_grant: Dictionary = entry.get("grant", _empty_grant())
		var target: Dictionary = targets.get(owner_id, _empty_grant())
		var reduced := {
			"spill_lights": mini(int(old_grant.get("spill_lights", 0)), int(target.get("spill_lights", 0))),
			"vfx_anchors": mini(int(old_grant.get("vfx_anchors", 0)), int(target.get("vfx_anchors", 0))),
		}
		if reduced != old_grant:
			entry["grant"] = reduced
			_owners[owner_id] = entry
			_publish(entry, reduced)

	for entry: Dictionary in ranked:
		var owner_id := int(entry.get("owner_id", 0))
		if not _owners.has(owner_id):
			continue
		entry = _owners[owner_id]
		var current: Dictionary = entry.get("grant", _empty_grant())
		var target: Dictionary = targets.get(owner_id, _empty_grant())
		if current != target:
			entry["grant"] = target.duplicate(true)
			_owners[owner_id] = entry
			_publish(entry, target)

	_last_receipt = _make_receipt(ranked)


func _revoke_all() -> void:
	for owner_id: Variant in _owners.keys():
		if not _owners.has(owner_id):
			continue
		var entry: Dictionary = _owners[owner_id]
		var old_grant: Dictionary = entry.get("grant", _empty_grant())
		if int(old_grant.get("spill_lights", 0)) == 0 and int(old_grant.get("vfx_anchors", 0)) == 0:
			continue
		var empty := _empty_grant()
		entry["grant"] = empty
		_owners[owner_id] = entry
		_publish(entry, empty)
	_resolve_pending = false
	_last_receipt = _make_receipt(_ranked_entries())


func _ranked_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for owner_id: Variant in _owners.keys():
		var entry: Dictionary = _owners[owner_id]
		entry["owner_id"] = int(owner_id)
		result.append(entry)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority := int(left.get("priority", 0))
		var right_priority := int(right.get("priority", 0))
		if left_priority != right_priority:
			return left_priority > right_priority
		var left_distance := float(left.get("distance_m", MAX_DISTANCE_M))
		var right_distance := float(right.get("distance_m", MAX_DISTANCE_M))
		if left_distance != right_distance:
			return left_distance < right_distance
		return str(left.get("stable_id", "")) < str(right.get("stable_id", ""))
	)
	return result


func _make_receipt(ranked: Array) -> Dictionary:
	var grants: Array[Dictionary] = []
	for entry_value: Variant in ranked:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var grant: Dictionary = entry.get("grant", _empty_grant())
		grants.append({
			"stable_id": str(entry.get("stable_id", "")),
			"priority": int(entry.get("priority", 0)),
			"distance_m": float(entry.get("distance_m", MAX_DISTANCE_M)),
			"requested_spill_lights": int(entry.get("requested_spill", 0)),
			"requested_vfx_anchors": int(entry.get("requested_vfx", 0)),
			"spill_lights": int(grant.get("spill_lights", 0)),
			"vfx_anchors": int(grant.get("vfx_anchors", 0)),
		})
	return {
		"world_id": _world_id,
		"quality": _quality,
		"spill_limit": _limit_for_quality(),
		"vfx_anchor_limit": _limit_for_quality(),
		"registered_owners": _owners.size(),
		"grants": grants,
	}


func _limit_for_quality() -> int:
	match _quality:
		"low": return 0
		"standard": return 2
		"high": return 4
	return 0


func _normalize_request(raw: Dictionary) -> Dictionary:
	var priority_value: Variant = raw.get("priority", 0)
	var distance_value: Variant = raw.get("distance_m", 0.0)
	var spill_value: Variant = raw.get("spill_lights", 0)
	var vfx_value: Variant = raw.get("vfx_anchors", 0)
	if typeof(priority_value) != TYPE_INT or typeof(spill_value) != TYPE_INT or typeof(vfx_value) != TYPE_INT:
		return {"ok": false}
	if not (typeof(distance_value) == TYPE_INT or typeof(distance_value) == TYPE_FLOAT):
		return {"ok": false}
	var distance := float(distance_value)
	if not is_finite(distance) or distance < 0.0 or distance > MAX_DISTANCE_M:
		return {"ok": false}
	var priority := int(priority_value)
	if abs(priority) > MAX_PRIORITY or int(spill_value) < 0 or int(vfx_value) < 0:
		return {"ok": false}
	return {
		"ok": true,
		"priority": priority,
		"distance_m": distance,
		"spill_lights": mini(int(spill_value), MAX_PER_OWNER_REQUEST),
		"vfx_anchors": mini(int(vfx_value), MAX_PER_OWNER_REQUEST),
	}


func _prune_dead_owners() -> bool:
	var removed := false
	for owner_id: Variant in _owners.keys():
		var entry: Dictionary = _owners[owner_id]
		var owner_ref: Variant = entry.get("owner")
		var owner: Variant = owner_ref.get_ref() if owner_ref is WeakRef else null
		if owner == null or not is_instance_valid(owner):
			_owners.erase(owner_id)
			removed = true
	return removed


func _reconcile_dead_owners() -> void:
	if _prune_dead_owners():
		_resolve_and_publish()


func _world_is_live() -> bool:
	if _world_ref == null:
		return false
	var world: Variant = _world_ref.get_ref()
	return world != null and is_instance_valid(world)


func _publish(entry: Dictionary, grant: Dictionary) -> void:
	var owner_ref: Variant = entry.get("owner")
	var owner: Variant = owner_ref.get_ref() if owner_ref is WeakRef else null
	if owner == null or not is_instance_valid(owner):
		return
	var method_name := StringName(entry.get("publish_method", PUBLISH_METHOD))
	if owner.has_method(method_name):
		owner.call(method_name, grant.duplicate(true))


func _empty_grant() -> Dictionary:
	return {"spill_lights": 0, "vfx_anchors": 0}


static func _prune_world_registry() -> void:
	for world_id: Variant in _world_registry.keys():
		var record: Dictionary = _world_registry[world_id]
		var world_ref: Variant = record.get("world")
		var budget_ref: Variant = record.get("budget")
		var world: Variant = world_ref.get_ref() if world_ref is WeakRef else null
		var budget: Variant = budget_ref.get_ref() if budget_ref is WeakRef else null
		if world == null or budget == null or not is_instance_valid(world) or not is_instance_valid(budget):
			_world_registry.erase(world_id)
