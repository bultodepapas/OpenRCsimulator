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
	view.free()
	print("FSR history: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check(label: String, valid: bool) -> void:
	_checks += 1
	if not valid:
		_failures += 1
		printerr("FAIL ", label)
