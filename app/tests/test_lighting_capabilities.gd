extends SceneTree

const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	stage.name = "LightingCapabilityTestStage"
	root.add_child(stage)
	await process_frame

	var aircraft := _make_aircraft("LightingCapabilityAircraft")
	stage.add_child(aircraft)
	var rig := Rig.new()
	var fresh_report: Dictionary = rig.capability_report()
	_check("fresh unconfigured rig reports unavailable with empty rows", fresh_report.get("state") == "unavailable" and fresh_report.get("zones", []).is_empty() and fresh_report.get("effects", []).is_empty())
	var inherit_result: Dictionary = rig.configure(aircraft, Profile.defaults())
	var inherited: Dictionary = rig.capability_report()
	var inherited_children := aircraft.get_child_count()
	for _index in 6:
		inherited = rig.capability_report()
	_check("inherit report is empty and creates no kit", bool(inherit_result.get("ok", false)) and inherited.get("state") == "inherit" and inherited.get("zones", []).is_empty() and inherited.get("effects", []).is_empty() and aircraft.get_node_or_null("NightKit") == null)
	_check("repeated inherit reporting allocates no effects or aircraft nodes", inherited_children == aircraft.get_child_count() and int(rig.budget_info().get("vfx", {}).get("effects_allocated", -1)) == 0)
	rig.dispose()

	aircraft.set_meta("light_anchors", {
		"landing": {"position": Vector3(-0.08, -0.02, -0.2)},
		"landing_right": {"position": Vector3(0.08, -0.02, -0.2)},
	})
	var kit := AircraftLights.attach(aircraft)
	_remove_kit_node(kit, "strip_left")
	_remove_kit_node(kit, "strip_right")
	_remove_kit_node(kit, "strip_top_left")
	_add_test_strip(kit, "strip_right")
	_unbind_kit_node(kit, "strip_right")
	_add_test_strip(kit, "strip_top_left")
	var profile: Dictionary = Profile.preset("custom")
	for zone: Dictionary in profile.get("zones", []):
		if str(zone.get("id", "")) == "strip_top_left":
			zone["enabled"] = false
		if str(zone.get("id", "")) == "landing_lamp":
			zone["enabled"] = true
	var configured: Dictionary = rig.configure(aircraft, profile)
	var report: Dictionary = rig.capability_report()
	var left_row := _row(report.get("zones", []), "strip_left")
	var right_row := _row(report.get("zones", []), "strip_right")
	var top_left_row := _row(report.get("zones", []), "strip_top_left")
	var landing_rows := _rows(report.get("zones", []), "landing_lamp")
	var left_effect := _row(report.get("effects", []), "vfx_tip_left")
	var landing_binding_count := 0
	for binding: Dictionary in rig._materials:
		if str(binding.get("zone_id", "")) == "landing_lamp":
			landing_binding_count += 1
	_check("configured report includes only requested zones and canonicalizes paired landing hardware once", bool(configured.get("ok", false)) and report.get("state") == "configured" and report.get("zones", []).size() == profile.get("zones", []).size() and landing_rows.size() == 1 and landing_binding_count >= 2)
	_check("zone and effect rows contain only detached scalar schema fields", _rows_follow_schema(report.get("zones", [])) and _rows_follow_schema(report.get("effects", [])))
	_check("missing strip fitting is reported from the absent live binding", not bool(left_row.get("available", true)) and str(left_row.get("reason", "")) == "missing_fitting")
	_check("unbound compatible mesh stays reported and visible through profile rendering", bool(right_row.get("available", false)) and bool(right_row.get("enabled", false)) and str(right_row.get("reason", "x")).is_empty() and (kit.get_node("strip_right") as MeshInstance3D).visible)
	_check("disabled zone reports its fitted hardware without becoming enabled", bool(top_left_row.get("available", false)) and not bool(top_left_row.get("enabled", true)) and str(top_left_row.get("reason", "x")).is_empty())
	_check("disabled optional effect reports a live tip anchor and world host", not bool(left_effect.get("enabled", true)) and bool(left_effect.get("available", false)) and str(left_effect.get("reason", "x")).is_empty())

	var kit_children := kit.get_child_count()
	var warnings_before: int = rig.budget_info().get("warnings", []).size()
	var effects_before := int(rig.budget_info().get("vfx", {}).get("effects_allocated", -1))
	var detached: Dictionary = rig.capability_report()
	var detached_zone: Dictionary = _row(detached.get("zones", []), "strip_top_left")
	detached_zone["enabled"] = true
	detached.get("zones", []).clear()
	detached.get("effects", []).clear()
	detached.get("warnings", []).append("mutated by caller")
	var reread: Dictionary = rig.capability_report()
	_check("report arrays and rows are detached from rig state", reread.get("zones", []).size() == profile.get("zones", []).size() and not bool(_row(reread.get("zones", []), "strip_top_left").get("enabled", true)) and not reread.get("warnings", []).has("mutated by caller"))
	for _index in 6:
		rig.capability_report()
	_check("reporting does not grow warnings, kit nodes, or effect pools", kit.get_child_count() == kit_children and rig.budget_info().get("warnings", []).size() == warnings_before and int(rig.budget_info().get("vfx", {}).get("effects_allocated", -1)) == effects_before and effects_before == 0)

	kit.set_meta("supported_light_groups", ["navigation", "strobe", "landing"])
	var unsupported := _row(rig.capability_report().get("zones", []), "strip_right")
	_check("unsupported group takes precedence over a present fitted binding", not bool(unsupported.get("available", true)) and bool(unsupported.get("enabled", false)) and str(unsupported.get("reason", "")) == "unsupported_group")
	kit.set_meta("supported_light_groups", ["strobe", "landing", "orientation"])
	var unsupported_nav_effect := _row(rig.capability_report().get("effects", []), "vfx_tip_left")
	_check("effect anchor remains available when navigation lights are unsupported", bool(unsupported_nav_effect.get("available", false)) and str(unsupported_nav_effect.get("reason", "x")).is_empty())
	kit.set_meta("supported_light_groups", AircraftLights.GROUPS.duplicate())

	var removed_tip := _remove_kit_node(kit, "nav_left", false)
	var missing_anchor := _row(rig.capability_report().get("effects", []), "vfx_tip_left")
	_check("effect without its actual navigation anchor reports missing_anchor", not bool(missing_anchor.get("available", true)) and str(missing_anchor.get("reason", "")) == "missing_anchor")

	var disabled_profile: Dictionary = Profile.defaults()
	disabled_profile["selection"] = "disabled"
	var disabled_result: Dictionary = rig.configure(aircraft, disabled_profile)
	var disabled_report: Dictionary = rig.capability_report()
	_check("disabled selection preserves lazy empty report state", bool(disabled_result.get("ok", false)) and disabled_report.get("state") == "disabled" and disabled_report.get("zones", []).is_empty() and disabled_report.get("effects", []).is_empty())
	if is_instance_valid(removed_tip):
		removed_tip.free()
	rig.dispose()
	_check("disposed rig reports unavailable with empty rows", rig.capability_report().get("state") == "unavailable" and rig.capability_report().get("zones", []).is_empty())
	rig.free()

	var detached_aircraft := _make_aircraft("DetachedLightingCapabilityAircraft")
	var detached_kit := AircraftLights.attach(detached_aircraft)
	_add_test_strip(detached_kit, "strip_right")
	var detached_profile: Dictionary = Profile.preset("custom")
	var detached_rig := Rig.new()
	var detached_configured: Dictionary = detached_rig.configure(detached_aircraft, detached_profile)
	var no_world_effect := _row(detached_rig.capability_report().get("effects", []), "vfx_tip_left")
	_check("disabled effect is unavailable until a usable world parent exists", bool(detached_configured.get("ok", false)) and not bool(no_world_effect.get("available", true)) and str(no_world_effect.get("reason", "")) == "missing_anchor")
	stage.add_child(detached_aircraft)
	await process_frame
	var world_effect := _row(detached_rig.capability_report().get("effects", []), "vfx_tip_left")
	_check("same disabled effect becomes available after the host joins a render world", bool(world_effect.get("available", false)) and str(world_effect.get("reason", "x")).is_empty() and int(detached_rig.budget_info().get("vfx", {}).get("effects_allocated", -1)) == 0)
	detached_rig.dispose()
	detached_rig.free()

	var freed_aircraft := _make_aircraft("FreedLightingCapabilityAircraft")
	stage.add_child(freed_aircraft)
	var freed_kit := AircraftLights.attach(freed_aircraft)
	_add_test_strip(freed_kit, "strip_right")
	var freed_rig := Rig.new()
	freed_rig.configure(freed_aircraft, Profile.preset("custom"))
	freed_aircraft.free()
	_check("freed aircraft root makes the report unavailable", freed_rig.capability_report().get("state") == "unavailable" and freed_rig.capability_report().get("zones", []).is_empty())
	freed_rig.free()

	stage.free()
	print("lighting capabilities: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _make_aircraft(node_name: String) -> Node3D:
	var aircraft := Node3D.new()
	aircraft.name = node_name
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.9)
	body.mesh = box
	aircraft.add_child(body)
	return aircraft


