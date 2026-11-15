## DR-29/30: parked preview parity and independently driven rotor observers.
extends SceneTree

const Visual = preload("res://vehicles/multirotor/multirotor_visual.gd")
const Data = preload("res://physics/multirotor_data.gd")
const Catalog = preload("res://vehicles/multirotor/multirotor_catalog.gd")
const Presentation = preload("res://ui/home_presentation.gd")
const Blur = preload("res://render/propeller_blur.gd")
const Shadow = preload("res://render/shadow.gd")
const Model = preload("res://assets/multirotors/ion-r5/ion_r5.glb")

var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: " + label)


func _initialize() -> void:
	_run.call_deferred()


## Compare every visible surface and its transform/material values, including procedural fallback meshes.
static func visible_geometry(node: Node3D) -> Dictionary:
	var out := {}
	for item: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not item.is_visible_in_tree():
			continue
		var surfaces := []
		for surface in item.mesh.get_surface_count():
			var material := item.get_active_material(surface) as BaseMaterial3D
			surfaces.append([var_to_bytes(item.mesh.surface_get_arrays(surface)), material.albedo_color,
				material.metallic, material.roughness, material.transparency])
		out[str(node.get_path_to(item))] = [Blur.relative(node, item), surfaces]
	return out


func _run() -> void:
	var loaded := Data.load_file(Catalog.DATA_PATH)
	var prepared := Data.prepare(loaded.data, loaded.sha256)
	check("stock data prepares", prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	for path: String in [Visual.MODEL_PATH, "res://assets/multirotors/missing-preview.glb"]:
		await compare(prepared.prepared, path)
	print("MR visual: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func compare(data: Dictionary, path: String) -> void:
	var parked := Visual.new()
	var flight := Visual.new()
	check("parked visual builds", parked.build(data, path, false))
	check("default flight visual builds", flight.build(data, path))
	root.add_child(parked.root)
	root.add_child(flight.root)
	await process_frame
	check("preview retains Home shadow extent before any flight pose", Shadow.model_extent(parked.root).is_equal_approx(Shadow.model_extent(flight.root)))
	var body := PackedFloat64Array([2.0, 4.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var stopped := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	parked.pose(body, stopped, 0.0)
	flight.pose(body, stopped, 0.0)
	var before := visible_geometry(parked.root)
	check("preview retains exact visible geometry, transforms and materials", before == visible_geometry(flight.root))
	check("preview retains Home bounds", Presentation.mesh_bounds(parked.root, parked.root) == Presentation.mesh_bounds(flight.root, flight.root))
	check("preview retains camera mount and fallback classification", parked.fpv_mount_frd == flight.fpv_mount_frd
		and parked.fixture == flight.fixture and parked.complete_rotors == flight.complete_rotors)
	check("preview creates no rotor blur nodes", parked.rotors.size() == 4
		and parked.rotors.all(func(r: Dictionary) -> bool: return r.blur == null))
	check("flight creates four manually driven observers", flight.rotors.size() == 4
		and flight.rotors.all(func(r: Dictionary) -> bool: return r.blur != null and not r.blur.is_processing()))
	flight.pose(body, PackedFloat64Array([0.0, 60.0, 500.0, 1500.0]), 0.016)
	check("each rotor retains its independent achieved-RPM blur", flight.blur_fraction(0) == 0.0
		and flight.blur_fraction(1) > 0.0 and flight.blur_fraction(1) < 1.0
		and flight.blur_fraction(2) == 1.0 and flight.blur_fraction(3) == 1.0)
	check("flight fades do not mutate the parked model", before == visible_geometry(parked.root))
	var phase := float(flight.rotors[3].phase)
	body[0] = 12.0
	body[2] = -5.0
	flight.pose(body, PackedFloat64Array([0.0, 60.0, 500.0, 1500.0]), 0.0)
	check("held frame preserves phase", float(flight.rotors[3].phase) == phase)
	check("unchanged RPM still follows body motion", flight.rotors.all(func(r: Dictionary) -> bool:
		return r.blur.global_transform.is_equal_approx(r.pivot.global_transform)))
	var phases := flight.rotors.map(func(r: Dictionary) -> float: return r.phase)
	flight.pose(body, stopped, 0.0)
	check("stopping preserves each rotor phase", phases == flight.rotors.map(func(r: Dictionary) -> float: return r.phase))
	var restored := visible_geometry(flight.root)
	check("stopping restores every original surface and material at its retained phase", before.size() == restored.size()
		and before.keys().all(func(key: String) -> bool: return restored.has(key) and before[key][1] == restored[key][1]))
	flight.root.free()
	check("retiring flight preserves the parked model", before == visible_geometry(parked.root))
	parked.root.free()
