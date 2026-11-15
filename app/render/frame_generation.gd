## DT-MAC-12c: explicit developer trial. Rendering only; no simulation ticks.
extends Node

const Policy := preload("res://render/frame_generation_policy.gd")
const OWNER_META := &"openrc_frame_generation_owner"
const STATUS_META := &"openrc_frame_generation_status"
const HISTORY_META := &"openrc_reconstruction_history_reset"
const RECONSTRUCTION_META := &"openrc_reconstruction"
const RECONSTRUCTION_RESET_META := &"openrc_metalfx_pending_reset"
const RECONSTRUCTION_SCOPE_META := &"openrc_metalfx_status_scope"
const ATOMIC_HISTORY_RESET_METHOD := &"viewport_request_temporal_history_reset_if_current"
const POLL_USEC := 100_000
const PRESENT_TIMEOUT_USEC := 500_000
const PRESENT_MAX_AGE_USEC := 350_000
const BUSY_RETRY_USEC := 1_000_000
const HISTORY_SYNC_GRACE_USEC := 2_000_000
const HISTORY_SYNC_TIMEOUT_USEC := 5_000_000
const DIAGNOSTIC_TRANSITIONS := 16
const DIAGNOSTICS_ENV := "OPENRC_METALFX_TRIAL_DIAGNOSTICS"
const REQUIRED_API := ["viewport_get_metalfx_frame_capability", "viewport_get_metalfx_status",
	"viewport_request_temporal_history_reset", "get_temporal_history_reset_providers",
	"viewport_set_real_gpu_observation_requested", "viewport_reset_real_gpu_observation",
	"viewport_get_real_gpu_observation", "viewport_set_metalfx_gpu_observation_requested",
	"viewport_get_metalfx_gpu_status", "viewport_set_metalfx_frame_requested", "viewport_get_metalfx_frame_status",
	"viewport_set_metalfx_frame_composition_requested", "viewport_get_metalfx_frame_composition_status"]
static var _present_failure_process_latched := false
static var _present_unresolved_process_latched := false

var _view: WeakRef
var _simulation: WeakRef
var _backend: Object
var _policy: RefCounted
var _rid := RID()
var _source_id := 0
var _source_epoch := 1
var _next_poll := 0
var _last_clock := 0
var _real_on := false
var _gpu_on := false
var _producer_on := false
var _composition_on := false
var _last_frame_proof: Dictionary = {}
var _frame_ticket_barrier: Dictionary = {}
var _real_generation := 0
var _reset_sent_generation := 0
var _busy_retry_at := 0
var _history_notifications := -1
var _camera_id := -1
var _drawable: Variant = null
var _present_pending := false
var _present_sequence := 0
var _present_sent_at := 0
var _present_value: Dictionary = {}
var _present_value_sent_at := 0
var _present_generation := 0
var _closed := false
var _api_available := false
var _clock_override := Callable()
var _facts_override := Callable()
var _present_dispatch_override := Callable()
var _history_reset_override := Callable()
var _diagnostics_enabled := OS.get_environment(DIAGNOSTICS_ENV) == "1"
var _diagnostic_transitions: Variant = null
var _history_sync_probe: Dictionary = {}
var _history_sync_pending: Dictionary = {}
var _history_sync_attempted: Dictionary = {}
var _history_sync_blocked := false
var _history_sync_failure_reason := ""


static func startup_requested(fg: String, owner: String) -> bool:
	return fg == "1" and owner == "1"


## Nothing is instantiated on ordinary launches. The viewport metadata holds a
## weak owner so AppRoot and a standalone flight cannot install two controllers.
static func install(host: Node) -> Node:
	if not startup_requested(OS.get_environment("OPENRC_METALFX_FRAME_GENERATION"), OS.get_environment("OPENRC_METALFX_DISPLAY_LINK")):
		return null
	if not is_instance_valid(host) or not host.is_inside_tree():
		return null
	var viewport := host.get_viewport()
	if not is_instance_valid(viewport):
		return null
	var old: Variant = viewport.get_meta(OWNER_META) if viewport.has_meta(OWNER_META) else null
	if old is WeakRef and is_instance_valid(old.get_ref()):
		return old.get_ref()
	var controller: Node = load("res://render/frame_generation.gd").new()
	controller.name = "FrameGenerationTrial"
	controller.configure(viewport, RenderingServer)
	host.add_child(controller)
	viewport.set_meta(OWNER_META, weakref(controller))
	return controller


## Backend, clock and dispatch are injectable for deterministic, headless tests.
func configure(viewport: Viewport, backend: Object, clock := Callable(), facts := Callable(), dispatch := Callable(), history_reset := Callable()) -> void:
	_view = weakref(viewport)
	_backend = backend
	_clock_override = clock
	_facts_override = facts
	_present_dispatch_override = dispatch
	_history_reset_override = history_reset
	_policy = Policy.new()
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000 # Run after the flight's camera/reset work, before drawing.
	_rid = viewport.get_viewport_rid()
	_source_id = _rid.get_id() if _rid.is_valid() else 0
	_api_available = is_instance_valid(_backend)
	for method: String in REQUIRED_API:
		_api_available = _api_available and _backend.has_method(method)
	if viewport is Window and not viewport.size_changed.is_connected(_window_resized):
		viewport.size_changed.connect(_window_resized)
	_set_status({"requested": true, "state": "suspended", "reason": "waiting_for_trial" if _api_available else "engine_api_unavailable"})


func _now() -> int:
	return int(_clock_override.call()) if _clock_override.is_valid() else Time.get_ticks_usec()


func _dict(method: String, rid: RID) -> Dictionary:
	if not _api_available or not rid.is_valid():
		return {}
	var value: Variant = _backend.call(method, rid)
	return value if value is Dictionary else {}


func _window_resized() -> void:
	note_discontinuity("window_resize")


## Observe the existing simulation signal without advancing or changing it.
func bind_simulation(simulation: Object) -> void:
	var previous: Variant = _simulation.get_ref() if _simulation != null else null
	if previous == simulation:
		return
	var callback := Callable(self, "_simulation_pause_changed")
	if is_instance_valid(previous) and previous.has_signal("paused_changed") and previous.is_connected("paused_changed", callback):
		previous.disconnect("paused_changed", callback)
	_simulation = weakref(simulation) if is_instance_valid(simulation) else null
	if is_instance_valid(simulation) and simulation.has_signal("paused_changed") and not simulation.is_connected("paused_changed", callback):
		simulation.connect("paused_changed", callback)
	note_discontinuity("simulation_replaced")


