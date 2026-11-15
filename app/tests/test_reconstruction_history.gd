extends SceneTree

const Reconstruction := preload("res://render/reconstruction.gd")

class Backend extends RefCounted:
	var requests: Array[RID] = []
	func viewport_request_temporal_history_reset(viewport: RID) -> void:
		requests.append(viewport)

class MetalBackend extends RefCounted:
	var status := {}
	var response: Variant = {}
	var requests: Array[RID] = []
	var status_reads := 0
	var post_status_patch := {}
	func viewport_get_metalfx_status(_viewport: RID) -> Dictionary:
		status_reads += 1
		return status.duplicate(true)
	func viewport_request_temporal_history_reset(viewport: RID) -> Variant:
		requests.append(viewport)
		if typeof(response) == TYPE_DICTIONARY and response.get("accepted") == true \
				and typeof(response.get("serial")) == TYPE_INT:
			status["reset_requested_serial"] = response.serial
		status.merge(post_status_patch, true)
		return response

var _checks := 0
var _failures := 0

func _initialize() -> void:
	var backend := Backend.new()
	var first := SubViewport.new()
	var second := SubViewport.new()
	first.set_meta(Reconstruction.POLICY_META, {"provider": "dlss"})
	second.set_meta(Reconstruction.POLICY_META, {"provider": "dlss"})
	_check("null viewport is harmless", not Reconstruction.request_history_reset(null, "cut", backend))
	_check("unsupported API leaves the renderer alone", not Reconstruction.request_history_reset(first, "camera_view", RefCounted.new()))
	var receipt: Dictionary = first.get_meta(Reconstruction.HISTORY_RESET_META)
	_check("unsupported build distinguishes notification from submission", receipt.notifications == 1 and receipt.submitted == 0)
	_check("active DLSS submits a viewport-scoped request", Reconstruction.request_history_reset(first, "camera_view", backend))
	_check("request carries the actual viewport RID", backend.requests == [first.get_viewport_rid()])
	_check("second viewport can independently request a reset", Reconstruction.request_history_reset(second, "flight_reset", backend))
	_check("viewport identities are not conflated", backend.requests == [first.get_viewport_rid(), second.get_viewport_rid()])
	var first_receipt: Dictionary = first.get_meta(Reconstruction.HISTORY_RESET_META)
	var second_receipt: Dictionary = second.get_meta(Reconstruction.HISTORY_RESET_META)
	_check("notification counts stay scoped", first_receipt.notifications == 2 and second_receipt.notifications == 1)
	_check("submission counts are distinct from SDK success", first_receipt.submitted == 1 and second_receipt.submitted == 1
		and not first_receipt.has("accepted") and not first_receipt.has("successful"))
	_check("reasons stay scoped", first_receipt.last_reason == "camera_view" and second_receipt.last_reason == "flight_reset")
	first.set_meta(Reconstruction.POLICY_META, {"provider": "native"})
	_check("Native does not submit a DLSS request", not Reconstruction.request_history_reset(first, "native_cut", backend))
	first.set_meta(Reconstruction.POLICY_META, {"provider": "fsr2"})
	_check("FSR2 does not submit an unsupported history request", not Reconstruction.request_history_reset(first, "fsr_cut", backend))
	_check("inactive providers leave backend call count unchanged", backend.requests.size() == 2)
	first.set_meta(Reconstruction.POLICY_META, {"provider": "dlss"})
	Reconstruction.request_history_reset(first, "x".repeat(200), backend)
	_check("diagnostic reason is bounded", str(first.get_meta(Reconstruction.HISTORY_RESET_META).last_reason).length() == 80)
	var description := Reconstruction.describe(first)
	_check("description reports API presence honestly", description.history_reset.api_available == RenderingServer.has_method(Reconstruction.HISTORY_RESET_METHOD))
	description.history_reset.notifications = -1
	_check("description does not expose mutable viewport bookkeeping", first.get_meta(Reconstruction.HISTORY_RESET_META).notifications > 0)
	_test_metalfx_reset()
	_test_metalfx_refusal_diagnostics()
	first.free()
	second.free()
	print("reconstruction history: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_metalfx_reset() -> void:
	# Injected status exercises the reducer without assigning a MetalFX enum on
	# the headless host. These checks do not prove SDK or GPU execution.
	var view := SubViewport.new()
	var other := SubViewport.new()
	var mode := int(view.scaling_3d_mode)
	var caps := {"high": false, "metalfx_temporal": true, "metalfx_temporal_mode": 202,
		"metalfx_min_scale": 0.5, "metalfx_max_scale": 1.0}
	var saved := {"reconstruction": "metalfx_temporal_85", "msaa_3d": Viewport.MSAA_8X}
	var backend := MetalBackend.new()
	backend.status = {"generation": 7, "requested_mode": mode, "configured_mode": mode,
		"render_buffers_available": true, "provider": "temporal", "allocation": "created", "submission": "enqueued",
		"reset_requested_serial": 0, "reset_submitted_serial": 0, "reset_encoded_serial": 0,
		"reset_gpu_completion": "unobserved", "temporal_attempts": 10}
	backend.response = {"accepted": true, "generation": 7, "serial": 1, "reset_request_attempt": 10}
	var request := Reconstruction._request_metalfx_reset(view, backend, mode, 7)
	_check("injected matching request is pending", request.get("state") == "pending"
		and request.get("serial") == 1 and backend.requests == [view.get_viewport_rid()])
	var receipt := {"notifications": 1, "submitted": 1}
	Reconstruction._update_metalfx_reset_receipt(receipt, request, "pending")
	view.set_meta(Reconstruction.HISTORY_RESET_META, receipt)
	view.set_meta(Reconstruction.METALFX_RESET_META, request)
	view.set_meta(Reconstruction.CONFIG_META, saved.duplicate(true))
	view.set_meta(Reconstruction.POLICY_META, {"provider": "metalfx_temporal", "requested_provider": "metalfx_temporal"})
	var scope := {"generation": 7}
	for _i: int in 100:
		Reconstruction._poll_metalfx_reset(view, backend.status, mode, scope, caps)
	_check("unchanged render attempts never time out a paused view",
		view.has_meta(Reconstruction.METALFX_RESET_META) and view.get_meta(Reconstruction.HISTORY_RESET_META).pending)
	backend.status.temporal_attempts = 11
	backend.status.reset_submitted_serial = 1
	_check("one injected RD admission remains pending", not Reconstruction._poll_metalfx_reset(view, backend.status, mode, scope, caps)
		and view.get_meta(Reconstruction.HISTORY_RESET_META).pending)
	backend.status.reset_encoded_serial = 1
	_check("matching injected CPU encode closes pending", not Reconstruction._poll_metalfx_reset(view, backend.status, mode, scope, caps)
		and not view.has_meta(Reconstruction.METALFX_RESET_META))
	var encoded: Dictionary = view.get_meta(Reconstruction.HISTORY_RESET_META)
	_check("receipt never claims GPU completion", encoded.encoded and not encoded.pending
		and encoded.reset_submitted_serial == 1 and encoded.reset_encoded_serial == 1 and encoded.gpu_completion == "unobserved")
	Reconstruction._expire_metalfx_reset_receipt(view, {"generation": 8})
	_check("an old encoded receipt does not survive a new generation",
		view.get_meta(Reconstruction.HISTORY_RESET_META).reset_state == "superseded"
		and not view.get_meta(Reconstruction.HISTORY_RESET_META).encoded)

	# Rapid cuts coalesce to the newest serial. A late older encode cannot complete it.
	backend.response = {"accepted": true, "generation": 7, "serial": 2, "reset_request_attempt": 11}
	var older := Reconstruction._request_metalfx_reset(view, backend, mode, 7)
	backend.response = {"accepted": true, "generation": 7, "serial": 3, "reset_request_attempt": 11}
	var newer := Reconstruction._request_metalfx_reset(view, backend, mode, 7)
	_check("two cuts retain the newest injected serial", older.get("serial") == 2 and newer.get("serial") == 3)
	view.set_meta(Reconstruction.METALFX_RESET_META, newer)
	backend.status.reset_submitted_serial = 2
	backend.status.reset_encoded_serial = 2
	_check("older injected completion cannot close the newer cut",
		not Reconstruction._poll_metalfx_reset(view, backend.status, mode, scope, caps)
		and view.get_meta(Reconstruction.HISTORY_RESET_META).pending)
	backend.status.reset_submitted_serial = 3
	backend.status.reset_encoded_serial = 3
	_check("newest injected completion is recorded", not Reconstruction._poll_metalfx_reset(view, backend.status, mode, scope, caps)
		and view.get_meta(Reconstruction.HISTORY_RESET_META).serial == 3 and view.get_meta(Reconstruction.HISTORY_RESET_META).encoded)

	# A stale generation or mismatched viewport must restore Native and its saved AA.
	backend.response = {"accepted": true, "generation": 7, "serial": 4, "reset_request_attempt": 11}
	request = Reconstruction._request_metalfx_reset(view, backend, mode, 7)
	for invalid: Array in [["generation", 6], ["requested_mode", mode + 1], ["configured_mode", -1],
			["render_buffers_available", false], ["provider", "spatial"], ["allocation", "not_attempted"],
			["submission", "enqueue_failed"], ["reset_requested_serial", 3], ["reset_submitted_serial", -1],
			["reset_encoded_serial", 5], ["reset_gpu_completion", "completed"], ["temporal_attempts", 10],
			["temporal_attempts", 11.0]]:
		var corrupted := backend.status.duplicate(true)
		corrupted[invalid[0]] = invalid[1]
		_check("malformed or stale injected acknowledgement is unavailable: " + str(invalid),
			Reconstruction._metalfx_reset_state(corrupted, request) == "unavailable")
	var incoherent := backend.status.duplicate(true)
	incoherent.reset_encoded_serial = 4
	_check("encoding without matching RD admission cannot acknowledge the cut",
		Reconstruction._metalfx_reset_state(incoherent, request) == "pending")
	view.set_meta(Reconstruction.METALFX_RESET_META, request)
	view.scaling_3d_scale = 0.85
	view.msaa_3d = Viewport.MSAA_DISABLED
	var stale := backend.status.duplicate(true)
	stale.generation = 8
	_check("stale injected generation restores Native and AA", Reconstruction._poll_metalfx_reset(view, stale, mode, scope, caps)
		and view.scaling_3d_scale == 1.0 and view.msaa_3d == Viewport.MSAA_8X
		and view.get_meta(Reconstruction.RUNTIME_FAILURE_META).reason == "history_reset_unavailable")
	_check("stale completion is not reported encoded", not view.get_meta(Reconstruction.HISTORY_RESET_META).encoded
		and view.get_meta(Reconstruction.HISTORY_RESET_META).reset_state == "unavailable")
	view.remove_meta(Reconstruction.RUNTIME_FAILURE_META)
	view.set_meta(Reconstruction.CONFIG_META, saved.duplicate(true))
	view.set_meta(Reconstruction.POLICY_META, {"provider": "metalfx_temporal", "requested_provider": "metalfx_temporal"})
	request.rid = other.get_viewport_rid()
	view.set_meta(Reconstruction.METALFX_RESET_META, request)
	_check("another viewport cannot acknowledge this reset", Reconstruction._poll_metalfx_reset(view, backend.status, mode, scope, caps))
	view.remove_meta(Reconstruction.RUNTIME_FAILURE_META)
	view.set_meta(Reconstruction.CONFIG_META, saved.duplicate(true))
	view.set_meta(Reconstruction.POLICY_META, {"provider": "metalfx_temporal", "requested_provider": "metalfx_temporal"})
	request.rid = view.get_viewport_rid()
	view.set_meta(Reconstruction.METALFX_RESET_META, request)
	backend.status.temporal_attempts = 12
	_check("one actual attempt does not time out", not Reconstruction._poll_metalfx_reset(view, backend.status, mode, scope, caps))
	backend.status.temporal_attempts = 13
	_check("two actual attempts without encoding roll back", Reconstruction._poll_metalfx_reset(view, backend.status, mode, scope, caps)
		and view.get_meta(Reconstruction.RUNTIME_FAILURE_META).reason == "history_reset_unavailable")

	# Rejected and malformed receipts never admit a reset.
	for bad: Variant in [null, {}, {"accepted": false, "generation": 7, "serial": 0, "reset_request_attempt": 13},
			{"accepted": true, "generation": 8, "serial": 5, "reset_request_attempt": 13},
			{"accepted": true, "generation": 7, "serial": "5", "reset_request_attempt": 13},
			{"accepted": true, "generation": 7, "serial": 5, "reset_request_attempt": -1}]:
		backend.response = bad
		_check("rejected or malformed injected receipt stays unavailable", Reconstruction._request_metalfx_reset(view, backend, mode, 7).is_empty())
	var native_status := {"generation": 8, "requested_mode": 4, "configured_mode": Viewport.SCALING_3D_MODE_BILINEAR,
		"render_buffers_available": true}
	_check("configured Bilinear downgrade is distinguished from pending buffers",
		Reconstruction._metalfx_configured_native(native_status, 4, 8)
		and not Reconstruction._metalfx_configured_native(native_status, 4, 9))
	view.free()
	other.free()


func _test_metalfx_refusal_diagnostics() -> void:
	var view := SubViewport.new()
	var mode := int(view.scaling_3d_mode)
	var backend := MetalBackend.new()
	var ready := {"generation": 7, "requested_mode": mode, "configured_mode": mode,
		"render_buffers_available": true, "provider": "temporal", "allocation": "created", "submission": "enqueued",
		"reset_requested_serial": 0, "reset_submitted_serial": 0, "reset_encoded_serial": 0,
		"reset_gpu_completion": "unobserved", "temporal_attempts": 10}
	backend.status = ready.duplicate(true)
	backend.status.render_buffers_available = false
	backend.status.provider = "p".repeat(200)
	backend.status["unrelated"] = "x".repeat(10000)
	var cold := {}
	_check("unready status is not submitted", Reconstruction._request_metalfx_reset(view, backend, mode, 7, cold).is_empty()
		and backend.requests.is_empty() and backend.status_reads == 1)
	_check("unready status has a bounded diagnostic", cold.get("reason") == "before_status_not_ready"
		and cold.before_status.render_buffers_available == false and cold.before_status.provider.length() == 64
		and not cold.before_status.has("unrelated"))
	backend.status = ready.duplicate(true)
	backend.response = {"accepted": false, "generation": 7, "serial": 0, "reset_request_attempt": 10}
	var refused := {}
	_check("rejected reset remains unaccepted", Reconstruction._request_metalfx_reset(view, backend, mode, 7, refused).is_empty()
		and backend.requests.size() == 1 and backend.status_reads == 2)
	_check("backend rejection is distinct from readiness", refused.get("reason") == "reset_rejected"
		and refused.reset_receipt.accepted == false and refused.before_status.allocation == "created")
	backend.status = ready.duplicate(true)
	backend.response = {"accepted": true, "generation": 7, "serial": "s".repeat(200), "reset_request_attempt": 10}
	var malformed := {}
	_check("malformed reset receipt stays unavailable", Reconstruction._request_metalfx_reset(view, backend, mode, 7, malformed).is_empty()
		and malformed.get("reason") == "reset_receipt_malformed" and malformed.reset_receipt.serial.length() == 64)
	backend.status = ready.duplicate(true)
	backend.response = {"accepted": true, "generation": 7, "serial": 1, "reset_request_attempt": 10}
	backend.post_status_patch = {"generation": 8}
	var inconsistent := {}
	var reads_before := backend.status_reads
	_check("inconsistent post-status stays unavailable", Reconstruction._request_metalfx_reset(view, backend, mode, 7, inconsistent).is_empty()
		and inconsistent.get("reason") == "post_status_unavailable" and inconsistent.before_status.generation == 7
		and inconsistent.after_status.generation == 8 and backend.status_reads == reads_before + 2)
	var invalid := Reconstruction._metalfx_diagnostic_fields({"generation": [1], "provider": {}, "other": 5},
		Reconstruction.METALFX_RESET_STATUS_FIELDS)
	_check("diagnostics omit extra fields and bound invalid values", invalid == {"generation": "invalid_type", "provider": "invalid_type"})
	view.free()


func _check(label: String, valid: bool) -> void:
	_checks += 1
	if not valid:
		_failures += 1
		printerr("FAIL ", label)