func _add_test_strip(kit: Node3D, node_name: String) -> void:
	var line := PackedVector3Array([Vector3(-0.25, 0.0, 0.0), Vector3(0.0, 0.01, 0.1), Vector3(0.25, 0.0, 0.0)])
	var strip: MeshInstance3D = AircraftLights.strip(node_name, line)
	kit.add_child(strip)
	var groups: Dictionary = kit.get_meta("light_bindings", {})
	var orientation: Array = groups.get("orientation", [])
	orientation.append(strip)
	groups["orientation"] = orientation
	kit.set_meta("light_bindings", groups)


func _remove_kit_node(kit: Node3D, node_name: String, free_node := true) -> Node3D:
	var node := kit.get_node_or_null(NodePath(node_name)) as Node3D
	if node == null:
		return null
	var groups: Dictionary = kit.get_meta("light_bindings", {})
	for group: String in groups:
		var remaining: Array = []
		for candidate: Variant in groups[group]:
			if candidate != node and is_instance_valid(candidate):
				remaining.append(candidate)
		groups[group] = remaining
	kit.set_meta("light_bindings", groups)
	kit.remove_child(node)
	if free_node:
		node.free()
	return node


func _unbind_kit_node(kit: Node3D, node_name: String) -> void:
	var node := kit.get_node_or_null(NodePath(node_name)) as Node3D
	if not is_instance_valid(node):
		return
	var groups: Dictionary = kit.get_meta("light_bindings", {})
	for group: String in groups:
		var remaining: Array = []
		for candidate: Variant in groups[group]:
			if candidate != node and is_instance_valid(candidate):
				remaining.append(candidate)
		groups[group] = remaining
	kit.set_meta("light_bindings", groups)


func _row(rows: Variant, id: String) -> Dictionary:
	for row: Variant in rows:
		if row is Dictionary and str(row.get("id", "")) == id:
			return row
	return {}


func _rows(rows: Variant, id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Variant in rows:
		if row is Dictionary and str(row.get("id", "")) == id:
			result.append(row)
	return result


func _rows_follow_schema(rows: Variant) -> bool:
	if not rows is Array:
		return false
	for row: Variant in rows:
		if not row is Dictionary or row.size() != 4 or not row.has("id") or not row.has("enabled") \
				or not row.has("available") or not row.has("reason"):
			return false
		if typeof(row["id"]) != TYPE_STRING or typeof(row["enabled"]) != TYPE_BOOL \
				or typeof(row["available"]) != TYPE_BOOL or typeof(row["reason"]) != TYPE_STRING:
			return false
	return true


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1