func _simulation_pause_changed(_paused: bool) -> void:
	note_discontinuity("simulation_pause_changed")


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN,
			NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED,
			NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		if _policy != null and not _closed:
			note_discontinuity("window_focus")


func _process(_delta: float) -> void:
	if _closed or _policy == null or not _api_available:
		return
	var viewport: Variant = _view.get_ref() if _view != null else null
	if not is_instance_valid(viewport) or not viewport.is_inside_tree():
		shutdown()
		return
	var current_rid: RID = viewport.get_viewport_rid()
	if current_rid != _rid:
		note_discontinuity("viewport_replaced")
		_disable_all()
		_rid = current_rid
		_source_id = _rid.get_id() if _rid.is_valid() else 0
	var history: Variant = viewport.get_meta(HISTORY_META, {})
	var notifications := int(history.get("notifications", 0)) if history is Dictionary else 0
	if _history_notifications >= 0 and notifications != _history_notifications:
		note_discontinuity("camera_history_reset")
	_history_notifications = notifications
	var camera: Camera3D = viewport.get_camera_3d()
	var camera_id: int = camera.get_instance_id() if is_instance_valid(camera) else 0
	if _camera_id >= 0 and camera_id != _camera_id:
		note_discontinuity("camera_changed")
	_camera_id = camera_id
	var drawable: bool = viewport.can_draw() if viewport is Window else false
	if _drawable != null and drawable != _drawable:
		note_discontinuity("window_visibility")
	_drawable = drawable
	var now := _now()
	if now < _last_clock:
		note_discontinuity("poll_clock_reset")
		_next_poll = 0
	_last_clock = now
	if now < _next_poll:
		return
	_next_poll = now + POLL_USEC
	_poll(now, viewport, drawable)


## This runs every frame when a cut is noticed, not at the slower status cadence.
func note_discontinuity(reason: String) -> void:
	if _closed or _policy == null:
		return
	_history_sync_probe = {}
	_history_sync_pending = {}
	_history_sync_attempted = {}
	_history_sync_blocked = false
	_history_sync_failure_reason = ""
	_source_epoch += 1
	_present_value = {}
	_present_value_sent_at = 0
	_clear_frame_proof()
	_policy.notify_discontinuity()
	_set_composition(false)
	_set_producer(false)
	_set_gpu(false)
	if _real_on and _api_available and _rid.is_valid():
		_backend.call("viewport_reset_real_gpu_observation", _rid)
		_reset_sent_generation = _real_generation
	_real_generation = 0
	_set_status({"requested": true, "state": "suspended", "reason": reason})


func _request_present_status(now: int) -> void:
	if _present_pending or not _rid.is_valid() or _source_id <= 0:
		return
	_present_pending = true
	_present_sequence += 1
	_present_sent_at = now
	if _present_dispatch_override.is_valid():
		_present_dispatch_override.call(_present_sequence, _source_epoch, _rid, _source_id)
	else:
		RenderingServer.call_on_render_thread(Callable(self, "_present_on_render_thread").bind(_present_sequence, _source_epoch, _rid, _source_id))


## Render thread: capture no mutable controller state and do no viewport calls.
func _present_on_render_thread(sequence: int, epoch: int, rid: RID, source_id: int) -> void:
	var rd := RenderingServer.get_rendering_device()
	var value: Dictionary = rd.call("openrc_metalfx_present_status") if rd != null and rd.has_method("openrc_metalfx_present_status") else {}
	call_deferred("_present_status_delivered", sequence, epoch, rid, source_id, value)


func _present_status_delivered(sequence: int, epoch: int, rid: RID, source_id: int, value: Dictionary) -> void:
	if _closed or not _present_pending or sequence != _present_sequence:
		return
	_present_pending = false
	# A trusted outstanding query can report a GPU failure even if its source
	# was retired before delivery. Never use that stale reply for admission.
	if typeof(value.get("gpu_failed")) == TYPE_INT and int(value.gpu_failed) > 0:
		var first_failure := not _present_failure_process_latched
		_present_failure_process_latched = true
		if first_failure:
			note_discontinuity("presenter_gpu_failure_latched")
	if (typeof(value.get("nonterminal_completion_commands")) == TYPE_INT and int(value.nonterminal_completion_commands) > 0) \
			or (typeof(value.get("submission_retention_rejected")) == TYPE_INT and int(value.submission_retention_rejected) > 0):
		var first_unresolved := not _present_unresolved_process_latched
		_present_unresolved_process_latched = true
		if first_unresolved:
			note_discontinuity("presenter_submission_unresolved_latched")
	var now := _now()
	if epoch != _source_epoch or rid != _rid or source_id != _source_id or now < _present_sent_at \
			or now - _present_sent_at > PRESENT_TIMEOUT_USEC:
		return
	if typeof(value.get("generation")) == TYPE_INT and int(value.generation) > 0:
		var generation := int(value.generation)
		if _present_generation > 0 and generation != _present_generation:
			_present_generation = generation
			if not _history_sync_pending.is_empty():
				# The reset itself can retire the presenter's source. FG is
				# already disabled; obtain one new status without losing 0006.
				_present_value = {}
				_present_value_sent_at = 0
				return
			note_discontinuity("presenter_generation_changed")
			return
		_present_generation = generation
	_present_value = value.duplicate(true)
	_present_value_sent_at = _present_sent_at


func _present_active(now: int) -> bool:
	return not _present_failure_process_latched and not _present_unresolved_process_latched \
			and _present_value_sent_at > 0 and now >= _present_value_sent_at \
			and now - _present_value_sent_at <= PRESENT_MAX_AGE_USEC \
			and _present_value.get("requested") == true and _present_value.get("owner") == "display_link" \
			and _present_value.get("synthetic_control") == false \
			and typeof(_present_value.get("generation")) == TYPE_INT and int(_present_value.generation) > 0 \
			and typeof(_present_value.get("gpu_failed")) == TYPE_INT and int(_present_value.gpu_failed) == 0 \
			and typeof(_present_value.get("nonterminal_completion_commands")) == TYPE_INT \
			and int(_present_value.nonterminal_completion_commands) == 0 \
			and typeof(_present_value.get("submission_retention_rejected")) == TYPE_INT \
			and int(_present_value.submission_retention_rejected) == 0


