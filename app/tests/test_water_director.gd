## LU-27: water terminal impacts route through the water aftermath and return to the ordinary dry crash path.
extends SceneTree

const MainScene = preload("res://main.tscn")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const Director = preload("res://render/crash/director.gd")
const ImpactSnapshot = preload("res://physics/impact_snapshot.gd")
const RB = preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)


func _run() -> void:
	var loaded: Dictionary = LakeLoader.load_from("res://data/fields/lake.json")
	_check("normalized lake fixture loads", bool(loaded.get("ok", false)))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var flight: Variant = MainScene.instantiate()
	flight.name = "WaterDirectorFixture"
	flight.set("crash_effects_enabled", false)
	root.add_child(flight)
	await process_frame
	flight.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	_check("production session accepts the normalized lake", flight.session.set_lake_context(loaded.lake))
	var director: Variant = Director.new()
	director.name = "WaterDirectorFixtureNode"
	root.add_child(director)
	var aircraft_data: String = str(Catalog.entry(str(flight.get("aircraft_id"))).get("data", ""))
	director.configure(flight, aircraft_data, true)
	_check("director creates and configures one water-effects child",
		director.water_effects != null and director.water_effects.get_parent() == director
			and director.water_effects._configured)

	var source_root: Node3D = flight._airplane.root
	var source_transform: Transform3D = source_root.global_transform
	var shadow: MeshInstance3D = flight._shadow
	var shadow_visible := shadow.visible
	var water_hit := _impact(flight.session, "water", PackedFloat64Array([110.0, 125.0, 0.80]),
		PackedFloat64Array([0.0, 0.0, 18.0]))
	flight.session.crash = {"impact": water_hit, "why": "test water contact", "ticks_left": 20}
	director.update(0.1)
	_check("water event activates its own aftermath and water report",
		director.active and director._water_active and director.report.get("trigger", "") == "water"
			and director.report.get("surface", "") == "water" and director.description().contains("Water impact"))
	_check("water event skips dry wreck, crash particles and dry crash audio",
		not director.wreck.stats().started and not director.effects._active
			and not director.audio._primary_played and director.audio.active_voice_count() == 0)
	_check("one water impact selects exactly one splash voice",
		director.water_effects._impact_audio_requests_this_event == 1
			and director.water_effects._impact_audio_emitted
			and director.stats().water_event_count == 1)
	_check("airframe remains visible and begins the render-only sink while its shadow is hidden",
		source_root.visible and source_root.global_position.y < source_transform.origin.y and not shadow.visible)
	var camera := Camera3D.new()
	root.add_child(camera)
	director.aim(camera, true)
	_check("water impact remains a valid camera target", camera.fov == 58.0 and camera.global_position != Vector3.ZERO)

	director.update(0.12)
	var water_stats: Dictionary = director.stats().water
	_check("pooled plume, rings and droplets are prepared for the splash",
		director.water_effects._plume != null and director.water_effects._rings.size() == 2
			and director.water_effects._droplet_multimesh.instance_count == 16
			and int(water_stats.get("rings_visible", 0)) > 0)
	var elapsed_before_pause: float = director.water_effects._elapsed_s
	flight.session.hold("water-director-test")
	director.update(0.1)
	_check("user hold pauses water aftermath even though the crash already froze physics",
		director.water_effects._elapsed_s == elapsed_before_pause)
	flight.session.release("water-director-test")
	director.update(0.1)
	_check("aftermath resumes after the user hold is released",
		director.water_effects._elapsed_s > elapsed_before_pause)

	flight.session.reset()
	_check("reset clears the water event and restores the original render state",
		not director.active and not director._water_active and not director.water_effects._has_event
			and source_root.visible and source_root.global_transform == source_transform
			and shadow.visible == shadow_visible)

	var dry_hit := _impact(flight.session, "hull_contact",
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 16.0]))
	flight.session.crash = {"impact": dry_hit, "why": "test dry contact", "ticks_left": 20}
	director.update(1.0 / 60.0)
	_check("water reset returns the same director to the ordinary dry wreck and sound path",
		director.active and not director._water_active and director.wreck.stats().started
			and director.audio._primary_played and director.report.get("trigger", "") == "hull_contact")
	_check("water event count is retained in director stats across the dry transition",
		director.stats().water_event_count == 1 and not director.stats().water_active)

	flight.session.reset()
	flight.free()
	director.free()
	camera.free()
	await process_frame
	await process_frame
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _impact(session: Node, trigger: String, point: PackedFloat64Array,
		velocity: PackedFloat64Array) -> ImpactSnapshot.Snapshot:
	var snapshot := ImpactSnapshot.Snapshot.new()
	snapshot.trigger = trigger
	snapshot.tick = int(session.sim.tick) + 1
	snapshot.detected_state = session.sim.state.duplicate()
	snapshot.has_kinematics = true
	snapshot.point_ned = point
	snapshot.velocity_ned = velocity
	snapshot.speed_mps = sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2])
	snapshot.down_speed_mps = velocity[2]
	return snapshot
