extends SceneTree

const Startup := preload("res://ui/startup.gd")
const Intro := preload("res://ui/brand_intro.gd")
const PREFS := "user://test_brand_startup.cfg"
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	if passed:
		print("ok  ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	check("interactive launch animates", Startup.should_animate("Windows", PackedStringArray()))
	check("headless launch bypasses intro", not Startup.should_animate("headless", PackedStringArray()))
	for arg in ["--quick-flight", "--input-report", "--trace=tmp/check.csv", "--vehicle=mt8-bisonte"]:
		check("technical route bypass: " + arg, not Startup.should_animate("Windows", PackedStringArray([arg])))
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 5)
	cfg.set_value("ui", "language", "es")
	cfg.save(PREFS)
	var display := ConfigFile.new()
	display.set_value("meta", "schema", 1)
	display.set_value("accessibility", "reduced_motion", true)
	display.save(PREFS + ".display")
	var original_hash := FileAccess.get_sha256(PREFS)
	var choices := Startup.read_presentation(PREFS)
	check("saved Spanish and reduced motion respected", choices.language == "es" and choices.reduced_motion)
	check("intro never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", 123)
	cfg.save(PREFS)
	display.set_value("accessibility", "reduced_motion", "false")
	display.save(PREFS + ".display")
	choices = Startup.read_presentation(PREFS)
	check("malformed values use defaults", choices.language == "en" and not choices.reduced_motion)
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute(PREFS + ".display")
	check("missing preferences use defaults", Startup.read_presentation(PREFS) == {"language": "en", "reduced_motion": false})
	var intro := Intro.new()
	root.add_child(intro)
	for resolution in [Vector2i(1920, 1080), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = resolution
		await process_frame
		check("intro fills viewport %s" % resolution, intro.size == Vector2(resolution))
	intro.seek(Intro.DURATION)
	await process_frame
	check("review/reduced motion frame remains still", not intro.playing and intro.elapsed == Intro.DURATION)
	var weak: WeakRef = weakref(intro)
	intro.queue_free()
	await process_frame
	check("presentation nodes released", weak.get_ref() == null)
	print("Brand startup: %d failed" % failures)
	quit(1 if failures else 0)
