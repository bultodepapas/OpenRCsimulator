extends SceneTree

const GroundAudio := preload("res://audio/ground_audio.gd")
const GroundModel := preload("res://audio/ground_audio_model.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_surface_selection()
	_test_real_session_snapshot()
	_test_contact_audio_state_machine()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_surface_selection() -> void:
	var field := {surfaces = [
		{type = "rough", center_north = 0.0, center_east = 0.0, width_north_south = 100.0, length_east_west = 100.0},
		{type = "mown", center_north = 0.0, center_east = 0.0, width_north_south = 30.0, length_east_west = 30.0},
		{type = "runway", center_north = 0.0, center_east = 0.0, width_north_south = 8.0, length_east_west = 20.0},
	]}
	_check("surface classifier keeps runway precedence inside mown grass", GroundModel.surface_name(field, 0.0, 0.0) == "hard")
	_check("surface classifier maps mown areas to grass", GroundModel.surface_name(field, 0.0, 11.0) == "grass")
	_check("surface classifier maps rough/outside ground to gravel", GroundModel.surface_name(field, 0.0, 30.0) == "gravel")


func _test_real_session_snapshot() -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	var before_state: PackedFloat64Array = session.sim.state.duplicate()
	var before_aux: PackedFloat64Array = session.sim.aux.duplicate()
	var before_continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	var contacts: Array[Dictionary] = GroundModel.snapshot_contacts(session, {surfaces = []})
	var gear: Dictionary = session.current_landing_gear()
	_check("real FlightSession snapshot returns one row per installed contact", contacts.size() == gear.get("contacts", []).size(),
		"rows=%d contacts=%d" % [contacts.size(), gear.get("contacts", []).size()])
	var row_shape_ok: bool = true
	for contact: Dictionary in contacts:
		row_shape_ok = row_shape_ok and contact.get("position") is Vector3 \
			and contact.get("velocity_mps") is Vector3 and contact.get("force_n") is Vector3 \
			and contact.has_all(["normal_force_n", "compression_m", "approach_speed_mps", "rolling_speed_mps", "surface"])
	_check("contact rows expose world-space point forces and velocities", row_shape_ok)
	_check("snapshot leaves accepted state, aux and continuous arrays unchanged",
		before_state == session.sim.state and before_aux == session.sim.aux and before_continuous == session.sim.continuous)
	_check("spawn snapshot does not invent wheel loading in the airborne start",
		contacts.is_empty() or contacts.all(func(c: Dictionary) -> bool: return float(c.normal_force_n) == 0.0),
		"normal forces=%s" % str(contacts.map(func(c: Dictionary) -> float: return float(c.normal_force_n))))
	root.remove_child(session)
	session.free()


func _test_contact_audio_state_machine() -> void:
	var audio := GroundAudio.new()
	audio.configure(root, &"Master")
	var parked := _contact("main", 1400.0, 1000.0, 0.0, 0.0, true, "hard")
	audio.update_contacts(0, false, [parked], 0.0, 1.0 / 60.0, Vector3.ZERO)
	_check("spawn on loaded gear seeds the contact without a phantom touchdown", audio.touchdown_events == 0)
	_check("parked gear is silent at zero wheel speed", not audio.get_node("Roll_0_0").playing)
	var taxi := _contact("main", 1400.0, 1000.0, 0.0, 8.0, true, "hard")
	taxi.position = Vector3(12.0, 0.2, -5.0)
	audio.update_contacts(1, false, [taxi], 0.0, 1.0 / 60.0, Vector3.ZERO)
	var hard_player: AudioStreamPlayer3D = audio.get_node("Roll_0_0") as AudioStreamPlayer3D
	_check("loaded taxi speed starts a spatial hard-surface roll layer", hard_player.playing)
	_check("roll source is positioned at its gear point before playback", hard_player.global_position == taxi.position)
	_check("ground audio uses the common manual path law without Godot double attenuation",
		hard_player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED)
	var grass := _contact("main", 1400.0, 1000.0, 0.0, 8.0, true, "grass")
	audio.update_contacts(2, false, [grass], 1.0, 1.0 / 60.0, Vector3.ZERO)
	_check("mown terrain crossfades to the grass recording", (audio.get_node("Roll_0_1") as AudioStreamPlayer3D).playing)
	var landing := _contact("nose", 0.0, 1000.0, 0.0, 0.0, false, "hard")
	for tick: int in range(3, 50):
		landing.approach_speed_mps = 2.4 if tick == 49 else 0.0
		audio.update_contacts(tick, false, [grass, landing], 0.2, 0.02, Vector3.ZERO)
	landing.normal_force_n = 1500.0
	landing.grounded = true
	landing.approach_speed_mps = 0.0 # The accepted state can already be rebounding at first contact sample.
	audio.update_contacts(50, false, [grass, landing], 0.2, 0.02, Vector3.ZERO)
	_check("airborne-to-loaded contact creates one touchdown impact", audio.touchdown_events == 1)
	_check("touchdown is emitted at the individual nose gear point", (audio.get_node("Touchdown_1") as AudioStreamPlayer3D).global_position == landing.position)
	(audio.get_node("Touchdown_1") as AudioStreamPlayer3D).stop()
	for tick: int in range(51, 55):
		landing.normal_force_n = 0.0 if tick < 54 else 1500.0
		landing.grounded = tick >= 54
		landing.approach_speed_mps = 2.0 if tick >= 54 else 0.0
		audio.update_contacts(tick, false, [grass, landing], 0.2, 0.02, Vector3.ZERO)
	_check("brief taxi chatter cannot retrigger the touchdown one-shot", audio.touchdown_events == 1)
	audio.reset()
	var stale_descent := _contact("nose", 0.0, 1000.0, 3.0, 0.0, false, "hard")
	for tick: int in range(51):
		stale_descent.approach_speed_mps = 3.0 if tick < 10 else 0.0
		audio.update_contacts(tick, false, [stale_descent], 0.0, 1.0 / 60.0)
	stale_descent.normal_force_n = 1200.0
	audio.update_contacts(51, false, [stale_descent], 0.0, 1.0 / 60.0)
	_check("an earlier dive cannot turn a later settled contact into a hard touchdown", audio.touchdown_events == 0)
	audio.reset()
	var gentle := _contact("nose", 0.0, 1000.0, 0.3, 0.0, false, "hard")
	gentle.roll_enabled = false
	for tick: int in range(51):
		audio.update_contacts(tick, false, [gentle], 0.0, 1.0 / 60.0)
	gentle.normal_force_n = 1200.0
	gentle.rolling_speed_mps = 8.0
	audio.update_contacts(51, false, [gentle], 0.0, 1.0 / 60.0)
	_check("a gentle skid touchdown emits an impact", audio.touchdown_events == 1)
	_check("skids never emit wheel rolling even with lateral speed",
		not (audio.get_node("Roll_1_0") as AudioStreamPlayer3D).playing)
	audio.reset()
	var reset_ground := _contact("main", 1200.0, 1000.0, 0.0, 0.0, true, "hard")
	audio.update_contacts(0, false, [reset_ground], 0.0, 1.0 / 60.0, Vector3.ZERO)
	_check("reset re-seeds loaded contacts without replaying their spawn impact", audio.touchdown_events == 0)
	audio.reset()
	var repeat_air := _contact("repeat", 0.0, 1000.0, 0.0, 0.0, false, "hard")
	audio.update_contacts(0, false, [repeat_air], 0.0, 1.0 / 60.0, Vector3.ZERO)
	for _i: int in range(100):
		audio.update_contacts(0, false, [repeat_air], 0.0, 0.1, Vector3.ZERO)
	repeat_air.normal_force_n = 1200.0
	repeat_air.grounded = true
	repeat_air.approach_speed_mps = 3.0
	audio.update_contacts(1, false, [repeat_air], 0.0, 1.0 / 60.0, Vector3.ZERO)
	_check("repeated render snapshots do not age airborne time into a touchdown", audio.touchdown_events == 0)
	audio.reset()
	var paused_air := _contact("paused", 0.0, 1000.0, 0.0, 0.0, false, "hard")
	audio.update_contacts(0, false, [paused_air], 0.0, 1.0 / 60.0, Vector3.ZERO)
	for tick: int in range(1, 41):
		paused_air.approach_speed_mps = 3.0 if tick == 40 else 0.0
		audio.update_contacts(tick, false, [paused_air], 0.0, 1.0 / 60.0, Vector3.ZERO)
	audio.update_contacts(40, true, [paused_air], 0.0, 1.0 / 60.0, Vector3.ZERO)
	paused_air.normal_force_n = 1200.0
	paused_air.grounded = true
	paused_air.approach_speed_mps = 0.0
	audio.update_contacts(41, false, [paused_air], 0.0, 1.0 / 60.0, Vector3.ZERO)
	_check("resuming into contact re-seeds without a paused-frame touchdown", audio.touchdown_events == 0)
	var crowded: Array = []
	for i: int in range(GroundAudio.MAX_CONTACTS + 4):
		crowded.append(_contact("wheel_%d" % i, 500.0, 500.0, 0.0, 0.0, true, "hard"))
	audio.update_contacts(1, false, crowded, 0.0, 1.0 / 60.0, Vector3.ZERO)
	_check("per-contact voice pool remains bounded", audio.contact_slot_count == GroundAudio.MAX_CONTACTS
		and audio.get_child_count() <= GroundAudio.MAX_CONTACTS * 4)
	audio.stop()
	root.remove_child(audio)
	audio.free()


func _contact(identity: String, normal_force: float, reference: float, approach: float,
		rolling_speed: float, grounded: bool, surface: String) -> Dictionary:
	return {id = identity, position = Vector3(1.0, 0.0, -1.0), velocity_mps = Vector3.ZERO,
		force_n = Vector3.ZERO, surface_normal = Vector3.UP, normal_force_n = normal_force,
		reference_load_n = reference, compression_m = 0.0, approach_speed_mps = approach,
		rolling_speed_mps = rolling_speed, rim_speed_mps = rolling_speed, surface = surface,
		grounded = grounded, roll_enabled = true}