static func _capability_flag(value: Variant, yes: String, no: String) -> Variant:
	if value == yes:
		return true
	if value == no:
		return false
	return null


func _facts(viewport: Viewport, now: int, drawable: bool, temporal: Dictionary, capability: Dictionary) -> Dictionary:
	if _facts_override.is_valid():
		return _facts_override.call(viewport, now, drawable, temporal, capability, _present_value)
	var mode: Variant = ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_METALFX_TEMPORAL") \
			if ClassDB.class_has_integer_constant("Viewport", "SCALING_3D_MODE_METALFX_TEMPORAL") else null
	var selected: Variant = viewport.get_meta(RECONSTRUCTION_META, {})
	var active: bool = typeof(mode) == TYPE_INT and int(viewport.scaling_3d_mode) == int(mode) \
			and selected is Dictionary and selected.get("provider") == "metalfx_temporal" \
			and OS.get_environment("OPENRC_METALFX_TRIAL") == "1"
	var cpu_ready: bool = active and temporal.get("provider") == "temporal" and temporal.get("allocation") == "created" \
			and temporal.get("submission") == "enqueued" and temporal.get("render_buffers_available") == true \
			and temporal.get("requested_mode") == mode and temporal.get("configured_mode") == mode
	return {"compiled": _capability_flag(capability.get("compiled"), "yes", "no"),
		"os_supported": _capability_flag(capability.get("os_available"), "yes", "no"),
		"device_supported": _capability_flag(capability.get("device_support"), "supported", "unsupported"),
		"owner_startup_requested": OS.get_environment("OPENRC_METALFX_DISPLAY_LINK") == "1",
		"owner_active": _present_active(now), "window_drawable": drawable,
		"temporal_active": active, "temporal_cpu_ready": cpu_ready,
		"transparent_background_disabled": not viewport.transparent_bg,
		"msaa_2d_disabled": viewport.msaa_2d == Viewport.MSAA_DISABLED,
		"msaa_3d_disabled": viewport.msaa_3d == Viewport.MSAA_DISABLED,
		"backend": RenderingServer.get_current_rendering_driver_name(),
		"renderer": RenderingServer.get_current_rendering_method()}


func _poll(now: int, viewport: Viewport, drawable: bool) -> void:
	if _history_sync_blocked:
		_publish_history_sync_status(_history_sync_failure_reason, {}, {}, {})
		return
	_request_present_status(now)
	var temporal_before := _dict("viewport_get_metalfx_status", _rid)
	var capability := _dict("viewport_get_metalfx_frame_capability", _rid)
	var facts := _facts(viewport, now, drawable, temporal_before, capability)
	if _present_failure_process_latched or _present_unresolved_process_latched:
		facts["owner_active"] = false
	# Read the SDK completion first: the later real-frame snapshot can then
	# contain the same completed frame. These remain independent observations.
	var sdk := _sdk_receipt(temporal_before, now)
	var observation := _dict("viewport_get_real_gpu_observation", _rid) if _real_on else {}
	if _real_on and observation.get("reason") == "observer_busy" and now >= _busy_retry_at:
		# 0013 retries this viewport's acquisition on another explicit true.
		_backend.call("viewport_set_real_gpu_observation_requested", _rid, true)
		_busy_retry_at = now + BUSY_RETRY_USEC
	if _real_on and typeof(observation.get("generation")) == TYPE_INT:
		var generation := int(observation.generation)
		if _real_generation > 0 and generation != _real_generation:
			if not _history_sync_pending.is_empty():
				if generation != int(_history_sync_pending.real_generation):
					_fail_history_sync("temporal_reset_sync_scope_changed", facts, observation, sdk)
					return
			else:
				note_discontinuity("observer_generation_changed")
				observation = _dict("viewport_get_real_gpu_observation", _rid)
				sdk = {} # The pre-reset SDK receipt belongs to the retired scope.
		_real_generation = int(observation.get("generation", 0))
	if _handle_history_sync(viewport, now, facts, observation, sdk):
		return
	var decision: Dictionary = _policy.step(true, facts, observation, sdk)
	if _present_failure_process_latched:
		decision["reason"] = "presenter_gpu_failure_latched"
	elif _present_unresolved_process_latched:
		decision["reason"] = "presenter_submission_unresolved_latched"
	elif _present_pending and now >= _present_sent_at and now - _present_sent_at > PRESENT_TIMEOUT_USEC:
		decision["reason"] = "presenter_poll_timeout"
	if decision.get("restart_observer") == true and _real_on:
		var blocked := int(observation.get("generation", 0))
		if blocked > 0 and blocked != _reset_sent_generation:
			_backend.call("viewport_reset_real_gpu_observation", _rid)
			_reset_sent_generation = blocked
	_apply(decision)
	decision["trial"] = "experimental_unverified"
	decision["presenter_scope"] = "recent_render_thread_status_not_a_presentation_receipt"
	decision["presenter_failure_scope"] = "delivered_status_only_controller_teardown_may_drop_a_reply"
	decision["presenter_generation_scope"] = "presenter_local_equal_generation_replacement_not_identified"
	decision["sleep_wake_scope"] = "application_lifecycle_notifications_only_macos_sleep_delivery_unverified"
	if _diagnostics_enabled:
		decision["diagnostics"] = _poll_diagnostics(facts, observation, sdk)
	_set_status(decision)


## Bounded, opt-in debugging evidence; never retain the full observer ring.
func _poll_diagnostics(facts: Dictionary, observation: Dictionary, sdk: Dictionary) -> Dictionary:
	var samples: Array = []
	var records: Variant = observation.get("samples", [])
	if records is Array:
		for index in range(maxi(0, records.size() - 6), records.size()):
			var record: Variant = records[index]
			if record is Dictionary:
				samples.append({"generation": record.get("generation"), "frame": record.get("frame"),
					"gpu_end_seconds": record.get("gpu_end_seconds")})
	return {"source_id": _source_id, "source_epoch": _source_epoch, "facts": facts.duplicate(true),
		"real": {"generation": observation.get("generation"), "now_seconds": observation.get("now_seconds"),
			"observed_through_seconds": observation.get("observed_through_seconds"),
			"coverage_start_seconds": observation.get("coverage_start_seconds"), "samples": samples},
		"sdk": sdk.duplicate(true)}


