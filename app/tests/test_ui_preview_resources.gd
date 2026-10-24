# UI-05-R3: the actual ResourceLoader broker, bounded ownership and supersession.
extends SceneTree
var checks := 0
var failures := 0
var completions: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("ok   " if ok else "FAIL ", label)
func _complete(ok: bool, id: String) -> void:
	completions.append(id if ok else "failed:" + id)
func _drain(broker: Node) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not broker._active_path.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check("broker finishes without blocking get", broker._active_path.is_empty())
func _run() -> void:
	var paths: Array[String] = []
	for id: String in ["a", "b", "c", "d"]:
		var node := Node3D.new()
		node.name = id
		var scene := PackedScene.new()
		scene.pack(node)
		var path := "user://ui05_preview_" + id + ".tscn"
		ResourceSaver.save(scene, path)
		node.free()
		paths.append(path)
	var broker: Node = load("res://ui/home_preview_resources.gd").new()
	root.add_child(broker)
	broker.request(paths[0], _complete.bind("a"))
	broker.request(paths[1], _complete.bind("b"))
	broker.request(paths[2], _complete.bind("c"))
	_check("only one active resource and latest queued intent", broker._active_path == paths[0] and broker._queued_path == paths[2])
	await _drain(broker)
	_check("obsolete requests never call completion", completions == ["c"])
	_check("obsolete active resource is not retained", not broker._resources.has(paths[0]))
	broker.request(paths[0], _complete.bind("a"))
	await _drain(broker)
	broker.request(paths[3], _complete.bind("d"))
	await _drain(broker)
	_check("resource cache is bounded to two", broker._resources.size() == 2 and not broker._resources.has(paths[2]))
	broker.retain_loaded(paths[2], load(paths[2]) as PackedScene)
	_check("foreground scene shares the two-resource bound", broker._resources.size() == 2
		and broker._resources.has(paths[2]) and not broker._resources.has(paths[0]))
	broker.request(paths[2], _complete.bind("foreground-cached"))
	_check("foreground scene is reusable without a worker request", completions[-1] == "foreground-cached"
		and broker._active_path.is_empty())
	broker.request(paths[3], _complete.bind("cached"))
	_check("cached resource completes synchronously", completions[-1] == "cached" and broker._active_path.is_empty())
	broker.request(paths[1], _complete.bind("cancelled"))
	broker.cancel_for(self)
	await _drain(broker)
	_check("Home exit drains without applying or retaining", not completions.has("cancelled") and broker._resources.is_empty())
	broker.request(paths[0], _complete.bind("procedural-obsolete"))
	broker.request("", _complete.bind("procedural"))
	await _drain(broker)
	_check("procedural request supersedes older completion", completions[-1] == "procedural" and not completions.has("procedural-obsolete"))
	broker.request(paths[1], _complete.bind("shutdown"))
	broker.free()
	_check("shutdown drains without callback", not completions.has("shutdown"))
	for path in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Preview resources: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
