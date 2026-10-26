extends SceneTree

const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const LightingPolicy := preload("res://render/lighting/lighting_policy.gd")
const SceneBudget := preload("res://render/lighting/lighting_scene_budget.gd")

var _checks := 0
var _failures := 0
var _shared_fixtures: Array = []
var _overlap_spill_events := 0
var _overlap_effect_events := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var saved_quality: String = LightingPolicy.quality
	var saved_reduced_flashes: bool = LightingPolicy.reduced_flashes
	var saved_show_vfx: bool = LightingPolicy.show_vfx
	# Build every real rig with grants disabled, then observe all transitions when
	# they begin requesting at Standard quality.
	LightingPolicy.quality = "low"
	LightingPolicy.reduced_flashes = false
	LightingPolicy.show_vfx = true

	var shared_world := World3D.new()
	var isolated_world := World3D.new()
	var companion_view := _make_viewport("CompanionViewport", shared_world)
	var player_view := _make_viewport("PlayerViewport", shared_world)
	var workshop_view := _make_viewport("WorkshopViewport", isolated_world)
	await process_frame

	var companion := _make_rig(companion_view, "Companion")
	var player := _make_rig(player_view, "Player")
	var workshop := _make_rig(workshop_view, "Workshop")
	_check("three real lighting rigs configure with visible strip and VFX pools",
		bool(companion.result.get("ok", false)) and bool(player.result.get("ok", false))
			and bool(workshop.result.get("ok", false))
			and companion.rig._vfx._spills.size() == 2 and player.rig._vfx._spills.size() == 2
			and workshop.rig._vfx._spills.size() == 2
			and companion.rig._vfx._effects.size() == 2 and player.rig._vfx._effects.size() == 2
			and workshop.rig._vfx._effects.size() == 2)
	_check("two viewports sharing World3D share one runtime coordinator",
		companion.rig._vfx._scene_budget == player.rig._vfx._scene_budget)
	_check("Workshop World3D owns an isolated runtime coordinator",
		workshop.rig._vfx._scene_budget != companion.rig._vfx._scene_budget)
	_watch_shared_visibility([companion, player])
	LightingPolicy.quality = "standard"

	var workshop_telemetry := _telemetry(3.0, 0)
	workshop.rig.advance(1.0, workshop_telemetry)
	companion.rig.advance(1.0, _telemetry(1.0, 0))
	_check("Workshop gets its own actual Omni and MultiMesh quota",
		_visible_spills(workshop.rig) == 2 and _visible_effect_anchors(workshop.rig) == 2
			and _visible_particles(workshop.rig) > 0)
	_check("closer companion initially renders both decorative categories",
		_visible_spills(companion.rig) == 2 and _visible_effect_anchors(companion.rig) == 2
			and _visible_particles(companion.rig) > 0)

	player.rig.advance(1.0, _telemetry(10.0, 100))
	_check("player priority preempts a closer companion in actual light visibility",
		_visible_spills(player.rig) == 2 and _visible_spills(companion.rig) == 0)
	_check("player priority preempts a closer companion in actual MultiMesh visibility and count",
		_visible_effect_anchors(player.rig) == 2 and _visible_particles(player.rig) > 0
			and _visible_effect_anchors(companion.rig) == 0)
	_check("priority transfer leaves the isolated Workshop visibility unchanged",
		_visible_spills(workshop.rig) == 2 and _visible_effect_anchors(workshop.rig) == 2)
	_check("actual scene totals never exceed two visible decorative resources per category",
		_visible_spills(player.rig) + _visible_spills(companion.rig) <= 2
			and _visible_effect_anchors(player.rig) + _visible_effect_anchors(companion.rig) <= 2)
	_check("synchronous actual visibility callbacks never create an over-cap overlap",
		_overlap_spill_events == 0 and _overlap_effect_events == 0)

	player.rig.set_mode("nav")
	_check("NAV mode hides actual spills and VFX and returns both grants",
		_visible_spills(player.rig) == 0 and _visible_effect_anchors(player.rig) == 0
			and _total_particle_instances(player.rig) == 0
			and _visible_spills(companion.rig) == 2 and _visible_effect_anchors(companion.rig) == 2)
	player.rig.set_mode("all")
	player.rig.advance(1.6, _telemetry(10.0, 100, 0.0))
	player.rig.advance(1.7, _telemetry(10.0, 100, 1.0))
	_check("returning to ALL mode reclaims actual pools after a displayed update",
		_visible_spills(player.rig) == 2 and _visible_effect_anchors(player.rig) == 2
			and _visible_effect_anchors(companion.rig) == 0)

	player.rig.reset()
	var reset_grant: Dictionary = player.rig._vfx._scene_budget.grant_for(player.rig._vfx)
	_check("reset clears MultiMesh counts and synchronously gives the VFX quota to companion",
		_visible_particles(player.rig) == 0 and _total_particle_instances(player.rig) == 0
			and _visible_effect_nodes(player.rig) == 0
			and int(reset_grant.get("vfx_anchors", -1)) == 0
			and _visible_effect_nodes(companion.rig) == 2
			and _visible_effect_anchors(companion.rig) == 2 and _visible_particles(companion.rig) > 0)
	player.rig.advance(2.0, _telemetry(10.0, 100, 1.0))
	_check("advance after reset can reacquire visible effect anchors",
		_visible_effect_anchors(player.rig) == 2 and _visible_particles(player.rig) > 0
			and _visible_effect_anchors(companion.rig) == 0)

	player.rig.dispose()
	_check("disposing player unregisters and immediately restores companion actual lights and effects",
		_visible_spills(player.rig) == 0 and _visible_effect_anchors(player.rig) == 0
			and _has_no_spill_nodes(player) and not is_instance_valid(player.stage.get_node_or_null("AircraftLightingWorldVfx"))
			and _visible_spills(companion.rig) == 2 and _visible_effect_anchors(companion.rig) == 2
			and _visible_particles(companion.rig) > 0)
	_check("isolated Workshop remains visible after shared-world disposal",
		_visible_spills(workshop.rig) == 2 and _visible_effect_anchors(workshop.rig) == 2)

	LightingPolicy.quality = "low"
	companion.rig.advance(2.1, _telemetry(1.0, 0, 0.0))
	workshop.rig.advance(2.1, _telemetry(3.0, 0, 0.0))
	_check("Low quality hides actual Omni lights and clears all visible MultiMesh instances",
		_visible_spills(companion.rig) == 0 and _visible_effect_anchors(companion.rig) == 0
			and _visible_effect_nodes(companion.rig) == 0 and _visible_particles(companion.rig) == 0
			and _visible_spills(workshop.rig) == 0 and _visible_effect_anchors(workshop.rig) == 0
			and _visible_effect_nodes(workshop.rig) == 0 and _visible_particles(workshop.rig) == 0)
	_check("Low quality is propagated to each independent World3D coordinator",
		companion.rig._vfx._scene_budget.quality() == "low"
			and workshop.rig._vfx._scene_budget.quality() == "low")

	companion.rig.dispose()
	workshop.rig.dispose()
	companion.rig.free()
	player.rig.free()
	workshop.rig.free()
	companion_view.free()
	player_view.free()
	workshop_view.free()
	shared_world = null
	isolated_world = null
	SceneBudget._prune_world_registry()
	_check("World3D registry drops disposed fixture coordinators",
		SceneBudget._world_registry.is_empty())
	LightingPolicy.quality = saved_quality
	LightingPolicy.reduced_flashes = saved_reduced_flashes
	LightingPolicy.show_vfx = saved_show_vfx
	print("lighting scene integration checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _make_viewport(view_name: String, world: World3D) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.size = Vector2i(64, 64)
	viewport.world_3d = world
	root.add_child(viewport)
	return viewport


func _make_rig(viewport: SubViewport, suffix: String) -> Dictionary:
	var stage := Node3D.new()
	stage.name = "Stage" + suffix
	viewport.add_child(stage)
	var aircraft := Node3D.new()
	aircraft.name = "Aircraft" + suffix
	aircraft.set_meta("light_anchors", {
		"landing": {"position": Vector3(-0.08, -0.02, -0.2)},
		"landing_right": {"position": Vector3(0.08, -0.02, -0.2)},
		"strobe_dorsal": {"position": Vector3(0.0, 0.07, 0.0)},
		"strobe_ventral": {"position": Vector3(0.0, -0.07, 0.0)},
	})
	stage.add_child(aircraft)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.9)
	body.mesh = box
	aircraft.add_child(body)
	var rig := Rig.new()
	rig.name = "LightingRig" + suffix
	stage.add_child(rig)
	var configured: Dictionary = rig.configure(aircraft, Profile.preset("festival"))
	return {"stage": stage, "aircraft": aircraft, "rig": rig, "result": configured}


