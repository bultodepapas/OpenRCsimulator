extends SceneTree

const Preview := preload("res://ui/workshop_preview.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Presentation := preload("res://workshop/presentation.gd")

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
	for slot: Dictionary in described.bindings.smoke_slots:
		profile.smoke.append({"slot": slot.id, "enabled": true, "color": "#FF3030FF",
			"amount": 0.6, "width_m": 0.15, "lifetime_s": 8.0, "shape": "ribbon", "mode": "hold",
			"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0})
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
		_check("%d FPS ends at tick 1440, pauses and retains the bounded budget" % fps,
			preview._playhead_tick == 1440 and not preview._playing and not preview.is_processing()
			and preview._rig.position.is_equal_approx(-pass_start)
			and preview._smoke.budget_info().capacity == 768 and preview._smoke.budget_info().fault.is_empty())
		preview._process(1.0)
		_check("%d FPS completion cannot advance while paused" % fps, preview._playhead_tick == 1440)
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
	for scale: float in [0.5, 1.0, 2.0]:
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
	preview.set_motion_mode("unknown")
	_check("unknown motion mode is ignored", preview._motion_mode == "stationary")
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
	preview.free()
	await process_frame
	_finish()


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


func _check(label: String, condition: bool) -> void:
	checks += 1
	if condition: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _finish() -> void:
	print("Workshop smoke preview: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
