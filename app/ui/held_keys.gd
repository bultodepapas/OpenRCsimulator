# After a menu closes, keyboard keys still held from navigating it must not fly the airplane (MENU-PLAN §8:
# "release navigation inputs before applying flight keys again"). The keyboard is sampled by polling, so a held
# Down arrow used to reach "Restart" would otherwise pull the elevator the moment the flight resumes.
# mask() wraps the session's keyboard reader: each axis that is non-zero when the flight resumes reads 0 until its
# keys are released once; then the original reader comes back. The radio is unaffected: its sticks are positions.
extends RefCounted


## `reader`: the session's own keyboard reader (kept by the caller, so masks never wrap each other).
static func mask(session: Node, reader: Callable) -> void:
	var first: Dictionary = reader.call()
	var held := {}
	for axis in first:
		if first[axis] != 0.0:
			held[axis] = true
	if held.is_empty():
		session.read_raw = reader
		return
	session.read_raw = func() -> Dictionary:
		var r: Dictionary = reader.call()
		for axis in held.keys():
			if r[axis] == 0.0:
				held.erase(axis) # released once: this axis flies again
			else:
				r[axis] = 0.0
		if held.is_empty():
			session.read_raw = reader
		return r
