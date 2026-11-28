## CAM-FPV-02d: direct stock HX-700 camera, input and structural clearance.
extends SceneTree

const Flight := preload("res://helicopter_main.gd")

var failed := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var heli := Flight.new()
	heli.set_user_args(PackedStringArray(["--view=fpv", "--soundscape=off", "--physics-backend=gdscript_reference"]))
	root.add_child(heli)
	_check("direct stock flight starts with the nose installed", heli.startup_error.is_empty()
		and heli._rig != null and heli._rig.view == "fpv")
	if heli.startup_error.is_empty() and heli._rig != null:
		var airframe: Node3D = heli._airplane.root
		var canopy := airframe.find_child("Carenado", true, false) as MeshInstance3D
		var camera: Camera3D = heli._camera
		_check("the active stock canopy is available", canopy != null)
		if canopy != null:
			# GLB +X is the nose, +Y is up. Compare with the real mesh data and pivot.
			var eye := canopy.to_local(camera.global_position)
			var clear_m := eye.x - canopy.get_aabb().end.x
			_check("first frame places lens 15 mm ahead of the fixed canopy", absf(clear_m - 0.015) < 0.002
				and absf(eye.y - 0.155) < 0.002 and absf(eye.z) < 0.002)
			_check("the lens follows the drawn heading", (-camera.global_basis.z).dot(-airframe.global_basis.z) > 0.9999)
		var state: PackedFloat64Array = heli.session.sim.state.duplicate()
		var event := InputEventKey.new()
		event.pressed = true
		event.physical_keycode = KEY_1
		heli._unhandled_input(event)
		_check("pilot view remains selectable", heli._rig.view == "pilot")
		event.physical_keycode = KEY_3
		heli._unhandled_input(event)
		_check("3 restores stock FPV without advancing the helicopter", heli._rig.view == "fpv" and heli.session.sim.state == state)
		heli.creator_visual = {"name": "test replacement"}
		heli._bind_stock_fpv_mount()
		_check("an imported visual cannot inherit the HX-700 lens", not heli._rig.set_view("fpv") and heli._rig.view == "pilot")
	heli.free()
	print("helicopter FPV: %d checks, %d failures" % [checks, failed])
	quit(1 if failed else 0)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label)
