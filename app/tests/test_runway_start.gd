# E3b2: runway start in static equilibrium. The threshold spot from the field; the two-stage solve converges; after
# 1 s (and 10 s) at idle the airplane has not moved (|v| < 1e-6 m/s), ΣN = m·g within 0.1 %, attitude within 0.1° of
# the solve, every wheel still stuck. Independent checks: anchors balance the thrust, the nose load matches a
# quasi-static moment balance with thrust, the lean onto the anchors is T/Σk. Aircraft without stiction are refused.
# Run: godot --headless --path . --script res://tests/test_runway_start.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Air := preload("res://physics/air_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const G := 9.80665

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var f := FieldLoader.load_from()
	_check("default field loads", f.ok)
	var field: Dictionary = f.field
	var spot := GroundStart.threshold(field)
	var runway: Dictionary = {}
	for s in field.surfaces:
		if s.type == "runway":
			runway = s
	_check("threshold: west end + 3 m, runway centre line, heading east", spot.ok and spot.north == runway.center_north
		and spot.east == runway.center_east - runway.length_east_west / 2.0 + 3.0 and spot.heading == PI / 2.0, str(spot))
	var west := GroundStart.threshold(field, false)
	_check("west-bound threshold: east end − 3 m, heading west", west.ok and west.east == runway.center_east + runway.length_east_west / 2.0 - 3.0
		and west.heading == -PI / 2.0)
	_check("a field without a runway has no threshold", not GroundStart.threshold({ surfaces = [] }).ok)

	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	_check("Stik session on the field", session.set_field(field))
	var ok: bool = session.reset_on_runway(spot.north, spot.east, spot.heading)
	_check("runway start solves and resets", ok and session.sim.fault_reason.is_empty())
	if not ok:
		print("%d checks, %d failed" % [_count, _failures])
		quit(1)
		return
	var model: Dictionary = session.aircraft.model
	var gear: Dictionary = model.landing_gear
	var solved: PackedFloat64Array = session.sim.state.duplicate()
	var anchors: PackedFloat64Array = session.sim.aux.slice(FlightSession.AUX_ANCHORS)
	_check("every wheel starts stuck, engine idling at closed throttle", anchors[2] == 1.0 and anchors[5] == 1.0 and anchors[8] == 1.0
		and session.engine_running and session.sim.inputs[3] == 0.0 and session.sim.aux[0] == float(model.propulsion.idle_rpm))
	_physics_checks(session, model, gear, solved, anchors, spot)
	# Run 1 s, then 10 s: nothing moves.
	var worst_v := 0.0
	var worst_w := 0.0
	var one_second: PackedFloat64Array
	for i in roundi(10.0 / session.sim.dt()):
		session.sim.step()
		var s: PackedFloat64Array = session.sim.state
		worst_v = maxf(worst_v, sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2))
		worst_w = maxf(worst_w, sqrt(s[RB.RATE] ** 2 + s[RB.RATE + 1] ** 2 + s[RB.RATE + 2] ** 2))
		if i + 1 == roundi(1.0 / session.sim.dt()):
			one_second = s.duplicate()
			_check("after 1 s: |v| < 1e-6 m/s", worst_v < 1e-6, "max %s m/s" % String.num_scientific(worst_v))
			var n_sum := _normal_sum(one_second, gear)
			var weight: float = model.mass_kg * G
			var t_down: float = n_sum - weight
			_check("after 1 s: ΣN = m·g within 0.3 %% (the idle thrust, tilted by the nose-down lean, adds %.4f N)" % t_down,
				absf(n_sum - weight) < 0.003 * weight, "%.5f N vs %.5f N" % [n_sum, weight])
			_check("after 1 s: attitude within 0.1° of the solve", _angle(one_second, solved) < deg_to_rad(0.1),
				"%s°" % String.num_scientific(rad_to_deg(_angle(one_second, solved))))
	var s10: PackedFloat64Array = session.sim.state
	var a10: PackedFloat64Array = session.sim.aux.slice(FlightSession.AUX_ANCHORS)
	var moved := sqrt((s10[RB.POS] - solved[RB.POS]) ** 2 + (s10[RB.POS + 1] - solved[RB.POS + 1]) ** 2)
	_check("10 s at idle: |v| and |ω| < 1e-6 throughout, moved < 1 µm, anchors unchanged", worst_v < 1e-6 and worst_w < 1e-6
		and moved < 1e-6 and a10 == anchors, "v %s, ω %s, %s m" % [String.num_scientific(worst_v), String.num_scientific(worst_w), String.num_scientific(moved)])
	# The other end of the runway works too.
	_check("west-bound runway start solves", session.reset_on_runway(west.north, west.east, west.heading))
	_refusals(field)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _physics_checks(session: Node, model: Dictionary, gear: Dictionary, solved: PackedFloat64Array, anchors: PackedFloat64Array, spot: Dictionary) -> void:
	var rows := _rows(solved)
	var thrust: float = Propulsion.thrust_torque(PackedFloat64Array([0.0, 0.0, 0.0]), session.sim.aux[0], model.propulsion, Air.RHO_SEA_LEVEL)[0]
	var ground := Ground.loads(solved, gear, session.sim.aux[3], session.ground_surfaces, anchors)
	# Horizontal balance in NED: thrust along body x plus the ground's tangential force.
	var gn: float = rows[0][0] * ground[0] + rows[0][1] * ground[1] + rows[0][2] * ground[2]
	var ge: float = rows[1][0] * ground[0] + rows[1][1] * ground[1] + rows[1][2] * ground[2]
	var tn: float = rows[0][0] * thrust
	var te: float = rows[1][0] * thrust
	_check("anchors hold the idle thrust: Σ horizontal = 0 within 1e-9 N", absf(gn + tn) < 1e-9 and absf(ge + te) < 1e-9,
		"thrust %.4f N, ground north %s N, east %.6f N" % [thrust, String.num_scientific(gn), ge])
	# Lean onto the anchors relative to the engine-off rest pose: T/Σk.
	var sum_k := 0.0
	for c in gear.contacts:
		sum_k += c.anchor_stiffness
	var rest := GroundStart.solve(model, session.ground_surfaces, spot.north, spot.east, spot.heading,
		session._deflections(session.sim.aux), session.sim.aux[3], session.sim.aux[0], Air.RHO_SEA_LEVEL, G)
	# Each wheel's ground point leans past its anchor by about T/Σk (the springs act at the wheels, not at the CG).
	var lean := INF
	var lean_max := 0.0
	for i in gear.contacts.size():
		var r: PackedFloat64Array = gear.contacts[i].position
		var p_e: float = solved[RB.POS + 1] + rows[1][0] * r[0] + rows[1][1] * r[1] + rows[1][2] * r[2]
		var d: float = p_e - anchors[i * Ground.ANCHOR_STRIDE + 1]
		lean = minf(lean, d)
		lean_max = maxf(lean_max, d)
	_check("solve converged (residual < 1e-11 in %d iterations) and is the session's start" % rest.iterations,
		rest.ok and rest.residual < GroundStart.TOLERANCE and rest.state == solved)
	_check("each wheel leans past its anchor by ≈ T/Σk = %.3f mm (within 5 %%)" % (thrust / sum_k * 1000.0),
		absf(lean - thrust / sum_k) < 0.05 * thrust / sum_k and absf(lean_max - thrust / sum_k) < 0.05 * thrust / sum_k,
		"%.4f–%.4f mm" % [lean * 1000.0, lean_max * 1000.0])
	# Nose load from a side-view balance in world axes at the solved attitude (heading east: X east, Z up), using only
	# geometry and equilibrium: vertical ΣN + T_Z = W and moments about the CG, with the anchors' horizontal pull shared
	# by spring stiffness at the wheels' ground points.
	var weight: float = model.mass_kg * G
	var t_x: float = rows[1][0] * thrust # east component of the thrust (body x)
	var t_z: float = -rows[2][0] * thrust # up component
	var p_r: PackedFloat64Array = M.v3(-model.propulsion.offset[0], model.propulsion.offset[1], -model.propulsion.offset[2])
	var p_x: float = rows[1][0] * p_r[0] + rows[1][1] * p_r[1] + rows[1][2] * p_r[2]
	var p_z: float = -(rows[2][0] * p_r[0] + rows[2][1] * p_r[1] + rows[2][2] * p_r[2])
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for c in gear.contacts:
		var r: PackedFloat64Array = c.position
		xs.append(rows[1][0] * r[0] + rows[1][1] * r[1] + rows[1][2] * r[2])
		zs.append(-(rows[2][0] * r[0] + rows[2][1] * r[1] + rows[2][2] * r[2]))
	# Unknowns: mains total N_m (at the mains' mean X) and nose N_n. Tangential pull per wheel f_i = −(k_i/Σk)·T_X.
	var x_m: float = 0.5 * (xs[0] + xs[1])
	var friction_moment := 0.0
	for i in 3:
		friction_moment += -zs[i] * (-gear.contacts[i].anchor_stiffness / sum_k * t_x)
	var thrust_moment: float = p_x * t_z - p_z * t_x
	# N_m + N_n = W − T_Z ; x_m·N_m + x_n·N_n + friction_moment + thrust_moment = 0
	var vertical: float = weight - t_z
	var nose_expect: float = (-(friction_moment + thrust_moment) - x_m * vertical) / (xs[2] - x_m)
	var comp := Ground.compressions(solved, gear)
	var nose: float = gear.contacts[2].stiffness * comp[2]
	_check("nose load %.4f N matches the world side-view moment balance %.4f N within 0.5 %%" % [nose, nose_expect], absf(nose - nose_expect) < 0.005 * nose_expect)
	var pitch_down: float = -M.q_to_euler(PackedFloat64Array([solved[RB.ATT], solved[RB.ATT + 1], solved[RB.ATT + 2], solved[RB.ATT + 3]]))[1]
	_check("vertical balance: ΣN = m·g + T·sin(nose-down %.2f°) within 1e-9 N (ΣN/m·g = %.4f)" % [rad_to_deg(pitch_down), _normal_sum(solved, gear) / weight],
		absf(_normal_sum(solved, gear) - vertical) < 1e-9)


