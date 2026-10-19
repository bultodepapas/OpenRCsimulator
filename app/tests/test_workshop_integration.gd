extends SceneTree
## AE-08/10: real menu route, frozen reload, scaled render/CG and transactional return.
const AppRoot := preload("res://app_root.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Driver := preload("res://tests/ui_driver.gd")
const Frames := preload("res://render/frames.gd")
const Builder := preload("res://render/airplane.gd")
const Shadow := preload("res://render/shadow.gd")
const Wreck := preload("res://render/crash/wreck.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Exposure := preload("res://render/world/exposure.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, condition: bool, detail := "") -> void:
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)
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
	editor.set_recipe({scale = 0.5})
	editor.set_recipe({scale = 2.0, tank_capacity_multiplier = 1.25})
	var editor_history_size: int = editor.get("_undo_history").size()
	var source: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var payload := {base_id = Catalog.DEFAULT_ID, base_bytes = source,
		recipe = {scale = 2.0, tank_capacity_multiplier = 1.25}}
	editor.call("_set_page", "compare")
	var preview: Control = editor.get("_preview")
	preview.call("set_standard_view", "side")
	preview.call("zoom_by", 1.2)
	var preview_state: Dictionary = preview.call("get_view_state")
	var trial_button := editor.find_child("TestFly", true, false) as Button
	trial_button.grab_focus()
	await ui.tap(KEY_ENTER)
	check("200% trial starts", host.flight != null and host.flight.startup_error.is_empty())
	if host.flight != null:
		var flight: Node = host.flight
		var session: Node = flight.session
		session.physics_enabled = false
		session.sim.process_mode = Node.PROCESS_MODE_DISABLED
		check("trial has distinct physical identity", session.aircraft.model.id != Catalog.DEFAULT_ID)
		check("catalog visual identity is retained", flight.aircraft_id == Catalog.DEFAULT_ID)
		check("trial is airborne", session.start_choice == "airborne")
		var base_raw: Dictionary = JSON.parse_string(source.get_string_from_utf8())
		var base_capacity_m3: float = float(base_raw.fuel_system.tanks[0].capacity.value) * 0.001
		var trial_tank: Dictionary = session.aircraft.model.fuel_system.tanks[0]
		var fuel_sample: Dictionary = session.mass_properties()
		check("trial session applies tank-size ratio and reports accepted total mass",
			is_equal_approx(trial_tank.capacity_m3, base_capacity_m3 * 8.0 * 1.25)
			and fuel_sample.get("ok", false) and not fuel_sample.get("finite_fuel", false)
			and fuel_sample.get("stores", []).is_empty()
			and is_equal_approx(float(fuel_sample.mass_kg), session.sim.mass)
			and is_equal_approx(float(fuel_sample.mass_kg), float(session.aircraft.model.mass_kg)),
			str({tank = trial_tank, fuel_sample = fuel_sample, start_fill = session.fuel_start_fill}))
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
		_check_wreck_scale(flight._airplane.root, Catalog.DEFAULT_ID, 2.0)
		host.open_pause()
		host.restart_flight()
		check("trial restart keeps frozen identity and experimental mass", session.sim.tick == 0
			and session.sim.mass == mass and session.aircraft.input_identity.sha256 == fingerprint
			and host.flight == flight)
		host.open_pause()
		host.end_flight()
		await ui.settle()
		check("return restores same editor instance", host.screens.top() == editor and host.flight == null)
		check("trial return preserves draft and edit history", editor.get_recipe().scale == 2.0
			and editor.get_recipe().tank_capacity_multiplier == 1.25
			and editor.get("_undo_history").size() == editor_history_size)
		check("trial return restores page, camera and focused action",
			editor.get("_active_page") == "compare" and preview.call("get_view_state") == preview_state
			and root.gui_get_focus_owner() == trial_button and not editor.get("_trial_pending"))
		check("Home is still behind editor", host.home != null and host.home_scene.is_inside_tree())
	for scale_value: float in [0.5, 2.0]:
		editor.set_aircraft("gp-extra-300s-60", true)
		editor.set_recipe({scale = scale_value})
		var scale_control := editor.find_child("Scale", true, false) as OptionButton
		var trial_control := editor.find_child("TestFly", true, false) as Button
		var scale_reason := editor.find_child("ScaleSupport", true, false) as Label
		check("Extra %.0f%% is blocked while finite-glow transforms remain fixed" % (scale_value * 100.0),
			scale_control != null and scale_control.disabled
			and trial_control != null and trial_control.disabled
			and scale_reason != null and scale_reason.text.contains("finite-glow installation data must remain fixed")
			and host.flight == null)
	host.close_workshop()
	host.home.set_start_choice("airborne")
	host.start_flight()
	check("original aircraft still starts", host.flight != null and host.flight.startup_error.is_empty())
	if host.flight != null:
		var original: Node = host.flight
		original.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
		host.open_pause()
		check("paused original accepts an independent sky", original.apply_sky_config(SkyConfig.for_preset("broken")).ok)
		original._env.tonemap_exposure = 2.7
		Exposure.set_value(2.7)
		host.open_workshop()
		await ui.settle()
		var checkpoint: Dictionary = original.session.sim.checkpoint()
		var editor_from_pause: Node = host.screens.top()
		var bad := payload.duplicate(true)
		bad.recipe.scale = 0.0
		host._start_workshop_trial(bad)
		check("invalid draft retains original flight and editor", host.flight == original and host.screens.top() == editor_from_pause)
		var valid_field_path: String = host.field_path
		var retained_exposure: float = original._env.tonemap_exposure
		host.field_path = "user://workshop_missing_field_fixture.json"
		host._start_workshop_trial(payload)
		host.field_path = valid_field_path
		check("failed candidate startup preserves old flight and camera", host.flight == original and original.is_inside_tree() and root.get_camera_3d() == original._camera)
		check("failed candidate startup preserves old recorder", original.recorder != null and original.session.sim.tick == checkpoint.tick)
		check("failed candidate startup preserves adapted exposure", is_equal_approx(original._env.tonemap_exposure, retained_exposure) and is_equal_approx(Exposure.last, retained_exposure))
		payload.recipe.scale = 0.5
		host._start_workshop_trial(payload)
		check("50% trial from Pause starts independently", host.flight != original and not original.is_inside_tree())
		if host.flight != original:
			host.open_pause()
			check("trial can choose its own sky", host.flight.apply_sky_config(SkyConfig.for_preset("clear")).ok)
			host.end_flight()
			check("trial return preserves adapted exposure", is_equal_approx(original._env.tonemap_exposure, retained_exposure) and is_equal_approx(Exposure.last, retained_exposure))
			await ui.settle()
			check("return restores previous flight", host.flight == original and original.is_inside_tree())
			check("original tick and state preserved", original.session.sim.tick == checkpoint.tick and original.session.sim.state == checkpoint.state)
			check("previous flight remains paused", original.session.sim.paused)
			check("return restores original sky presentation", original.sky_config.preset == "broken" and Atmosphere.appearance_config().preset == "broken")
			check("Pause editor draft preserved", host.screens.top() == editor_from_pause)
	await ui.close_app(host)
	DirAccess.remove_absolute("user://test_workshop_integration.cfg")
	print("Workshop integration: %d failed" % failures)
	quit(1 if failures else 0)


func _check_wreck_scale(airplane: Node3D, visual_id: String, scale_value: float) -> void:
	# Preserve the same propeller phase and surface deflections in the reference.
	var original := airplane.duplicate(0) as Node3D
	original.scale = Vector3.ONE
	root.add_child(original)
	var baseline := Wreck.new()
	var scaled := Wreck.new()
	root.add_child(baseline)
	root.add_child(scaled)
	var prepared := baseline.prepare(original) and scaled.prepare(airplane)
	check("wreck geometry follows %s at %.0f%%" % [visual_id, scale_value * 100.0], prepared
		and scaled._whole_bounds.size.is_equal_approx(baseline._whole_bounds.size * scale_value))
	check("wreck rigid bodies keep unit scale", scaled._bodies.all(func(body: RigidBody3D) -> bool:
		return body.scale.is_equal_approx(Vector3.ONE)))
	scaled.free()
	baseline.free()
	original.free()
