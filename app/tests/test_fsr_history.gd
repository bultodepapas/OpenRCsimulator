extends SceneTree

const Reconstruction := preload("res://render/reconstruction.gd")

class Backend extends RefCounted:
	var providers: Variant = PackedStringArray(["dlss", "fsr2", "fsr3"])
	var requests: Array[RID] = []
	func viewport_request_temporal_history_reset(viewport: RID) -> void:
		requests.append(viewport)
	func get_temporal_history_reset_providers() -> Variant:
		return providers

var _checks := 0
var _failures := 0

func _initialize() -> void:
	var backend := Backend.new()
	var view := SubViewport.new()
	for provider: String in ["fsr2", "fsr3", "dlss"]:
		view.set_meta(Reconstruction.POLICY_META, {"provider": provider})
		_check(provider + " submits on explicitly wired engine", Reconstruction.request_history_reset(view, "camera_cut", backend))
	_check("each provider submits the actual viewport", backend.requests == [view.get_viewport_rid(), view.get_viewport_rid(), view.get_viewport_rid()])
	var receipt: Dictionary = view.get_meta(Reconstruction.HISTORY_RESET_META)
	_check("submission is not successful SDK acknowledgement", receipt.submitted == 3 and not receipt.has("successful"))
	backend.providers = PackedStringArray(["dlss"])
	view.set_meta(Reconstruction.POLICY_META, {"provider": "fsr2"})
	_check("DLSS-only engine rejects FSR2 despite shared API", not Reconstruction.request_history_reset(view, "cut", backend))
	view.set_meta(Reconstruction.POLICY_META, {"provider": "fsr3"})
	_check("DLSS-only engine rejects FSR3", not Reconstruction.request_history_reset(view, "cut", backend))
	backend.providers = PackedStringArray()
	view.set_meta(Reconstruction.POLICY_META, {"provider": "dlss"})
	_check("explicit empty provider list overrides legacy DLSS assumption", not Reconstruction.request_history_reset(view, "cut", backend))
	backend.providers = "fsr3"
	view.set_meta(Reconstruction.POLICY_META, {"provider": "fsr3"})
	_check("malformed provider list does not admit string membership", not Reconstruction.request_history_reset(view, "cut", backend))
	backend.providers = PackedStringArray(["dlss", "fsr2", "fsr3"])
	view.set_meta(Reconstruction.POLICY_META, {"provider": "native"})
	_check("Native does not request temporal reset", not Reconstruction.request_history_reset(view, "cut", backend))
	_check("unsupported calls never reach backend", backend.requests.size() == 3)
	var saved := {"reconstruction": "fsr2_quality", "msaa_3d": 3, "fsr2_sharpness": 0.4}
	var original := saved.duplicate(true)
	var caps := {"high": true, "fsr2": true, "fsr2_mode": Viewport.SCALING_3D_MODE_FSR2}
	view.set_meta(Reconstruction.POLICY_META, {"provider": "fsr2", "requested_provider": "fsr2"})
	view.set_meta(Reconstruction.CONFIG_META, saved.duplicate(true))
	view.scaling_3d_scale = 2.0 / 3.0
	view.msaa_3d = Viewport.MSAA_DISABLED
	if not RenderingServer.has_method("get_fsr2_status"):
		_check("stock engine without FSR2 status keeps the active request",
			not Reconstruction.guard_runtime_failure(view, {}, caps)
			and is_equal_approx(view.scaling_3d_scale, 2.0 / 3.0)
			and view.msaa_3d == Viewport.MSAA_DISABLED)
	_check("healthy FSR2 status does not trigger rollback",
		not Reconstruction.guard_runtime_failure(view, {"backend_failed": false}, caps))
	var failed := {"backend_failed": true, "last_return_code": -2147483635}
	_check("latched FSR2 failure restores Native scale and saved MSAA",
		Reconstruction.guard_runtime_failure(view, failed, caps)
		and view.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR
		and view.scaling_3d_scale == 1.0 and view.msaa_3d == Viewport.MSAA_8X)
	var failure: Dictionary = view.get_meta(Reconstruction.RUNTIME_FAILURE_META)
	var policy: Dictionary = view.get_meta(Reconstruction.POLICY_META)
	_check("FSR2 failure preserves request and backend evidence",
		policy.requested == "fsr2_quality" and policy.effective == "native"
		and policy.fallback_reason == "fsr2_runtime_failure" and failure.provider == "fsr2"
		and failure.backend.last_return_code == failed.last_return_code
		and saved == original and view.get_meta(Reconstruction.CONFIG_META) == original)
	_check("FSR2 rollback is idempotent", not Reconstruction.guard_runtime_failure(view, failed, caps))
	view.free()
	print("FSR history: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check(label: String, valid: bool) -> void:
	_checks += 1
	if not valid:
		_failures += 1
		printerr("FAIL ", label)
