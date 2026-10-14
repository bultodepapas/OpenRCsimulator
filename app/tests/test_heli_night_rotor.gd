# Run: godot --headless --path app --script res://tests/test_heli_night_rotor.gd
extends SceneTree

const Rotor := preload("res://render/rotor/heli_night_rotor.gd")

const TOP := Color(1.0, 0.46, 0.12, 1.0)
const BOTTOM := Color(0.12, 0.66, 1.0, 1.0)

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_invalid_inputs()
	_stationary_and_spin_samples()
	_instances_and_cadence(world)
	_mesh_budget_and_shader_clock()
	world.queue_free()
	print("heli night rotor: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _invalid_inputs() -> void:
	var mount := Node3D.new()
	root.add_child(mount)
	_check("reject non-finite radius", Rotor.attach(mount, NAN, 0.0, TOP, BOTTOM) == null)
	_check("reject non-positive radius", Rotor.attach(mount, 0.0, 0.0, TOP, BOTTOM) == null)
	_check("reject non-finite plane", Rotor.attach(mount, 1.0, INF, TOP, BOTTOM) == null)
	var bad_color := Color(NAN, 0.0, 0.0)
	_check("reject non-finite upper color", Rotor.attach(mount, 1.0, 0.0, bad_color, BOTTOM) == null)
	var blade := _make_tip_mesh(0.62, 0.96)
	mount.add_child(blade)
	var accepted := Rotor.attach(mount, 1.0, 0.0, TOP, BOTTOM) as Rotor
	_check("valid rotor attaches", accepted != null)
	if accepted != null:
		_check("rest phase follows the model blade-tip azimuth modulo pi",
			absf(fposmod(accepted.rest_phase_offset_rad - 0.62 + PI * 0.5, PI) - PI * 0.5) < 0.03)
		accepted.update(INF, NAN)
		_check("non-finite telemetry sanitizes to stopped zero phase",
			accepted.current_omega_rad_s == 0.0 and is_finite(accepted.current_phase_rad))
		_check("node visibility controls all traces", accepted.visible and accepted.get_child_count() == 2)
		accepted.gain = 0.35
		_check("dusk gain updates without changing the phase inputs",
			accepted.gain == 0.35 and accepted.top_material.get_shader_parameter("effect_gain") == 0.35)
	mount.queue_free()


func _stationary_and_spin_samples() -> void:
	var radius := 0.93
	var phase := 0.7
	var stationary := Rotor._sample_coverage(phase, 0.0, phase, radius)
	var opposite := Rotor._sample_coverage(phase + PI, 0.0, phase, radius)
	var quarter := Rotor._sample_coverage(phase + PI * 0.5, 0.0, phase, radius)
	_check("stopped LEDs are discrete at their actual two-blade phase",
		stationary == 1.0 and opposite == 1.0 and quarter == 0.0)
	var positive_inside := Rotor._sample_coverage(phase - 0.5, 60.0, phase, radius)
	var positive_outside := Rotor._sample_coverage(phase - 1.4, 60.0, phase, radius)
	var negative_inside := Rotor._sample_coverage(phase + 0.5, -60.0, phase, radius)
	var negative_outside := Rotor._sample_coverage(phase + 1.4, -60.0, phase, radius)
	_check("positive speed sweeps the previous 1/60 s arc", positive_inside == 1.0 and positive_outside == 0.0)
	_check("negative speed reverses the finite shutter arc", negative_inside == 1.0 and negative_outside == 0.0)
	_check("invalid CPU sampling has no light coverage",
		Rotor._sample_coverage(0.0, NAN, phase, radius) == 0.0)


func _instances_and_cadence(world: Node3D) -> void:
	var mount_a := Node3D.new()
	var mount_b := Node3D.new()
	world.add_child(mount_a)
	world.add_child(mount_b)
	var first := Rotor.attach(mount_a, 1.0, 0.02, TOP, BOTTOM) as Rotor
	var second := Rotor.attach(mount_b, 1.0, -0.03, Color.WHITE, Color.CYAN) as Rotor
	_check("independent rotors create isolated materials and colors",
		first != null and second != null and first.top_material != second.top_material
		and first.bottom_material != second.bottom_material
		and first.top_material.get_shader_parameter("light_color") != first.bottom_material.get_shader_parameter("light_color"))
	if first == null or second == null:
		return
	first.update(120.0, 0.25)
	for frame in range(1, 25):
		second.update(float(frame) * 5.0, float(frame) * 0.01)
	second.update(120.0, 0.25)
	_check("identical final telemetry gives cadence-independent uniforms",
		first.current_omega_rad_s == second.current_omega_rad_s
		and first.current_phase_rad == second.current_phase_rad
		and first.top_material.get_shader_parameter("phase_rad") == second.top_material.get_shader_parameter("phase_rad")
		and first.top_material.get_shader_parameter("omega_rad_s") == second.top_material.get_shader_parameter("omega_rad_s"))
	_check("fixed visual shutter is independent of update count",
		first.top_material.get_shader_parameter("shutter_s") == Rotor.SHUTTER_SECONDS
		and second.top_material.get_shader_parameter("shutter_s") == Rotor.SHUTTER_SECONDS)


func _mesh_budget_and_shader_clock() -> void:
	var mesh := Rotor._build_annular_mesh(1.0, 0.0)
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var triangles := indices.size() / 3
	_check("each side stays within the 512-triangle rotor budget", triangles * 2 <= 512)
	var shader_text := FileAccess.get_file_as_string("res://render/rotor/heli_night_rotor.gdshader")
	_check("shader uses analytic caller state and fixed shutter, with no TIME clock",
		shader_text.contains("omega_rad_s") and shader_text.contains("phase_rad")
		and shader_text.contains("shutter_s") and not shader_text.contains("TIME"))


func _make_tip_mesh(angle: float, radius: float) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	for tip_angle: float in [angle - 0.01, angle + 0.01, angle]:
		var tip_radius := radius if absf(tip_angle - angle) > 0.001 else radius - 0.01
		vertices.append(Vector3(tip_radius * cos(tip_angle), tip_radius * sin(tip_angle), 0.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "blade_tip"
	instance.mesh = mesh
	return instance
