# UI-05-R2: bounded Home-only visual reuse, eviction, hidden models and ownership.
extends SceneTree
var _checks := 0
var _failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var script: Script = load("res://ui/home_scene.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--home="): script = load(arg.trim_prefix("--home="))
	var home: Node3D = script.new()
	root.add_child(home)
	await process_frame
	var stik: Node3D = home.airplane.root
	var stik_ref: WeakRef = weakref(stik)
	home.show_aircraft("gp-extra-300s-60")
	var extra: Node3D = home.airplane.root
	home.show_aircraft("sebart-avanti-s-a200-p100rx")
	var jet: Node3D = home.airplane.root
	_check("only the current aircraft is visible", not stik.visible and not extra.visible and jet.visible)
	_check("retained aircraft cannot process", stik.process_mode == Node.PROCESS_MODE_DISABLED and extra.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("at most three models are retained", home._preview_models.size() == 3)
	var pose := extra.transform
	home.show_aircraft("gp-extra-300s-60")
	_check("returning to Extra reuses its root", home.airplane.root == extra)
	_check("returning preserves pose and resumes visibility", extra.transform == pose and extra.visible and extra.process_mode == Node.PROCESS_MODE_INHERIT)
	_check("the old selected model is hidden", not jet.visible)
	for repeat in range(4): home.show_aircraft("gp-extra-300s-60")
	_check("same selection reuses its model", home.airplane.root == extra)
	await process_frame
	await process_frame
	_check("only one projected shadow is attached", home._shadow.get_child_count() == 1)
	var geometry: Dictionary = home._preview_geometry["gp-extra-300s-60"]
	var projected: Node = home._shadow.get_child(0)
	_check("projection uses the retained neutral shape", projected.bounds == geometry.shape.bounds and projected.triangle_count == geometry.shape.triangles)
	var fresh: Dictionary = load("res://render/airplane.gd").build("gp-extra-300s-60")
	var fresh_shape: Dictionary = load("res://render/projected_shadow.gd").collect(fresh.root)
	_check("retained shadow vertices equal a fresh model", geometry.shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == fresh_shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	_check("retained shadow bounds equal a fresh model", geometry.shape.bounds == fresh_shape.bounds)
	fresh.root.free()
	fresh.clear()
	fresh_shape.clear()
	geometry = {} # Do not let the measurement retain a GPU mesh through renderer shutdown.
	home.show_aircraft("turbo-lumber-evolution")
	await process_frame
	await process_frame
	_check("least recently used Stik is freed", stik_ref.get_ref() == null)
	_check("recent Extra remains retained", is_instance_valid(extra) and home._preview_models.size() == 3)
	home.show_aircraft("xcell-60-research")
	_check("helicopter selection preserves its visual identity", home.airplane.visual_family == "hx-700" and home.airplane.root.visible)
	home.show_aircraft("gp-extra-300s-60")
	_check("airplane returns after helicopter without reconstruction", home.airplane.root == extra)
	var refs: Array[WeakRef] = []
	for model: Dictionary in home._preview_models.values(): refs.append(weakref(model.root))
	home.free()
	await process_frame
	await process_frame
	for ref in refs: _check("Home frees retained models", ref.get_ref() == null)
	print("Home preview cache: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)
