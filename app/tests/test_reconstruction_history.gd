extends SceneTree

const Reconstruction := preload("res://render/reconstruction.gd")

class Backend extends RefCounted:
	var requests: Array[RID] = []
	func viewport_request_temporal_history_reset(viewport: RID) -> void:
		requests.append(viewport)

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
	first.free()
	second.free()
	print("reconstruction history: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check(label: String, valid: bool) -> void:
	_checks += 1
	if not valid:
		_failures += 1
		printerr("FAIL ", label)
