# US-V18c: the Ugly Stik's radio and fuel installation (fuel tank and lines, receiver battery, receiver, switch harness,
# servo leads), laid out by equipment.installation from the Jensen compartments and the flight inventory. Visual only:
# the flight model keeps its own mass items. Interior parts belong to the maintenance group; the switch plate is outside.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const Equipment := preload("res://aircraft/ugly_stik_equipment.gd")
const D: Dictionary = Geometry.DATA

const TANK_PLASTIC := Color("ddd8c8") # milky polyethylene
const RUBBER := Color("1b1d20")
const BRASS := Color("b88736")
const STEEL := Color("9ca3a8")
const LEAD := Color("15181b")
const FOAM := Color("c9c3b2") # latex foam
const SHRINK := Color("2f5fae") # NiCd pack shrink wrap
const RECEIVER := Color("2a2d31")
const SWITCH_PLASTIC := Color("101214")
const FUEL_LINE_RADIUS_M := 0.0027 # matches the delivered silicone lines
const LEAD_RADIUS_M := 0.00065
const NIPPLE_LENGTH_M := 0.010
const FUSELAGE_SIDE_M := 0.00635 # Jensen sheet 1: 1/4 in sides
const FUSELAGE_BOTTOM_M := 0.0024 # 3/32 in bottom


## Builds the installation under `service` (and the switch plate under `linkages`) and routes every servo lead to the
## receiver. Returns the placed parts in root space for the checks.
static func build(root: Node3D, service: Node3D, linkages: Node3D, servos: Dictionary) -> Dictionary:
	var spec: Dictionary = D.equipment.installation
	var parts := {}
	parts["tank"] = _add_tank(service, spec.tank)
	parts["fuel_line"] = _add_fuel_line(root, service, "fuel", Equipment.engine_origin() + Equipment.engine_anchor("engine_fuel_grommet"), parts.tank.feed_tip, "M_Silicone_Fuel")
	parts["pressure_line"] = _add_fuel_line(root, service, "pressure", Equipment.engine_origin() + Equipment.engine_anchor("engine_pressure_grommet"), parts.tank.vent_tip, "M_Silicone_Pressure")
	parts["battery"] = _add_battery(service, spec.battery)
	parts["receiver"] = _add_receiver(service, spec.receiver)
	parts["switch"] = _add_switch(service, linkages, spec.switch_zy)
	_route_leads(service, servos, parts)
	return parts


## Fuselage interior at station z: (inner half width, floor top, outer top).
static func _interior(z: float) -> Vector3:
	var stations: Array = D.fuselage_stations
	for i in range(stations.size() - 1):
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		if float(a[0]) <= z and z <= float(b[0]):
			var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			return Vector3(lerpf(float(a[1]), float(b[1]), t) - FUSELAGE_SIDE_M, lerpf(float(a[3]), float(b[3]), t) + FUSELAGE_BOTTOM_M, lerpf(float(a[2]), float(b[2]), t))
	return Vector3.ZERO


## Highest floor top under a part `length` long centred at station z (the nose floor rises toward F1).
static func _floor_under(z: float, length: float) -> float:
	return maxf(_interior(z - length * 0.5).y, _interior(z + length * 0.5).y)


static func _add_tank(service: Node3D, tank: Dictionary) -> Dictionary:
	var size := Vector3(float(tank.size[0]), float(tank.size[1]), float(tank.size[2]))
	var centre := Vector3(float(tank.centre[0]), float(tank.centre[1]), float(tank.centre[2]))
	var body := MeshInstance3D.new()
	body.name = "fuel_tank"
	body.mesh = _rounded_prism(size, float(tank.corner))
	body.mesh.surface_set_material(0, Finish.material(TANK_PLASTIC, "plastic"))
	body.position = centre
	service.add_child(body)
	# Neck and rubber stopper on the front face, a cap screw, and two brass nipples: feed (clunk) and vent.
	var front := centre + Vector3(0, 0, -size.z * 0.5)
	_add(service, _cylinder("fuel_tank_neck", 0.0105, 0.003, TANK_PLASTIC, "plastic", 16), front + Vector3(0, 0, -0.0015), Vector3.BACK)
	_add(service, _cylinder("fuel_tank_stopper", 0.009, 0.004, RUBBER, "rubber", 16), front + Vector3(0, 0, -0.005), Vector3.BACK)
	_add(service, _cylinder("fuel_tank_cap_screw", 0.003, 0.002, STEEL, "steel", 8), front + Vector3(0, 0, -0.008), Vector3.BACK)
	var face := front.z - 0.007
	var feed := Vector3(-0.0045, centre.y - 0.003, face)
	var vent := Vector3(0.0045, centre.y + 0.003, face)
	for nipple: Vector3 in [feed, vent]:
		_add(service, _cylinder("fuel_tank_nipple", 0.0016, NIPPLE_LENGTH_M, BRASS, "aluminum", 8), nipple + Vector3(0, 0, -NIPPLE_LENGTH_M * 0.5), Vector3.BACK)
	return {"centre": centre, "size": size, "corner": float(tank.corner), "wall": float(tank.wall),
		"feed_tip": feed + Vector3(0, 0, -NIPPLE_LENGTH_M), "vent_tip": vent + Vector3(0, 0, -NIPPLE_LENGTH_M)}