## A reset can predate observer 0006. Wait for an in-flight reset first, then
## request at most one fresh reset for this observer scope while it stays on.
func _handle_history_sync(viewport: Viewport, now: int, facts: Dictionary, observation: Dictionary, sdk: Dictionary) -> bool:
	if not _history_sync_pending.is_empty():
		return _advance_history_sync(now, facts, observation, sdk)
	if not _real_on or not _gpu_on or not Policy.capability_reason(facts).is_empty() \
			or observation.get("valid") != true or observation.get("eligible") != true \
			or observation.get("overflow") != false or observation.get("failed") != false \
			or observation.get("invalid_clock") != false or typeof(observation.get("generation")) != TYPE_INT:
		_history_sync_probe = {}
		return false
	var gpu: Variant = sdk.get("temporal_gpu")
	if not gpu is Dictionary or gpu.get("requested_by_caller") != true or gpu.get("provider") != "temporal":
		_history_sync_probe = {}
		return false
	for key: String in ["viewport_generation", "observation_generation", "current_reset_requested_serial"]:
		if typeof(gpu.get(key)) != TYPE_INT:
			_history_sync_probe = {}
			return false
	var scaler: Variant = gpu.get("scaler")
	if not scaler is Dictionary or scaler.get("state") not in ["pending", "completed"] \
			or typeof(scaler.get("reset_completed_serial")) != TYPE_INT \
			or not scaler.get("first_observed_failure") is Dictionary \
			or typeof(scaler.first_observed_failure.get("ticket")) != TYPE_INT \
			or int(scaler.first_observed_failure.ticket) != 0 or not _frame_role_valid(scaler, 0):
		_history_sync_probe = {}
		return false
	var reset_serial := int(gpu.current_reset_requested_serial)
	var completed_serial := int(scaler.reset_completed_serial)
	if reset_serial <= 0 or completed_serial < 0 or completed_serial >= reset_serial:
		_history_sync_probe = {}
		return false
	if reset_serial >= 9223372036854775806:
		_fail_history_sync("temporal_reset_sync_serial_exhausted", facts, observation, sdk)
		return true
	var scope := {"source_id": _source_id, "viewport_generation": int(gpu.viewport_generation),
		"observation_generation": int(gpu.observation_generation)}
	if scope.viewport_generation <= 0 or scope.observation_generation <= 0 or int(observation.generation) <= 0:
		return false
	var probe_scope := scope.duplicate()
	probe_scope["reset_serial"] = reset_serial
	var reset: Variant = sdk.get("temporal_reset")
	if not reset is Dictionary or typeof(reset.get("gpu_completed_after")) != TYPE_INT \
			or int(reset.gpu_completed_after) < completed_serial or int(reset.gpu_completed_after) > reset_serial:
		_history_sync_probe = {}
		return false
	if int(reset.gpu_completed_after) == reset_serial:
		_history_sync_probe = {}
		return false # The later bracket already observed the reset's GPU completion.
	if scope == _history_sync_attempted:
		_fail_history_sync("temporal_reset_sync_receipt_lost", facts, observation, sdk)
		return true
	var settled := not viewport.has_meta(RECONSTRUCTION_RESET_META) and reset is Dictionary
	if settled:
		for key: String in ["submitted_before", "encoded_before", "submitted_after", "encoded_after"]:
			if typeof(reset.get(key)) != TYPE_INT or int(reset[key]) != reset_serial:
				settled = false
	var phase := "gpu_receipt" if settled else "prior_reset"
	if _history_sync_probe.get("scope") != probe_scope or _history_sync_probe.get("phase") != phase:
		_history_sync_probe = {"scope": probe_scope, "phase": phase, "started": now}
		return false
	if now < int(_history_sync_probe.started):
		_fail_history_sync("temporal_reset_sync_clock_invalid", facts, observation, sdk)
		return true
	if not settled:
		if now - int(_history_sync_probe.started) > HISTORY_SYNC_TIMEOUT_USEC:
			_fail_history_sync("prior_temporal_reset_unsettled", facts, observation, sdk)
			return true
		return false
	if now - int(_history_sync_probe.started) < HISTORY_SYNC_GRACE_USEC:
		return false
	return _begin_history_sync(viewport, now, facts, observation, sdk, scope, reset_serial)


func _request_history_sync(viewport: Viewport, scope: Dictionary, expected_serial: int) -> Dictionary:
	if _history_reset_override.is_valid():
		var result: Variant = _history_reset_override.call(viewport, expected_serial)
		return result if result is Dictionary else {}
	var reconstruction: Variant = load("res://render/reconstruction.gd")
	if reconstruction == null:
		return {}
	var mode: Variant = reconstruction._integer_constant_or_null("Viewport", "SCALING_3D_MODE_METALFX_TEMPORAL")
	if typeof(mode) != TYPE_INT:
		return {}
	return _request_history_sync_checked(viewport, scope, int(mode), reconstruction, expected_serial)


