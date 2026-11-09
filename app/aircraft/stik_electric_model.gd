# Electric installation on the unchanged, per-instance Jensen airframe.
# The motor and adapter are simple visual estimates, not a measured fit model.
extends RefCounted

const Airframe := preload("res://aircraft/ugly_stik_model.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Equipment := preload("res://aircraft/ugly_stik_equipment.gd")
const Controls := preload("res://aircraft/ugly_stik_controls.gd")
const Fracture := preload("res://aircraft/ugly_stik_fracture.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const D: Dictionary = Geometry.DATA

static func build() -> Dictionary:
	var root := Node3D.new()
	root.name = "airplane"
	root.set_meta("aircraft_id", "stik-electric-6s")
	root.set_meta("visual_revision", "stik-electric-6s-v1")
	var hinges := {}
	Airframe._fuselage(root)
	Airframe._wings(root, hinges)
	Airframe._tail(root, hinges)
	Fracture.build(root, Airframe.FUSELAGE_BREAK_STATION, {left = root.get_node("wing_frame_left"), right = root.get_node("wing_frame_right")})
	Equipment.retainers(root)
	var gear := {}
	Equipment._add_main_gear(root, gear)
	Equipment._add_nose_gear(root, gear)
	var propeller := _electric_propeller(root)
	_add_motor(root)
	var controls := _surface_controls(root, hinges)
	return {root = root, propeller = propeller, hinges = hinges, gear = gear, controls = controls}


static func _electric_propeller(root: Node3D) -> Node3D:
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(0, float(D.equipment.shaft_y), float(D.equipment.prop_z))
	propeller.set_meta("crash_section", "propeller")
	root.add_child(propeller)
	var blades := SurfaceTool.new()
	blades.begin(Mesh.PRIMITIVE_TRIANGLES)
	blades.set_material(Finish.material(Color("292b30"), "plastic"))
	# Renderer scales this authored mesh to the accepted installation.
	Equipment._prop_blades(blades, float(D.equipment.prop_diameter) * 0.5)
	blades.generate_normals()
	var blade_node := Equipment._flush(propeller, "propeller_blades", {"composite": blades})
	blade_node.set_meta("prop_strike_breaks", true)
	return propeller


static func _add_motor(root: Node3D) -> void:
	var shaft_y := float(D.equipment.shaft_y)
	var prop_z := float(D.equipment.prop_z)
	var firewall_z := float(D.equipment.firewall_z)
	var motor := Node3D.new()
	motor.name = "electric_motor"
	motor.position = Vector3(0, shaft_y, prop_z + 0.040)
	motor.set_meta("crash_section", "engine")
	root.add_child(motor)
	_cylinder(motor, "motor_can", 0.025, 0.050, Vector3.ZERO, Color("30353a"))
	_cylinder(motor, "motor_endbell", 0.022, 0.005, Vector3(0, 0, -0.0275), Color("b59b49"))
	_cylinder(motor, "motor_adapter", 0.006, 0.017, Vector3(0, 0, -0.036), Color("92999e"))
	# Visual stand-in for the motor mount; actual retention and fit remain unverified.
	var mount_length := firewall_z - (prop_z + 0.065)
	if mount_length > 0.0:
		_cylinder(root, "electric_motor_mount", 0.010, mount_length,
			Vector3(0, shaft_y, (firewall_z + prop_z + 0.065) * 0.5), Color("92999e"))


static func _cylinder(parent: Node3D, label: String, radius: float, length: float, position: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 24
	mesh.material = Finish.material(color, "aluminum")
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = position
	node.rotation.x = PI * 0.5
	node.set_meta("crash_section", "engine")
	node.set_meta("airframe_scuff_skip", true)
	parent.add_child(node)


static func _surface_controls(root: Node3D, hinges: Dictionary) -> Dictionary:
	# Reuse only the four surface linkages. No carburettor, throttle servo,
	# tank, fuel plumbing or combustion installation is built for electric.
	var assembly := Node3D.new()
	assembly.name = "control_system"
	root.add_child(assembly)
	var service := Node3D.new()
	service.name = "maintenance_installation"
	service.visible = false
	assembly.add_child(service)
	var linkages := Node3D.new()
	linkages.name = "external_linkages"
	assembly.add_child(linkages)
	var mechanisms := {}
	var servos := {}
	var failures: Array[String] = []
	Controls._build_wing_mechanism(root, assembly, service, linkages, hinges, "left", mechanisms, servos, failures)
	Controls._build_wing_mechanism(root, assembly, service, linkages, hinges, "right", mechanisms, servos, failures)
	Controls._build_tail_mechanism(root, assembly, service, linkages, hinges, "elevator", mechanisms, servos, failures)
	Controls._build_tail_mechanism(root, assembly, service, linkages, hinges, "rudder", mechanisms, servos, failures)
	Controls._add_servo_tray(service)
	Controls._batch_static_meshes(service, "maintenance_static")
	Controls._batch_static_meshes(linkages, "linkage_static")
	var controls := {ok = failures.is_empty(), root = root, assembly = assembly, maintenance_group = service,
		linkage_group = linkages, hinges = hinges, mechanisms = mechanisms, servos = servos,
		maintenance = false, errors = {}, failures = failures}
	Controls.update(controls)
	return controls
