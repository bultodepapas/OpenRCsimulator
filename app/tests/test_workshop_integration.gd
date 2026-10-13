extends SceneTree
## AE-08/10: real menu route, frozen reload, scaled render/CG and transactional return.
const AppRoot := preload("res://app_root.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Driver := preload("res://tests/ui_driver.gd")
const Frames := preload("res://render/frames.gd")
const Builder := preload("res://render/airplane.gd")
const Shadow := preload("res://render/shadow.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok   ", label)

func _run() -> void:
	var host := AppRoot.new()
	host.user_args = PackedStringArray()
	host.preferences_path = "user://test_workshop_integration.cfg"
	if FileAccess.file_exists(host.preferences_path):
		DirAccess.remove_absolute(host.preferences_path)
	root.add_child(host)
	var ui := Driver.new(self)
	await ui.settle()
	host.home.workshop_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("Home keyboard opens Workshop", host.screens.is_top("workshop"))
	var editor: Node = host.screens.top()
	var source: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var payload := {base_id = Catalog.DEFAULT_ID, base_bytes = source, recipe = {scale = 2.0}}
	host._start_workshop_trial(payload)
	check("200% trial starts", host.flight != null and host.flight.startup_error.is_empty())
	if host.flight != null:
		var flight: Node = host.flight
		var session: Node = flight.session
		session.physics_enabled = false
		session.sim.process_mode = Node.PROCESS_MODE_DISABLED
		check("trial has distinct physical identity", session.aircraft.model.id != Catalog.DEFAULT_ID)
		check("catalog visual identity is retained", flight.aircraft_id == Catalog.DEFAULT_ID)
		check("trial is airborne", session.start_choice == "airborne")
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(source)
		check("trial trace records exact source", session.trace_meta().workshop.base_sha256 == hashing.finish().hex_encode())
		var mass: float = session.sim.mass
		var fingerprint: String = session.aircraft.input_identity.sha256
		check("F5 resolves frozen candidate", not session.reload().begins_with("reload failed") and session.sim.mass == mass and session.aircraft.input_identity.sha256 == fingerprint)
		flight._render_pose(flight._current_pose(), session.surfaces(), 0.3)
		check("render pose preserves 200% scale", flight._airplane.root.scale.is_equal_approx(Vector3.ONE * 2.0))
		var datum: Vector2 = Builder.datum(Catalog.DEFAULT_ID) * 2.0
		var cg: Vector3 = Frames.cg_in_model_frame(session.aircraft.model.cg_le, datum.x, datum.y)
		check("scaled CG is the simulated world position", (flight._airplane.root.global_transform * (cg / 2.0)).distance_to(flight._current_pose().pos) < 0.0001)
		var visual := Builder.build(Catalog.DEFAULT_ID)
		check("camera extent follows scaled geometry", flight._extent.is_equal_approx(Shadow.model_extent(visual.root) * 2.0))
		visual.root.free()
		host.open_pause()
		host.end_flight()
		check("return restores same editor instance", host.screens.top() == editor and host.flight == null)
		check("Home is still behind editor", host.home != null and host.home_scene.is_inside_tree())
	host.close_workshop()
	host.home.set_start_choice("airborne")
	host.start_flight()
	check("original aircraft still starts", host.flight != null and host.flight.startup_error.is_empty())
	if host.flight != null:
		var original: Node = host.flight
		original.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
		host.open_pause()
		host.open_workshop()
		var checkpoint: Dictionary = original.session.sim.checkpoint()
		var editor_from_pause: Node = host.screens.top()
		var bad := payload.duplicate(true)
		bad.recipe.scale = 0.0
		host._start_workshop_trial(bad)
		check("invalid draft retains original flight and editor", host.flight == original and host.screens.top() == editor_from_pause)
		payload.recipe.scale = 0.5
		host._start_workshop_trial(payload)
		check("50% trial from Pause starts independently", host.flight != original and not original.is_inside_tree())
		if host.flight != original:
			host.open_pause()
			host.end_flight()
			check("return restores previous flight", host.flight == original and original.is_inside_tree())
			check("original tick and state preserved", original.session.sim.tick == checkpoint.tick and original.session.sim.state == checkpoint.state)
			check("previous flight remains paused", original.session.sim.paused)
			check("Pause editor draft preserved", host.screens.top() == editor_from_pause)
	host.queue_free()
	await process_frame
	DirAccess.remove_absolute("user://test_workshop_integration.cfg")
	print("Workshop integration: %d failed" % failures)
	quit(1 if failures else 0)
