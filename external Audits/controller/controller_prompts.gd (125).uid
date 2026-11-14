extends SceneTree

const Store = preload("res://input/controller_profile_store.gd")
const Profile = preload("res://input/controller_profile.gd")

class CoordinatedStore extends Store:
	func _write_transaction(profiles: Array, recovered_from_backup := false, ui_preference: Dictionary = {}) -> Dictionary:
		# Test scheduler pauses each real save after its read/merge, before publication.
		var dir := OS.get_environment("AUDIT_SYNC")
		var id := OS.get_environment("AUDIT_WRITER")
		var ready := FileAccess.open(dir.path_join(id + ".ready"), FileAccess.WRITE)
		if ready == null: return {"ok": false, "error": "could not write scheduler marker", "warning": ""}
		ready.store_string("ready")
		ready.close()
		var deadline := Time.get_ticks_msec() + 15000
		while not FileAccess.file_exists(dir.path_join(id + ".release")) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(5)
		if not FileAccess.file_exists(dir.path_join(id + ".release")):
			return {"ok": false, "error": "scheduler timed out", "warning": ""}
		return super._write_transaction(profiles, recovered_from_backup, ui_preference)

func _initialize() -> void:
	var name := OS.get_environment("AUDIT_WRITER")
	var store := CoordinatedStore.new(OS.get_environment("AUDIT_STORE"), OS.get_environment("AUDIT_STORE") + ".legacy")
	var candidate := Profile.defaults("gamepad", "mode2")
	candidate.name = "Writer " + name
	candidate.association = {"serial_number": name}
	var result: Dictionary = store.save_profile(candidate)
	print("WRITER_DONE name=", name, " ok=", result.ok, " error=", result.error)
	quit(0 if result.ok else 1)