func _telemetry(distance_m: float, lighting_priority: int, maneuver := 1.0) -> Dictionary:
	return {
		"distance_m": distance_m,
		"lighting_priority": lighting_priority,
		"maneuver": maneuver,
		"effects_allowed": true,
		"exposure": 1.0,
	}


func _visible_spills(rig: Variant) -> int:
	if rig._vfx == null:
		return 0
	var total := 0
	for binding: Dictionary in rig._vfx._spills:
		var light: OmniLight3D = binding.get("light")
		if is_instance_valid(light) and light.visible:
			total += 1
	return total


func _watch_shared_visibility(fixtures: Array) -> void:
	_shared_fixtures = fixtures.duplicate()
	for fixture: Dictionary in _shared_fixtures:
		var rig: Variant = fixture.rig
		for binding: Dictionary in rig._vfx._spills:
			var light: OmniLight3D = binding.get("light")
			light.visibility_changed.connect(_on_shared_spill_visibility_changed)
		for pool: Dictionary in rig._vfx._effects:
			var instance: MultiMeshInstance3D = pool.get("instance")
			instance.visibility_changed.connect(_on_shared_effect_visibility_changed)


func _on_shared_spill_visibility_changed() -> void:
	var visible := 0
	for fixture: Dictionary in _shared_fixtures:
		visible += _visible_spills(fixture.rig)
	if visible > 2:
		_overlap_spill_events += 1


