# EX-06: independent installation oracles, not measured flight-performance acceptance.
# Run: godot --headless --path app --script res://tests/test_extra_installation.gd
# Source: manual p43 dry CG; plan thrust angles. Evidence: docs/research/extra-300-realism/.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const FuelProperties := preload("res://physics/fuel_properties.gd")
const GlowProp := preload("res://physics/glow/propeller.gd")
const P := preload("res://physics/propulsion.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Model := preload("res://aircraft/extra_300s_model.gd")
const Geometry := preload("res://aircraft/extra_300s_geometry.gd")
const PATH := "res://data/aircraft/gp_extra_300s_60.json"
var checks := 0
var failures := 0


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1


func _initialize() -> void:
	call_deferred("_run") # Node3D.global_transform requires the scene tree to have entered.


func _run() -> void:
	var loaded := AD.load_file(PATH)
	check("Extra v2 file, wheel profile and model validate", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		quit(1)
		return
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var model: Dictionary = loaded.model
	_balance(raw, model)
	_installation(model)
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _balance(raw: Dictionary, model: Dictionary) -> void:
	var total := 0.0
	var dry := 0.0
	var fuel := 0.0
	var tank: Dictionary = raw.fuel_system.tanks[0]
	var fuel_inventory_id: String = str(tank.liquid_inventory_id)
	var moment := [0.0, 0.0, 0.0]
	var dry_moment := [0.0, 0.0, 0.0]
	for component: Dictionary in raw.inventory:
		var mass: float = component.mass.value
		var position: Array = component.position.value
		# Inventory roles bind by stable ID; display names are descriptive only.
		var is_fuel: bool = str(component.get("id", "")) == fuel_inventory_id
		total += mass
		if is_fuel:
			fuel += mass
		else:
			dry += mass
		for i in 3:
			moment[i] += mass * float(position[i])
			if not is_fuel:
				dry_moment[i] += mass * float(position[i])
	# EX-01's digitized manual station: model z=0, root LE=-0.1088 m.
	# Deliberately independent of the generator's ballast solution and declared loaded CG.
	check("dry tank balance at manual/plan station within 1 micrometre",
		absf(dry_moment[0] / dry - 0.1088) < 1e-6, "x=%.9f m" % (dry_moment[0] / dry))
	# FUEL-08: the full authored reference liquid amount is distinct from the tank's capacity.
	var registry: Dictionary = FuelProperties.load_file()
	var density: Dictionary = FuelProperties.blend_density(registry, tank.fuel) if registry.get("ok", false) else {}
	check("full finite-glow reference mass matches tank capacity and registry density",
		tank.capacity.value == 0.355 and fuel_inventory_id == "fuel_flight" and density.get("ok", false)
		and absf(fuel - 0.355e-3 * float(density.density_kg_m3)) <= 1e-9,
		"%s kg" % fuel)
	check("loaded mass equals complete component inventory", absf(total - model.mass_kg) < 1e-6)
	var cg_ok := true
	for i in 3:
		cg_ok = cg_ok and absf(moment[i] / total - model.cg_le[i]) < 1e-6
	check("loaded CG equals inventory on all axes", cg_ok)
	check("fuel forward of dry CG moves loaded balance forward", model.cg_le[0] < dry_moment[0] / dry)
	check("loaded balance is explicitly derived", raw.balance.plan_cg.kind == "derived")


func _installation(model: Dictionary) -> void:
	var prop: Dictionary = model.propulsion
	# Independent direction cosines from the plan's installation angles, not prop.axis itself.
	var down := deg_to_rad(0.5)
	var right := deg_to_rad(2.0)
	var axis := [cos(down) * cos(right), cos(down) * sin(right), sin(down)]
	var valid := prop.has("axis")
	for i in 3:
		valid = valid and absf(P.axis(prop)[i] - axis[i]) < 1e-12
	check("plan right/down thrust is active in body FRD", valid)
	var built: Dictionary = Model.build()
	root.add_child(built.root)
	var hub: Node3D = built.propeller
	var visual_axis: Vector3 = -hub.global_basis.z
	var mapped := [-visual_axis.z, visual_axis.x, -visual_axis.y]
	var axis_error := 0.0
	for i in 3:
		axis_error = maxf(axis_error, absf(mapped[i] - P.axis(prop)[i]))
	check("actual visual shaft matches physical shaft", axis_error < 1e-6, "max error " + String.num_scientific(axis_error))
	var at: Vector3 = hub.global_position
	var visual_le := [at.z - float(Geometry.DATA.wing.le_z_root), at.x, at.y]
	var arm_error := 0.0
	for i in 3:
		arm_error = maxf(arm_error, absf(visual_le[i] - model.cg_le[i] - prop.offset[i]))
	check("actual visual hub matches physical CG-relative arm", arm_error < 1e-6, "max error " + String.num_scientific(arm_error) + " m")
	check("selected 12x6 visual installation", absf(Geometry.DATA.propeller.diameter - 0.3048) < 1e-12
		and absf(Geometry.DATA.propeller.pitch - 0.1524) < 1e-12
		and absf(prop.diameter - Geometry.DATA.propeller.diameter) < 1e-12)
	built.root.free()
	var arm := [-prop.offset[0], prop.offset[1], -prop.offset[2]]
	for velocity in [[0.0, 0.0, 0.0], [17.0, 1.0, -2.0]]:
		var rpm: float = prop.glow.propeller.max_rpm
		var along: float = velocity[0] * axis[0] + velocity[1] * axis[1] + velocity[2] * axis[2]
		# The finite-glow propeller uses its declared annular model, not the legacy Ct/Cp tables.
		# Keep the shaft-axis force and r-cross-F/reaction-torque oracle independent of P.loads().
		var propeller_result: Dictionary = GlowProp.evaluate(rpm, along, 1.225, prop.glow.propeller)
		var thrust: float = float(propeller_result.thrust_n)
		var torque: float = float(propeller_result.torque_nm)
		var force := [axis[0] * thrust, axis[1] * thrust, axis[2] * thrust]
		var expected := [force[0], force[1], force[2],
			arm[1] * force[2] - arm[2] * force[1] - torque * axis[0],
			arm[2] * force[0] - arm[0] * force[2] - torque * axis[1],
			arm[0] * force[1] - arm[1] * force[0] - torque * axis[2]]
		var actual := P.loads(PackedFloat64Array(velocity), rpm, prop, 1.225)
		var ok := true
		for i in 6:
			ok = ok and absf(actual[i] - expected[i]) <= 1e-9 * maxf(1.0, absf(expected[i]))
		check("shaft-frame propeller wrench and r-cross-F minus shaft torque at " + str(velocity), ok)
		check("power produces right/down force and left torque reaction", actual[1] > 0.0 and actual[2] > 0.0 and actual[3] < 0.0)
	var momentum := Dynamics.rotor_momentum(model, prop.max_rpm)
	var h: float = prop.rotor_inertia * prop.max_rpm * TAU / 60.0
	var aligned := true
	for i in 3:
		aligned = aligned and absf(momentum[i] - h * axis[i]) < 1e-12
	check("rotor angular momentum follows the installed shaft", aligned)
	var stopped_loads: PackedFloat64Array = P.loads(PackedFloat64Array([17.0, 0.0, 0.0]), 0.0, prop, 1.225)
	var stopped_finite: bool = true
	for value in stopped_loads:
		stopped_finite = stopped_finite and is_finite(value)
	check("stopped propeller retains finite flow loads and zero rotor momentum",
		stopped_finite and stopped_loads != PackedFloat64Array([0, 0, 0, 0, 0, 0])
		and Dynamics.rotor_momentum(model, 0.0) == PackedFloat64Array([0, 0, 0]))
