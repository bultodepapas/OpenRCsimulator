extends SceneTree

const Bridge = preload("res://debug/debug_bridge.gd")
const CONTENT = '{"payload":"café 日本 🚁 xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}'
const ORIGINAL = '{"old":"previous checkpoint"}'


class FakeSim extends Node:
	var paused := true
	var tick := 12
	var fault_reason := ""
	var stop_at_tick := -1
	var state := PackedFloat64Array([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	func dt() -> float: return 1.0 / 240.0
	func time() -> float: return tick * dt()
	func set_paused(value: bool) -> void: paused = value


class FakeSession extends Node:
	var sim := FakeSim.new()
	var holds := {}
	var crash := {}
	var pause_reason := ""
	var commands := {}
	var raw := {}
	var restored := ""
	func checkpoint_json() -> String: return CONTENT
	func restore_checkpoint_json(text: String) -> bool:
		restored = text
		return true


class FakeFlight extends Node:
	var session := FakeSession.new()
	var aircraft_id := "fixture"


class FakeApp extends Node:
	var flight := FakeFlight.new()
	var ground_vehicle: Node
	var home: Node
	var screens: Node


func _initialize() -> void:
	var path := OS.get_environment("OPENRC_CHECKPOINT_REPRO_PATH")
	var scenario := OS.get_environment("OPENRC_CHECKPOINT_REPRO_SCENARIO")
	var app := FakeApp.new()
	app.add_child(app.flight)
	app.flight.add_child(app.flight.session)
	app.flight.session.add_child(app.flight.session.sim)
	var bridge := Bridge.new()
	bridge.app = app
	var original_ok := scenario in ["dangling", "cycle", "missing-intermediate"] or FileAccess.get_file_as_string(path) == ORIGINAL
	var reply: Dictionary = bridge._cmd_checkpoint({action = "save", path = path})
	var unreadable := scenario == "cycle" or (scenario == "missing-intermediate" and OS.get_name() != "Windows")
	var actual := PackedByteArray() if unreadable else FileAccess.get_file_as_bytes(path)
	var reloaded := false
	if scenario != "limited" and not unreadable:
		var result: Dictionary = bridge._cmd_checkpoint({action = "load", path = path})
		reloaded = result.has("pending") and app.flight.session.restored == CONTENT
	var directory := DirAccess.open(path.get_base_dir())
	var other_files := PackedStringArray()
	if directory != null:
		directory.include_hidden = true
		for filename in directory.get_files():
			if filename != path.get_file():
				other_files.append(filename)
	else:
		other_files.append("<directory could not be opened>")
	var observation := {
		"scenario": scenario,
		"original_setup_ok": original_ok,
		"save_ok": reply.get("ok", false),
		"error": reply.get("error", ""),
		"reported_bytes": reply.get("result", {}).get("bytes"),
		"expected_utf8_bytes": CONTENT.to_utf8_buffer().size(),
		"expected_characters": CONTENT.length(),
		"actual_bytes": actual.size(),
		"original_preserved": actual == ORIGINAL.to_utf8_buffer(),
		"exact_new_content": actual == CONTENT.to_utf8_buffer(),
		"reload_ok": reloaded,
		"other_files": Array(other_files),
	}
	print("OPENRC_CHECKPOINT_OBSERVATION=", JSON.stringify(observation))
	OS.remove_logger(bridge.debug_log)
	bridge.free()
	app.free()
	quit(0)
