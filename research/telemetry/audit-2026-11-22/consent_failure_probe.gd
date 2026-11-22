# Run only with a synthetic enabled-grant file inside a non-writable temporary directory.
# No real user profile, receiver, or network sender is used.
extends SceneTree

const Service := preload("res://telemetry/telemetry_service.gd")
const Store := preload("res://telemetry/telemetry_consent_store.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")

func _initialize() -> void:
	var path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--consent-path="):
			path = arg.trim_prefix("--consent-path=")
	if path == "":
		printerr("A synthetic --consent-path is required")
		quit(2)
		return
	var first := _service(path)
	first.refresh()
	var before: String = first.state
	var saved_error: int = first.disable()
	var after: String = first.state
	var persisted: Dictionary = Store.load_choice(path)
	first.free()
	var next := _service(path)
	next.refresh()
	var reopened: String = next.state
	next.free()
	print("CONSENT_FAILURE_PROBE ", JSON.stringify({"before": before, "after_disable": after,
		"save_error": saved_error, "persisted_choice": persisted.choice, "next_instance": reopened}))
	if before == "on" and after == "off" and saved_error != OK and persisted.choice == "enabled" and reopened == "on":
		print("REPRODUCED: failed revocation leaves an enabled grant that restarts telemetry")
		quit(0)
	else:
		printerr("INCONCLUSIVE: expected permission failure was not reproduced")
		quit(1)

func _service(path: String) -> Node:
	var s := Service.new()
	s.release = {"ok": true, "reason": "qualification", "qualification": true,
		"notice": Contract.NOTICE_VERSION, "release_id": "v0.3.2", "channel": "stable",
		"endpoint": "http://127.0.0.1:9/v1/batches", "operator": "Synthetic audit", "contact": "-"}
	s.interactive = true
	s.locale = "en"
	s.consent_path = path
	s.clock_usec = func() -> int: return 0
	s.utc_day = func() -> String: return "2026-11-22"
	s.hardware_facts = {"os": "Linux", "architecture": "x86_64", "cpu": "Synthetic",
		"threads": 4, "memory_bytes": 4294967296, "gpu": "Synthetic", "renderer": "forward_plus", "driver": "vulkan"}
	s.context_provider = func() -> Dictionary: return {"window_size": Vector2i(1920, 1080), "vsync": 1}
	return s
