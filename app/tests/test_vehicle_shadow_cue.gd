## SA-04/SA-08: the planar vehicle cue for non-fixed-wing activities, and terrain-relative cue reception.
extends SceneTree

const VehicleShadowCue := preload("res://render/vehicle_shadow_cue.gd")
const Shadow := preload("res://render/shadow.gd")
const Projected := preload("res://render/projected_shadow.gd")
const ShadowSettings := preload("res://render/shadow_settings.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Spec := preload("res://spec.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance)
	return instance


func _select(technique: String, cue: String = "auto") -> void:
	ShadowSettings.apply({"shadow_technique": technique, "shadow_aircraft_cue": cue})


func _receiving_ground() -> void:
	var flat := func(_x: float, _z: float) -> float: return 2.0
	var level := Shadow.receiving_ground(Vector3(0, 10, 0), Vector3.UP, flat, 2.0)
	_check("SA-04: flat raised terrain is found with full fit", is_equal_approx(float(level.y), 2.0) and level.fit == 1.0)
	# Light from +x at 45°: the shadow lands toward −x, on a 3 m bank that is not under the vehicle.
	var bank := func(x: float, _z: float) -> float: return 3.0 if x < -4.0 else 0.0
	var landed := Shadow.receiving_ground(Vector3(0, 10, 0), Vector3(1, 1, 0).normalized(), bank, 1.0)
	_check("SA-04: the receiver follows the light to where the shadow lands, not straight down",
		is_equal_approx(float(landed.y), 3.0), str(landed))
	var ramp := func(x: float, _z: float) -> float: return x * 0.5
	var sloped := Shadow.receiving_ground(Vector3(0, 5, 0), Vector3.UP, ramp, 3.0)
	_check("SA-04: a steep ramp across the footprint fades the planar cue", float(sloped.fit) < 0.5, str(sloped))
	var gentle := func(x: float, _z: float) -> float: return x * 0.02
	_check("SA-04: a gentle slope keeps the cue", float(Shadow.receiving_ground(Vector3(0, 5, 0), Vector3.UP, gentle, 3.0).fit) == 1.0)
	_check("SA-04: no ground query keeps the historical flat field",
		is_nan(float(Shadow.receiving_ground(Vector3(0, 5, 0), Vector3.UP, Callable(), 1.0).y)))


func _vehicle_cue() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var vehicle := Node3D.new()
	vehicle.name = "Vehicle"
	host.add_child(vehicle)
	_box(vehicle, "Body", Vector3(1.0, 0.3, 2.0), Vector3.ZERO)
	var rotor := Node3D.new()
	rotor.name = "Rotor1"
	vehicle.add_child(rotor)
	_box(rotor, "Blade", Vector3(3.0, 0.02, 0.1), Vector3(0, 0.3, 0))
	vehicle.position = Vector3(0, 4, 0)
	var ground := func(_x: float, _z: float) -> float: return 1.5
	_select("auto")
	var cue := VehicleShadowCue.attach(host, vehicle, {}, ground, [rotor])
	cue._process(0.0)
	_check("SA-08: Auto keeps the vehicle on native shadows and collects nothing",
		not cue.carrier.visible and cue.carrier.get_node_or_null("ProjectedShadow") == null)
	_select("projected")
	cue._process(0.0)
	var projected: Node = cue.carrier.get_node_or_null("ProjectedShadow")
	_check("SA-08: Projected draws the vehicle cue", cue.carrier.visible and projected != null
		and (projected.get("receiver") as MeshInstance3D).visible)
	if projected != null:
		_check("SA-08: an excluded spinning rotor stays out of the silhouette", int(projected.get("triangle_count")) == 12,
			str(projected.get("triangle_count")))
		_check("SA-04: the receiver sits on the terrain under the vehicle",
			is_equal_approx(float(projected.get("receiver_height")), 1.5 + Spec.SHADOW.height)
			and is_equal_approx((projected.get("receiver") as MeshInstance3D).global_position.y, 1.5 + Spec.SHADOW.height))
		var alpha_now := float((cue.carrier.material_override as StandardMaterial3D).albedo_color.a)
		_check("SA-04: height fade is terrain-relative (2.5 m above a 1.5 m bank)",
			is_equal_approx(alpha_now, Shadow.alpha(2.5)), str(alpha_now))
	_select("projected", "off")
	cue._process(0.0)
	_check("SA-08: the saved Off cue hides the vehicle cue", not cue.carrier.visible
		or float((cue.carrier.material_override as StandardMaterial3D).albedo_color.a) == 0.0)
	_select("projected")
	var replacement := Node3D.new()
	host.add_child(replacement)
	_box(replacement, "Hull", Vector3(4, 1, 8), Vector3.ZERO)
	cue.set_vehicle(replacement)
	cue._process(0.0)
	projected = cue.carrier.get_node_or_null("ProjectedShadow")
	_check("SA-08: a replaced vehicle visual is rebound", projected != null and projected.get("source") == replacement)
	replacement.visible = false
	cue._process(0.0)
	_check("SA-08: a hidden vehicle hides its cue", not cue.carrier.visible)
	host.free()


func _helicopter_rotor_excluded() -> void:
	var heli: Dictionary = AirplaneBuilder.build(AirplaneBuilder.X_CELL_ID)
	if heli.is_empty() or heli.get("root") == null:
		_check("HX-700 builds for the rotor check", false)
		return
	var host := Node3D.new()
	root.add_child(host)
	var cue := VehicleShadowCue.attach(host, heli.root, {}, Callable(), VehicleShadowCue.helicopter_excluded(heli))
	var spinning := 0
	for entry: Dictionary in Projected.mesh_entries(heli.root):
		var node: Node = entry.instance
		while node != null and node != heli.root:
			if node == heli.get("main_rotor_pivot") or node == heli.get("tail_rotor_pivot"):
				spinning += 1
				break
			node = node.get_parent()
	_check("SA-08: the helicopter silhouette omits its spinning rotors", spinning == 0
		and not Projected.mesh_entries(heli.root).is_empty(), "%d rotor meshes" % spinning)
	host.free() # also frees the cue
	heli.root.free()


func _run() -> void:
	var previous: Dictionary = ShadowSettings.describe().requested
	_receiving_ground()
	_vehicle_cue()
	_helicopter_rotor_excluded()
	ShadowSettings.apply(previous)
	print("Vehicle shadow cue: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
