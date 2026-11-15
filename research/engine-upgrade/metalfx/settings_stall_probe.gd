## Research-only Settings trial witness. Install from the debug bridge after
## opening Settings; this never changes the draft, deadline, or preferences.
extends RefCounted

const META := &"openrc_settings_stall_probe"
const TRIAL_KEYS: Array[String] = ["window_mode", "window_resolution", "max_fps", "vsync_mode",
	"msaa_3d", "reconstruction", "fsr2_sharpness", "nvidia_reflex"]
const MODES: Array[String] = ["metalfx_temporal_native", "metalfx_temporal_85", "metalfx_temporal_quality"]


static func _settings(app: Node) -> Node:
	if not is_instance_valid(app) or not app.is_inside_tree():
		return null
	var script: Script = app.get_script()
	if script == null or script.resource_path != "res://app_root.gd":
		return null
	var screens: Variant = app.get("screens")
	if not screens is RefCounted or not screens.has_method("top") or not screens.has_method("is_top") \
			or not bool(screens.call("is_top", "settings")):
		return null
	var top: Variant = screens.call("top")
	if not top is Node or not is_instance_valid(top) or top.get_parent() != app:
		return null
	var settings: Node = top
	var settings_script: Script = settings.get_script()
	if settings_script == null or settings_script.resource_path != "res://ui/settings_screen.gd":
		return null
	return settings


static func _state(settings: Node) -> Dictionary:
	var draft: Variant = settings.get("_draft")
	var saved: Variant = settings.get("_saved")
	var keep: Variant = settings.get("_keep_button")
	var status: Variant = settings.get("_status")
	var deadline: Variant = settings.get("_trial_deadline_msec")
	var now := Time.get_ticks_msec()
	return {"observed_msec": now, "settings_instance_id": settings.get_instance_id(),
		"saved_reconstruction": str(saved.get("reconstruction", "")).left(80) if saved is Dictionary else "unavailable",
		"draft_reconstruction": str(draft.get("reconstruction", "")).left(80) if draft is Dictionary else "unavailable",
		"draft_equals_saved": draft == saved if draft is Dictionary and saved is Dictionary else false,
		"trial_deadline_msec": deadline if typeof(deadline) == TYPE_INT else -1,
		"trial_remaining_msec": int(deadline) - now if typeof(deadline) == TYPE_INT and int(deadline) > 0 else -1,
		"waiting_for_draw": settings.get("_trial_waiting_for_draw"),
		"barrier_seen": settings.get("_trial_barrier_seen"),
		"trial_remaining_seconds": settings.get("_trial_remaining_seconds"),
		"status_state": str(settings.get("_status_state")).left(80),
		"status_text": (status as Label).text.left(256) if status is Label else "unavailable",
		"keep_disabled": (keep as BaseButton).disabled if keep is BaseButton else null,
		"process_frame": Engine.get_process_frames(), "frames_drawn": Engine.get_frames_drawn()}


static func _only_target(config: Dictionary, baseline: Dictionary, target_mode: String) -> bool:
	if config.get("reconstruction") != target_mode:
		return false
	for key: String in TRIAL_KEYS:
		if not config.has(key) or not baseline.has(key):
			return false
		if key != "reconstruction" and config[key] != baseline[key]:
			return false
	return true


static func _choice_available(settings: Node, target_mode: String) -> bool:
	var value: Variant = settings.get("_reconstruction_picker")
	if not value is OptionButton:
		return false
	var picker: OptionButton = value
	if picker.disabled or not picker.is_visible_in_tree():
		return false
	for index in picker.item_count:
		if picker.get_item_metadata(index) == target_mode:
			return not picker.is_item_disabled(index)
	return false


static func _record_post_draw(app_ref: WeakRef, settings_ref: WeakRef, token: String) -> void:
	if not Thread.is_main_thread():
		return
	var app: Variant = app_ref.get_ref()
	var settings: Variant = settings_ref.get_ref()
	if not app is Node or not settings is Node or not is_instance_valid(app) or not is_instance_valid(settings):
		return
	var receipt: Variant = app.get_meta(META, {})
	if not receipt is Dictionary or receipt.get("token") != token or receipt.get("state") != "stall_returned" \
			or _settings(app) != settings:
		return
	receipt["first_post_draw_usec"] = Time.get_ticks_usec()
	receipt["first_post_draw_scope"] = "global_cpu_draw_callback_may_precede_changed_frame_not_os_presentation"
	receipt["first_post_draw_settings"] = _state(settings)
	app.set_meta(META, receipt)


