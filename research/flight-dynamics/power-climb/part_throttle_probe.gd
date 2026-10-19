# D6e-R3: part-throttle thrust of every fixed-wing catalog propulsion law, read-only.
# For each aircraft the session accepts, tabulates the steady engine speed, thrust and shaft power that the
# aircraft's own propulsion law gives at a grid of throttles and axial airspeeds (calm, ISA sea level), beside the
# level-flight drag of the data's parabolic polar at that speed. No flight; nothing is written to the tree.
# Run (repository root):
#   <godot> --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/power-climb/part_throttle_probe.gd" -- [--out=<csv>] [--aircraft=<id,id>]
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Turbine := preload("res://physics/turbine.gd")
const GlowOperating := preload("res://physics/glow/operating_point.gd")
const M := preload("res://physics/math3d.gd")

const G := 9.80665
const RHO := 1.225
const THROTTLES := [0.0, 0.1, 0.25, 0.5, 0.75, 1.0]


func _initialize() -> void:
	var out := ""
	var wanted: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--aircraft="):
			wanted = arg.substr(11).split(",")
	var lines := PackedStringArray(["aircraft,kind,mass_kg,weight_n,throttle,u_mps,rpm,thrust_n,shaft_power_w,drag_level_n,thrust_over_weight,excess_over_weight,predicted_climb_deg"])
	for id in Catalog.ids():
		if not wanted.is_empty() and not wanted.has(id):
			continue
		var session := FlightSession.new()
		session.setup(Catalog.entry(id).data)
		root.add_child(session)
		if not session.aircraft.get("ok", false) or not session.start.get("ok", false):
			session.queue_free()
			continue
		var model: Dictionary = session.aircraft.model
		var prop: Dictionary = model.propulsion
		var kind: String = Propulsion.source_kind(prop)
		var mass: float = float(model.mass_kg)
		var trim_model: Dictionary = session._trim_model(model)
		if trim_model.has("trim_mass_properties"):
			mass = float(trim_model.trim_mass_properties.mass_kg)
		var weight := mass * G
		var a: Dictionary = model.aero
		var S: float = float(model.reference.S)
		var vmax_grid: float = 40.0 if kind != "turbine" else 75.0
		var speeds := PackedFloat64Array([0.0])
		var v := 5.0
		while v <= vmax_grid + 1e-9:
			speeds.append(v)
			v += 5.0
		print("\n== %s (%s, %.2f kg, start %.1f m/s, trim throttle %.3f, trim rpm %.0f, trim thrust %.2f N)" % [id, kind, mass, float(model.start_speed), float(session.start.throttle), float(session.start.rpm), float(session.start.thrust)])
		print("%8s %6s | %8s %9s %9s | %8s %6s %7s" % ["throttle", "u m/s", "rpm", "thrust N", "shaft W", "drag N", "T/W", "climb°"])
		for throttle in THROTTLES:
			for u in speeds:
				var rpm: float = Propulsion.steady_rpm(throttle, u, prop, RHO, 1.0)
				var thrust := NAN
				var power := NAN
				if is_finite(rpm):
					var v_air := M.v3(u, 0.0, 0.0)
					thrust = Propulsion.loads(v_air, rpm, prop, RHO)[0]
					power = _shaft_power(prop, kind, rpm, throttle, u)
				var drag := _level_drag(a, S, weight, u)
				var tw: float = thrust / weight if is_finite(thrust) else NAN
				var excess: float = (thrust - drag) / weight if is_finite(thrust) and is_finite(drag) else NAN
				var climb: float = rad_to_deg(asin(clampf(excess, -1.0, 1.0))) if is_finite(excess) else NAN
				print("%8.2f %6.1f | %8.0f %9.2f %9.1f | %8.2f %6.3f %7.1f" % [throttle, u, rpm, thrust, power, drag, tw, climb])
				lines.append("%s,%s,%.4f,%.3f,%.2f,%.1f,%.1f,%.4f,%.2f,%.4f,%.4f,%.4f,%.2f" % [id, kind, mass, weight, throttle, u, rpm, thrust, power, drag, tw, excess, climb])
		session.queue_free()
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(lines) + "\n")
			print("wrote " + out)
	quit(0)


## Shaft (brake) power of the engine at this steady point, by law: glow source, legacy shaft curve, electric motor,
## D5 lag (the propeller's absorbed power at the commanded rpm), turbine (not a shaft quantity: gross thrust power).
func _shaft_power(prop: Dictionary, kind: String, rpm: float, throttle: float, u: float) -> float:
	var omega := rpm * TAU / 60.0
	if Propulsion.is_glow(prop):
		var point: Dictionary = GlowOperating.source(prop, rpm, throttle, RHO)
		return float(point.brake_power_w) if point.get("ok", false) else NAN
	if Turbine.is_turbine(prop):
		return NAN
	if Propulsion.is_electric(prop):
		var source: Dictionary = Propulsion.electric_source_state(rpm, throttle, prop)
		return float(source.shaft_torque_nm) * omega if source.get("ok", false) else NAN
	if Propulsion.has_shaft(prop):
		return Propulsion.engine_torque(rpm, throttle, prop, 1.0) * omega
	return Propulsion.prop_torque(rpm, u, prop, RHO) * omega


## Drag in level flight at speed u from the data's parabolic polar: CL = W/(qS), CD = CD0 + k (CL − CL_minD)².
func _level_drag(a: Dictionary, S: float, weight: float, u: float) -> float:
	if u <= 0.0:
		return NAN
	var q := 0.5 * RHO * u * u
	var cl := weight / (q * S)
	var cd: float = float(a.CD0) + float(a.k_induced) * pow(cl - float(a.CL_minD), 2.0)
	return q * S * cd
