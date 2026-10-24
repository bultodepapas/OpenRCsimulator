extends SceneTree
## AFC-02-R3: print the companion solver qualification identity of the project at --path as one JSON line.
## Used by tools/companions/rebind.py; the identity function itself lives in the production profile loader.

const Loader := preload("res://ai/companions/profile_loader.gd")


func _initialize() -> void:
	var identity: Dictionary = Loader.current_solver_qualification_identity()
	var ok: bool = identity.get("ok", false)
	print("SOLVER_IDENTITY " + JSON.stringify({
		ok = ok,
		sha256 = str(identity.get("sha256", "")),
		source_count = int(identity.get("source_count", 0)),
		errors = Array(identity.get("errors", PackedStringArray())),
	}))
	quit(0 if ok else 1)
