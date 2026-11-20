extends SceneTree
## Refuse benchmark startup before normal Home, including on an unowned profile.


class RefusingObserver extends Node:
	static var freed := 0
	func prepare_startup() -> bool: return false
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE: freed += 1


class MissingMethodObserver extends Node:
	static var freed := 0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE: freed += 1


class WrongObserver extends RefCounted:
	func prepare_startup() -> bool: return true


class InvalidResultObserver extends Node:
	func prepare_startup() -> int: return 1


class AcceptedObserver extends Node:
	func prepare_startup() -> bool:
		name = "GodTestGuardAccepted"
		return true


class GuardStartup extends "res://ui/startup.gd":
	var mode := "noenv"
	var refused := 0
	var debug_checks := 0
	var loads := 0
	var continued := 0
	var package_calls := 0
	func _godtest_requested() -> bool:
		return mode != "noenv"
	func _godtest_debug_build() -> bool:
		debug_checks += 1
		return mode != "nondebug"
	func _godtest_script() -> Script:
		loads += 1
		match mode:
			"missing": return null
			"refused": return RefusingObserver
			"no_method": return MissingMethodObserver
			"wrong_type": return WrongObserver
			"invalid_result": return InvalidResultObserver
			"accepted": return AcceptedObserver
			"real": return super._godtest_script()
		return null
	func _refuse_godtest_startup() -> void:
		# The production method exits with ERR_INVALID_PARAMETER. The test keeps
		# its SceneTree alive so it can assert no later startup work was entered.
		refused += 1
	func _start_package_default_probe() -> bool:
		package_calls += 1
		return true
	func _animate_requested() -> bool:
		continued += 1
		return false
	func _package_flight_window_wait_requested() -> bool: return true
	func _package_flight_window_has_focus() -> bool: return false
	func _package_flight_window_can_draw() -> bool: return true


var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("ok  ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	var original_scene := current_scene
	var had_probe := OS.has_environment("OPENRC_PACKAGE_DEFAULT_PROBE")
	var old_probe := OS.get_environment("OPENRC_PACKAGE_DEFAULT_PROBE")
	OS.set_environment("OPENRC_PACKAGE_DEFAULT_PROBE", "1")
	for mode: String in ["nondebug", "missing", "refused", "no_method", "wrong_type", "invalid_result"]:
		var startup := GuardStartup.new()
		startup.mode = mode
		root.add_child(startup)
		_check(startup.refused == 1 and startup.continued == 0 and startup.package_calls == 0
			and startup.intro == null and startup._scene_job == null and current_scene == original_scene,
			mode + " refuses before the package probe, intro or scene handoff")
		if mode == "nondebug": _check(startup.loads == 0, "non-debug build never loads the benchmark script")
		startup.free()
	_check(RefusingObserver.freed == 1 and MissingMethodObserver.freed == 1,
		"refused observers are freed")
	if had_probe: OS.set_environment("OPENRC_PACKAGE_DEFAULT_PROBE", old_probe)
	else: OS.unset_environment("OPENRC_PACKAGE_DEFAULT_PROBE")

	var normal := GuardStartup.new()
	normal.mode = "noenv"
	root.add_child(normal)
	_check(normal.refused == 0 and normal.debug_checks == 0 and normal.loads == 0 and normal.continued == 1
		and normal.get_node_or_null("_PackageFlightWindowReadiness") != null,
		"without the benchmark environment the normal startup route continues")
	root.remove_child(normal)
	await process_frame
	normal.free()

	var accepted := GuardStartup.new()
	accepted.mode = "accepted"
	root.add_child(accepted)
	await process_frame
	var observer := root.get_node_or_null("GodTestGuardAccepted")
	_check(accepted.refused == 0 and accepted.continued == 1 and observer != null,
		"a prepared observer remains attached while normal startup continues")
	if observer != null: observer.free()
	root.remove_child(accepted)
	await process_frame
	accepted.free()

	# Use the real observer with an output directory *inside* the isolated test
	# user directory; it cannot own that enclosing profile and must refuse.
	var had_config := OS.has_environment("OPENRC_GODTEST_CONFIG")
	var old_config := OS.get_environment("OPENRC_GODTEST_CONFIG")
	var unsafe_output := OS.get_user_data_dir().path_join("unowned-benchmark-output")
	DirAccess.make_dir_recursive_absolute(unsafe_output)
	var config_path := OS.get_user_data_dir().path_join("unowned-benchmark-config.json")
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		_check(false, "write isolated real-observer fixture")
	else:
		file.store_string(JSON.stringify({"output_dir": unsafe_output}))
		file.close()
		OS.set_environment("OPENRC_GODTEST_CONFIG", config_path)
		var real := GuardStartup.new()
		real.mode = "real"
		root.add_child(real)
		_check(real.refused == 1 and real.continued == 0 and real.intro == null
			and current_scene == original_scene and not FileAccess.file_exists("user://settings.cfg")
			and not FileAccess.file_exists("user://settings.cfg.display"),
			"real observer refuses an unowned profile without writing preferences or entering Home")
		real.free()
	if had_config: OS.set_environment("OPENRC_GODTEST_CONFIG", old_config)
	else: OS.unset_environment("OPENRC_GODTEST_CONFIG")

	print("GOD_STARTUP_GUARD_TESTS: ", failures, " failed")
	quit(0 if failures == 0 else 1)
