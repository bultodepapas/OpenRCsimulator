extends SceneTree

const Main := preload("res://main.gd")
const Config := preload("res://failures/config.gd")

class NoticeSession extends Node:
	var observed: Dictionary = {active = false}
	var queries := 0
	func failure_status() -> Dictionary:
		queries += 1
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
	check("healthy flight allocates no notice", main._failure_notice == null and session.queries == 1)
	session.observed = {active = true, label = "Ailerons jammed.", hint = "Use gentle inputs."}
	main.failure_notifications = false
	var before := session.queries
	for i in 3:
		main._update_failure_notice()
	check("disabled notices skip status queries and card allocation", session.queries == before and main._failure_notice == null)
	main.failure_notifications = true
	main.set_overlays_visible(false)
	before = session.queries
	for i in 3:
		main._update_failure_notice()
	check("menu-hidden notices skip status queries and card allocation", session.queries == before and main._failure_notice == null)
	main.set_overlays_visible(true)
	main._update_failure_notice()
	check("committed event presents label", main._failure_notice != null and main._failure_notice.visible and main._failure_label.text.contains("Ailerons jammed."))
	session.observed.label = "Rudder jammed."
	main._update_failure_notice()
	check("visible notice refreshes changed status", main._failure_label.text.contains("Rudder jammed."))
	main.set_overlays_visible(false)
	session.observed.label = "Elevator jammed."
	before = session.queries
	for i in 3:
		main._update_failure_notice()
	check("menu hides an existing card without repeated queries", not main._failure_notice.visible and session.queries == before)
	main.set_overlays_visible(true) # May query status once to establish immediate visibility.
	main._update_failure_notice()
	check("revealing the card refreshes the latest label", main._failure_notice.visible and main._failure_label.text.contains("Elevator jammed."))
	main.failure_notifications = false
	session.observed.label = "Throttle limited."
	before = session.queries
	for i in 3:
		main._update_failure_notice()
	check("disabling an existing card hides it without repeated queries", not main._failure_notice.visible and session.queries == before)
	main.failure_notifications = true
	main._update_failure_notice()
	check("re-enabled notice refreshes the latest label", main._failure_notice.visible and main._failure_label.text.contains("Throttle limited."))
	main.set_overlays_visible(false)
	session.observed.active = false
	before = session.queries
	for i in 3:
		main._update_failure_notice()
	check("hidden reset skips status queries", session.queries == before and not main._failure_notice.visible)
	main.set_overlays_visible(true)
	main._update_failure_notice()
	check("reset while hidden keeps the card hidden when revealed", not main._failure_notice.visible)
	session.observed.active = true
	main._update_failure_notice()
	check("a later active event is visible", main._failure_notice.visible)
	main.session = null
	main._update_failure_notice()
	check("missing session hides an old incident", not main._failure_notice.visible)
	main.free()
	session.free()
	print("failure launch/notice: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL: ", label)