static func _on_preview(config: Dictionary, app_ref: WeakRef, settings_ref: WeakRef,
		baseline: Dictionary, target_mode: String, delay_msec: int, token: String) -> void:
	if not Thread.is_main_thread():
		return
	var app: Variant = app_ref.get_ref()
	var settings: Variant = settings_ref.get_ref()
	if not app is Node or not settings is Node or not is_instance_valid(app) or not is_instance_valid(settings):
		return
	var receipt: Variant = app.get_meta(META, {})
	if not receipt is Dictionary or receipt.get("token") != token or receipt.get("state") != "armed":
		return
	var draft: Variant = settings.get("_draft")
	var saved: Variant = settings.get("_saved")
	var active_deadline: Variant = settings.get("_trial_deadline_msec")
	if _settings(app) != settings or not _choice_available(settings, target_mode) \
			or app.get("flight") != null or app.get("ground_vehicle") != null \
			or not draft is Dictionary or not saved is Dictionary or draft != config \
			or settings.get("_trial_waiting_for_draw") != true \
			or typeof(active_deadline) != TYPE_INT or int(active_deadline) <= 0 \
			or not _only_target(config, baseline, target_mode):
		receipt["state"] = "ignored_unexpected_first_change"
		receipt["observed_reconstruction"] = str(config.get("reconstruction", "")).left(80)
		app.set_meta(META, receipt)
		return
	for key: String in TRIAL_KEYS:
		if not saved.has(key) or saved[key] != baseline[key]:
			receipt["state"] = "ignored_changed_saved_settings"
			app.set_meta(META, receipt)
			return
	receipt["state"] = "stall_in_progress"
	receipt["callback_started_usec"] = Time.get_ticks_usec()
	receipt["before_stall"] = _state(settings)
	app.set_meta(META, receipt)
	var started := Time.get_ticks_usec()
	OS.delay_msec(delay_msec)
	var finished := Time.get_ticks_usec()
	receipt["started_usec"] = started
	receipt["finished_usec"] = finished
	receipt["actual_delay_usec"] = finished - started
	receipt["after_stall_before_signal_return"] = _state(settings)
	receipt["state"] = "stall_returned"
	app.set_meta(META, receipt)
	var post_draw := func() -> void:
		_record_post_draw(app_ref, settings_ref, token)
	var post_draw_error := RenderingServer.frame_post_draw.connect(post_draw, Object.CONNECT_ONE_SHOT)
	if post_draw_error != OK:
		receipt["post_draw_connect_error"] = post_draw_error
		app.set_meta(META, receipt)