func _refusals(field: Dictionary) -> void:
	var spot := GroundStart.threshold(field)
	for id in ["gp-extra-300s-60", "p51d-mustang-120"]:
		var other := FlightSession.new()
		other.setup(Catalog.entry(id).data)
		root.add_child(other)
		other.input_enabled = false
		other.set_field(field)
		var refused: bool = not other.reset_on_runway(spot.north, spot.east, spot.heading)
		_check("%s (no stiction data) is refused and keeps its normal flying start" % id, refused and other.is_flyable()
			and -other.sim.state[RB.POS + 2] > 5.0)
		other.queue_free()


func _normal_sum(s: PackedFloat64Array, gear: Dictionary) -> float:
	var comp := Ground.compressions(s, gear)
	var n := 0.0
	for i in comp.size():
		if comp[i] > 0.0:
			n += gear.contacts[i].stiffness * comp[i]
	return n


func _angle(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var dot := absf(a[RB.ATT] * b[RB.ATT] + a[RB.ATT + 1] * b[RB.ATT + 1] + a[RB.ATT + 2] * b[RB.ATT + 2] + a[RB.ATT + 3] * b[RB.ATT + 3])
	return 2.0 * acos(clampf(dot, 0.0, 1.0))


func _rows(s: PackedFloat64Array) -> Array:
	var w := s[RB.ATT]
	var x := s[RB.ATT + 1]
	var y := s[RB.ATT + 2]
	var z := s[RB.ATT + 3]
	return [
		[1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y)],
		[2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x)],
		[2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)],
	]
