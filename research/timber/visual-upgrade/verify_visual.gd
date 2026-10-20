## TT-20: visual additions must not change original articulation or wreck contact boxes.
extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const Builder := preload("res://render/airplane.gd")
const Imported := preload("res://aircraft/imported_model.gd")
const WreckScript := preload("res://render/crash/wreck.gd")

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures.append(label)
		printerr("FAIL ", label)

func _groups(wreck: Node) -> Array:
	var records: Array = []
	for group: Dictionary in wreck._prepared_groups:
		records.append({
			kind = group.get("kind", ""),
			bounds = str(group.bounds),
			center = str(group.center),
			member_bounds = str(group.get("member_bounds", [])),
		})
	return records

func _run() -> void:
	var source := Timber.build()
	var candidate := Builder.build(Builder.TIMBER_ID)
	_check("both models build", not source.is_empty() and not candidate.is_empty())
	if source.is_empty() or candidate.is_empty():
		quit(1)
		return
	root.add_child(source.root)
	root.add_child(candidate.root)
	var original_paths: Array[NodePath] = []
	for original: Node in source.root.find_children("*", "Node3D", true, false):
		var path: NodePath = source.root.get_path_to(original)
		original_paths.append(path)
		var current: Node3D = candidate.root.get_node_or_null(path)
		_check("original node survives " + str(path), current != null)
		if current == null:
			continue
		_check("rest transform " + str(path), Imported.relative(source.root, original).is_equal_approx(Imported.relative(candidate.root, current)))
		if original is MeshInstance3D:
			_check("original mesh resource " + str(path), original.mesh == current.mesh)
	var details := 0
	for node: MeshInstance3D in candidate.root.find_children("*", "MeshInstance3D", true, false):
		if not original_paths.has(candidate.root.get_path_to(node)):
			details += 1
			_check("detail excluded from collision bounds " + str(node.name), node.has_meta("crash_no_bounds"))
	for pose: Dictionary in [{aileron_left = 10.0, aileron_right = -10.0, elevator = 12.0, rudder = 15.0},
			{aileron_left = -10.0, aileron_right = 10.0, elevator = -12.0, rudder = -15.0},
			{aileron_left = 0.0, aileron_right = 0.0, elevator = 0.0, rudder = 0.0}]:
		Timber.apply_surfaces(source, pose)
		Imported.apply_surfaces(candidate, pose)
		for key: String in source.hinges:
			_check("control pose " + key, Imported.relative(source.root, source.hinges[key].node).is_equal_approx(Imported.relative(candidate.root, candidate.hinges[key].node)))
	var source_wreck := WreckScript.new()
	var candidate_wreck := WreckScript.new()
	root.add_child(source_wreck)
	root.add_child(candidate_wreck)
	_check("source wreck prepares", source_wreck.prepare(source.root))
	_check("candidate wreck prepares", candidate_wreck.prepare(candidate.root))
	var source_groups := _groups(source_wreck)
	var candidate_groups := _groups(candidate_wreck)
	_check("wreck section contact boxes and centers unchanged", source_groups == candidate_groups)
	var report := {checks = _checks, failures = _failures, visual_detail_meshes = details,
		source_groups = source_groups, candidate_groups = candidate_groups,
		asset_sha256 = FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/timber.glb")}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t") + "\n")
	print("TT-20 visual isolation: %d checks, %d failed; %d detail meshes" % [_checks, _failures.size(), details])
	source_wreck.free()
	candidate_wreck.free()
	source.root.free()
	candidate.root.free()
	quit(1 if not _failures.is_empty() else 0)