## Silicone line from an engine grommet (F1 mid-plane) back to a tank nipple, in the engine's own line material.
static func _add_fuel_line(root: Node3D, service: Node3D, label: String, grommet: Vector3, nipple_tip: Vector3, material_name: String) -> Array[Vector3]:
	var f1_back := float(D.equipment.firewall_z) + 0.0064
	var points: Array[Vector3] = [grommet, Vector3(grommet.x, grommet.y, f1_back + 0.004)]
	points.append(Vector3(lerpf(grommet.x, nipple_tip.x, 0.5), lerpf(grommet.y, nipple_tip.y, 0.55), lerpf(f1_back, nipple_tip.z, 0.55)))
	points.append(nipple_tip + Vector3(0, 0, -0.004))
	points.append(nipple_tip + Vector3(0, 0, 0.006)) # slipped over the nipple
	var path := _catmull_rom(points, 8)
	var line := MeshInstance3D.new()
	line.name = label + "_line_to_tank"
	line.mesh = _tube(path, FUEL_LINE_RADIUS_M, 10)
	line.mesh.surface_set_material(0, _engine_material(root, material_name))
	service.add_child(line)
	return path


static func _add_battery(service: Node3D, battery: Dictionary) -> Dictionary:
	var cells := int(battery.cells)
	var radius := float(battery.cell_radius)
	var length := float(battery.cell_length)
	var foam := float(battery.foam)
	var xz := Vector2(float(battery.centre_xz[0]), float(battery.centre_xz[1]))
	var floor_y := _floor_under(xz.y, length + 0.006)
	var axis_y := floor_y + foam + radius
	_add(service, _box("battery_foam", Vector3(radius * 2.0 * cells + 0.006, foam, length + 0.006), FOAM, "rubber"), Vector3(xz.x, floor_y + foam * 0.5, xz.y), Vector3.UP)
	for cell in cells:
		var x := xz.x + (float(cell) - (cells - 1) * 0.5) * radius * 2.0
		_add(service, _cylinder("battery_cell", radius, length, SHRINK, "plastic", 14), Vector3(x, axis_y, xz.y), Vector3.BACK)
	var size := Vector3(radius * 2.0 * cells, radius * 2.0 + foam, length)
	return {"centre": Vector3(xz.x, floor_y + size.y * 0.5, xz.y), "size": size, "lead": Vector3(xz.x - radius * (cells - 1), axis_y, xz.y + length * 0.5)}


static func _add_receiver(service: Node3D, receiver: Dictionary) -> Dictionary:
	var size := Vector3(float(receiver.size[0]), float(receiver.size[1]), float(receiver.size[2]))
	var xz := Vector2(float(receiver.centre_xz[0]), float(receiver.centre_xz[1]))
	var under := float(receiver.foam[0])
	var over := float(receiver.foam[1])
	var floor_y := _floor_under(xz.y, size.z + 0.006)
	var centre := Vector3(xz.x, floor_y + under + size.y * 0.5, xz.y)
	# Wrapped in foam: a pad under it and one over it, the case showing at the sides.
	_add(service, _box("receiver_foam_under", Vector3(size.x + 0.008, under, size.z + 0.006), FOAM, "rubber"), Vector3(centre.x, floor_y + under * 0.5, centre.z), Vector3.UP)
	_add(service, _box("receiver_foam_over", Vector3(size.x + 0.008, over, size.z + 0.006), FOAM, "rubber"), centre + Vector3(0, size.y * 0.5 + over * 0.5, 0), Vector3.UP)
	_add(service, _box("receiver_case", size, RECEIVER, "plastic"), centre, Vector3.UP)
	# Two 2.4 GHz antenna leads from the front, at right angles.
	var front := centre + Vector3(0, 0, -size.z * 0.5)
	for direction: Vector3 in [Vector3(-0.6, 0.8, -0.2).normalized(), Vector3(0.8, 0.1, -0.6).normalized()]:
		var tip := front + direction * 0.045
		var antenna := MeshInstance3D.new()
		antenna.name = "receiver_antenna"
		antenna.mesh = _tube([front, front + direction * 0.01, tip], 0.0005, 5)
		antenna.mesh.surface_set_material(0, Finish.material(LEAD, "rubber"))
		service.add_child(antenna)
	# Lead ports along the back end, low on the case.
	var ports: Array[Vector3] = []
	for index in range(7):
		ports.append(centre + Vector3(-size.x * 0.5 + 0.004 + index * (size.x - 0.008) / 6.0, -size.y * 0.15, size.z * 0.5))
	return {"centre": centre, "size": size + Vector3(0.008, under + over, 0.006), "ports": ports}


