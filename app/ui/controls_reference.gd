# The keyboard reference shown by Home, Help and the first-flight hint (MENU-PLAN UI-04b): one table, so the
# screens never disagree with each other. tests/test_controls_reference.gd reads input/keyboard.gd and main.gd's
# _unhandled_input and fails if a key is handled there but missing here, or listed here but handled nowhere.
# Keys are PHYSICAL (QWERTY positions, as the flight reads them); screens show them through ui/key_labels.gd, which
# names them as the player's keyboard layout prints them. Texts are English source strings (res://i18n/*.po).
extends RefCounted

const AIRPLANE := "airplane"
const ROTORCRAFT := "rotorcraft"

## The sticks: [keys, action] (keyboard.gd: virtual stick, rate-limited, self-centring; throttle holds).
const FLIGHT := [
	[[KEY_LEFT, KEY_RIGHT], "Roll"],
	[[KEY_UP, KEY_DOWN], "Pitch"],
	[[KEY_A, KEY_D], "Rudder"],
	[[KEY_W, KEY_S], "Throttle"],
]

## Shortcuts while flying: [keys, what they do] (main.gd _unhandled_input).
const SHORTCUTS := [
	[[KEY_BRACKETLEFT, KEY_BRACKETRIGHT], "Aileron trim: left / right"],
	[[KEY_PAGEUP, KEY_PAGEDOWN], "Elevator trim: nose down / up"],
	[[KEY_ESCAPE], "Pause menu (in the radio calibration: cancel it)"],
	[[KEY_R, KEY_P], "Restart / resume after radio failsafe"],
	[[KEY_C, KEY_1, KEY_2, KEY_5], "Views: next (Shift+C back), pilot, chase, orbit"],
	[[KEY_Z, KEY_EQUAL, KEY_MINUS, KEY_BACKSPACE], "Zoom: auto on/off, in, out, reset"],
	[[KEY_V, KEY_L], "Ground shadow · night lights"],
	[[KEY_T], "Record a flight trace (press again to save it)"],
	[[KEY_K], "Calibrate the radio"],
	[[KEY_H], "Stik smoke pump"],
	[[KEY_J], "Assign smoke AUX"],
	[[KEY_G, KEY_B], "Gear toggle · wheel brake (hold)"],
	[[KEY_ENTER, KEY_KP_ENTER], "Next radio calibration step"],
	[[KEY_F2, KEY_F3], "Overlay preset · developer overlays"],
	[[KEY_F5], "Reload the aircraft data file"],
	[[KEY_F6, KEY_F7, KEY_F8, KEY_F9], "Glow: cut, starter, lean/rich mixture"],
]

## The first-flight hint: at most three things (research 22), all of them already in the tables above.
const FIRST_FLIGHT := [
	[[KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN], "Fly with the arrows"],
	[[KEY_W, KEY_S], "Throttle"],
	[[KEY_ESCAPE], "Pause"],
]

## Helicopter controls use the same physical keyboard axes, with W/S controlling collective rather than throttle.
const ROTORCRAFT_FLIGHT := [
	[[KEY_LEFT, KEY_RIGHT], "Cyclic roll"],
	[[KEY_UP, KEY_DOWN], "Cyclic pitch"],
	[[KEY_A, KEY_D], "Yaw"],
	[[KEY_W, KEY_S], "Collective"],
]

## Shortcuts implemented by helicopter_main.gd. Keep this table limited to its handled key set.
const ROTORCRAFT_SHORTCUTS := [
	[[KEY_ESCAPE], "Pause menu / cancel radio calibration"],
	[[KEY_R], "Restart the selected helicopter start"],
	[[KEY_P], "Pause / resume"],
	[[KEY_C, KEY_1, KEY_2, KEY_5], "Views: next, pilot, chase, orbit"],
	[[KEY_Z, KEY_EQUAL, KEY_MINUS], "Zoom: auto, in, out"],
	[[KEY_T], "Record / stop a flight trace"],
	[[KEY_K], "Calibrate the radio"],
	[[KEY_ENTER, KEY_KP_ENTER], "Next radio calibration step"],
	[[KEY_I], "Flight mode: normal / idle-up curves"],
	[[KEY_G], "Trainer mode"],
	[[KEY_H], "Zero-drive hold"],
	[[KEY_B], "Arm / disarm helicopter motor"],
]

const ROTORCRAFT_FIRST_FLIGHT := [
	[[KEY_B, KEY_H], "Arm, then release hold"],
	[[KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN], "Cyclic"],
	[[KEY_W, KEY_S], "Collective"],
]


static func flight_table(vehicle_type: String = AIRPLANE) -> Array:
	return ROTORCRAFT_FLIGHT if vehicle_type == ROTORCRAFT else FLIGHT


static func shortcut_table(vehicle_type: String = AIRPLANE) -> Array:
	return ROTORCRAFT_SHORTCUTS if vehicle_type == ROTORCRAFT else SHORTCUTS


static func first_flight_table(vehicle_type: String = AIRPLANE) -> Array:
	return ROTORCRAFT_FIRST_FLIGHT if vehicle_type == ROTORCRAFT else FIRST_FLIGHT


## Every physical key the tables mention (for the consistency test).
static func all_keys(vehicle_type: String = AIRPLANE) -> Array:
	var keys := []
	for table in [flight_table(vehicle_type), shortcut_table(vehicle_type)]:
		for row in table:
			for k in row[0]:
				if not k in keys:
					keys.append(k)
	return keys
