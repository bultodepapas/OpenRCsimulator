extends SceneTree
const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const Policy := preload("res://render/lighting/lighting_policy.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	Policy.apply({"aircraft_lighting_quality": "high"})
	var stage := Node3D.new()
	root.add_child(stage)
	var plane := Node3D.new()
	stage.add_child(plane)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.9)
	body.mesh = box
	plane.add_child(body)
	var rig := Rig.new()
	var result := rig.configure(plane, Profile.preset("classic_rc"))
	if not result.get("ok", false):
		printerr("configuration failed ", result)
		quit(1)
		return
	rig.set_mode("off")
	var lamp := rig.kit.get_node("strobe_left") as MeshInstance3D
	var material := lamp.get_surface_override_material(0) as ShaderMaterial
	var telemetry := {"effects_allowed": true, "distance_m": 0.0, "exposure": 1.0, "maneuver": 0.0, "throttle": 0.6}
	rig.advance(1.0, telemetry)
	var first_writes: int = rig.budget_info().frame_parameter_writes
	var first_clock: float = material.get_shader_parameter("local_clock")
	rig.advance(2.0, telemetry)
	var second_writes: int = rig.budget_info().frame_parameter_writes
	var second_clock: float = material.get_shader_parameter("local_clock")
	var hidden := not lamp.visible and not rig.kit.visible
	rig.advance(2.0, telemetry)
	var same_writes: int = rig.budget_info().frame_parameter_writes
	rig.set_mode("all")
	rig.advance(3.0, telemetry)
	var on_writes: int = rig.budget_info().frame_parameter_writes
	var on_clock: float = material.get_shader_parameter("local_clock")
	var on_visible := lamp.visible and rig.kit.visible
	print("OBS hidden=", hidden, " first_writes=", first_writes, " second_writes=", second_writes, " clocks=", first_clock, ",", second_clock, " same_writes=", same_writes, " reenabled=", on_visible, " reenabled_writes=", on_writes, " reenabled_clock=", on_clock)
	var ok := hidden and second_writes > 0 and first_clock == 1.0 and second_clock == 2.0 and same_writes == 0 and on_visible and on_clock == 3.0
	rig.dispose()
	rig.free()
	stage.free()
	print("lighting disabled probe: 1 check, ", 0 if ok else 1, " failed")
	quit(0 if ok else 1)