## The expected-generation/serial comparison and reset happen in one engine
## transaction. This does not use the ordinary cut-reset fallback metadata.
func _request_history_sync_checked(viewport: Viewport, scope: Dictionary, mode: int, reconstruction: Variant, expected_serial: int) -> Dictionary:
	if viewport.has_meta(RECONSTRUCTION_RESET_META) or not is_instance_valid(_backend) \
			or not _backend.has_method(ATOMIC_HISTORY_RESET_METHOD) \
			or not _backend.has_method("viewport_get_metalfx_status") \
			or typeof(scope.get("viewport_generation")) != TYPE_INT or int(scope.viewport_generation) <= 0 \
			or expected_serial < 0 or expected_serial >= 9223372036854775806 \
			or not _backend.has_method("get_temporal_history_reset_providers"):
		return {}
	var providers: Variant = _backend.call("get_temporal_history_reset_providers")
	var policy: Variant = viewport.get_meta(RECONSTRUCTION_META, {})
	var tracked: Variant = viewport.get_meta(RECONSTRUCTION_SCOPE_META, {})
	if (not providers is Array and not providers is PackedStringArray) or "metalfx_temporal" not in providers \
			or not policy is Dictionary or policy.get("provider") != "metalfx_temporal" or not tracked is Dictionary \
			or not reconstruction._metalfx_scope_matches(viewport, policy, tracked, mode):
		return {}
	var before: Variant = _backend.call("viewport_get_metalfx_status", viewport.get_viewport_rid())
	if not before is Dictionary or not reconstruction._metalfx_reset_ready(before, mode, int(scope.viewport_generation)) \
			or int(before.generation) != int(scope.viewport_generation) or int(before.reset_requested_serial) != expected_serial:
		return {}
	var raw: Variant = _backend.call(ATOMIC_HISTORY_RESET_METHOD, viewport.get_viewport_rid(), int(scope.viewport_generation), expected_serial)
	if not raw is Dictionary or raw.get("accepted") != true or typeof(raw.get("reason")) != TYPE_STRING \
			or typeof(raw.get("generation")) != TYPE_INT or int(raw.generation) != int(scope.viewport_generation) \
			or typeof(raw.get("previous_requested_serial")) != TYPE_INT or int(raw.previous_requested_serial) != expected_serial \
			or typeof(raw.get("requested_serial")) != TYPE_INT or int(raw.requested_serial) <= expected_serial \
			or int(raw.requested_serial) >= 9223372036854775807 \
			or typeof(raw.get("reset_request_attempt")) != TYPE_INT or int(raw.reset_request_attempt) < int(before.temporal_attempts):
		return {}
	var request := {"mode": mode, "generation": int(raw.generation), "serial": int(raw.requested_serial),
		"reset_request_attempt": int(raw.reset_request_attempt)}
	var after: Variant = _backend.call("viewport_get_metalfx_status", viewport.get_viewport_rid())
	if not after is Dictionary:
		return {}
	var state: String = reconstruction._metalfx_reset_state(after, request)
	if state not in ["pending", "encoded"]:
		return {}
	return {"accepted": true, "generation": request.generation, "previous_serial": expected_serial,
		"serial": request.serial, "reset_state": state}


func _begin_history_sync(viewport: Viewport, now: int, facts: Dictionary, observation: Dictionary,
		sdk: Dictionary, scope: Dictionary, previous_serial: int) -> bool:
	var real_generation := int(observation.generation)
	if real_generation >= 9223372036854775806:
		_fail_history_sync("temporal_reset_sync_scope_invalid", facts, observation, sdk)
		return true
	var previous: Variant = viewport.get_meta(HISTORY_META, {})
	var notifications: int = int(previous.get("notifications", 0)) if previous is Dictionary else 0
	if _history_notifications >= 0 and notifications != _history_notifications:
		_fail_history_sync("temporal_reset_sync_scope_changed", facts, observation, sdk)
		return true
	if not _history_reset_override.is_valid() and (not is_instance_valid(_backend) or not _backend.has_method(ATOMIC_HISTORY_RESET_METHOD)):
		_fail_history_sync("temporal_reset_atomic_unavailable", facts, observation, sdk)
		return true
	_history_sync_attempted = scope.duplicate()
	_source_epoch += 1
	_present_value = {}
	_present_value_sent_at = 0
	_clear_frame_proof()
	_policy.notify_discontinuity()
	_set_composition(false)
	_set_producer(false)
	var receipt := _request_history_sync(viewport, scope, previous_serial)
	var after: Variant = viewport.get_meta(HISTORY_META, {})
	if receipt.get("accepted") != true or typeof(receipt.get("generation")) != TYPE_INT \
			or int(receipt.generation) != int(scope.viewport_generation) \
			or typeof(receipt.get("previous_serial")) != TYPE_INT or int(receipt.previous_serial) != previous_serial \
			or typeof(receipt.get("serial")) != TYPE_INT or int(receipt.serial) <= previous_serial \
			or int(receipt.serial) >= 9223372036854775807 \
			or not after is Dictionary or int(after.get("notifications", 0)) != notifications \
			or receipt.get("reset_state") not in ["pending", "encoded"]:
		_fail_history_sync("temporal_reset_sync_refused", facts, observation, sdk)
		return true
	_history_sync_pending = {"scope": scope, "serial": int(receipt.serial), "previous_real_generation": real_generation,
		"real_generation": real_generation + 1, "started": now}
	_history_sync_probe = {}
	_publish_history_sync_status("waiting_for_temporal_reset_gpu_completion", facts, observation, sdk)
	return true


func _advance_history_sync(now: int, facts: Dictionary, observation: Dictionary, sdk: Dictionary) -> bool:
	var pending := _history_sync_pending
	if now < int(pending.started) or now - int(pending.started) > HISTORY_SYNC_TIMEOUT_USEC:
		_fail_history_sync("temporal_reset_sync_timeout", facts, observation, sdk)
		return true
	if _source_id != int(pending.scope.source_id) or not _real_on or not _gpu_on:
		_fail_history_sync("temporal_reset_sync_scope_changed", facts, observation, sdk)
		return true
	var real_generation: Variant = observation.get("generation")
	if typeof(real_generation) == TYPE_INT and int(real_generation) not in [int(pending.previous_real_generation), int(pending.real_generation)]:
		_fail_history_sync("temporal_reset_sync_scope_changed", facts, observation, sdk)
		return true
	if observation.get("requested") != true or observation.get("supported") != true \
			or observation.get("overflow") != false or observation.get("failed") != false or observation.get("invalid_clock") != false:
		_fail_history_sync("temporal_reset_sync_observer_failed", facts, observation, sdk)
		return true
	var gpu: Variant = sdk.get("temporal_gpu")
	if gpu is Dictionary:
		if gpu.get("requested_by_caller") != true or gpu.get("provider") != "temporal" \
				or gpu.get("viewport_generation") != pending.scope.viewport_generation \
				or gpu.get("observation_generation") != pending.scope.observation_generation \
				or gpu.get("current_reset_requested_serial") != pending.serial:
			_fail_history_sync("temporal_reset_sync_scope_changed", facts, observation, sdk)
			return true
		var scaler: Variant = gpu.get("scaler")
		if scaler is Dictionary:
			var failure: Variant = scaler.get("first_observed_failure")
			if scaler.get("state") in ["failed", "invalid_callback", "observation_exhausted"] \
					or (failure is Dictionary and typeof(failure.get("ticket")) == TYPE_INT and int(failure.ticket) > 0):
				_fail_history_sync("temporal_reset_sync_gpu_failed", facts, observation, sdk)
				return true
			if typeof(real_generation) == TYPE_INT and int(real_generation) == int(pending.real_generation) \
					and scaler.get("state") in ["pending", "completed"] \
					and typeof(scaler.get("reset_completed_serial")) == TYPE_INT \
					and int(scaler.reset_completed_serial) == int(pending.serial) \
					and failure is Dictionary and typeof(failure.get("ticket")) == TYPE_INT and int(failure.ticket) == 0:
				# Preserve this observer and its reset receipt until the new
				# presenter/source status is fresh; dropping it would lose proof.
				if not Policy.capability_reason(facts).is_empty():
					_publish_history_sync_status("waiting_for_reset_scope_readiness", facts, observation, sdk)
					return true
				_history_sync_pending = {}
				return false
	_publish_history_sync_status("waiting_for_temporal_reset_gpu_completion", facts, observation, sdk)
	return true