func _on_shared_effect_visibility_changed() -> void:
	var visible := 0
	for fixture: Dictionary in _shared_fixtures:
		visible += _visible_effect_anchors(fixture.rig)
	if visible > 2:
		_overlap_effect_events += 1


func _visible_effect_anchors(rig: Variant) -> int:
	if rig._vfx == null:
		return 0
	var total := 0
	for pool: Dictionary in rig._vfx._effects:
		var instance: MultiMeshInstance3D = pool.get("instance")
		if is_instance_valid(instance) and instance.visible and instance.multimesh != null \
				and instance.multimesh.visible_instance_count > 0:
			total += 1
	return total


func _visible_particles(rig: Variant) -> int:
	if rig._vfx == null:
		return 0
	var total := 0
	for pool: Dictionary in rig._vfx._effects:
		var instance: MultiMeshInstance3D = pool.get("instance")
		if is_instance_valid(instance) and instance.visible and instance.multimesh != null:
			total += instance.multimesh.visible_instance_count
	return total


func _visible_effect_nodes(rig: Variant) -> int:
	if rig._vfx == null:
		return 0
	var total := 0
	for pool: Dictionary in rig._vfx._effects:
		var instance: MultiMeshInstance3D = pool.get("instance")
		if is_instance_valid(instance) and instance.visible:
			total += 1
	return total


func _total_particle_instances(rig: Variant) -> int:
	if rig._vfx == null:
		return 0
	var total := 0
	for pool: Dictionary in rig._vfx._effects:
		var instance: MultiMeshInstance3D = pool.get("instance")
		if is_instance_valid(instance) and instance.multimesh != null:
			total += instance.multimesh.visible_instance_count
	return total


func _has_no_spill_nodes(fixture: Dictionary) -> bool:
	var kit := fixture.aircraft.get_node_or_null("NightKit") as Node3D
	if kit == null:
		return false
	for child: Node in kit.get_children():
		if child is OmniLight3D and str(child.name).begins_with("strip_spill_"):
			return false
	return true


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)
