## LU-27: water terminal impacts route through the water aftermath and return to the ordinary dry crash path.
extends SceneTree

const MainScene = preload("res://main.tscn")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const Director = preload("res://render/crash/director.gd")
const PresentationContext = preload("res://render/crash/presentation_context.gd")
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
	flight.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	await process_frame
	_check("production session accepts the normalized lake", flight.session.set_lake_context(loaded.lake))
	var director: Variant = Director.new()
	director.name = "WaterDirectorFixtureNode"
	root.add_child(director)
	var aircraft_data: String = str(Catalog.entry(str(flight.get("aircraft_id"))).get("data", ""))
	var declined: Variant = Director.new()
	root.add_child(declined)
	var empty_context := PresentationContext.new()
	_check("director rejects an incomplete context before allocating presentation children",
		not declined.configure(empty_context, true) and declined.get_child_count() == 0 and not declined._configured)
	declined.update(0.1)
	declined.reset()
	_check("declined director stays inert without claiming the session reset signal",
		not declined.active and declined.get_child_count() == 0
			and not flight.session.resetting.is_connected(Callable(declined, "reset")))
	declined.free()
	var context := PresentationContext.new()
	var model_bindings := PresentationContext.ModelBindings.new()
	model_bindings.root = flight._airplane.root
	model_bindings.propeller = flight._airplane.get("propeller") as Node3D
	model_bindings.empty = flight._airplane.is_empty()
	context.session = flight.session
	context.model_bindings = model_bindings
	context.field = flight.field
	context.aircraft_id = str(flight.get("aircraft_id"))
	context.workshop_trial = flight.get("workshop_trial")
	context.aircraft_data_path = aircraft_data
	context.cg_model = flight._cg_model
	context.pose_provider = Callable(flight, "_current_pose")
	context.wind_provider = Callable(flight, "_render_wind")
	context.shadow = flight._shadow
	context.sun = flight.get("_sun") as DirectionalLight3D
	context.propeller_blur = flight.get_node_or_null("PropellerBlur") as Node3D
	var malformed_trial_director: Variant = Director.new()
	root.add_child(malformed_trial_director)
	var valid_trial: Dictionary = context.workshop_trial
	context.workshop_trial = {"raw_bytes": "not bytes"}
	_check("director declines malformed trial bytes before allocating presentation children",
		not malformed_trial_director.configure(context, true)
			and malformed_trial_director.get_child_count() == 0 and not malformed_trial_director._configured)
	context.workshop_trial = valid_trial
	malformed_trial_director.update(0.1)
	malformed_trial_director.reset()
	malformed_trial_director.free()
	_check("main-assembled presentation context has required providers and bindings", context.is_valid())
	_check("director accepts one explicit context before allocating its pools",
		director.configure(context, true) and director._configured)
	var configured_child_count: int = director.get_child_count()
	_check("configured director refuses replacement without duplicating reset ownership",
		not director.configure(context, true) and director.get_child_count() == configured_child_count
			and _reset_connection_count(flight.session, director) == 1)
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
	var bank_hit := _impact(flight.session, "lake_bank",
		PackedFloat64Array([110.0, 174.5, 0.2]), PackedFloat64Array([0.0, 0.0, 16.0]))
	flight.session.crash = {"impact": bank_hit, "why": "test bank contact", "ticks_left": 20}
	director.update(1.0 / 60.0)
	_check("dry bank aftermath preserves the detected excavated height",
		is_equal_approx(director._impact_point.y, -0.2) and not director._water_active)

	flight.session.reset()
	var session_ref: Node = flight.session
	var director_reset: Callable = Callable(director, "reset")
	director.free()
	_check("director free releases its session reset listener", not session_ref.resetting.is_connected(director_reset))
	flight.free()
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


func _reset_connection_count(session: Node, target: Node) -> int:
	var count := 0
	for connection: Dictionary in session.resetting.get_connections():
		if connection.get("callable") == Callable(target, "reset"):
			count += 1
	return count
