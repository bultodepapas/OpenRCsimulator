extends Node

const PerformanceProbe := preload("res://research/glow-engines/performance_probe.gd")


func _ready() -> void:
	var probe: SceneTree = PerformanceProbe.new()
	probe.runtime_pack_path = "embedded"
	probe.runtime_mode = "wrapped_exported_release"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--repo-root="):
			probe.repository_root_override = arg.trim_prefix("--repo-root=")
		elif arg.begins_with("--runtime-mode="):
			probe.runtime_mode = arg.trim_prefix("--runtime-mode=")
	probe._initialize()
	if not probe.report.has("summary"):
		printerr("Wrapped release performance probe did not produce a summary")
		probe.free()
		get_tree().quit(1)
		return
	print("WRAPPED_RELEASE_FEATURES debug=", OS.has_feature("debug"), " release=", OS.has_feature("release"))
	print("WRAPPED_RELEASE_SUMMARY=", JSON.stringify(probe.report.summary, "\t", true, true))
	probe.free()
	get_tree().quit(0)
