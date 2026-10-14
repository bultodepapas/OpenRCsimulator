extends SceneTree

const Data = preload("res://input/input_report_data.gd")
var _checks: int = 0
var _failures: int = 0


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var data: Data = Data.new()
	data.connect_device(7, {guid = "fake-guid", name = "Fake pad", raw_name = "Raw pad",
		vendor_id = "4617", product_id = "20308", known = true, vibration_supported = true,
		steam_input_index = "2", xinput_index = 1, serial_number = "SERIAL-MUST-NOT-LEAK"}, 100)
	data.button_event(7, 2, true, 101)
	data.button_event(7, 2, true, 101) # repeated state callback
	data.button_event(7, 2, false, 101)
	data.button_event(7, 2, false, 101) # repeated release callback
	var initial: Dictionary = data.snapshot()[0]
	check("raw button callbacks and state transitions are distinct",
		initial.button_events == 4 and initial.button_press_events == 2 and initial.button_release_events == 2 and initial.button_transition_count == 2)
	check("per-button counts expose final state",
		initial.buttons.size() == 1 and initial.buttons[0].button == 2 and initial.buttons[0].events == 4
		and initial.buttons[0].press_transitions == 1 and initial.buttons[0].release_transitions == 1 and not initial.buttons[0].pressed)
	check("transition samples retain mapped button and callback time",
		initial.button_transitions.size() == 2 and initial.button_transitions[0] == {button = 2, pressed = true, at_usec = 101}
		and initial.button_transitions[1] == {button = 2, pressed = false, at_usec = 101})
	check("known mapping and vibration capability are explicit",
		initial.capabilities.standard_mapping and initial.capabilities.vibration_supported)
	check("backend hints retain only valid indexes",
		initial.backend_hints.steam_input_index == 2 and initial.backend_hints.xinput_index == 1)

	for i: int in Data.MAX_RECORDED_BUTTON_TRANSITIONS + 20:
		data.button_event(7, 2, i % 2 == 0, 200 + i)
	var bounded: Dictionary = data.snapshot()[0]
	check("long runs cap transition samples while counting every state change",
		bounded.button_transitions.size() == Data.MAX_RECORDED_BUTTON_TRANSITIONS
		and bounded.button_transition_count == 2 + Data.MAX_RECORDED_BUTTON_TRANSITIONS + 20
		and bounded.button_transitions_omitted == 22)

	for button_index: int in range(3, 3 + Data.MAX_TRACKED_BUTTONS - 1):
		data.button_event(7, button_index, true, 1000 + button_index)
	data.button_event(7, 9000, true, 1100)
	data.button_event(7, 9000, false, 1101)
	var capped: Dictionary = data.snapshot()[0]
	check("per-button summaries have a fixed distinct-index limit", capped.buttons.size() == Data.MAX_TRACKED_BUTTONS)
	check("excess indexes are counted without retaining per-index state",
		capped.untracked_button_events == 2 and capped.untracked_button_press_events == 1 and capped.untracked_button_release_events == 1)
	check("transition log remains capped after many distinct buttons",
		capped.button_transitions.size() == Data.MAX_RECORDED_BUTTON_TRANSITIONS and capped.button_transitions_omitted == 85)

	var rejected_before: int = data.rejected_events
	data.button_event(7, -1, true, 1200)
	data.button_event(99, 1, true, 1200)
	data.button_event(7, 2, false, 1099)
	check("negative, unknown-device, and backward-time events are rejected", data.rejected_events == rejected_before + 3)

	data.connect_device(8, {guid = 7, name = ["bad"], raw_name = 12, vendor_id = "0x1209",
		product_id = 65536, known = "true", vibration_supported = 1,
		steam_input_index = -1, xinput_index = "7", serial_number = "ANOTHER-SECRET"}, 1500)
	var sanitized: Dictionary = data.snapshot()[1]
	check("malformed identity and capability metadata stays unknown",
		sanitized.guid == "" and sanitized.name == "" and sanitized.raw_name == null
		and sanitized.vendor_id == null and sanitized.product_id == null
		and not sanitized.is_joy_known and not sanitized.capabilities.standard_mapping
		and sanitized.capabilities.vibration_supported == null)
	check("malformed backend indexes are rejected independently",
		sanitized.backend_hints.steam_input_index == null and sanitized.backend_hints.xinput_index == 7)

	data.disconnect_device(7, 2000)
	data.connect_device(7, {guid = "replacement", name = "Reconnected", known = false}, 2001)
	data.button_event(7, 2, true, 2002)
	var sessions: Array[Dictionary] = data.snapshot()
	check("reused device IDs begin clean button sessions",
		sessions.size() == 3 and not sessions[0].connected and sessions[2].button_events == 1
		and sessions[2].button_transition_count == 1 and sessions[2].buttons.size() == 1)
	var encoded: String = JSON.stringify(sessions)
	check("device serials are never published", not encoded.contains("SERIAL-MUST-NOT-LEAK") and not encoded.contains("ANOTHER-SECRET") and not encoded.contains("serial_number"))
	check("internal state indexes are omitted from snapshots", not encoded.contains("_button_states") and not encoded.contains("_button_index_to_slot"))
	print("F1 button data: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
