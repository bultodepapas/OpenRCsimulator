extends SceneTree

const Data := preload("res://physics/aircraft_data.gd")
const Prop := preload("res://physics/propulsion.gd")
const Pack := preload("res://physics/battery/pack_ecm.gd")
const Supervisor := preload("res://physics/battery/esc_supervisor.gd")
const Flight := preload("res://sim/flight_session.gd")
const IDEAL := "res://data/aircraft/stik_electric_6s.json"
const FINITE := "res://data/aircraft/battery/stik_electric_6s_pack.json"
var checks := 0
var failures := 0

func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var ideal_path := IDEAL
	var finite_path := FINITE
	for arg: String in args:
		if arg.begins_with("--ideal="): ideal_path = arg.trim_prefix("--ideal=")
		if arg.begins_with("--finite="): finite_path = arg.trim_prefix("--finite=")
	var ideal := Data.load_file(ideal_path)
	var finite := Data.load_file(finite_path)
	check("ideal aircraft admits", ideal.ok, str(ideal.get("errors", [])))
	check("pack aircraft admits", finite.ok, str(finite.get("errors", [])))
	if ideal.ok and finite.ok:
		check("both modes apply the explicit wheel profile", ideal.model.wheel_profile.status == "applied" and finite.model.wheel_profile.status == "applied")
		var a: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ideal_path))
		var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(finite_path))
		var donor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
		check("shared wheel alias retains the exact donor gear", a.landing_gear == donor.landing_gear and b.landing_gear == donor.landing_gear)
		check("same physical inventory", a.inventory == b.inventory)
		check("same start, airframe, gear and controls", a.start == b.start and a.aero == b.aero and a.controls == b.controls and a.landing_gear == b.landing_gear)
		check("distinct energy modes", a.capabilities.energy == "fixed_voltage" and b.capabilities.energy == "pack_ecm")
		check("no glow or synthetic ballast", not a.has("fuel_system") and not str(a.inventory).contains("item_balance_mass_virtual") and not str(a.inventory).contains("item_engine_main"))
		var wrong_pack := b.duplicate(true)
		wrong_pack.propulsion.battery.pack.sha256 = "0".repeat(64)
		check("a corrupt pack identity is refused", not Data.validate_and_derive(wrong_pack).ok)
		var wrong_mass := b.duplicate(true)
		for item: Dictionary in wrong_mass.inventory:
			if item.id == "item_battery_main": item.mass.value += 0.1
		check("mismatched mounted pack mass is refused", not Data.validate_and_derive(wrong_mass).ok)
		var prop: Dictionary = ideal.model.propulsion
		var nominal := Prop.steady_operating_point(1.0, 0.0, prop, 1.225)
		check("nominal steady torque balance", nominal.get("ok", false), str(nominal))
		if nominal.get("ok", false):
			var ns := Prop.electric_source_state(nominal.rpm, 1.0, prop)
			check("nominal steady electrical input is available", ns.ok and ns.bus_power_w > 350.0 * ideal.model.mass_kg, str(ns))
			var thrust := Prop.loads(PackedFloat64Array([0.0, 0.0, 0.0]), nominal.rpm, prop, 1.225)
			check("nominal static thrust exceeds 1.2 weight", thrust[0] > 1.2 * ideal.model.mass_kg * 9.80665, str(thrust))
			print("STIK_NOMINAL ", JSON.stringify(nominal))
		var charged := prop.duplicate(true)
		charged.battery.voltage_v = 25.2
		var full := Prop.steady_operating_point(1.0, 0.0, charged, 1.225)
		check("full-charge steady torque balance", full.get("ok", false), str(full))
		if full.get("ok", false):
			var fs := Prop.electric_source_state(full.rpm, 1.0, charged)
			check("static full-charge steady current, power and rpm screen", fs.ok and fs.motor_current_a < 68.0 and fs.bus_power_w < 1850.0 and full.rpm < 12500.0, str(fs))
			print("STIK_FULL ", JSON.stringify(full))
		for speed: int in range(0, 31, 5):
			var flight := Prop.steady_operating_point(1.0, float(speed), charged, 1.225)
			check("bounded full-charge flight speed %d m/s" % speed, flight.get("ok", false) and float(flight.get("rpm", INF)) < 12500.0, str(flight))
		var fp: Dictionary = finite.model.propulsion
		var initial := Pack.initial_block(fp.battery, fp.motor, fp.esc.low_voltage_cutoff, 288.15)
		check("finite pack initializes", initial.get("ok", false), str(initial))
		if initial.get("ok", false):
			var point := Prop.electric_pack_state(0.0, 1.0, fp, true, initial.block, 288.15, 0.0)
			check("finite pack evaluates startup current and sag", point.get("ok", false), str(point))
			if point.get("ok", false):
				check("startup shows sag and unbounded current", point.bus_voltage_v < point.ocv_v and point.motor_current_a > 80.0)
				print("STIK_PACK_START ", JSON.stringify(point))
		var lvc: Dictionary = fp.esc.low_voltage_cutoff
		var cells := Supervisor.detect_cells(lvc, 25.2)
		var phase := Supervisor.step(lvc, 1.0, Supervisor.PHASE_NORMAL, 0.0, cells, 17.0, 1.0, 1.0)
		check("low-voltage model enters soft cut", cells == 6 and int(phase[1]) == Supervisor.PHASE_SOFT_CUT, str(phase))
		var reduced := Supervisor.step(lvc, phase[0], int(phase[1]), phase[2], cells, 17.0, 1.0, 3.0)
		check("low-voltage model reduces output", reduced[0] == 0.5, str(reduced))
		var recovered := Supervisor.step(lvc, reduced[0], int(reduced[1]), reduced[2], cells, 22.0, 0.0, 0.1)
		check("voltage recovery and throttle reset release cut", recovered[0] == 1.0 and int(recovered[1]) == Supervisor.PHASE_NORMAL, str(recovered))
		var ideal_flight := Flight.new()
		ideal_flight.setup(ideal_path, "stik-electric-6s")
		check("ideal session starts coupled without depletion", ideal_flight.is_flyable() and ideal_flight.shaft_is_coupled() and not ideal_flight.battery_is_dynamic(), str(ideal_flight.start_error))
		ideal_flight.free()
		var first := Flight.new()
		first.setup(finite_path, "stik-electric-6s")
		check("finite session starts coupled", first.is_flyable() and first.shaft_is_coupled() and first.battery_is_pack(), str(first.start_error))
		if first.is_flyable():
			first.input_enabled = false
			var saved: Dictionary = first.checkpoint()
			var second := Flight.new()
			second.setup(finite_path, "stik-electric-6s")
			second.input_enabled = false
			check("fresh finite owner restores checkpoint", second.is_flyable() and second.restore_checkpoint(bytes_to_var(var_to_bytes(saved))))
			first.sim.inputs[3] = 0.7
			second.sim.inputs[3] = 0.7
			var clean := true
			for i: int in 240:
				first.sim.step()
				second.sim.step()
				if not first.sim.fault_reason.is_empty() or not second.sim.fault_reason.is_empty():
					clean = false
					break
			check("one-second coupled pack replay is exact", clean and var_to_bytes(first.checkpoint()) == var_to_bytes(second.checkpoint()), first.sim.fault_reason + " " + second.sim.fault_reason)
			second.free()
		first.free()
	print("STIK_ELECTRIC_TEST %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
