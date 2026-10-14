extends SceneTree

## Export the costly measured coverage fields used by the HX-700 runtime adapter.
## Run from the repository root:
## godot --headless --path app --script ../research/helicopter/assets/export_heli_rotor_profiles.gd -- --out=../.tools/heli25/hx700-rotor-profiles.json

const Builder := preload("res://aircraft/hx700_model.gd")
const PropellerBlur := preload("res://render/propeller_blur.gd")
const PROFILE_SCHEMA := "openrc-heli-rotor-profiles v1"
const PROFILE_ALGORITHM := "vq05-polar-coverage-rings36-bins240-gap1-blade-share0.5-hub0.98-count0.7-v1"


func _initialize() -> void:
	var model: Dictionary = Builder.build()
	if model.is_empty():
		printerr("Unable to build the imported HX-700 source scene.")
		quit(1)
		return
	var data := {
		"schema": PROFILE_SCHEMA,
		"algorithm": PROFILE_ALGORITHM,
		"source_glb_sha256": Builder.GLB_SHA256,
		"rotors": {},
	}
	data.rotors.main = _profile(model.main_rotor_mount, model.root)
	data.rotors.tail = _profile(model.tail_rotor, model.root)
	if data.rotors.main.is_empty() or data.rotors.tail.is_empty():
		printerr("The source GLB did not yield two valid rotor coverage profiles.")
		model.root.free()
		quit(1)
		return
	var out_path := ProjectSettings.globalize_path("res://../.tools/heli25/hx700-rotor-profiles.json")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var tools_dir := ProjectSettings.globalize_path("res://../.tools").replace("\\", "/").simplify_path().trim_suffix("/")
	var normalized_out := out_path.replace("\\", "/").simplify_path()
	if not normalized_out.begins_with(tools_dir + "/"):
		printerr("Profile output must stay under the ignored repository .tools directory: ", out_path)
		model.root.free()
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write profile export at %s (error %d)." % [out_path, FileAccess.get_open_error()])
		model.root.free()
		quit(1)
		return
	file.store_string(JSON.stringify(data, "\t", true))
	file.close()
	print("HX-700 rotor profiles written: ", out_path)
	print("main radius %.9f m, %d blades; tail radius %.9f m, %d blades" % [
		float(data.rotors.main.radius), int(data.rotors.main.blades),
		float(data.rotors.tail.radius), int(data.rotors.tail.blades)])
	model.root.free()
	quit(0)


func _profile(rotor: Node3D, root: Node3D) -> Dictionary:
	var measured: Dictionary = PropellerBlur.profile(rotor, root)
	if measured.is_empty():
		return {}
	var surfaces: Array = []
	var material_slots: Dictionary = {}
	for item: Dictionary in measured.surfaces:
		var node: MeshInstance3D = item.node
		var node_path := _relative_path(rotor, node)
		if node_path.is_empty():
			return {}
		var material: Material = item.material
		var key := _material_key(material)
		if not material_slots.has(key):
			material_slots[key] = surfaces.size()
		surfaces.append({
			"node_path": node_path,
			"surface": int(item.surface),
			"rmax": float(item.rmax),
		})
	var colors: Array[int] = []
	for material: Material in measured.colors:
		colors.append(int(material_slots.get(_material_key(material), -1)))
	var coverage: Array[float] = []
	for share: float in measured.coverage:
		coverage.append(share)
	return {
		"radius": float(measured.radius),
		"radius_space": "rotor_local_m_before_runtime_radius_alignment",
		"hub_radius": float(measured.hub_radius),
		"inner_radius": float(measured.inner_radius),
		"blades": int(measured.blades),
		"plane_z": float(measured.plane_z),
		"ring_width": float(measured.ring_width),
		"coverage": coverage,
		"colors": colors,
		"surfaces": surfaces,
		"alignment": "runtime rotor mount is aligned from accepted aircraft data before attach; cached surface copies inherit its transform",
	}


func _relative_path(root: Node, node: Node) -> String:
	var parts: Array[String] = []
	var current: Node = node
	while current != null and current != root:
		parts.push_front(String(current.name))
		current = current.get_parent()
	return "/".join(PackedStringArray(parts)) if current == root else ""


func _material_key(material: Material) -> String:
	return "null" if material == null else str(material.get_instance_id())
