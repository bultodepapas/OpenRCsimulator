extends SceneTree

const SmokeAux := preload("res://input/smoke_aux.gd")

var _checks: int = 0
var _failures: int = 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _new_switch(buttons: Array, invert: bool = false, id: int = 3):
	var channel = SmokeAux.new()
	channel.configure({"type": "switch", "buttons": buttons, "invert": invert})
	channel.connect_device(id)
	return channel


func _initialize() -> void:
	_test_binding_validation()
	_test_two_position_switch()
	_test_three_position_switch()
	_test_inverted_switch()
	_test_invalid_snapshots()
	_test_device_and_connection_boundaries()
	print("switch AUX: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_binding_validation() -> void:
	_check("valid two-position binding", SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5], "invert": false}))
	_check("valid three-position binding and user label", SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5, 6], "invert": true, "label": "Sa"}))
	var typed_buttons: Array[int] = [126, 127]
	_check("typed integer Array is valid, including button 127", SmokeAux.valid_binding({"type": "switch", "buttons": typed_buttons, "invert": false}))
	_check("24-character label is accepted", SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5], "invert": false, "label": "123456789012345678901234"}))
	var config := ConfigFile.new()
	config.set_value("aux", "switch", {"type": "switch", "buttons": typed_buttons, "invert": false})
	_check("ConfigFile typed-array binding validates", SmokeAux.valid_binding(config.get_value("aux", "switch")))
	_check("bound_buttons returns validated group order", SmokeAux.bound_buttons({"type": "switch", "buttons": typed_buttons, "invert": false}) == [126, 127])
	_check("packed integer array is rejected by the profile contract", not SmokeAux.valid_binding({"type": "switch", "buttons": PackedInt32Array([8, 9]), "invert": false}))
	_check("two-button binding rejects a missing inversion flag", not SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5]}))
	_check("one-position group is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [4], "invert": false}))
	_check("four-position group is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5, 6, 7], "invert": false}))
	_check("non-array group is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": "4,5", "invert": false}))
	_check("boolean index is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [true, 5], "invert": false}))
	_check("float index is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [4.0, 5], "invert": false}))
	_check("string index is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": ["4", 5], "invert": false}))
	_check("negative index is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [-1, 5], "invert": false}))
	_check("index 128 is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [5, 128], "invert": false}))
	_check("duplicate indices are rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [5, 5], "invert": false}))
	_check("wrong inversion type is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5], "invert": 0}))
	_check("empty label is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5], "invert": false, "label": ""}))
	_check("whitespace-only label is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5], "invert": false, "label": "   "}))
	_check("overlong label is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5], "invert": false, "label": "1234567890123456789012345"}))
	_check("non-string label is rejected", not SmokeAux.valid_binding({"type": "switch", "buttons": [4, 5], "invert": false, "label": 9}))


func _test_two_position_switch() -> void:
	var channel = _new_switch([10, 11])
	var startup: Array[bool] = [false, true]
	channel.sample_switch(startup)
	_check("startup held ON is baseline only", not channel.is_armed() and channel.amount() == 0.0)
	for _repeat in 3:
		channel.sample_switch([false, true])
	_check("held startup ON never activates", not channel.is_armed() and channel.amount() == 0.0)
	channel.on_button(3, 11, false)
	channel.on_button(3, 10, true)
	_check("event pair does not output per event", not channel.is_armed() and channel.amount() == 0.0)
	channel.sample_switch([true, false])
	_check("release-old then press-new arms on coherent OFF poll", channel.is_armed() and channel.amount() == 0.0)
	channel.sample_switch([false, true])
	_check("two-position ON detent maps to one", channel.amount() == 1.0)
	channel.sample_switch([false, true])
	_check("held ON samples remain absolute with no repeat", channel.amount() == 1.0)
	channel.on_button(3, 11, false)
	channel.on_button(3, 10, true)
	_check("button events cannot change an armed switch output", channel.amount() == 1.0 and channel.is_armed())
	channel.sample_switch([true, false])
	_check("the next complete OFF snapshot updates the output", channel.amount() == 0.0 and channel.is_armed())

	channel = _new_switch([20, 21])
	channel.sample_switch([false, true])
	channel.on_button(3, 20, true)
	channel.on_button(3, 21, false)
	_check("press-new then release-old does not output per event", not channel.is_armed() and channel.amount() == 0.0)
	channel.sample_switch([true, false])
	_check("press-new then release-old also arms from coherent OFF", channel.is_armed() and channel.amount() == 0.0)


func _test_three_position_switch() -> void:
	var channel = _new_switch([30, 31, 32])
	channel.sample_switch([false, false, true])
	channel.on_button(3, 32, false)
	channel.on_button(3, 30, true)
	channel.sample_switch([true, false, false])
	_check("three-position OFF arms without activating", channel.is_armed() and channel.amount() == 0.0)
	channel.sample_switch([false, true, false])
	_check("middle detent maps to one half", is_equal_approx(channel.amount(), 0.5))
	channel.sample_switch([false, false, true])
	_check("three-position ON detent maps to one", channel.amount() == 1.0)
	channel.sample_switch([false, true, false])
	_check("middle detent is absolute in either direction", is_equal_approx(channel.amount(), 0.5))


func _test_inverted_switch() -> void:
	var channel = _new_switch([40, 41], true)
	channel.sample_switch([true, false])
	_check("inverted switch startup still has no action", not channel.is_armed() and channel.amount() == 0.0)
	channel.on_button(3, 40, false)
	channel.on_button(3, 41, true)
	channel.sample_switch([false, true])
	_check("inverted effective OFF endpoint arms at zero", channel.is_armed() and channel.amount() == 0.0)
	channel.sample_switch([true, false])
	_check("inversion reverses two-position amounts", channel.amount() == 1.0)
	channel.sample_switch([false, true])
	_check("inverted OFF endpoint remains zero", channel.amount() == 0.0)

	channel = _new_switch([50, 51, 52], true)
	channel.sample_switch([true, false, false])
	channel.on_button(3, 50, false)
	channel.on_button(3, 52, true)
	channel.sample_switch([false, false, true])
	_check("inverted three-position switch arms at reversed OFF endpoint", channel.is_armed() and channel.amount() == 0.0)
	channel.sample_switch([true, false, false])
	_check("inverted three-position ON detent maps to one", channel.amount() == 1.0)
	channel.sample_switch([false, true, false])
	_check("inverted middle remains one half", is_equal_approx(channel.amount(), 0.5))


func _test_invalid_snapshots() -> void:
	var channel = _new_switch([60, 61])
	channel.sample_switch([false, true])
	channel.on_button(3, 60, true)
	channel.sample_switch([true, false])
	_check("fixture reaches armed OFF", channel.is_armed())
	channel.sample_switch([false, true])
	_check("fixture reaches ON", channel.amount() == 1.0)
	var invalid_snapshots: Array = [[], [true], [true, 1], [true, true], [false, false]]
	for snapshot in invalid_snapshots:
		channel.sample_switch(snapshot)
		_check("invalid snapshot fails closed and disarms", not channel.is_armed() and channel.amount() == 0.0, str(snapshot))
		channel.sample_switch([false, true])
		channel.sample_switch([false, true])
		_check("fresh baseline alone cannot restore output", not channel.is_armed() and channel.amount() == 0.0)
		channel.on_button(3, 60, true)
		channel.sample_switch([true, false])
		_check("fresh deliberate OFF event and snapshot re-arm", channel.is_armed() and channel.amount() == 0.0)
		channel.sample_switch([false, true])
		_check("absolute output resumes after re-arm", channel.amount() == 1.0)


func _test_device_and_connection_boundaries() -> void:
	var channel = _new_switch([70, 71])
	channel.on_button(3, 70, true)
	channel.sample_switch([false, true])
	channel.sample_switch([false, true])
	_check("pre-baseline held ON event is ignored", not channel.is_armed() and channel.amount() == 0.0)
	channel.on_button(8, 70, true)
	channel.sample_switch([true, false])
	_check("foreign-device event cannot arm", not channel.is_armed() and channel.amount() == 0.0)
	channel.on_button(3, 70, true)
	channel.sample_switch([true, false])
	_check("selected-device OFF event arms", channel.is_armed() and channel.amount() == 0.0)
	channel.sample_switch([false, true])
	_check("selected device produces ON detent", channel.amount() == 1.0)
	channel.reset()
	channel.sample_switch([false, true])
	_check("enable reset clears old arming state and takes a new baseline", not channel.is_armed() and channel.amount() == 0.0)
	channel.disconnect_device()
	channel.connect_device(3)
	channel.on_button(3, 70, true)
	channel.sample_switch([true, false])
	_check("reconnect held OFF starts unarmed", not channel.is_armed() and channel.amount() == 0.0)
	channel.sample_switch([true, false])
	_check("reconnect held OFF never auto-activates", not channel.is_armed() and channel.amount() == 0.0)
	channel.on_button(3, 70, false)
	channel.on_button(3, 70, true)
	channel.sample_switch([true, false])
	_check("reconnect requires a post-baseline OFF event", channel.is_armed() and channel.amount() == 0.0)

	channel = _new_switch([80, 81])
	channel.on_button(3, 80, true)
	channel.sample_switch([true, false])
	channel.on_button(3, 80, true)
	channel.sample_switch([true, false])
	_check("duplicate startup OFF event cannot arm", not channel.is_armed() and channel.amount() == 0.0)
	channel.on_button(3, 80, false)
	channel.on_button(3, 80, true)
	channel.sample_switch([true, false])
	_check("a fresh OFF transition after leaving the detent can arm", channel.is_armed() and channel.amount() == 0.0)

