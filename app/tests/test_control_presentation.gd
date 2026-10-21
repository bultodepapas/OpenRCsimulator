extends SceneTree

const Adapter = preload("res://render/airplane.gd")
const Commands = preload("res://input/commands.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ", label)

func _snapshot(node: Node, rows: Array) -> void:
	if node is Node3D:
		rows.append([node.get_class(), node.transform, node.visible])
	for child in node.get_children():
		_snapshot(child, rows)

func _same_visual(a: Dictionary, b: Dictionary) -> bool:
	var left := []
	var right := []
	_snapshot(a.root, left)
	_snapshot(b.root, right)
	if left != right:
		return false
	if a.has("controls"):
		for key in a.controls.mechanisms:
			var old: Dictionary = a.controls.mechanisms[key]
			var current: Dictionary = b.controls.mechanisms[key]
			for property in ["last_servo_angle", "last_bell_angle", "endpoints_root", "length_errors_m", "closure_error_m", "solved"]:
				if old.get(property) != current.get(property):
					return false
	return true

func _free_visual(visual: Dictionary) -> void:
	# Release instance materials before immediate free. The headless renderer can
	# otherwise query a material RID after its owner has been destroyed.
	for node: Node in visual.root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface_index in mesh_node.mesh.get_surface_count():
				mesh_node.set_surface_override_material(surface_index, null)
	visual.root.free()

func _run() -> void:
	var ids := [Adapter.STIK_ID, Adapter.STIK_GLOW_55AX_ID, Adapter.STIK_GLOW_61FX_ID,
		Adapter.STIK_GLOW_FS64V_ID, Adapter.EXTRA_ID, Adapter.P51_ID, Adapter.TIMBER_ID, Adapter.AVANTI_ID]
	for id: String in ids:
		var reference := Adapter.build(id)
		var candidate := Adapter.build(id)
		_check(id + " paired models build", not reference.is_empty() and not candidate.is_empty())
		if reference.is_empty() or candidate.is_empty():
			quit(1)
			return
		root.add_child(reference.root)
		root.add_child(candidate.root)
		var equal := true
		for frame in 64:
			var phase := float(frame) * 0.71
			var commands := {roll = sin(phase) * 0.7, pitch = cos(phase * 0.63) * 0.6,
				yaw = sin(phase * 0.83) * 0.7, throttle = float(frame % 5) / 4.0}
			var rotations := Commands.hinge_rotations(commands)
			var transform := Transform3D(Basis.from_euler(Vector3(phase * 0.1, -phase * 0.14, phase * 0.03)), Vector3(frame, 2, -frame))
			reference.root.transform = transform
			candidate.root.transform = transform
			Adapter.apply_surfaces(reference, rotations)
			Adapter.apply_throttle(reference, commands.throttle)
			Adapter.apply_controls(candidate, rotations, commands.throttle)
			if not _same_visual(reference, candidate):
				equal = false
				printerr("visual mismatch: ", id, " frame ", frame)
				break
		_check(id + " all node transforms and linkage branches match over 64 control poses", equal)
		if id == Adapter.STIK_ID:
			# Keep the standalone methods valid, including interleaving them after a batch.
			Adapter.apply_surfaces(reference, Commands.hinge_rotations(Commands.neutral_commands()))
			Adapter.apply_surfaces(candidate, Commands.hinge_rotations(Commands.neutral_commands()))
			Adapter.apply_throttle(reference, 1.0)
			Adapter.apply_throttle(candidate, 1.0)
			_check("standalone immediate updates remain equivalent after batching", _same_visual(reference, candidate))
			reference.controls.mechanisms.erase("throttle")
			candidate.controls.mechanisms.erase("throttle")
			var rotations := Commands.hinge_rotations({roll = 0.4, pitch = -0.2, yaw = 0.3, throttle = 0.8})
			Adapter.apply_surfaces(reference, rotations)
			Adapter.apply_throttle(reference, 0.8)
			Adapter.apply_controls(candidate, rotations, 0.8)
			_check("missing throttle linkage retains surface updates", _same_visual(reference, candidate))
		_free_visual(reference)
		_free_visual(candidate)
	print("control presentation: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)
