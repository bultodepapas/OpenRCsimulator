# Keyboard adapter: keys -> raw targets (Mode 2 layout). The only input file that reads the keyboard.
extends RefCounted


static func _axis(minus: Key, plus: Key) -> float:
	return float(Input.is_physical_key_pressed(plus)) - float(Input.is_physical_key_pressed(minus))


static func read_raw() -> Dictionary:
	return {
		roll = _axis(KEY_LEFT, KEY_RIGHT),
		pitch = _axis(KEY_UP, KEY_DOWN), # Down = stick back = nose up
		yaw = _axis(KEY_A, KEY_D),
		throttle = _axis(KEY_S, KEY_W),
	}
