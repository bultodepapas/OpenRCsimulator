extends SceneTree
const Store = preload("res://input/controller_profile_store.gd")
func _initialize() -> void:
	var store := Store.new(OS.get_environment("AUDIT_STORE"), OS.get_environment("AUDIT_STORE") + ".legacy")
	var result: Dictionary = store.load_all()
	var names := []
	for p: Dictionary in result.get("profiles", []): names.append(p.name)
	print("FINAL_STORE names=", names, " ok=", result.ok)
	quit(0 if result.ok and names == ["Writer B"] else 1)
