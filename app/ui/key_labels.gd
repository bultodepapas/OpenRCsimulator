# Names a PHYSICAL key the way the player's keyboard layout prints it (MENU-PLAN UI-04b, research 22/25): the flight
# reads physical positions (QWERTY A is AZERTY Q), so Help must not print "A" on a French keyboard.
# keyboard_get_label_from_physical gives the printed character (physical A on a Russian layout is "Ф";
# keyboard_get_keycode_from_physical would still say "A"). It reads the active layout on every call (≈45 µs on
# X11), so screens call it when they are built or shown, never per frame. Headless, web and Android do not
# implement it and print an engine ERROR: keyboard_get_current_layout() is -1 there, and QWERTY names are used.
# Named keys (arrows, Esc, Enter, F-keys) do not depend on the layout and get their own translatable names.
extends RefCounted

const NAMES := {
	KEY_ESCAPE: "Esc",
	KEY_ENTER: "Enter",
	KEY_KP_ENTER: "Num Enter",
	KEY_LEFT: "Left arrow",
	KEY_RIGHT: "Right arrow",
	KEY_UP: "Up arrow",
	KEY_DOWN: "Down arrow",
}


## The printed name of a physical key on the current layout: "Q" for physical A on AZERTY, "F3", "Esc".
## `mapper` (physical keycode -> label keycode) replaces the display server, e.g. a fixed AZERTY map in tests. It is a
## parameter, never stored: a lambda kept in a static variable aborts the engine at exit (4.7.2, measured).
static func label(physical: Key, mapper := Callable()) -> String:
	var shown := physical
	if mapper.is_valid():
		shown = mapper.call(physical)
	elif DisplayServer.keyboard_get_current_layout() >= 0:
		shown = DisplayServer.keyboard_get_label_from_physical(physical)
	if shown == KEY_NONE or shown == KEY_UNKNOWN:
		shown = physical
	if shown & KEY_SPECIAL:
		# Static: no tr(); TranslationServer gives the current language.
		return TranslationServer.translate(NAMES.get(shown, OS.get_keycode_string(shown)))
	return String.chr(shown).to_upper()
