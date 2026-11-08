extends SceneTree
## AFC-02-R3: print the companion solver qualification identity of the project at --path as one JSON line.
## Used by tools/companions/rebind.py; the identity function itself lives in the production profile loader.

const Loader := preload("res://ai/companions/profile_loader.gd")
const FlightLogCli := preload("res://tools/flight_log_cli.gd")


func _initialize() -> void:
	var identity: Dictionary = Loader.current_solver_qualification_identity()
	var errors := PackedStringArray(identity.get("errors", PackedStringArray()))
	var inspected_tapes := 0
	var inspected_tape_sha256 := {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--tape="):
			errors.append("Unknown identity argument: " + argument)
			continue
		var tape: String = argument.trim_prefix("--tape=")
		var before: String = FileAccess.get_sha256(tape) if FileAccess.file_exists(tape) else ""
		if before.length() != 64:
			errors.append("Tape '%s' cannot be hashed before inspection." % tape)
			continue
		var inspected: Dictionary = FlightLogCli.inspect(tape)
		var after: String = FileAccess.get_sha256(tape) if FileAccess.file_exists(tape) else ""
		if not inspected.get("ok", false) or not inspected.get("complete", false):
			errors.append("Tape '%s' is invalid or incomplete: %s" % [tape, str(inspected.get("error", "unknown error"))])
		elif str(inspected.header.get("engine", "")) != str(Engine.get_version_info().string):
			errors.append("Tape '%s' was recorded with %s, not %s" % [tape, str(inspected.header.get("engine", "")), str(Engine.get_version_info().string)])
		elif before != after:
			errors.append("Tape '%s' changed during inspection." % tape)
		else:
			inspected_tapes += 1
			inspected_tape_sha256[tape] = after
	var ok: bool = identity.get("ok", false) and errors.is_empty()
	print("SOLVER_IDENTITY " + JSON.stringify({
		ok = ok,
		sha256 = str(identity.get("sha256", "")),
		source_count = int(identity.get("source_count", 0)),
		inspected_tapes = inspected_tapes,
		inspected_tape_sha256 = inspected_tape_sha256,
		errors = Array(errors),
	}))
	quit(0 if ok else 1)
