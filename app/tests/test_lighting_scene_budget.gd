extends SceneTree

const Budget := preload("res://render/lighting/lighting_scene_budget.gd")

class Probe:
	extends RefCounted
	var stable_id := ""
	var budget: Variant = null
	var grant := {"spill_lights": 0, "vfx_anchors": 0}
	var events: Array = []
	var peers: Array = []
	var cap := 2
	var over_cap_callbacks := 0
	var reentrant_request: Dictionary = {}
	var reenter_once := false

	func _init(id: String, event_log: Array = []) -> void:
		stable_id = id
		events = event_log

	func apply_scene_budget(value: Dictionary) -> void:
		grant = value.duplicate(true)
		events.append({"id": stable_id, "grant": grant.duplicate(true)})
		var spill_total := 0
		var vfx_total := 0
		for peer: Probe in peers:
			spill_total += int(peer.grant.spill_lights)
			vfx_total += int(peer.grant.vfx_anchors)
		if spill_total > cap or vfx_total > cap:
			over_cap_callbacks += 1
		if reenter_once and budget != null:
			reenter_once = false
			budget.submit(self, reentrant_request)


var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_world_identity()
	_test_ranking_and_revocation_order()
	_test_stable_id_tie_break()
	_test_quality_changes_and_bounds()
	_test_unregister_and_weak_cleanup()
	_test_reentrant_submission()
	print("lighting scene budget checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_world_identity() -> void:
	var shared_world := World3D.new()
	var isolated_world := World3D.new()
	var view_a := SubViewport.new()
	var view_b := SubViewport.new()
	view_a.world_3d = shared_world
	view_b.world_3d = shared_world
	var budget_a = Budget.for_world(view_a.world_3d)
	var budget_b = Budget.for_world(view_b.world_3d)
	var budget_isolated = Budget.for_world(isolated_world)
	_check("viewports sharing World3D share a coordinator", budget_a == budget_b)
	_check("separate World3D resources isolate coordinators", budget_a != budget_isolated)
	var shared_owners: Array[Probe] = []
	var isolated_owners: Array[Probe] = []
	for index in range(3):
		var shared_owner := Probe.new("owner-%d" % index)
		var isolated_owner := Probe.new("owner-%d" % index)
		shared_owners.append(shared_owner)
		isolated_owners.append(isolated_owner)
		var shared_budget = budget_a if index % 2 == 0 else budget_b
		_check("shared-world owner %d registers" % index,
			shared_budget.register_owner(shared_owner, shared_owner.stable_id))
		_check("isolated-world owner %d registers" % index,
			budget_isolated.register_owner(isolated_owner, isolated_owner.stable_id))
		shared_budget.submit(shared_owner, _request(0, float(index), 1, 0))
		budget_isolated.submit(isolated_owner, _request(0, float(index), 1, 0))
	_check("shared viewports use one combined cap while a separate World3D has its own",
		_count_granted(shared_owners, "spill_lights") == 2
			and _count_granted(isolated_owners, "spill_lights") == 2)
	for owner: Probe in shared_owners:
		budget_a.unregister_owner(owner)
	for owner: Probe in isolated_owners:
		budget_isolated.unregister_owner(owner)
	view_a.free()
	view_b.free()
	shared_world = null
	isolated_world = null
	budget_a = null
	budget_b = null
	budget_isolated = null
	Budget._prune_world_registry()
	_check("weak World3D registry prunes abandoned coordinators",
		Budget._world_registry.is_empty())


func _test_ranking_and_revocation_order() -> void:
	var world := World3D.new()
	var budget = Budget.for_world(world)
	var events: Array = []
	var far := Probe.new("far", events)
	var middle := Probe.new("middle", events)
	var near := Probe.new("near", events)
	var preferred := Probe.new("preferred", events)
	var peers: Array = [far, middle, near, preferred]
	for owner: Probe in peers:
		owner.peers = peers
		owner.cap = 2
		_check("owner %s registers" % owner.stable_id, budget.register_owner(owner, owner.stable_id))
	# Submit out of rank order. Standard grants two independent spill/VFX requests.
	budget.submit(far, _request(0, 90.0, 1, 1))
	budget.submit(middle, _request(0, 20.0, 1, 1))
	budget.submit(near, _request(0, 10.0, 1, 1))
	_check("nearest owners receive equal-priority grants", near.grant.spill_lights == 1
		and middle.grant.spill_lights == 1 and far.grant.spill_lights == 0)
	_check("spill and VFX have independent scene caps", near.grant.vfx_anchors == 1
		and middle.grant.vfx_anchors == 1 and far.grant.vfx_anchors == 0)
	# A higher stable priority wins even at a greater distance. The displaced owner is
	# synchronously revoked before the preferred owner is enabled.
	events.clear()
	budget.submit(preferred, _request(10, 500.0, 1, 1))
	_check("higher priority outranks distance", preferred.grant.spill_lights == 1
		and near.grant.spill_lights == 1 and middle.grant.spill_lights == 0)
	var displaced_revoke := _event_index(events, "middle", 0)
	var preferred_grant := _event_index(events, "preferred", 1)
	_check("revocations publish before new grants", displaced_revoke >= 0 and preferred_grant > displaced_revoke)
	_check("synchronous publish never transiently exceeds either cap",
		peers.all(func(owner: Probe) -> bool: return owner.over_cap_callbacks == 0))
	var receipt: Dictionary = budget.receipt()
	_check("receipt reports limits and stable ranked rows", receipt.spill_limit == 2
		and receipt.vfx_anchor_limit == 2 and receipt.grants.size() == 4
		and receipt.grants[0].stable_id == "preferred")
	budget.unregister_owner(far)
	budget.unregister_owner(middle)
	budget.unregister_owner(near)
	budget.unregister_owner(preferred)
	budget = null
	world = null


func _test_stable_id_tie_break() -> void:
	var world := World3D.new()
	var budget = Budget.for_world(world)
	var owners: Array[Probe] = [Probe.new("c"), Probe.new("b"), Probe.new("a")]
	for owner: Probe in owners:
		_check("stable tie owner %s registers" % owner.stable_id,
			budget.register_owner(owner, owner.stable_id))
		budget.submit(owner, _request(4, 12.0, 1, 0))
	_check("equal priority and distance use stable ID, independent of submission order",
		owners[0].grant.spill_lights == 0 and owners[1].grant.spill_lights == 1
			and owners[2].grant.spill_lights == 1)
	var receipt: Dictionary = budget.receipt()
	_check("receipt rows follow the same stable tie order",
		receipt.grants[0].stable_id == "a" and receipt.grants[1].stable_id == "b"
			and receipt.grants[2].stable_id == "c")
	for owner: Probe in owners:
		budget.unregister_owner(owner)
	budget = null
	world = null


func _test_quality_changes_and_bounds() -> void:
	var world := World3D.new()
	var budget = Budget.for_world(world)
	var owners: Array[Probe] = []
	for index in range(5):
		var owner := Probe.new("q%d" % index)
		owners.append(owner)
		_check("quality owner %d registers" % index, budget.register_owner(owner, owner.stable_id))
		budget.submit(owner, _request(0, float(index), 1, 1))
	_check("Standard independently caps each category at two",
		_count_granted(owners, "spill_lights") == 2 and _count_granted(owners, "vfx_anchors") == 2)
	_check("High independently raises both caps to four", budget.set_quality("high")
		and _count_granted(owners, "spill_lights") == 4 and _count_granted(owners, "vfx_anchors") == 4)
	_check("Low synchronously revokes all decorative grants", budget.set_quality("low")
		and _count_granted(owners, "spill_lights") == 0 and _count_granted(owners, "vfx_anchors") == 0)
	_check("invalid quality leaves the accepted quality unchanged",
		not budget.set_quality("ultra") and budget.quality() == "low")
	_check("per-owner request counts clamp to two", budget.set_quality("high")
		and budget.submit(owners[0], _request(0, 0.0, 99, 99)) == {"spill_lights": 2, "vfx_anchors": 2})
	for owner: Probe in owners:
		budget.unregister_owner(owner)
	budget = null
	world = null


func _test_unregister_and_weak_cleanup() -> void:
	var world := World3D.new()
	var budget = Budget.for_world(world)
	var events: Array = []
	var first := Probe.new("first", events)
	var second := Probe.new("second", events)
	_check("unregister fixture registers", budget.register_owner(first, "first") and budget.register_owner(second, "second"))
	budget.submit(first, _request(1, 1.0, 1, 1))
	budget.submit(second, _request(0, 2.0, 2, 2))
	_check("fixture starts with both owners granted", first.grant.spill_lights == 1 and second.grant.spill_lights == 1)
	var event_start := events.size()
	budget.unregister_owner(first)
	_check("unregister publishes zero to the departing owner", first.grant.spill_lights == 0 and first.grant.vfx_anchors == 0)
	_check("unregister immediately frees capacity for the next owner", second.grant.spill_lights == 2
		and second.grant.vfx_anchors == 2 and budget.registered_owner_count() == 1)
	var first_revoke := _event_index_from(events, "first", 0, event_start)
	var second_increase := _event_index_from(events, "second", 2, event_start)
	_check("unregister callback happens before the replacement grant", first_revoke >= 0 and second_increase > first_revoke)
	budget.unregister_owner(second)
	first = null
	second = null

	var weak_owner_ref: WeakRef = _register_ephemeral(budget)
	_check("registry stores weak owner references", weak_owner_ref.get_ref() == null)
	_check("query prunes a dead owner and its stale grant", budget.registered_owner_count() == 0
		and budget.receipt().registered_owners == 0)
	budget = null
	world = null


func _test_reentrant_submission() -> void:
	var world := World3D.new()
	var budget = Budget.for_world(world)
	var owner := Probe.new("reentrant")
	owner.budget = budget
	_check("reentrant owner registers", budget.register_owner(owner, owner.stable_id))
	owner.reenter_once = true
	owner.reentrant_request = _request(2, 0.0, 1, 1)
	var result: Dictionary = budget.submit(owner, _request(1, 2.0, 1, 1))
	_check("callback-triggered submit is bounded and reconciled", result.spill_lights == 1
		and result.vfx_anchors == 1 and owner.grant == result)
	budget.unregister_owner(owner)
	budget = null
	world = null


func _register_ephemeral(budget: Variant) -> WeakRef:
	var owner := Probe.new("ephemeral")
	var owner_ref: WeakRef = weakref(owner)
	budget.register_owner(owner, "ephemeral")
	budget.submit(owner, _request(0, 0.0, 1, 1))
	return owner_ref


func _request(priority: int, distance_m: float, spill_lights: int, vfx_anchors: int) -> Dictionary:
	return {"priority": priority, "distance_m": distance_m,
		"spill_lights": spill_lights, "vfx_anchors": vfx_anchors}


func _count_granted(owners: Array, field: String) -> int:
	var total := 0
	for owner_value: Variant in owners:
		total += int(owner_value.grant.get(field, 0))
	return total


func _event_index(events: Array, id: String, spill_grant: int) -> int:
	return _event_index_from(events, id, spill_grant, 0)


func _event_index_from(events: Array, id: String, spill_grant: int, start: int) -> int:
	for index in range(start, events.size()):
		var event: Dictionary = events[index]
		var grant: Dictionary = event.get("grant", {})
		if str(event.get("id", "")) == id and int(grant.get("spill_lights", -1)) == spill_grant:
			return index
	return -1


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)