func _fail_history_sync(reason: String, facts: Dictionary, observation: Dictionary, sdk: Dictionary) -> void:
	_history_sync_probe = {}
	_history_sync_pending = {}
	_history_sync_blocked = true
	_history_sync_failure_reason = reason
	_policy.notify_discontinuity()
	_disable_all()
	_real_generation = 0
	_publish_history_sync_status(reason, facts, observation, sdk)


func _publish_history_sync_status(reason: String, facts: Dictionary, observation: Dictionary, sdk: Dictionary) -> void:
	var status := {"requested": true, "state": "suspended", "reason": reason, "effective": "unverified",
		"observer_requested": _real_on, "metalfx_gpu_observer_requested": _gpu_on,
		"frame_producer_requested": false, "attempt_renderer_gated_composition": false,
		"trial": "experimental_unverified"}
	if _diagnostics_enabled:
		status["diagnostics"] = _poll_diagnostics(facts, observation, sdk)
	_set_status(status)


func _sample_failed(status: Dictionary, role: String) -> bool:
	var sample: Variant = status.get(role)
	if not sample is Dictionary:
		return true
	if sample.get("state") in ["failed", "invalid_callback", "observation_exhausted"]:
		return true
	var failed: Variant = sample.get("first_observed_failure")
	return not failed is Dictionary or typeof(failed.get("ticket")) != TYPE_INT or int(failed.ticket) != 0


static func _frame_role_valid(role: Variant, epoch: int) -> bool:
	if not role is Dictionary or role.get("state") not in ["pending", "completed"]:
		return false
	var completed: Variant = role.get("completed")
	var encoded: Variant = role.get("encoded")
	if not completed is Dictionary or not encoded is Dictionary:
		return false
	for sample: Dictionary in [completed, encoded]:
		for key: String in ["ticket", "render_frame", "epoch"]:
			if typeof(sample.get(key)) != TYPE_INT:
				return false
	if int(completed.ticket) <= 0 or int(completed.render_frame) <= 0 or int(encoded.ticket) < int(completed.ticket) \
			or int(encoded.render_frame) < int(completed.render_frame) or int(completed.epoch) != epoch or int(encoded.epoch) != epoch \
			or typeof(completed.get("succeeded")) != TYPE_BOOL or not completed.succeeded \
			or typeof(completed.get("error_present")) != TYPE_BOOL or completed.error_present:
		return false
	if (int(encoded.ticket) == int(completed.ticket)) != (int(encoded.render_frame) == int(completed.render_frame)):
		return false
	return (role.state == "completed") == (int(encoded.ticket) == int(completed.ticket))


static func _frame_roles_advance(before: Dictionary, after: Dictionary) -> bool:
	for role: String in ["encoded", "completed"]:
		var prior: Dictionary = before[role]
		var next: Dictionary = after[role]
		if int(next.ticket) < int(prior.ticket) or int(next.render_frame) < int(prior.render_frame) \
				or ((int(next.ticket) == int(prior.ticket)) != (int(next.render_frame) == int(prior.render_frame))):
			return false
	return true


