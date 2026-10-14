extends SceneTree

const Main := preload("res://main.gd")
const Config := preload("res://failures/config.gd")

class NoticeSession extends Node:
	var observed: Dictionary = {active = false}
	func failure_status() -> Dictionary:
		return observed.duplicate(true)

var checks := 0
var failed := 0

func _initialize() -> void:
	var main := Main.new()
	var defaults: Dictionary = main._failure_options({})
	check("direct launch defaults to off", defaults.ok and defaults.config == Config.defaults() and defaults.seed == 0)
	for value in ["-1", "101", "10.5", "yes", "", true, 90]:
		check("invalid CLI probability rejected: %s" % str(value), not main._failure_options({failures = value}).ok)
	for value in ["-1", "4294967296", "1.5", "abc", true]:
		check("invalid CLI seed rejected: %s" % str(value), not main._failure_options({"failure-seed" = value}).ok)
	for flag in ["catastrophic", "failure-notices"]:
		check("invalid boolean spelling rejected", not main._failure_options({flag: "true"}).ok)
	var requested := {"failures": "100", "failure-seed": "223", "catastrophic": "off", "failure-notices": "off"}
	var resolved: Dictionary = main._failure_options(requested)
	check("technical launch fully resolves", resolved.ok and resolved.seed == 223 and resolved.config.probability_percent == 100 and not resolved.config.notify)
	check("resolution retains launch preferences", main.failure_config == Config.defaults())
	check("same explicit seed resolves exactly", resolved == main._failure_options(requested))
	main.failure_config.probability_percent = 90
	main.failure_seed = 158
	check("Home settings honored without reading preferences", main._failure_options({}).config.probability_percent == 90 and main._failure_options({}).seed == 158)
	var session := NoticeSession.new()
	main.session = session
	main._update_failure_notice()
	check("healthy flight allocates no notice", main._failure_notice == null)
	session.observed = {active = true, label = "Ailerons jammed.", hint = "Use gentle inputs."}
	main.failure_notifications = false
	main._update_failure_notice()
	check("hidden notices do not allocate card", main._failure_notice == null)
	main.failure_notifications = true
	main._update_failure_notice()
	check("committed event presents label", main._failure_notice != null and main._failure_notice.visible and main._failure_label.text.contains("Ailerons jammed."))
	main._failure_overlays_visible = false
	main._update_failure_notice()
	check("menu hides incident card", not main._failure_notice.visible)
	main._failure_overlays_visible = true
	session.observed.active = false
	main._update_failure_notice()
	check("reset hides old incident", not main._failure_notice.visible)
	main.free()
	session.free()
	print("failure launch/notice: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL: ", label)
