extends SceneTree
## NK-8a: the kernel's walk over a projected shadow's parts equals ProjectedShadow._part_pose and _part_visible bit for
## bit: random hierarchies mixing Node3D and plain Node levels with rotations, non-uniform scales and offsets, hidden
## levels, a part outside the source, the source itself, a part never found and a part freed after binding, over 400
## rounds of random transform and visibility changes. Skips (passes) without the verified library.

const ProjectedShadow := preload("res://render/projected_shadow.gd")

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _transform() -> Transform3D:
	var basis := Basis(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
		_rng.randf_range(-PI, PI)).scaled(Vector3(_rng.randf_range(0.5, 2.0), _rng.randf_range(0.5, 2.0), _rng.randf_range(0.5, 2.0)))
	return Transform3D(basis, Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3), _rng.randf_range(-3, 3)))


func _run() -> void:
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"shadow_parts_bind"):
		print("NK8A_SKIP no native library with the shadow parts")
		quit(0)
		return
	_rng.seed = 8008
	var source := Node3D.new()
	root.add_child(source)
	var outside := Node3D.new()
	root.add_child(outside)
	var spatial: Array[Node3D] = []
	var nodes: Array[Node] = [source]
	for i: int in 60:
		var parent: Node = nodes[_rng.randi_range(0, nodes.size() - 1)]
		var node: Node = Node.new() if _rng.randf() < 0.2 else Node3D.new()
		parent.add_child(node)
		nodes.append(node)
		if node is Node3D:
			(node as Node3D).transform = _transform()
			spatial.append(node)
	var stray := Node3D.new()
	outside.add_child(stray)
	var doomed := Node3D.new()
	spatial[3].add_child(doomed)
	var shadow: Node = ProjectedShadow.new()
	shadow.source = source
	var parts: Array[Dictionary] = []
	var candidates: Array = [source, stray, null, doomed]
	for i: int in 30:
		candidates.append(spatial[_rng.randi_range(0, spatial.size() - 1)])
	for node: Variant in candidates:
		parts.append({node = node, bound = node != null, bounds = AABB(), rest = _transform()})
	shadow._parts.assign(parts)
	shadow._parts_revision += 1
	var mismatched := 0
	var first := ""
	var hidden_seen := false
	for round: int in 400:
		if round == 200:
			doomed.free() # freed after binding: rest pose, not visible
		for k: int in 6:
			var node: Node3D = spatial[_rng.randi_range(0, spatial.size() - 1)]
			node.transform = _transform()
			node.visible = _rng.randf() > 0.15
		var native_poses: Array[Transform3D] = []
		var native_visibility: Array[bool] = []
		var answered: bool = shadow._native_part_poses(native_poses, native_visibility)
		var poses: Array[Transform3D] = []
		var visibility: Array[bool] = []
		for part: Dictionary in shadow._parts:
			poses.append(shadow._part_pose(part))
			visibility.append(shadow._part_visible(part))
		hidden_seen = hidden_seen or visibility.has(false)
		if not answered or var_to_bytes(native_poses) != var_to_bytes(poses) or native_visibility != visibility:
			mismatched += 1
			if first.is_empty():
				first = "round %d answered %s" % [round, answered]
	_check("native part poses and visibility equal the GDScript walks (400 rounds)", mismatched == 0 and hidden_seen,
		"%d differ; %s" % [mismatched, first])
	ProjectedShadow.native_part_poses_enabled = false
	var off_poses: Array[Transform3D] = []
	var off_visibility: Array[bool] = []
	_check("the hook off leaves the walks to GDScript", not shadow._native_part_poses(off_poses, off_visibility))
	ProjectedShadow.native_part_poses_enabled = true
	shadow.free()
	print("native shadow parts: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