## The CPU frame status is read before the GPU observation. Afterwards both
## viewport/observer generations and frame epoch are rechecked independently.
func _sdk_receipt(temporal_before: Dictionary, now: int) -> Dictionary:
	var frame_before := _dict("viewport_get_metalfx_frame_status", _rid)
	var gpu_before := _dict("viewport_get_metalfx_gpu_status", _rid) if _gpu_on else {}
	var composition := _dict("viewport_get_metalfx_frame_composition_status", _rid) if _producer_on else {}
	var frame_after := _dict("viewport_get_metalfx_frame_status", _rid)
	var temporal_after := _dict("viewport_get_metalfx_status", _rid)
	var gpu_after := _dict("viewport_get_metalfx_gpu_status", _rid) if _gpu_on else {}
	if not _rid.is_valid() or _source_id <= 0 or _rid.get_id() != _source_id \
			or typeof(frame_before.get("generation")) != TYPE_INT or frame_before.get("generation") != frame_after.get("generation") \
			or typeof(frame_before.get("requested")) != TYPE_BOOL or frame_before.get("requested") != frame_after.get("requested"):
		_clear_frame_proof()
		return {}
	var sdk := {"producer_requested": frame_before.requested, "current_generation": int(frame_before.generation), "source_id": _source_id}
	if _gpu_on and typeof(gpu_before.get("observation_generation")) == TYPE_INT \
			and typeof(gpu_before.get("viewport_generation")) == TYPE_INT \
			and typeof(temporal_before.get("generation")) == TYPE_INT \
			and typeof(temporal_before.get("reset_requested_serial")) == TYPE_INT \
			and gpu_before.get("observation_generation") == gpu_after.get("observation_generation") \
			and gpu_before.get("viewport_generation") == gpu_after.get("viewport_generation") \
			and gpu_before.get("viewport_generation") == temporal_before.get("generation") \
			and temporal_before.get("generation") == temporal_after.get("generation") \
			and temporal_before.get("reset_requested_serial") == temporal_after.get("reset_requested_serial") \
			and gpu_before.get("current_reset_requested_serial") == temporal_after.get("reset_requested_serial") \
			and gpu_after.get("current_reset_requested_serial") == temporal_after.get("reset_requested_serial"):
		sdk["temporal_gpu"] = gpu_before
		sdk["temporal_recheck"] = {"source_id": _source_id, "viewport_generation": gpu_after.viewport_generation,
			"observation_generation": gpu_after.observation_generation, "reset_requested_serial": temporal_after.reset_requested_serial}
		var reset_fields_valid := true
		for status: Dictionary in [temporal_before, temporal_after]:
			for key: String in ["reset_submitted_serial", "reset_encoded_serial"]:
				reset_fields_valid = reset_fields_valid and typeof(status.get(key)) == TYPE_INT
		if reset_fields_valid:
			sdk["temporal_reset"] = {"submitted_before": int(temporal_before.reset_submitted_serial),
				"encoded_before": int(temporal_before.reset_encoded_serial),
				"submitted_after": int(temporal_after.reset_submitted_serial),
				"encoded_after": int(temporal_after.reset_encoded_serial)}
		if _sample_failed(gpu_after, "scaler"):
			var scoped: Dictionary = sdk.temporal_gpu.duplicate(true)
			scoped["scaler"] = gpu_after.get("scaler", {})
			sdk.temporal_gpu = scoped
		else:
			var before_scaler: Variant = gpu_before.get("scaler")
			var after_scaler: Variant = gpu_after.get("scaler")
			if before_scaler is Dictionary and after_scaler is Dictionary \
					and typeof(before_scaler.get("reset_completed_serial")) == TYPE_INT \
					and typeof(after_scaler.get("reset_completed_serial")) == TYPE_INT \
					and int(after_scaler.reset_completed_serial) >= int(before_scaler.reset_completed_serial) \
					and int(after_scaler.reset_completed_serial) <= int(temporal_after.reset_requested_serial):
				if sdk.has("temporal_reset"):
					sdk.temporal_reset["gpu_completed_after"] = int(after_scaler.reset_completed_serial)
			else:
				sdk.erase("temporal_gpu")
				sdk.erase("temporal_recheck")
				sdk.erase("temporal_reset")
	if not frame_before.requested:
		_clear_frame_proof()
		return sdk
	for status: Dictionary in [frame_before, frame_after]:
		var reason: Variant = status.get("reason")
		if typeof(reason) == TYPE_STRING and reason not in ["none", "not_attempted"]:
			sdk["frame_reason"] = reason
	if not sdk.has("frame_reason") and typeof(frame_after.get("reason")) == TYPE_STRING:
		sdk["frame_reason"] = frame_after.reason
	if typeof(composition.get("latest_submission")) == TYPE_STRING:
		sdk["latest_submission"] = composition.latest_submission
	if _present_active(now) and typeof(_present_value.get("blocked_source_epoch")) == TYPE_INT \
			and typeof(frame_after.get("requested_epoch")) == TYPE_INT and int(frame_after.requested_epoch) > 0 \
			and int(_present_value.blocked_source_epoch) == int(frame_after.requested_epoch):
		sdk["latest_submission"] = "presenter_blocked_epoch"
	if frame_before.get("allocation") == "not_attempted" and frame_before.get("submission") == "not_attempted" \
			and frame_after.get("allocation") == "not_attempted" and frame_after.get("submission") == "not_attempted":
		_clear_frame_proof()
		sdk["state"] = "pending_context"
		return sdk
	var error_free := typeof(frame_before.get("callback_error")) == TYPE_INT and int(frame_before.callback_error) == 0 \
			and typeof(frame_after.get("callback_error")) == TYPE_INT and int(frame_after.callback_error) == 0 \
			and not _sample_failed(gpu_before, "frame_interpolation") and not _sample_failed(gpu_after, "frame_interpolation")
	sdk["error_free"] = error_free
	sdk["ready"] = false
	sdk["gpu_completed"] = false
	var output_ready: bool = typeof(frame_before.get("ready_for_debug_readback")) == TYPE_BOOL \
			and frame_before.ready_for_debug_readback and typeof(frame_after.get("ready_for_debug_readback")) == TYPE_BOOL \
			and frame_after.ready_for_debug_readback
	var frame_role_before: Variant = gpu_before.get("frame_interpolation")
	var frame_role_after: Variant = gpu_after.get("frame_interpolation")
	var frame_scope_valid: bool = sdk.has("temporal_gpu") and _gpu_on \
			and frame_before.get("allocation") == "created" and frame_after.get("allocation") == "created" \
			and frame_before.get("submission") == "enqueued" and frame_after.get("submission") == "enqueued" \
			and typeof(frame_before.get("encoded_in_epoch")) == TYPE_INT and int(frame_before.encoded_in_epoch) >= 5 \
			and typeof(frame_after.get("encoded_in_epoch")) == TYPE_INT \
			and int(frame_after.encoded_in_epoch) >= int(frame_before.encoded_in_epoch) \
			and typeof(frame_before.get("requested_epoch")) == TYPE_INT and int(frame_before.requested_epoch) > 0 \
			and frame_before.get("requested_epoch") == frame_after.get("requested_epoch") \
			and frame_before.get("encoded_epoch") == frame_before.get("requested_epoch") \
			and frame_after.get("encoded_epoch") == frame_before.get("requested_epoch") \
			and gpu_before.get("frame_generation") == frame_before.generation and gpu_after.get("frame_generation") == frame_before.generation \
			and gpu_before.get("current_frame_epoch") == frame_before.requested_epoch \
			and gpu_after.get("current_frame_epoch") == frame_before.requested_epoch \
			and _frame_role_valid(frame_role_before, int(frame_before.requested_epoch)) \
			and _frame_role_valid(frame_role_after, int(frame_before.requested_epoch)) \
			and _frame_roles_advance(frame_role_before, frame_role_after)
	if not error_free or not output_ready or not frame_scope_valid:
		_clear_frame_proof()
		return sdk
	# The GPU observation ticket is recorded before the callback increments
	# encoded_in_epoch. Freeze a ticket read after the fifth CPU encode; later
	# polls must observe that ticket (or a later one) actually complete.
	var barrier_scope := {"source_id": _source_id, "viewport_generation": int(gpu_before.viewport_generation),
		"observation_generation": int(gpu_before.observation_generation),
		"reset_serial": int(gpu_before.current_reset_requested_serial),
		"frame_generation": int(frame_before.generation), "epoch": int(frame_before.requested_epoch)}
	if _frame_ticket_barrier.is_empty() or _frame_ticket_barrier.get("scope") != barrier_scope:
		_clear_frame_proof()
		_frame_ticket_barrier = {"scope": barrier_scope, "ticket": int(frame_role_before.encoded.ticket)}
	sdk["gpu_warmup_barrier_ticket"] = int(_frame_ticket_barrier.ticket)
	if error_free and output_ready and frame_scope_valid and not _last_frame_proof.is_empty() \
			and _last_frame_proof.get("proof_generation") == frame_before.generation \
			and _last_frame_proof.get("current_epoch") == frame_after.get("requested_epoch"):
		sdk.merge(_last_frame_proof, true)
		sdk["ready"] = false
		sdk["gpu_completed"] = false
	var frame_gpu: Variant = gpu_before.get("frame_interpolation")
	if not frame_gpu is Dictionary:
		return sdk
	var completed: Variant = frame_gpu.get("completed")
	var encoded: Variant = frame_gpu.get("encoded")
	if not completed is Dictionary or not encoded is Dictionary \
			or typeof(completed.get("succeeded")) != TYPE_BOOL or not completed.succeeded \
			or typeof(completed.get("error_present")) != TYPE_BOOL or completed.error_present \
			or typeof(completed.get("ticket")) != TYPE_INT or typeof(encoded.get("ticket")) != TYPE_INT \
			or typeof(completed.get("render_frame")) != TYPE_INT or typeof(encoded.get("render_frame")) != TYPE_INT \
			or typeof(completed.get("epoch")) != TYPE_INT or typeof(encoded.get("epoch")) != TYPE_INT \
			or int(completed.ticket) < int(_frame_ticket_barrier.ticket) \
			or completed.get("epoch") != encoded.get("epoch") \
			or completed.get("epoch") != frame_before.requested_epoch:
		return sdk
	_last_frame_proof = {"proof_generation": int(frame_before.generation),
		"current_epoch": int(frame_after.requested_epoch), "epoch": int(completed.epoch),
		"frame": int(completed.render_frame), "gpu_ticket": int(completed.ticket),
		"encoded_in_epoch": int(frame_before.encoded_in_epoch)}
	sdk.merge(_last_frame_proof, true)
	sdk["ready"] = true
	sdk["gpu_completed"] = true
	return sdk


