extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Turbine := preload("res://physics/turbine.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")

const JET_PATH := "res://data/aircraft/sebart_avanti_s_a200.json"
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"


func _initialize() -> void:
	var jet := AircraftData.load_file(JET_PATH)
	var stik := AircraftData.load_file(STIK_PATH)
	if not jet.get("ok", false) or not stik.get("ok", false):
		push_error("AircraftData.load_file failed: jet=%s stik=%s" % [str(jet.get("errors", [])), str(stik.get("errors", []))])
		quit(1)
		return

	var jet_model: Dictionary = jet.model
	var stik_model: Dictionary = stik.model
	var jet_prop: Dictionary = jet_model.propulsion
	var stik_prop: Dictionary = stik_model.propulsion
	var raw_jet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JET_PATH))
	var raw_stik: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STIK_PATH))

	print("JET id=%s sha256=%s" % [jet_model.id, jet.input_identity.sha256])
	print("JET load_warnings=%s" % str(jet.warnings))
	_print_airframe("JET", jet_model)
	_print_inventory("JET", raw_jet)
	_print_fuel_cg_sensitivity("JET", jet_model, raw_jet)
	print("JET propulsion kind=%s axis=%s offset_LE=%s intake_offset_LE=%s" % [str(jet_prop.kind), str(jet_prop.axis), str(jet_prop.offset), str(jet_prop.intake_offset)])
	print("JET turbine idle_rpm=%.1f max_rpm=%.1f installed_factor=%.6f ram_flow=%.9f rotor_inertia=%.9f rotor_sense=%.1f" % [jet_prop.idle_rpm, jet_prop.max_rpm, jet_prop.installed_factor, jet_prop.ram_flow, jet_prop.rotor_inertia, jet_prop.rotor_sense])
	for rpm: float in [jet_prop.idle_rpm, jet_prop.max_rpm]:
		for speed: float in [0.0, 70.0]:
			var mdot: float = Turbine.mass_flow(rpm, jet_prop, 1.225, speed)
			var gross: float = Turbine.gross_thrust(rpm, jet_prop, 1.225, speed)
			var net: float = Turbine.thrust(rpm, speed, jet_prop, 1.225)
			var fuel: float = Turbine.fuel_flow(rpm, jet_prop)
			var loads: PackedFloat64Array = Turbine.loads(M.v3(speed, 0.0, 0.0), rpm, jet_prop, 1.225)
			print("JET rpm=%.0f V=%.1f rho=1.225 mdot=%.9f gross=%.6f net=%.6f fuel=%.9f SFC_gross=%.6f SFC_net=%.6f loads=%s" % [rpm, speed, mdot, gross, net, fuel, fuel * 3600.0 / maxf(gross, 1e-12), fuel * 3600.0 / maxf(net, 1e-12), str(loads)])
	print("JET rotor_momentum_at_max=%s" % str(Turbine.rotor_momentum(jet_prop.max_rpm, jet_prop)))
	print("JET rho_sensitivity max_rpm V=0.0 rho=1.000 net=%.6f; rho=0.900 net=%.6f" % [Turbine.thrust(jet_prop.max_rpm, 0.0, jet_prop, 1.0), Turbine.thrust(jet_prop.max_rpm, 0.0, jet_prop, 0.9)])

	print("STIK id=%s sha256=%s" % [stik_model.id, stik.input_identity.sha256])
	print("STIK load_warnings=%s" % str(stik.warnings))
	_print_airframe("STIK", stik_model)
	_print_inventory("STIK", raw_stik)
	_print_fuel_cg_sensitivity("STIK", stik_model, raw_stik)
	var raw_engine: Dictionary = raw_stik.propulsion.engine
	var raw_propeller: Dictionary = raw_stik.propulsion.propeller
	var prop_mass := 0.0
	for item: Dictionary in raw_stik.inventory:
		if item.id == "item_propeller_main":
			prop_mass = item.mass.value
	print("STIK engine=%s peak_power_W=%.3f peak_power_rpm=%.1f max_rpm_static=%.1f prop=%s D_m=%.6f prop_inventory_mass_kg=%.6f prop_rotating_inertia_kgm2=%.9f" % [raw_engine.name, raw_engine.peak_power.value, raw_engine.peak_power_rpm.value, raw_engine.max_rpm_static.value, raw_propeller.name, raw_propeller.diameter.value, prop_mass, raw_propeller.rotating_inertia.value])
	var prop_rpm: float = raw_engine.max_rpm_static.value
	print("STIK rotor_momentum_at_static=%s" % str(M.v3(stik_prop.rotor_inertia * prop_rpm * TAU / 60.0, 0.0, 0.0)))
	for speed: float in [0.0, 5.0, 15.0]:
		var point: PackedFloat64Array = Propulsion.thrust_torque(M.v3(speed, 0.0, 0.0), prop_rpm, stik_prop, 1.225)
		var absorbed_power: float = point[1] * prop_rpm * TAU / 60.0
		print("STIK static_rpm=%.1f V=%.1f thrust_N=%.6f torque_Nm=%.6f J=%.6f shaft_power_W=%.3f" % [prop_rpm, speed, point[0], point[1], point[2], absorbed_power])

	quit(0)


func _print_airframe(label: String, model: Dictionary) -> void:
	print("%s mass_kg=%.9f cg_LE=%s inventory_cg_LE=%s inertia_FRD=%s reference_S_m2=%.9f_b_m=%.9f_c_m=%.9f" % [label, model.mass_kg, str(model.cg_le), str(model.cg_inventory_le), str(model.inertia), model.reference.S, model.reference.b, model.reference.c])


func _print_inventory(label: String, raw: Dictionary) -> void:
	var total := 0.0
	var fuel := 0.0
	var ballast := 0.0
	for item: Dictionary in raw.inventory:
		var mass: float = item.mass.value
		total += mass
		if item.name.to_lower().contains("fuel (") or item.name.to_lower().contains("kerosene"):
			fuel += mass
		if item.name.to_lower().contains("virtual reference-build balancing mass"):
			ballast += mass
	print("%s inventory_mass_kg=%.9f fuel_mass_kg=%.9f dry_mass_kg=%.9f virtual_ballast_kg=%.9f ballast_fraction=%.6f" % [label, total, fuel, total - fuel, ballast, ballast / total])


func _print_fuel_cg_sensitivity(label: String, model: Dictionary, raw: Dictionary) -> void:
	var total: float = model.mass_kg
	var fuel_mass := 0.0
	var fuel_position := M.v3(0.0, 0.0, 0.0)
	for item: Dictionary in raw.inventory:
		var lower_name: String = item.name.to_lower()
		if lower_name.contains("half tank") or lower_name.contains("declared fuel state"):
			fuel_mass = item.mass.value
			var position: Array = item.position.value
			fuel_position = M.v3(position[0], position[1], position[2])
	var wet_cg: PackedFloat64Array = model.cg_inventory_le
	var empty_cg := M.scale(M.sub(M.scale(wet_cg, total), M.scale(fuel_position, fuel_mass)), 1.0 / (total - fuel_mass))
	var full_cg := M.scale(M.add(M.scale(wet_cg, total), M.scale(fuel_position, fuel_mass)), 1.0 / (total + fuel_mass))
	print("%s declared_fuel_CG_sensitivity half_state=%s full_assumed=%s empty=%s full_to_empty_dx_mm=%.3f" % [label, str(wet_cg), str(full_cg), str(empty_cg), (empty_cg[0] - full_cg[0]) * 1000.0])
