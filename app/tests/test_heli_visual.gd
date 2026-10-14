# HELI-25b: static HX-700 source binding, rotor presentation, scale and skid contract.
# Run: godot --headless --path . --script res://tests/test_heli_visual.gd
extends SceneTree

const Model := preload("res://aircraft/hx700_model.gd")
const RotorVisual := preload("res://render/rotor/heli_rotor_visual.gd")
const RotorBlur := preload("res://render/rotor/heli_rotor_blur.gd")

var _count := 0
var _failures := 0


func _initialize() -> void:
	var model: Dictionary = Model.build()
	_check("builder returns the established aircraft keys and helicopter handles",
		model.has("root") and model.root is Node3D and model.root.name == "airplane"
		and model.get("propeller") is Node3D and model.get("hinges", {}).is_empty()
		and model.get("gear", {}).is_empty() and model.get("has_propeller") == false
		and model.get("main_rotor_pivot") is Node3D and model.get("tail_rotor_pivot") is Node3D,
		str(model.keys()))
	if model.is_empty() or not (model.get("root") is Node3D):
		_finish()
		return
	var root: Node3D = model.root
	get_root().add_child(root)
	await process_frame
	var frame := root.get_node_or_null("hx700_model_frame") as Node3D
	_check("runtime frame maps glTF axes into right/up/back model coordinates",
		frame != null
		and (frame.basis.x - Vector3(0.0, 0.0, -1.0)).length() < 1e-6
		and (frame.basis.y - Vector3(0.0, 1.0, 0.0)).length() < 1e-6
		and (frame.basis.z - Vector3(1.0, 0.0, 0.0)).length() < 1e-6)
	_check("supplied visual remains an explicitly unpaired HX-700/X-Cell surrogate",
		root.get_meta("visual_identity", "") == "HX-700 flybarless visual design"
		and root.get_meta("flight_reference", "").contains("X-Cell")
		and root.get_meta("pairing", "") == "not established")
	var main_hub_model: Vector3 = root.to_local((model.main_rotor_mount as Node3D).global_position)
	var tail_hub_model: Vector3 = root.to_local((model.tail_rotor as Node3D).global_position)
	_check("authored main and tail hubs land at the measured positions",
		frame != null
		and (main_hub_model - Vector3(0.0, 0.345, 0.0)).length() < 0.002
		and (tail_hub_model - Vector3(0.0, 0.197, 0.942)).length() < 0.003,
		"main %s; tail %s" % [main_hub_model, tail_hub_model])

	var main_profile: Dictionary = RotorBlur.measured_profile(model.main_rotor_mount, root)
	var tail_profile: Dictionary = RotorBlur.measured_profile(model.tail_rotor, root)
	_check("rotor profiles load from hash-bound static coverage data", 
		main_profile.get("profile_source") == "verified_static_analysis"
		and tail_profile.get("profile_source") == "verified_static_analysis")
	_check("source main rotor profile is measured in its authored frame",
		main_profile.has("radius") and absf(float(main_profile.radius) - 0.791367365) < 0.003
		and int(main_profile.get("blades", 0)) == 2, str(main_profile.get("radius", 0.0)))
	_check("source tail rotor profile is independently measured",
		tail_profile.has("radius") and absf(float(tail_profile.radius) - 0.14743219) < 0.003
		and int(tail_profile.get("blades", 0)) == 2, str(tail_profile.get("radius", 0.0)))
	_check("main visual adapter radius is X-Cell reference without scaling the airframe",
		is_equal_approx(float(model.main_rotor_mount.scale.x), 0.775 / 0.791367365)
		and is_equal_approx(float(model.main_rotor_mount.scale.y), float(model.main_rotor_mount.scale.x))
		and is_equal_approx(float(model.main_rotor_mount.scale.z), 1.0)
		and is_equal_approx(float(model.root.scale.x), 1.0))
	_check("tail radius remains authored until runtime data explicitly aligns it",
		is_equal_approx(float(model.tail_rotor.scale.x), 1.0)
		and is_equal_approx(float(model.tail_rotor_radius_runtime_m), 0.14743219)
		and Model.align_tail_rotor_radius(model, 0.13)
		and is_equal_approx(float(model.tail_rotor.scale.x), 0.13 / 0.14743219)
		and Model.align_tail_rotor_radius(model, 0.14743219)
		and is_equal_approx(float(model.tail_rotor.scale.x), 1.0))
	_check("main rotor radius alignment is explicit and does not compound",
		Model.align_main_rotor_radius(model, 0.70)
		and is_equal_approx(float(model.main_rotor_mount.scale.x), 0.70 / 0.791367365)
		and Model.align_main_rotor_radius(model, 0.775)
		and is_equal_approx(float(model.main_rotor_mount.scale.x), 0.775 / 0.791367365))
	Model.align_tail_rotor_radius(model, 0.13)
	_check("cached rotor-local profiles inherit selected runtime data radii",
		absf(float(main_profile.radius) * model.main_rotor_mount.scale.x - 0.775) < 1e-6
		and absf(float(tail_profile.radius) * model.tail_rotor.scale.x - 0.13) < 1e-6)
	_check("four physical skid support points are CG-relative and ordered",
		model.skids.size() == 4
		and model.skids.left_front.x < 0.0 and model.skids.right_front.x > 0.0
		and model.skids.left_front.z < 0.0 and model.skids.left_rear.z > 0.0
		and absf(model.skids.left_front.y + 0.1098) < 0.001
		and is_equal_approx(model.skids.left_front.y, model.skids.right_rear.y))

	var visual := RotorVisual.attach(model, get_root())
	_check("rotor visual attaches both rotor-specific blur adapters", visual != null
		and visual.get_node_or_null("propeller_blur") != null
		and visual.get_node_or_null("tail_rotor_blur") != null)
	if visual == null:
		_finish()
		root.free()
		return
	var state := {
		"omega_rad_s": 8.0,
		"tail_omega_rad_s": 24.0,
		"a1": deg_to_rad(4.0),
		"b1": deg_to_rad(3.0),
		"collective": deg_to_rad(9.0),
	}
	visual.update(state, 0.25)
	var main_expected: Basis = Basis(Vector3(0.0, 0.0, 1.0), -2.0) * model.main_rotor_rest
	var tail_expected: Basis = Basis(Vector3(0.0, 0.0, 1.0), -6.0) * model.tail_rotor_rest
	_check("visual and X-Cell shaft axes oppose and map positive speeds with explicit negative signs",
		float(model.main_visual_spin_sign) == -1.0 and float(model.tail_visual_spin_sign) == -1.0
		and model.main_rotor_axis_body == Vector3.DOWN and model.main_rotor_axis_visual == Vector3.UP
		and model.tail_rotor_axis_body == Vector3.RIGHT and model.tail_rotor_axis_visual == Vector3.LEFT
		and ((model.main_rotor_pivot as Node3D).basis.x - main_expected.x).length() < 1e-5
		and ((model.main_rotor_pivot as Node3D).basis.y - main_expected.y).length() < 1e-5
		and ((model.tail_rotor_pivot as Node3D).basis.x - tail_expected.x).length() < 1e-5
		and ((model.tail_rotor_pivot as Node3D).basis.y - tail_expected.y).length() < 1e-5)
	_check("rotor state forwards flap angles and collective in radians",
		is_equal_approx(float(visual.telemetry.a1), float(state.a1))
		and is_equal_approx(float(visual.telemetry.b1), float(state.b1))
		and is_equal_approx(float(visual.telemetry.collective), float(state.collective))
		and is_equal_approx(float(root.get_meta("heli_collective", NAN)), float(state.collective)))
	var a1 := 0.12
	var b1 := -0.10
	visual.update({"omega_rad_s": 0.0, "tail_omega_rad_s": 0.0, "a1": a1, "b1": b1}, 0.0)
	var expected_normal: Vector3 = Vector3(sin(b1), cos(a1) * cos(b1), sin(a1)).normalized()
	var observed_normal: Vector3 = (Model.GLTF_TO_MODEL * model.main_rotor_tilt.basis
		* model.main_rotor_mount.basis * Vector3.BACK).normalized()
	_check("cyclic flap aligns the visual shaft to MainRotor's exact first-harmonic normal",
		(observed_normal - expected_normal).length() < 1e-6
		and (frame.basis.x - Vector3(0.0, 0.0, -1.0)).length() < 1e-6,
		"observed %s; expected %s" % [observed_normal, expected_normal])
	_check("rotor blur uses blade-passing thresholds at low and high RPM",
		RotorBlur.blur_fraction(300.0, 2) == 0.0
		and RotorBlur.blur_fraction(600.0, 2) > 0.0
		and RotorBlur.blur_fraction(1440.0, 2) == 1.0)
	var main_blur := visual.get_node("propeller_blur") as RotorBlur
	var tail_blur := visual.get_node("tail_rotor_blur") as RotorBlur
	_check("each rotor blur keeps independent measured blade count and disc mesh",
		int(main_blur.measured.get("blades", 0)) == 2 and int(tail_blur.measured.get("blades", 0)) == 2
		and main_blur.get_node_or_null("analytic_rotor_disc") is MeshInstance3D
		and tail_blur.get_node_or_null("analytic_rotor_disc") is MeshInstance3D)
	var main_sources: Array[MeshInstance3D] = []
	for surface: Dictionary in main_blur.measured.surfaces:
		var source: MeshInstance3D = surface.node
		if not main_sources.has(source):
			main_sources.append(source)
	main_blur.update(0.0)
	var stopped_blades_visible := main_sources.all(func(node: MeshInstance3D) -> bool: return node.visible)
	var rotor_disc: MeshInstance3D = main_blur.get_node("analytic_rotor_disc") as MeshInstance3D
	_check("stopped main rotor shows only authored blades",
		stopped_blades_visible and not rotor_disc.visible)
	main_blur.update(600.0)
	var fade_blades: Array[Node] = main_blur.find_children("*_blade_fade_*", "MeshInstance3D", true, false)
	_check("mid-RPM main rotor crossfades authored blades into the measured disc",
		main_sources.all(func(node: MeshInstance3D) -> bool: return not node.visible)
		and fade_blades.any(func(node: Node) -> bool: return node.visible) and rotor_disc.visible)
	main_blur.update(1440.0)
	_check("high-RPM main rotor keeps the analytic disc and suppresses strobing blades",
		main_sources.all(func(node: MeshInstance3D) -> bool: return not node.visible)
		and fade_blades.all(func(node: Node) -> bool: return not node.visible) and rotor_disc.visible)
	var disc_mesh := rotor_disc.mesh as ArrayMesh
	var disc_vertex_alpha_max := 0.0
	if disc_mesh != null:
		for surface in disc_mesh.get_surface_count():
			var arrays: Array = disc_mesh.surface_get_arrays(surface)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for color: Color in colors:
				disc_vertex_alpha_max = maxf(disc_vertex_alpha_max, color.a)
	var full_opacity := float(main_blur._disc_materials[0].albedo_color.a) if not main_blur._disc_materials.is_empty() else 0.0
	_check("full-speed main disc has measured coverage geometry and readable opacity",
		disc_mesh != null and disc_mesh.get_surface_count() > 0
		and disc_vertex_alpha_max > 0.3 and full_opacity >= 0.99,
		"surfaces %d; max measured alpha %.3f; material alpha %.3f" % [
			disc_mesh.get_surface_count() if disc_mesh != null else 0, disc_vertex_alpha_max, full_opacity])
	var tail_sources: Array[MeshInstance3D] = []
	for surface: Dictionary in tail_blur.measured.surfaces:
		var source: MeshInstance3D = surface.node
		if not tail_sources.has(source):
			tail_sources.append(source)
	var tail_disc := tail_blur.get_node("analytic_rotor_disc") as MeshInstance3D
	tail_blur.update(1000.0)
	var tail_fade_blades: Array[Node] = tail_blur.find_children("*_blade_fade_*", "MeshInstance3D", true, false)
	_check("tail rotor crossfades at its own blade-passing rate",
		tail_sources.all(func(node: MeshInstance3D) -> bool: return not node.visible)
		and tail_fade_blades.any(func(node: Node) -> bool: return node.visible) and tail_disc.visible)
	tail_blur.update(7369.0)
	_check("geared high-speed tail rotor suppresses authored blades and shows its disc",
		tail_sources.all(func(node: MeshInstance3D) -> bool: return not node.visible)
		and tail_fade_blades.all(func(node: Node) -> bool: return not node.visible) and tail_disc.visible)

	visual.update({"omega_rad_s": NAN, "tail_omega_rad_s": -INF, "a1": INF, "b1": "bad", "collective": NAN}, 0.1)
	_check("invalid visual telemetry is clamped to finite neutral values",
		visual.telemetry.values().all(func(value: Variant) -> bool: return is_finite(float(value)))
		and float(visual.telemetry.omega_rad_s) == 0.0
		and float(visual.telemetry.tail_omega_rad_s) == 0.0
		and float(visual.telemetry.a1) == 0.0
		and float(visual.telemetry.b1) == 0.0
		and float(visual.telemetry.collective) == 0.0)

	visual.queue_free()
	root.queue_free()
	await process_frame
	_finish()


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _finish() -> void:
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