func _clear_frame_proof() -> void:
	_last_frame_proof = {}
	_frame_ticket_barrier = {}


func _set_real(enabled: bool) -> void:
	if _real_on != enabled and _api_available and _rid.is_valid():
		_backend.call("viewport_set_real_gpu_observation_requested", _rid, enabled)
		_real_on = enabled
		if not enabled:
			_real_generation = 0
			_busy_retry_at = 0


func _set_gpu(enabled: bool) -> void:
	if _gpu_on != enabled and _api_available and _rid.is_valid():
		_backend.call("viewport_set_metalfx_gpu_observation_requested", _rid, enabled)
		_gpu_on = enabled
		if not enabled:
			_clear_frame_proof()


func _set_producer(enabled: bool) -> void:
	if _producer_on != enabled and _api_available and _rid.is_valid():
		_backend.call("viewport_set_metalfx_frame_requested", _rid, enabled)
		_producer_on = enabled
		if not enabled:
			_clear_frame_proof()


func _set_composition(enabled: bool) -> void:
	if _composition_on != enabled and _api_available and _rid.is_valid():
		_backend.call("viewport_set_metalfx_frame_composition_requested", _rid, enabled)
		_composition_on = enabled


func _apply(decision: Dictionary) -> void:
	var real: bool = decision.get("observer_requested") == true
	var gpu: bool = decision.get("metalfx_gpu_observer_requested") == true
	var producer: bool = decision.get("frame_producer_requested") == true
	var composition: bool = decision.get("attempt_renderer_gated_composition") == true
	if not composition: _set_composition(false)
	if not producer: _set_producer(false)
	if not gpu: _set_gpu(false)
	if not real: _set_real(false)
	if real: _set_real(true)
	if gpu: _set_gpu(true)
	if producer: _set_producer(true)
	if composition: _set_composition(true)


func _disable_all() -> void:
	_set_composition(false)
	_set_producer(false)
	_set_gpu(false)
	_set_real(false)


func _set_status(value: Dictionary) -> void:
	var viewport: Variant = _view.get_ref() if _view != null else null
	if is_instance_valid(viewport):
		if _diagnostics_enabled:
			if _diagnostic_transitions == null:
				_diagnostic_transitions = []
			var state := str(value.get("state", "")).left(80)
			var reason := str(value.get("reason", "")).left(160)
			if _diagnostic_transitions.is_empty() or _diagnostic_transitions.back().state != state \
					or _diagnostic_transitions.back().reason != reason:
				_diagnostic_transitions.append({"time_usec": _now(), "state": state,
					"reason": reason, "source_epoch": _source_epoch})
				if _diagnostic_transitions.size() > DIAGNOSTIC_TRANSITIONS:
					_diagnostic_transitions.pop_front()
			value["transition_history"] = _diagnostic_transitions.duplicate(true)
		viewport.set_meta(STATUS_META, value)


func shutdown() -> void:
	if _closed:
		return
	_disable_all()
	var simulation: Variant = _simulation.get_ref() if _simulation != null else null
	var callback := Callable(self, "_simulation_pause_changed")
	if is_instance_valid(simulation) and simulation.has_signal("paused_changed") and simulation.is_connected("paused_changed", callback):
		simulation.disconnect("paused_changed", callback)
	_simulation = null
	_closed = true
	_source_epoch += 1
	var viewport: Variant = _view.get_ref() if _view != null else null
	if is_instance_valid(viewport):
		if viewport is Window and viewport.size_changed.is_connected(_window_resized):
			viewport.size_changed.disconnect(_window_resized)
		var owner: Variant = viewport.get_meta(OWNER_META) if viewport.has_meta(OWNER_META) else null
		if owner is WeakRef and owner.get_ref() == self:
			viewport.remove_meta(OWNER_META)
			viewport.remove_meta(STATUS_META)
		elif owner == null and viewport.has_meta(STATUS_META):
			viewport.remove_meta(STATUS_META)


func _exit_tree() -> void:
	shutdown()