## Switch harness on the side opposite the muffler (-X), under the wing: body inside, face plate and toggle outside.
static func _add_switch(service: Node3D, linkages: Node3D, zy: Array) -> Dictionary:
	var z := float(zy[0])
	var y := float(zy[1])
	var inner := _interior(z)
	var outer_x := -(inner.x + FUSELAGE_SIDE_M)
	var body_centre := Vector3(-inner.x + 0.006, y, z)
	_add(service, _box("switch_body", Vector3(0.012, 0.012, 0.028), SWITCH_PLASTIC, "plastic"), body_centre, Vector3.UP)
	var plate := Node3D.new()
	plate.name = "switch_face_plate"
	plate.add_child(_placed(_box("switch_plate", Vector3(0.0015, 0.013, 0.032), SWITCH_PLASTIC, "plastic"), Vector3(outer_x - 0.00075, y, z), Vector3.UP))
	plate.add_child(_placed(_box("switch_toggle", Vector3(0.004, 0.004, 0.007), SWITCH_PLASTIC, "plastic"), Vector3(outer_x - 0.0035, y, z), Vector3.UP))
	for end in [-1.0, 1.0]:
		plate.add_child(_placed(_cylinder("switch_screw", 0.0011, 0.0008, STEEL, "steel", 8), Vector3(outer_x - 0.0017, y, z + end * 0.012), Vector3.LEFT))
	linkages.add_child(plate)
	return {"centre": body_centre, "plate": Vector3(outer_x, y, z), "port": body_centre + Vector3(0.006, 0, 0.014)}


## Every servo lead (and the battery-switch-receiver harness) runs low along the floor to a receiver port.
static func _route_leads(service: Node3D, servos: Dictionary, parts: Dictionary) -> void:
	var receiver: Dictionary = parts.receiver
	var ports: Array = receiver.ports
	var floor_y := float(receiver.centre.y) - float(receiver.size.y) * 0.5 + 0.004
	var order := ["aileron_left", "aileron_right", "elevator", "rudder", "throttle"]
	var paths: Array = []
	for index in order.size():
		var name: String = order[index]
		if not servos.has(name) or not servos[name].has("lead"):
			continue
		var start: Vector3 = servos[name].lead
		var away: Vector3 = servos[name].lead_dir
		var port: Vector3 = ports[index]
		var points: Array[Vector3] = [start, start + away * 0.010]
		if name.begins_with("aileron"):
			# Down out of the wing root through the saddle, then forward-down to the receiver.
			points.append(Vector3(start.x * 0.6, _interior(start.z).z - 0.012, start.z))
		points.append(Vector3(lerpf(start.x, port.x, 0.6), floor_y + 0.006, port.z + 0.035))
		points.append(port + Vector3(0, 0, 0.012))
		points.append(port)
		paths.append(_catmull_rom(points, 6))
	# Battery to switch to receiver.
	var battery_lead: Vector3 = parts.battery.lead
	var switch_port: Vector3 = parts.switch.port
	paths.append(_catmull_rom([battery_lead, battery_lead + Vector3(-0.004, 0.002, 0.01), Vector3(switch_port.x + 0.004, switch_port.y - 0.004, switch_port.z - 0.04), switch_port], 8))
	paths.append(_catmull_rom([switch_port + Vector3(0, 0, 0.002), Vector3(lerpf(switch_port.x, ports[6].x, 0.5), floor_y + 0.008, ports[6].z + 0.02), ports[6] + Vector3(0, 0, 0.012), ports[6]], 8))
	var lead_tool := SurfaceTool.new()
	lead_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for path: Array[Vector3] in paths:
		Equipment._sweep_tube(lead_tool, path, LEAD_RADIUS_M, 5)
	lead_tool.index()
	var leads := MeshInstance3D.new()
	leads.name = "radio_leads"
	leads.mesh = lead_tool.commit()
	leads.mesh.surface_set_material(0, Finish.material(LEAD, "rubber"))
	service.add_child(leads)
	parts["lead_paths"] = paths


