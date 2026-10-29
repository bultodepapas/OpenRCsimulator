extends SceneTree
## X8-03/04/05/08: the flying-wing extensions on the shipped X8 data and on mutated copies. Elevon mix and its exact
## decomposition, the fail-closed contract (mixed layouts, rudder terms, horizontal tail, pusher geometry, tolerance
## block), the tailless strip law against the oracle, the rudderless trim and the tolerant hull thresholds.

const AircraftData := preload("res://physics/aircraft_data.gd")
const ControlSurfaces := preload("res://physics/control_surfaces.gd")
const Commands := preload("res://input/commands.gd")
const Aero := preload("res://physics/aero.gd")
const Trim := preload("res://physics/trim.gd")
const Air := preload("res://physics/air_data.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const X8 := "res://data/aircraft/moonrunner_x99.json"
const X8_PACK := "res://data/aircraft/battery/moonrunner_x99_6s_pack.json"
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _raw(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _refused(raw: Dictionary, needle: String) -> bool:
	var result := AircraftData.validate_and_derive(raw)
	if result.ok:
		return false
	for e in result.errors:
		if str(e).contains(needle):
			return true
	printerr("  (errors were: %s)" % [result.errors])
	return false


func _initialize() -> void:
	_mix()
	_contract()
	var loaded := AircraftData.load_file(X8)
	_check("the X8 loads", loaded.ok, str(loaded.errors))
	_check("the X8 pack variant loads", AircraftData.load_file(X8_PACK).ok)
	if loaded.ok:
		_tailless(loaded.model)
		_trim(loaded.model)
		_hull(loaded.model)
	print("MoonRunner X99 flying wing: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _mix() -> void:
	var t := {aileron = 23.26, elevator = 19.47, elevon = 26.76, rudder = 0.0}
	var pitch := ControlSurfaces.surface_deflections_deg({roll = 0.0, pitch = 1.0, yaw = 1.0}, t)
	_check("pitch alone raises both elevons as one elevator", pitch.elevator == 19.47 and pitch.aileron_right == 0.0 and pitch.aileron_left == 0.0)
	_check("yaw moves no surface", pitch.rudder == 0.0)
	var roll := ControlSurfaces.surface_deflections_deg({roll = 1.0, pitch = 0.0, yaw = 0.0}, t)
	_check("roll alone is antisymmetric, right trailing edge up", roll.aileron_right == 23.26 and roll.aileron_left == -23.26 and roll.elevator == 0.0)
	var both := ControlSurfaces.surface_deflections_deg({roll = 1.0, pitch = 1.0, yaw = 0.0}, t)
	var right: float = both.elevator + both.aileron_right
	var left: float = both.elevator + both.aileron_left
	_check("full pitch and roll clip the right elevon at its end point", absf(right - 26.76) < 1e-12, str(right))
	_check("the unsaturated left elevon keeps pitch minus roll", absf(left - (19.47 - 23.26)) < 1e-12, str(left))
	var conventional := ControlSurfaces.surface_deflections_deg({roll = 0.5, pitch = 0.5, yaw = 0.5}, {aileron = 20.0, elevator = 20.0, rudder = 20.0})
	_check("a conventional throw set keeps the conventional mapping", conventional.aileron_right == 10.0 and conventional.rudder == 10.0)


func _contract() -> void:
	var raw := _raw(X8)
	var mixed := raw.duplicate(true)
	mixed.capabilities.controls = "conventional"
	# The closed structural contract refuses it first: conventional controls need the rudder and four surfaces.
	_check("a tailless airframe with conventional controls is refused", _refused(mixed, "missing required field 'rudder'"))
	var tail := raw.duplicate(true)
	tail.capabilities.erase("airframe_layout")
	# Without the tailless selection the wing-tail surfaces are required, so the structural contract refuses it first.
	_check("elevons without the tailless law are refused", _refused(tail, "missing required field 'horizontal'"))
	var relation := raw.duplicate(true)
	relation.capabilities.controls = "conventional"
	relation.controls.max_throw.rudder = relation.controls.max_throw.elevator.duplicate(true)
	relation.controls.max_throw.erase("elevon")
	relation.controls.rates.normal.rudder = relation.controls.rates.normal.elevator.duplicate(true)
	relation.controls.rates.normal.rudder_expo = relation.controls.rates.normal.elevator_expo.duplicate(true)
	relation.controls.surface_ids = {aileron_left = "surface_a_l", aileron_right = "surface_a_r", elevator = "surface_e", rudder = "surface_r"}
	_check("a structurally complete conventional-control tailless file is refused by the relation", _refused(relation, "elevon controls require airframe_layout tailless"))
	var rudder := raw.duplicate(true)
	rudder.aero.coefficients.Cndr.value = -0.01
	_check("a rudder term on an elevon aircraft is refused", _refused(rudder, "has no rudder"))
	var horizontal := raw.duplicate(true)
	horizontal.aero.surfaces.horizontal = {area = raw.aero.surfaces.vertical.area, position = raw.aero.surfaces.vertical.position,
		lift_slope = raw.aero.surfaces.vertical.lift_slope, control_effectiveness = raw.aero.surfaces.vertical.lift_slope,
		incidence = raw.aero.surfaces.vertical.incidence}
	_check("a horizontal tail on the tailless law is refused", not AircraftData.validate_and_derive(horizontal).ok)
	var tractor := raw.duplicate(true)
	tractor.propulsion.propeller.thrust_line_offset.value = [-0.4, 0.0, 0.0]
	_check("a pusher propeller ahead of the CG is refused", _refused(tractor, "must sit aft of the CG"))
	var untolerant := raw.duplicate(true)
	untolerant.erase("crash_tolerance")
	_check("a tolerant hull without its thresholds is refused", _refused(untolerant, "crash_tolerance"))
	var throw := raw.duplicate(true)
	throw.controls.max_throw.aileron.value = 30.0
	_check("a roll share beyond the elevon end point is refused", _refused(throw, "exceeds the elevon end point"))
	var elevon_flap := raw.duplicate(true)
	elevon_flap.aero.surfaces.tailless.elevon_coverage.value = [0.0, 0.0, 0.0]
	_check("elevons that cover no strip are refused", _refused(elevon_flap, "no wing strip carries an elevon"))
	var stik := AircraftData.load_file(STIK)
	_check("a conventional aircraft model has no elevon layout and keeps its tail",
		stik.ok and not stik.model.controls.has("layout") and stik.model.surfaces.has("horizontal") and not stik.model.surfaces.has("tailless"))


## Small-angle coefficients of the strip model and of the oracle by symmetric differences (lift, pitch).
func _coefficient(model: Dictionary, key: String, h: float, local: bool, index: int) -> float:
	var V := 15.0
	var rho := Air.RHO_SEA_LEVEL
	var values := []
	for sign: float in [1.0, -1.0]:
		var alpha := 0.03 + (sign * h if key == "alpha" else 0.0)
		var s := RB.make_state(M.v3(0, 0, -100), M.v3(V * cos(alpha), 0.0, V * sin(alpha)), M.q_from_euler(0, alpha, 0), M.v3(0, 0, 0))
		var d := {elevator = sign * h if key == "elevator" else 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
		var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), rho)
		var loads: PackedFloat64Array = Aero._local_loads(s, air, d, model, rho) if local else Aero._global_loads(s, air, d, model, rho)
		var q := 0.5 * rho * V * V
		var lift := -(loads[2] * cos(alpha) - loads[0] * sin(alpha))
		values.append(lift / (q * model.reference.S) if index == 0 else loads[4] / (q * model.reference.S * model.reference.c))
	return (values[0] - values[1]) / (2.0 * h)


func _tailless(model: Dictionary) -> void:
	var tl: Dictionary = model.surfaces.tailless
	_check("the tailless model has no horizontal element", not model.surfaces.has("horizontal"))
	_check("the loader derived elevon effectiveness, station shift and camber couple",
		tl.has("tau") and tl.has("station_shift") and tl.has("moment_per_rad") and model.surfaces.has("wing_cm_ac"))
	_check("the station shift stays well inside a quarter chord (geometry agrees with the oracle's neutral point)",
		absf(float(tl.station_shift)) < 0.05 * float(model.reference.c), str(tl.station_shift))
	for item in [["CLa", "alpha", 0], ["Cma", "alpha", 1], ["CLde", "elevator", 0], ["Cmde", "elevator", 1]]:
		var oracle := _coefficient(model, item[1], 0.01, false, item[2])
		var local := _coefficient(model, item[1], 0.01, true, item[2])
		_check("strip model reproduces the oracle's %s" % item[0], absf(local - oracle) <= 0.02 * absf(oracle) + 1e-4,
			"local %.5f oracle %.5f" % [local, oracle])
	var elevator := {elevator = deg_to_rad(-10.0), aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	var V := 15.0
	var s := RB.make_state(M.v3(0, 0, -100), M.v3(V, 0, 0), M.q_identity(), M.v3(0, 0, 0))
	var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), Air.RHO_SEA_LEVEL)
	var up := Aero._local_loads(s, air, elevator, model, Air.RHO_SEA_LEVEL)
	var neutral := Aero._local_loads(s, air, {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}, model, Air.RHO_SEA_LEVEL)
	_check("up elevon pitches the strip model nose up", up[4] > neutral[4], "%s vs %s" % [up[4], neutral[4]])


func _trim(model: Dictionary) -> void:
	for v: float in [model.start_speed, 18.0]:
		var t := Trim.solve("level", v, model, 9.80665, model.controls.throw_rad)
		_check("rudderless level trim at %.1f m/s converges" % v, t.ok, str(t.message))
		_check("rudderless trim keeps the rudder at zero and banks less than 2°", t.rudder == 0.0 and absf(float(t.get("bank", 99.0))) < deg_to_rad(2.0))
		var commands := Commands.neutral_commands()
		commands.pitch = t.pitch_command
		commands.roll = t.roll_command
		var surfaces := Commands.surface_deflections_deg(commands, model.controls.throw_deg)
		_check("the radio mix of the trims reproduces the trimmed surfaces at %.1f m/s" % v,
			absf(deg_to_rad(-surfaces.elevator) - t.elevator) < 1e-9 and absf(deg_to_rad(-surfaces.aileron_right) - t.aileron) < 1e-9)
	var glide := Trim.solve("glide", 12.0, model, 9.80665, model.controls.throw_rad)
	_check("power-off glide trims with a flat flying-wing glide (L/D 6-14)", glide.ok and -1.0 / tan(glide.gamma) > 6.0 and -1.0 / tan(glide.gamma) < 14.0,
		str(glide.get("gamma")))


func _hull(model: Dictionary) -> void:
	var prepared := HullContact.prepare(model.crash_hull, model.mass_kg, model.inertia, {}, PackedFloat64Array(), model.crash_tolerance)
	_check("the X8's tolerant hull carries its own thresholds", HullContact.terminal_energy(prepared) == float(model.crash_tolerance.terminal_specific_energy)
		and HullContact.crash_depth(prepared) == float(model.crash_tolerance.crash_depth))
	var shared := HullContact.prepare(model.crash_hull, model.mass_kg, model.inertia)
	_check("without a tolerance the shared thresholds apply", HullContact.terminal_energy(shared) == HullContact.TERMINAL_J_PER_KG
		and not shared.has("terminal_j_per_kg"))
	# A level belly touchdown sinking 3 m/s (4.5 J/kg at a point under the CG): terminal for the shared threshold,
	# survivable for the EPO airframe. Hull points are body FRD about the CG: the deepest has the largest z.
	var deepest := -INF
	for i in range(0, model.crash_hull.size(), 3):
		deepest = maxf(deepest, float(model.crash_hull[i + 2]))
	var before := RB.make_state(M.v3(0.0, 0, -deepest - 0.002), M.v3(12.0, 0.0, 3.0), M.q_identity(), M.v3(0, 0, 0))
	var after := RB.make_state(M.v3(0.05, 0, -deepest + 0.002), M.v3(12.0, 0.0, 3.0), M.q_identity(), M.v3(0, 0, 0))
	var tolerant := HullContact.terminal(before, after, prepared)
	var balsa := HullContact.terminal(before, after, shared)
	_check("a 3 m/s belly touchdown is terminal under the shared threshold", balsa.index >= 0 and balsa.rule == "impact", str(balsa))
	_check("the same touchdown is survivable for the EPO hull", tolerant.index == -1, str(tolerant))
