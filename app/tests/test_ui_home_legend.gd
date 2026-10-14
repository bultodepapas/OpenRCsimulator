## UI-05-R1: reuse unchanged legend nodes; refresh keyboard labels and vehicle semantics.
extends SceneTree

var Home: Script
var _checks := 0
var _failures := 0

func _initialize() -> void:
	Home = load("res://ui/home.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--home="): Home = load(arg.trim_prefix("--home="))
	_run.call_deferred()

func _run() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var home: Control = Home.new()
	root.add_child(home)
	for frame in range(4): await process_frame
	var initial := _ids(home.keys_legend)
	_check("four action rows and 28 descendants", home.keys_legend.get_child_count() == 4 and initial.size() == 28)
	_check("Fly has initial keyboard focus", home.fly_button.has_focus())
	for repeat in range(10): home._fill_legend()
	_check("unchanged refresh preserves every legend node", _ids(home.keys_legend) == initial)
	home.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check("focus regain with unchanged keyboard preserves nodes", _ids(home.keys_legend) == initial)
	home.set_aircraft("gp-extra-300s-60")
	_check("another airplane shares the same legend nodes", _ids(home.keys_legend) == initial)
	_check("aircraft selection retains Fly focus", home.fly_button.has_focus())
	home.set_aircraft("unknown-test-aircraft")
	_check("unknown selection keeps the default airplane legend", home.aircraft_id == "jensen-das-ugly-stik-60" and _ids(home.keys_legend) == initial)
	home.set_controller_devices("Flight Radio", "Menu Pad")
	_check("controller selection hides the keyboard legend", not home.keys_legend.visible)
	home._fill_legend()
	_check("hidden unchanged legend does not rebuild or become visible", not home.keys_legend.visible and _ids(home.keys_legend) == initial)
	home.set_controller_devices("", "")
	_check("keyboard selection reveals retained legend", home.keys_legend.visible and _ids(home.keys_legend) == initial)
	var old_row: WeakRef = weakref(home.keys_legend.get_child(0))
	home.set_aircraft("xcell-60-research")
	var rotor_ids := _ids(home.keys_legend)
	_check("rotorcraft replaces action rows", rotor_ids != initial and _actions(home) == ["Cyclic roll", "Cyclic pitch", "Yaw", "Collective"])
	home._fill_legend()
	_check("unchanged rotorcraft legend is reused", _ids(home.keys_legend) == rotor_ids)
	await process_frame
	await process_frame
	_check("retired rows are freed after the frame", old_row.get_ref() == null)
	home.set_aircraft("jensen-das-ugly-stik-60")
	_check("returning to airplane restores actions", _actions(home) == ["Roll", "Pitch", "Rudder", "Throttle"])
	var qwerty := func(key: int) -> int: return key
	var azerty := func(key: int) -> int: return KEY_Q if key == KEY_A else (KEY_Z if key == KEY_W else key)
	home._fill_legend(qwerty)
	var before_layout := _ids(home.keys_legend)
	home._fill_legend(azerty)
	_check("changed physical labels rebuild the legend", _ids(home.keys_legend) != before_layout)
	_check("AZERTY labels follow physical A/W positions", _key_text(home, 2, 0) == "Q" and _key_text(home, 3, 0) == "Z")
	var azerty_ids := _ids(home.keys_legend)
	home._fill_legend(azerty)
	_check("unchanged mapped keyboard preserves nodes", _ids(home.keys_legend) == azerty_ids)
	home._fill_legend(qwerty)
	_check("switching keyboard back restores printed labels", _key_text(home, 2, 0) == "A" and _key_text(home, 3, 0) == "W")
	_check("arrows remain drawn controls", not home.keys_legend.get_child(0).get_child(0).get_child(0).get_child(0) is Label)
	var english_ids := _ids(home.keys_legend)
	TranslationServer.set_locale("es")
	await process_frame
	_check("translation keeps existing action labels alive", _ids(home.keys_legend) == english_ids)
	var action: Label = home.keys_legend.get_child(0).get_child(1)
	_check("action text retains automatic locale translation", action.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED and action.tr(action.text) == TranslationServer.translate("Roll"))
	home._fill_legend(qwerty)
	_check("locale refresh keeps unchanged key labels", _ids(home.keys_legend) == english_ids)
	var ref: WeakRef = weakref(home)
	home.free()
	await process_frame
	await process_frame
	_check("Home disposal leaves no retained screen", ref.get_ref() == null)
	TranslationServer.set_locale(original_locale)
	print("Home legend: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _ids(node: Node) -> Array:
	var ids := []
	for child in node.find_children("*", "", true, false): ids.append(child.get_instance_id())
	return ids

func _actions(home: Control) -> Array:
	var names := []
	for row in home.keys_legend.get_children(): names.append(row.get_child(1).text)
	return names

func _key_text(home: Control, row: int, key: int) -> String:
	return home.keys_legend.get_child(row).get_child(0).get_child(key).get_child(0).text

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)