## The engine GLB's own material by name (the delivered silicone lines), so tank lines match the engine bay.
static func _engine_material(root: Node3D, material_name: String) -> Material:
	var engine := root.find_child("engine_assembly", true, false) as MeshInstance3D
	if engine != null:
		for surface in engine.mesh.get_surface_count():
			var material := engine.mesh.surface_get_material(surface)
			if material != null and material.resource_name == material_name:
				return material
	push_error("Stik installation: engine material %s missing" % material_name)
	return Finish.material(Color.MAGENTA, "plastic")


## Box with rounded long edges: a rounded rectangle (x, y) extruded along z, with flat end caps. Indexed.
static func _rounded_prism(size: Vector3, corner: float) -> ArrayMesh:
	var outline: Array[Vector2] = []
	var half := Vector2(size.x, size.y) * 0.5 - Vector2(corner, corner)
	for quadrant in 4:
		var centre := Vector2(half.x * (1.0 if quadrant in [0, 3] else -1.0), half.y * (1.0 if quadrant < 2 else -1.0))
		for step in range(5):
			var angle := (quadrant + step / 4.0) * PI * 0.5
			outline.append(centre + Vector2.from_angle(angle) * corner)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := outline.size()
	for i in count:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % count]
		for z: float in [size.z * 0.5, -size.z * 0.5]:
			_face(tool, Vector3(0, 0, z), Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(0, 0, signf(z)), Vector3(0, 0, signf(z)), Vector3(0, 0, signf(z)))
		# Smooth side normals point from the rounded corners' centres.
		var na := Vector3(signf(a.x) * maxf(absf(a.x) - half.x, 0.0), signf(a.y) * maxf(absf(a.y) - half.y, 0.0), 0).normalized()
		var nb := Vector3(signf(b.x) * maxf(absf(b.x) - half.x, 0.0), signf(b.y) * maxf(absf(b.y) - half.y, 0.0), 0).normalized()
		var top := size.z * 0.5
		_face(tool, Vector3(a.x, a.y, top), Vector3(b.x, b.y, top), Vector3(b.x, b.y, -top), na, nb, nb)
		_face(tool, Vector3(a.x, a.y, top), Vector3(b.x, b.y, -top), Vector3(a.x, a.y, -top), na, nb, na)
	tool.index()
	tool.generate_tangents()
	return tool.commit()


## One triangle wound to face its mean normal (Godot front faces are clockwise), with per-corner normals.
static func _face(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var corners := [[a, na], [b, nb], [c, nc]]
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		corners = [[a, na], [c, nc], [b, nb]]
	for corner: Array in corners:
		tool.set_normal(corner[1])
		tool.set_uv(Vector2((corner[0] as Vector3).x, (corner[0] as Vector3).z))
		tool.add_vertex(corner[0])


static func _tube(path: Array, radius: float, sides: int) -> ArrayMesh:
	var points: Array[Vector3] = []
	for point in path:
		points.append(point)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	Equipment._sweep_tube(tool, points, radius, sides)
	tool.index()
	return tool.commit()


## Uniform Catmull-Rom through `points` (ends extended along the end chords), `steps` samples per segment.
static func _catmull_rom(points: Array[Vector3], steps: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var count := points.size()
	for i in range(count - 1):
		var p0: Vector3 = points[i - 1] if i > 0 else points[0] * 2.0 - points[1]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[i + 2] if i + 2 < count else points[count - 1] * 2.0 - points[count - 2]
		for step in range(steps):
			var t := float(step) / float(steps)
			result.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	result.append(points[count - 1])
	return result


static func _box(name: String, size: Vector3, color: Color, profile: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = Finish.material(color, profile)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	return instance


static func _cylinder(name: String, radius: float, length: float, color: Color, profile: String, segments: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = Finish.material(color, profile)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	return instance


## Places `instance` at `position` with its local +Y along `axis`.
static func _placed(instance: MeshInstance3D, position: Vector3, axis: Vector3) -> MeshInstance3D:
	instance.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis.normalized())), position)
	return instance


static func _add(parent: Node3D, instance: MeshInstance3D, position: Vector3, axis: Vector3) -> void:
	parent.add_child(_placed(instance, position, axis))
