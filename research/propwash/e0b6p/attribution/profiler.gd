# E0b6p measurement collector. Copied into a disposable app before use.
extends RefCounted

static var enabled: bool = false
static var _elapsed_usec: Dictionary = {}
static var _calls: Dictionary = {}


static func reset() -> void:
	_elapsed_usec.clear()
	_calls.clear()


static func add(component: String, elapsed_usec: int) -> void:
	_elapsed_usec[component] = int(_elapsed_usec.get(component, 0)) + elapsed_usec
	_calls[component] = int(_calls.get(component, 0)) + 1


static func snapshot() -> Dictionary:
	return {elapsed_usec = _elapsed_usec.duplicate(), calls = _calls.duplicate()}
