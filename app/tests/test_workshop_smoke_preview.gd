extends SceneTree

const Preview := preload("res://ui/workshop_preview.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Presentation := preload("res://workshop/presentation.gd")
const LightProfiles := preload("res://render/lighting/lighting_profile.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var preview := Preview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(preview)
	await process_frame
	preview.set_aircraft("jensen-das-ugly-stik-60")
	var described := Customization.describe("jensen-das-ugly-stik-60")
	_check("verified bindings available", described.get("ok", false))
	if not described.get("ok", false):
		preview.free()
		_finish()
		return
	var profile := Presentation.defaults(described.bindings)
	profile.smoke = []
	var selected_slots: Array[Dictionary] = []
	var selected_show_count := 0
	var selected_source := false
	for slot: Dictionary in described.bindings.smoke_slots:
		if slot.kind == "show" and selected_show_count < 3:
			selected_slots.append(slot)
			selected_show_count += 1
		elif slot.kind == "source" and not selected_source:
			selected_slots.append(slot)
			selected_source = true
	_check("fixture selects no more than three show outlets and one source outlet",
		selected_show_count == 3 and selected_source and selected_slots.size() == 4)
	if selected_slots.size() != 4:
		preview.free()
		_finish()
		return
	for slot: Dictionary in selected_slots:
		var entry: Dictionary = Presentation.smoke_v2_defaults()
		entry.merge({"slot": slot.id, "enabled": true, "color": "#FF3030FF",
			"amount": 0.6, "width_m": 0.15, "lifetime_s": 8.0, "shape": "ribbon", "mode": "hold",
			"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0}, true)
		profile.smoke.append(entry)
	preview.set_presentation(profile)
	await process_frame
	_check("preview accepted the registered four-emitter profile", is_instance_valid(preview._smoke))
	if not is_instance_valid(preview._smoke):
		var probe: Node = load("res://render/smoke/profile_smoke.gd").new()
		probe.configure(profile, described.bindings)
		printerr(probe.budget_info())
		probe.free()
		preview.free()
		_finish()
		return
	_check("all four authored show/source emitters share 768 particles", preview._smoke.budget_info().capacity == 768
		and preview._smoke.budget_info().show_emitters == 3 and preview._smoke.budget_info().source_emitters == 1)
	var rate_feedback := preview.find_child("SmokeResolvedRates", true, false) as Label
	var initial_budget: Dictionary = preview._smoke.budget_info()
	_check("preview reports resolved per-emitter puffs/s and budget limiting",
		is_instance_valid(rate_feedback) and rate_feedback.visible and rate_feedback.text.contains("puffs/s")
		and rate_feedback.text.contains("budget limited") == bool(initial_budget.get("saturated", false)))
	for frame in 4:
		await process_frame
	_check("smoke rate feedback keeps readable width without consuming the aircraft image",
		rate_feedback.size.x >= 200.0 and rate_feedback.size.y < 120.0
		and preview._viewport_container.size.y >= 320.0)
	print("smoke_feedback_rect %s image_height=%.1f" % [rate_feedback.size, preview._viewport_container.size.y])
	await _check_edit_refresh(preview, profile)
	var original_model: Transform3D = preview._airplane_root.transform
	var original_slots := Customization.smoke_transforms(preview._airplane)
	_check("stationary and idle by default", preview._rig.position == Vector3.ZERO and not preview.is_processing())
	preview.set_motion_mode("pass")
	_check("pass choice clears clock and selects a readable side view", preview._playhead_tick == 0
		and not preview._playing and preview.get_view_state().standard_view == "side")
	var pass_start: Vector3 = preview._rig.position
	_check("pass moves only the parent pose and resolves each authored mount once", _mounts_shifted(preview, original_slots, pass_start)
		and preview._airplane_root.transform == original_model)
	var reference_slots := {}
	for fps: int in [30, 60, 144]:
		preview.reset_playback()
		preview.toggle_playback()
		preview.set_process(false)
		for frame in 6 * fps:
			preview._process(1.0 / fps)
			if frame + 1 == 3 * fps:
				_check("%d FPS reaches exact midpoint tick and pose" % fps,
					preview._playhead_tick == 720 and preview._rig.position.is_zero_approx())
				var slots := Customization.smoke_transforms(preview._airplane)
				if reference_slots.is_empty(): reference_slots = slots
				_check("%d FPS preserves the same midpoint mounts" % fps, slots == reference_slots)
			await process_frame
		_check("%d FPS reaches the six-second pass endpoint and stops emission" % fps,
			preview._playhead_tick == 1440 and preview._playing
			and preview._emission_stopped and preview._smoke.get("_stopped")
			and preview._rig.position.is_equal_approx(-pass_start)
			and preview._smoke.budget_info().capacity == 768 and preview._smoke.budget_info().fault.is_empty())
		var tail_steps := 0
		while preview._playing and tail_steps < 100:
			preview._process(0.1)
			tail_steps += 1
		var tail_history: Array = preview._smoke.get("_history")
		var history_window_ok := tail_history.is_empty() or \
			float(preview._playhead_tick - int(tail_history.front().tick)) / 240.0 <= 8.5
		_check("%d FPS ages eight-second residuals through the plume tail" % fps,
			not preview._playing and not preview.is_processing()
			and preview._playhead_tick >= preview._emission_stop_tick + 8 * 240
			and preview._playhead_tick >= preview.call("_pass_tail_end_tick")
			and preview._smoke.get("_stopped") and preview._smoke.get("_last_tick") == preview._playhead_tick
			and history_window_ok
			and preview._smoke.budget_info().fault.is_empty())
		preview._process(1.0)
		_check("%d FPS completion cannot advance while paused" % fps,
			preview._playhead_tick >= 1440 + 8 * 240)
	preview.toggle_playback()
	preview.set_process(false)
	_check("Play after completion explicitly starts a fresh pass", preview._playing and preview._playhead_tick == 0
		and preview._rig.position == pass_start and preview._smoke.get("_history").is_empty())
	preview._process(0.1)
	await process_frame
	preview.toggle_playback()
	var paused_tick: int = preview._playhead_tick
	var paused_pose: Transform3D = preview._rig.transform
	preview._process(0.1)
	_check("pause freezes clock and model", preview._playhead_tick == paused_tick and preview._rig.transform == paused_pose)
	preview.toggle_playback()
	preview.set_process(false)
	preview._process(NAN)
	preview._process(-1.0)
	_check("invalid deltas cannot poison the playhead", preview._playhead_tick == paused_tick)
	preview._process(5.0)
	await process_frame
	_check("long draw interval is bounded without catch-up", preview._playhead_tick == paused_tick + 24
		and preview._smoke.budget_info().fault.is_empty())
	preview.hide()
	_check("hidden preview pauses rendering and playhead", not preview._playing and not preview.is_processing()
		and preview._viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS)
	preview.show()
	preview.toggle_playback()
	preview.set_process(false)
	preview.set_view_mode("compare")
	preview.set_comparison_original(true)
	_check("Original comparison is stationary and pauses the draft", not preview._playing
		and preview._rig.position == Vector3.ZERO and not preview._smoke.visible and preview._play_button.disabled)
	preview.toggle_playback()
	_check("Original cannot accidentally start smoke", not preview._playing)
	preview.set_comparison_original(false)
	_check("Draft restores the paused pass pose", not preview._playing and preview._rig.position != Vector3.ZERO
		and preview._smoke.visible and not preview._play_button.disabled)
	preview.set_view_mode("inspect")
	for scale: float in [0.1, 0.35, 0.5, 1.0, 2.0, 2.25, 5.0]:
		preview.set_aircraft("jensen-das-ugly-stik-60", scale)
		_check("scale change resets pose and residual history %.1f" % scale,
			preview._playhead_tick == 0 and preview._smoke.get("_history").is_empty())
		for view: String in ["front", "side", "top"]:
			preview.set_standard_view(view)
			for tick: int in [0, 720, 1440]:
				preview._playhead_tick = tick
				preview._apply_preview_pose()
				_check("pass bounds fit scale %.1f / %s / tick %d" % [scale, view, tick], _model_fits(preview))
	preview.set_motion_mode("stationary")
	_check("stationary selection clears history and recenters model", preview._playhead_tick == 0
		and preview._rig.position == Vector3.ZERO and preview._smoke.get("_history").is_empty())
	preview.toggle_playback()
	preview.set_process(false)
	preview._process(1.0 / 30.0)
	await process_frame
	var smoke: Node = preview._smoke
	var before_stop_tick: int = preview._playhead_tick
	preview.stop_emission()
	_check("Stop emission leaves the preview running and tells the renderer to cancel new births",
		preview._playing and preview._emission_stopped and smoke.get("_stopped") and not smoke.get("_paused"))
	preview._process(1.0 / 30.0)
	await process_frame
	_check("stopped residuals keep aging on the isolated preview clock",
		preview._playhead_tick > before_stop_tick and smoke.get("_stopped") and smoke.get("_last_tick") == preview._playhead_tick)
	preview.toggle_playback()
	var stopped_pause_tick: int = preview._playhead_tick
	preview._process(1.0 / 30.0)
	_check("pause freezes stopped residuals without resuming emission", preview._playhead_tick == stopped_pause_tick and smoke.get("_stopped"))
	preview.toggle_playback()
	preview.set_process(false)
	preview._process(1.0 / 30.0)
	_check("resume keeps Stop emission active", preview._playhead_tick > stopped_pause_tick and smoke.get("_stopped"))
	preview.reset_playback()
	_check("Restart clears stopped state, playhead and residual history",
		not preview._emission_stopped and preview._playhead_tick == 0 and smoke.get("_history").is_empty())
	preview._zoom = 2.0
	preview.set_fit_plume(true)
	preview._refresh_camera()
	_check("explicit plume fit includes the complete bounded stationary envelope",
		preview._fit_plume and is_equal_approx(preview._zoom, 1.0) and _model_fits(preview) and _plume_fits(preview))
	preview.set_motion_mode("pass")
	preview.toggle_playback()
	preview.set_process(false)
	preview._process(1.0 / 30.0)
	await process_frame
	preview._refresh_camera()
	_check("plume fit keeps the bounded illustrative-pass envelope visible",
		preview._fit_plume and _model_fits(preview) and _plume_fits(preview))
	preview.reset_playback()
	preview.set_fit_plume(false)
	preview.set_motion_mode("unknown")
	_check("unknown motion mode is ignored", preview._motion_mode == "pass")
	_check("preview motion never changes the profile or creates flight state", profile == preview._profile
		and preview.find_child("Simulation", true, false) == null)
	var lifecycle_ok := true
	for cycle in 20:
		preview.set_motion_mode("pass")
		preview.toggle_playback()
		preview.set_process(false)
		preview._process(0.1)
		await process_frame
		preview.reset_playback()
		preview.set_motion_mode("stationary")
		await process_frame
		lifecycle_ok = lifecycle_ok and preview._smoke.budget_info().capacity == 768 \
			and preview._smoke.get_child_count() == 4 and preview._smoke.get("_history").is_empty() \
			and preview._rig.position == Vector3.ZERO and not preview._playing
	_check("twenty mode/play/reset cycles keep four pools, fixed budget and empty history", lifecycle_ok)
	preview.set_motion_mode("pass")
	preview.set_presentation(Presentation.defaults(described.bindings))
	_check("removing smoke restores normal centered inspection", preview._smoke == null
		and preview._rig.position == Vector3.ZERO and not preview._motion_selector.visible)
	await _check_aircraft_lifecycle(preview, profile)
	preview.free()
	await process_frame
	_finish()


func _check_edit_refresh(preview: Control, original: Dictionary) -> void:
	var candidate := original.duplicate(true)
	candidate.lighting = LightProfiles.preset("neon_rgb")
	preview.set_presentation(candidate)
	await process_frame
	var allocations := [0]
	var count_pool := func(node: Node) -> void:
		if node is GPUParticles3D:
			allocations[0] += 1
	node_added.connect(count_pool)
	for change: String in ["audio", "smoke", "lighting", "seed"]:
		preview.toggle_playback()
		preview.set_process(false)
		preview._process(0.1)
		preview.stop_emission()
		var smoke_id_before_edit: int = preview._smoke.get_instance_id()
		var vfx_id_before_edit: int = preview._lighting_rig.get("_vfx").get_instance_id()
		allocations[0] = 0
		match change:
			"audio": candidate.mechanical_audio.servo_type = "high_torque"
			"smoke": candidate.smoke[0].density = 0.8
			"lighting": candidate.lighting.brightness = 0.8
			"seed": candidate.visual_seed += 1
		preview.set_presentation(candidate)
		_check("%s edit creates only one replacement pool per emitter (created=%d expected=4)" % [change, allocations[0]], allocations[0] == 4)
		print("edit_pool_allocations %s=%d" % [change, allocations[0]])
		_check("%s edit retains explicit playback reset and bounded smoke" % change,
			not preview._playing and not preview.is_processing() and preview._playhead_tick == 0
			and not preview._emission_stopped and preview._smoke.get("_history").is_empty()
			and preview._smoke.budget_info().capacity == 768 and preview._profile == candidate)
		if change in ["audio", "lighting"]:
			_check("%s edit reuses the unchanged smoke configuration" % change,
				preview._smoke.get_instance_id() == smoke_id_before_edit)
		else:
			_check("%s edit refreshes its smoke settings" % change,
				preview._smoke.get("_profile").smoke[0].density == candidate.smoke[0].density
				and preview._smoke.get("_profile").visual_seed == candidate.visual_seed)
		_check("%s edit refreshes lighting resources only for a lighting change" % change,
			(preview._lighting_rig.get("_vfx").get_instance_id() != vfx_id_before_edit) == (change == "lighting"))
		await process_frame
	node_added.disconnect(count_pool)
	var bindings: Dictionary = preview._airplane.customization_bindings
	var paint_slot: String = bindings.lighting_layout.skins[0].paint_slot_id
	var paint_color := Color("#123456FF")
	candidate.paint = [{"slot": paint_slot, "color": "#123456FF", "pattern": "solid", "accent": "none"}]
	candidate.markings = [{"slot": bindings.marking_slots[0].id, "text": "RC42", "color": "#FFFFFFFF"}]
	var previous_smoke_id: int = preview._smoke.get_instance_id()
	var previous_vfx_id: int = preview._lighting_rig.get("_vfx").get_instance_id()
	preview.set_presentation(candidate)
	_check("paint edits refresh tinted lighting skins while retaining smoke configuration",
		preview._lighting_rig.get("_vfx").get_instance_id() != previous_vfx_id
		and preview._smoke.get_instance_id() == previous_smoke_id
		and _skin_has_color(preview, paint_color))
	preview.set_view_mode("compare")
	preview.set_comparison_original(true)
	_check("Original removes draft markings with the authored finish", preview._airplane.get("_customization_marking_nodes").is_empty())
	preview.set_comparison_original(false)
	_check("Draft restores painted skins and registration", _skin_has_color(preview, paint_color)
		and not preview._airplane.get("_customization_marking_nodes").is_empty())
	preview.set_view_mode("inspect")
	previous_vfx_id = preview._lighting_rig.get("_vfx").get_instance_id()
	var marking_id: int = preview._airplane.get("_customization_marking_nodes")[0].get_instance_id()
	preview.toggle_playback()
	preview.set_process(false)
	preview._process(0.1)
	preview.set_aircraft("jensen-das-ugly-stik-60", 1.25)
	_check("scale resets playback while retaining painted skins, registration and lighting resources",
		not preview._playing and preview._playhead_tick == 0 and _skin_has_color(preview, paint_color)
		and preview._airplane_root.scale.is_equal_approx(Vector3.ONE * 1.25)
		and preview._lighting_rig.get("_vfx").get_instance_id() == previous_vfx_id
		and preview._airplane.get("_customization_marking_nodes")[0].get_instance_id() == marking_id)
	candidate.paint = []
	candidate.markings = []
	preview.set_presentation(candidate)
	_check("removing paint restores the authored skin color and clears registration",
		not _skin_has_color(preview, paint_color) and preview._airplane.get("_customization_marking_nodes").is_empty())
	preview.set_aircraft("jensen-das-ugly-stik-60", 1.0)
	preview.set_presentation(original)
	await process_frame


func _skin_has_color(preview: Control, expected: Color) -> bool:
	var skins: RefCounted = preview._lighting_rig.get("_skins")
	if skins == null:
		return false
	for binding: Dictionary in skins.get("_bindings"):
		var material: StandardMaterial3D = binding.material
		if material.albedo_color.is_equal_approx(expected) \
			and binding.mesh.get_active_material(binding.surface) == material:
			return true
	return false


func _check_aircraft_lifecycle(preview: Control, profile: Dictionary) -> void:
	preview.set_presentation(profile)
	preview.toggle_playback()
	preview.set_process(false)
	preview._process(0.1)
	var old_smoke: Node = preview._smoke
	var discarded_allocations := [0]
	var count_discarded := func(node: Node) -> void:
		if node is GPUParticles3D and node.get_parent() == old_smoke:
			discarded_allocations[0] += 1
	node_added.connect(count_discarded)
	preview.set_aircraft("stik-glow-61fx-2t")
	node_added.disconnect(count_discarded)
	_check("aircraft replacement does not recreate the discarded smoke pools", discarded_allocations[0] == 0)
	print("discarded_swap_pools=%d" % discarded_allocations[0])
	_check("aircraft replacement installs independent smoke and pauses playback",
		preview._smoke != old_smoke and not preview._playing and not preview.is_processing()
		and preview._playhead_tick == 0 and preview._smoke.budget_info().capacity == 768)
	await process_frame
	_check("discarded aircraft smoke is released after the swap", not is_instance_valid(old_smoke))
	# Only this intentional unknown-ID rejection suppresses the builder's push_error.
	var print_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	preview.set_aircraft("workshop-test-missing-aircraft")
	Engine.print_error_messages = print_errors
	await process_frame
	_check("failed build clears old model and smoke state", preview._airplane.is_empty()
		and preview._airplane_root == null and preview._smoke == null)
	_check("failed build removes stale playback controls and capability claims",
		not preview._play_button.visible and preview._play_button.disabled
		and not preview._motion_selector.visible and not preview._rate_feedback.visible
		and not preview._badge_panel.visible
		and preview.get_lighting_capability_report().state == "unavailable")
	preview.toggle_playback()
	preview.set_process(false)
	_check("failed model cannot restart the previous aircraft's smoke", not preview._playing)
	preview.set_aircraft("jensen-das-ugly-stik-60")
	_check("valid retry rebuilds smoke controls from the retained presentation",
		is_instance_valid(preview._airplane_root) and is_instance_valid(preview._smoke)
		and preview._badge_panel.visible
		and preview._play_button.visible and not preview._play_button.disabled
		and preview._profile == profile and preview._smoke.budget_info().capacity == 768)
	preview.toggle_playback()
	preview.set_process(false)
	_check("fixture closes a running preview", preview._playing)


func _mounts_shifted(preview: Control, original: Dictionary, shift: Vector3) -> bool:
	var current := Customization.smoke_transforms(preview._airplane)
	if current.size() != original.size(): return false
	for key: String in original:
		if not current[key].origin.is_equal_approx(original[key].origin + shift): return false
		if not current[key].basis.is_equal_approx(original[key].basis): return false
	return true


func _model_fits(preview: Control) -> bool:
	var camera: Camera3D = preview._camera
	var canvas: Vector2 = camera.get_viewport().get_visible_rect().size
	for index in 8:
		var point: Vector3 = preview._airplane_root.global_transform * preview._model_bounds.get_endpoint(index)
		if camera.is_position_behind(point): return false
		var pixel := camera.unproject_position(point)
		if not Rect2(canvas * 0.02, canvas * 0.96).has_point(pixel): return false
	return true


func _plume_fits(preview: Control) -> bool:
	var camera: Camera3D = preview._camera
	var canvas: Vector2 = camera.get_viewport().get_visible_rect().size
	var plume: AABB = preview.call("_plume_bounds")
	for index in 8:
		var point := plume.position + Vector3(
			plume.size.x if (index & 1) != 0 else 0.0,
			plume.size.y if (index & 2) != 0 else 0.0,
			plume.size.z if (index & 4) != 0 else 0.0
		)
		if camera.is_position_behind(point): return false
		if not Rect2(canvas * 0.01, canvas * 0.98).has_point(camera.unproject_position(point)): return false
	return true


func _check(label: String, condition: bool) -> void:
	checks += 1
	if condition: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _finish() -> void:
	print("Workshop smoke preview: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