## Connect after AppRoot's real handler. A different first change consumes the
## one-shot without sleeping; a second installation in this app is refused.
static func install(app: Node, target_mode: String = "metalfx_temporal_quality", delay_msec: int = 20000) -> Dictionary:
	if not Thread.is_main_thread() or target_mode not in MODES or delay_msec != 20000:
		return {"ok": false, "error": "invalid_thread_mode_or_delay"}
	var settings := _settings(app)
	if settings == null:
		return {"ok": false, "error": "settings_not_top_or_unexpected_script"}
	if app.get("flight") != null or app.get("ground_vehicle") != null or app.get("has_home") != true:
		return {"ok": false, "error": "home_only"}
	if not _choice_available(settings, target_mode):
		return {"ok": false, "error": "temporal_choice_not_visible_or_enabled"}
	if app.has_meta(META):
		return {"ok": false, "error": "already_installed"}
	var draft: Variant = settings.get("_draft")
	var saved: Variant = settings.get("_saved")
	if not draft is Dictionary or not saved is Dictionary or draft != saved \
			or str(saved.get("reconstruction", "")) not in ["native", "auto"] \
			or settings.get("_trial_waiting_for_draw") != false \
			or typeof(settings.get("_trial_deadline_msec")) != TYPE_INT \
			or int(settings.get("_trial_deadline_msec")) != 0:
		return {"ok": false, "error": "existing_trial_or_nonfresh_settings"}
	var apply := Callable(app, "_apply_presentation")
	var found_sync_apply := false
	for connection: Dictionary in settings.get_signal_connection_list("presentation_changed"):
		if connection.get("callable") == apply and (int(connection.get("flags", 0)) & Object.CONNECT_DEFERRED) == 0:
			found_sync_apply = true
	if not found_sync_apply:
		return {"ok": false, "error": "app_apply_handler_missing_or_deferred"}
	var baseline := {}
	for key: String in TRIAL_KEYS:
		if not saved.has(key):
			return {"ok": false, "error": "missing_trial_key:" + key}
		baseline[key] = saved[key]
	var token := str(app.get_instance_id()) + ":" + str(Time.get_ticks_usec())
	var app_ref: WeakRef = weakref(app)
	var settings_ref: WeakRef = weakref(settings)
	var observer := func(config: Dictionary) -> void:
		_on_preview(config, app_ref, settings_ref, baseline, target_mode, delay_msec, token)
	var err := settings.connect("presentation_changed", observer, Object.CONNECT_ONE_SHOT)
	if err != OK:
		return {"ok": false, "error": "signal_connect_failed", "code": err}
	var receipt := {"ok": true, "state": "armed", "token": token, "target_mode": target_mode,
		"requested_delay_msec": delay_msec, "installed_usec": Time.get_ticks_usec(),
		"settings_instance_id": settings.get_instance_id(), "baseline_reconstruction": str(saved.reconstruction),
		"scope": "main_thread_delay_after_app_apply_not_gpu_timing_or_presentation"}
	app.set_meta(META, receipt)
	return receipt.duplicate(true)


## Call from the bridge after allowing the app to process/render. CPU receipt
## and drawable state do not prove a changed pixel or OS presentation.
static func snapshot(app: Node) -> Dictionary:
	if not Thread.is_main_thread() or not is_instance_valid(app) or not app.has_meta(META):
		return {"ok": false, "error": "not_installed_or_wrong_thread"}
	var receipt: Variant = app.get_meta(META)
	if not receipt is Dictionary:
		return {"ok": false, "error": "invalid_receipt"}
	var result: Dictionary = receipt.duplicate(true)
	result["triggered"] = receipt.get("state") == "stall_returned"
	var settings := _settings(app)
	if settings == null or settings.get_instance_id() != int(receipt.get("settings_instance_id", -1)):
		result["snapshot_error"] = "settings_closed_or_replaced"
		return result
	result["current"] = _state(settings)
	var viewport := settings.get_viewport()
	var window := viewport as Window
	result["window_drawable"] = window.can_draw() if window != null else false
	result["viewport_instance_id"] = viewport.get_instance_id()
	result["viewport_rid"] = viewport.get_viewport_rid().get_id()
	result["temporal_status_scope"] = "ordered_cpu_status_not_gpu_completion_or_os_presentation"
	result["snapshot_scope"] = "settings_read_before_separate_non_atomic_temporal_status_query"
	result["temporal_query_started_usec"] = Time.get_ticks_usec()
	if RenderingServer.has_method("viewport_get_metalfx_status"):
		var value: Variant = RenderingServer.call("viewport_get_metalfx_status", viewport.get_viewport_rid())
		var bounded := {}
		if value is Dictionary:
			for key: String in ["generation", "requested_mode", "configured_mode", "provider", "allocation", "submission", "render_buffers_available", "temporal_attempts"]:
				var item: Variant = value.get(key)
				if typeof(item) in [TYPE_BOOL, TYPE_INT, TYPE_STRING]:
					bounded[key] = str(item).left(80) if item is String else item
		result["temporal_status"] = bounded
	else:
		result["temporal_status"] = {"reason": "api_unavailable"}
	result["temporal_query_finished_usec"] = Time.get_ticks_usec()
	return result
