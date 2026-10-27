## VQ-01c / NK-0 release-template host for session_probe.gd: export templates ignore --script, so this main
## scene runs the probe's own _initialize/_run and exits with its status.
extends Node

const SessionProbe := preload("res://perf_probe/session_probe.gd")

var _probe: Object


func _ready() -> void:
	_probe = SessionProbe.new()
	_probe._initialize() # parses the user arguments and defers _run
	call_deferred("_finish") # deferred calls run in order, so this follows _run


func _finish() -> void:
	var failure: String = str(_probe.get("_failure"))
	print("RELEASE_SESSION_PROBE ", "complete" if failure.is_empty() else failure,
		" debug=", OS.is_debug_build(), " release=", OS.has_feature("template_release"))
	get_tree().quit(0 if failure.is_empty() else 1)
