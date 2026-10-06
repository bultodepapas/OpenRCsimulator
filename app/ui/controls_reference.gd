# The keyboard reference shown by Home, Help and the first-flight hint (MENU-PLAN UI-04b): one table, so the
# screens never disagree with each other. tests/test_controls_reference.gd reads input/keyboard.gd and main.gd's
# _unhandled_input and fails if a key is handled there but missing here, or listed here but handled nowhere.
# Keys are PHYSICAL (QWERTY positions, as the flight reads them); screens show them through ui/key_labels.gd, which
# names them as the player's keyboard layout prints them. Texts are English source strings (res://i18n/*.po).
extends RefCounted

## The sticks: [keys, action] (keyboard.gd: virtual stick, rate-limited, self-centring; throttle holds).
const FLIGHT := [
	[[KEY_LEFT, KEY_RIGHT], "Roll"],
	[[KEY_UP, KEY_DOWN], "Pitch"],
	[[KEY_A, KEY_D], "Rudder"],
	[[KEY_W, KEY_S], "Throttle"],
]

## Shortcuts while flying: [keys, what they do] (main.gd _unhandled_input).
const SHORTCUTS := [
	[[KEY_ESCAPE], "Pause menu (in the radio calibration: cancel it)"],
	[[KEY_R], "Restart the flight"],
	[[KEY_P], "Resume after a radio failsafe"],
	[[KEY_C], "Camera: pilot view or close-up"],
	[[KEY_Z], "Auto-zoom on or off"],
	[[KEY_V], "Ground shadow: sun, vertical or off"],
	[[KEY_T], "Record a flight trace (press again to save it)"],
	[[KEY_K], "Calibrate the radio"],
	[[KEY_ENTER, KEY_KP_ENTER], "Next radio calibration step"],
	[[KEY_F3], "Performance numbers"],
	[[KEY_F5], "Reload the aircraft data file"],
]

## The first-flight hint: at most three things (research 22), all of them already in the tables above.
const FIRST_FLIGHT := [
	[[KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN], "Fly with the arrows"],
	[[KEY_W, KEY_S], "Throttle"],
	[[KEY_ESCAPE], "Pause"],
]


## Every physical key the tables mention (for the consistency test).
static func all_keys() -> Array:
	var keys := []
	for table in [FLIGHT, SHORTCUTS]:
		for row in table:
			for k in row[0]:
				if not k in keys:
					keys.append(k)
	return keys
