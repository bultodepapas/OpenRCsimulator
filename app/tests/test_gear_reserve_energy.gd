# GP-06c: no geared catalog airplane collapses its landing gear (terminal crash) in the reserve-energy drop of the former
# 14 CFR Part 23 (2011 text), applied to RC models as an engineering convention, not as RC data: §23.473(d) limit
# descent velocity 4.4·(W/S)^¼ ft/s but never below 7 ft/s (every model here sits at that floor); §23.473(e) wing lift
# up to 2/3 of the weight through the CG during the impact; §23.727 the reserve drop from 1.44× the limit height
# (1.2× the velocity), in which the gear "may not fail". Rigid body on the production gear law (Ground.loads, no
# aerodynamics or propulsion), CG gravity g/3, zero horizontal speed, 960 Hz RK4. Two attitudes per topology
# (§23.479/§23.481): tricycle all wheels together and mains-only nose-high (10°); taildragger mains-only level fuselage
# and three-point. Before GP-06c the Extra, P-51 tail, Avanti and Timber collapsed already in the 7 ft/s limit drop.
# research/ground-physics/gp06/reserve_drop.gd writes the same drops as a JSON report.
# Run: godot --headless --path . --script res://tests/test_gear_reserve_energy.gd
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")

const G := 9.80665
const FT := 0.3048
const LIMIT_SINK_MPS := 7.0 * FT # §23.473(d) floor: 2.1336 m/s
const RESERVE_SINK_MPS := 1.2 * 7.0 * FT # §23.727: 1.44× the drop height → 2.5603 m/s
const LIFT_FRACTION := 2.0 / 3.0 # §23.473(e)
const HZ := 960
const DURATION_S := 0.6
const NOSE_HIGH_DEG := 10.0

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var rows := fleet_report()
	_check("every geared catalog airplane was dropped", rows.size() >= 5, str(rows.size()))
	for row: Dictionary in rows:
		for result: Dictionary in row.cases:
			if result.sink_mps != RESERVE_SINK_MPS:
				continue
			var worst := 0.0
			var detail := ""
			for i in result.names.size():
				worst = maxf(worst, float(result.peak[i]) / float(result.travel[i]))
				detail += "%s %.1f/%.0f mm " % [result.names[i], 1000.0 * float(result.peak[i]), 1000.0 * float(result.travel[i])]
			_check("%s %s reserve drop (%.2f m/s, lift 2/3 W): finite, every leg within its travel" % [row.id, result.attitude,
				RESERVE_SINK_MPS], result.finite and worst <= 1.0, detail + "(worst %.0f %%)" % (100.0 * worst))
	print("GP-06c gear reserve energy: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


## Every geared flyable airplane: {id, tricycle, support_pitch_deg, cases: [drop(), …]} at the limit and reserve sinks.
static func fleet_report() -> Array:
	var rows := []
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		var loaded: Dictionary = AircraftData.load_file(str(entry.data))
		if not loaded.ok or loaded.model.get("landing_gear", {}).is_empty():
			continue
		var model: Dictionary = loaded.model
		var gear: Dictionary = model.landing_gear
		var tricycle := false
		for c: Dictionary in gear.contacts:
			tricycle = tricycle or str(c.name) == "nose"
		var support := support_pitch(gear)
		var attitudes: Array = [["all_wheels", support], ["mains_nose_high", deg_to_rad(NOSE_HIGH_DEG)]] if tricycle \
			else [["mains_level", 0.0], ["three_point", support]]
		var row := {id = str(entry.id), tricycle = tricycle, support_pitch_deg = rad_to_deg(support), cases = []}
		for attitude: Array in attitudes:
			for sink: float in [LIMIT_SINK_MPS, RESERVE_SINK_MPS]:
				var result := drop(model, gear, float(attitude[1]), sink)
				result.attitude = attitude[0]
				result.sink_mps = sink
				row.cases.append(result)
		rows.append(row)
	return rows


## Pitch (rad, nose up +) at which the mains and the third wheel touch together: equal depth −x·sinθ + z·cosθ.
static func support_pitch(gear: Dictionary) -> float:
	var mains := PackedFloat64Array()
	var other := PackedFloat64Array()
	for c: Dictionary in gear.contacts:
		if str(c.name).begins_with("main"):
			mains = c.position
		else:
			other = c.position
	return atan((mains[2] - other[2]) / (mains[0] - other[0]))


## Released with the lowest contact touching, the CG sinking at `sink`, LIFT_FRACTION of the weight carried at the CG.
## Returns {peak (m per contact), travel, names, peak_load_factor (ground reaction / weight), finite}.
static func drop(model: Dictionary, gear: Dictionary, pitch: float, sink: float) -> Dictionary:
	var q := M.q_from_euler(0.0, pitch, 0.0)
	var probe := RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 0), q, M.v3(0, 0, 0))
	var lowest := -INF
	for depth: float in Ground.compressions(probe, gear):
		lowest = maxf(lowest, depth)
	var s := RB.make_state(M.v3(0.0, 0.0, -lowest), M.q_rotate(M.q_conj(q), M.v3(0.0, 0.0, sink)), q, M.v3(0, 0, 0))
	var mass: float = model.mass_kg
	var inertia: PackedFloat64Array = model.inertia
	var inverse := RB.inertia_inverse(inertia)
	var g_effective := G * (1.0 - LIFT_FRACTION)
	var f := func(x: PackedFloat64Array) -> PackedFloat64Array:
		var loads := Ground.loads(x, gear)
		var force := PackedFloat64Array([0.0, 0.0, 0.0])
		var moment := PackedFloat64Array([0.0, 0.0, 0.0])
		if not loads.is_empty():
			force = loads.slice(0, 3)
			moment = loads.slice(3, 6)
		return RB.derivative(x, mass, inertia, inverse, force, moment, g_effective)
	var peak := PackedFloat64Array()
	peak.resize(gear.contacts.size())
	var peak_n := 0.0
	var dt := 1.0 / float(HZ)
	var finite := true
	for tick in roundi(DURATION_S * HZ):
		s = RK.rk4_step(s, dt, f)
		if not Sim.state_is_valid(s):
			finite = false
			break
		var comp := Ground.compressions(s, gear)
		for i in comp.size():
			peak[i] = maxf(peak[i], comp[i])
		var loads := Ground.loads(s, gear)
		if not loads.is_empty():
			# Ground reaction load factor: the up component of the summed contact force over the weight.
			var down_row := PackedFloat64Array([2.0 * (s[7] * s[9] - s[6] * s[8]), 2.0 * (s[8] * s[9] + s[6] * s[7]),
				1.0 - 2.0 * (s[7] * s[7] + s[8] * s[8])])
			peak_n = maxf(peak_n, -(down_row[0] * loads[0] + down_row[1] * loads[1] + down_row[2] * loads[2]) / (mass * G))
	return {peak = Array(peak), peak_load_factor = peak_n, finite = finite,
		travel = gear.contacts.map(func(c: Dictionary) -> float: return float(c.max_compression)),
		names = gear.contacts.map(func(c: Dictionary) -> String: return str(c.name))}
