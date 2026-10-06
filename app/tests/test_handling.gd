# D8a: handling through the real loop against the predicted-handling table (ROADMAP). These numbers come from the
# same borrowed coefficients, so this VERIFIES the implementation; validation against independent data is D8b.
# Run: godot --headless --path . --script res://tests/test_handling.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _max(trace: RefCounted, column: String) -> float:
	var m := -1e30
	for r in trace.row_count():
		m = maxf(m, trace.value(r, column))
	return m


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	var m := Maneuvers.all()
	var last := 0

	# Trim at 15 m/s: α 4.26° ± 0.5 (predicted); hands-off it holds for 5 s.
	var hold: RefCounted = Maneuvers.fly(session, m.hold_15)
	last = hold.row_count() - 1
	var alpha := rad_to_deg(atan2(float(hold.value(last, "w_mps")), float(hold.value(last, "u_mps"))))
	_check("trim α at 15 m/s within 4.26° ± 0.5", absf(alpha - 4.26) <= 0.5, "%.2f°" % alpha)
	_check("hands-off 5 s: altitude and speed hold", absf(hold.value(last, "alt_m") - hold.value(0, "alt_m")) < 1e-3 and absf(hold.value(last, "speed_mps") - 15.0) < 1e-3,
		"Δalt %s m" % String.num_scientific(hold.value(last, "alt_m") - hold.value(0, "alt_m")))

	# Full-aileron roll rate: the table's 144°/s at 15 m/s and 192°/s at 20 m/s are SINGLE-AXIS (−Clδa·δa/Clp·2V/b).
	# Flown coordinated (rudder holding β ≈ 0) the airplane must reproduce them (± 7 %); flown with the feet still,
	# adverse yaw (Cnδa) builds sideslip and the dihedral effect (Clβ) slows the roll: about 15 % less (6-DOF reality).
	for case in [["roll_15", 144.0], ["roll_20", 192.0]]:
		var co: RefCounted = Maneuvers.fly(session, m[case[0] + "_coordinated"])
		var p_co := rad_to_deg(_max(co, "p_radps"))
		_check("%s coordinated: roll rate %.0f°/s ± 7 %% (single-axis prediction)" % [case[0], case[1]], absf(p_co - case[1]) <= 0.07 * case[1], "%.1f°/s" % p_co)
		var tr: RefCounted = Maneuvers.fly(session, m[case[0]])
		var p := rad_to_deg(_max(tr, "p_radps"))
		_check("%s feet still: adverse yaw slows roll; coordination reduces sideslip" % case[0], p < p_co and _max_slip(tr) > _max_slip(co), "%.1f°/s (%.0f %% of coordinated)" % [p, 100.0 * p / p_co])

	# Dead-stick glide at 15 m/s (engine stopped): L/D ≈ 9.1 (the solver's 9.11), over the last 4 s of flight, ± 2 %.
	var glide: RefCounted = Maneuvers.fly(session, m.glide_15)
	last = glide.row_count() - 1
	var r0 := last - 960
	var dn: float = glide.value(last, "north_m") - glide.value(r0, "north_m")
	var de: float = glide.value(last, "east_m") - glide.value(r0, "east_m")
	var dist := sqrt(dn * dn + de * de) # 64-bit (Vector2 is 32-bit)
	var sink: float = glide.value(r0, "alt_m") - glide.value(last, "alt_m")
	_check("glide L/D at 15 m/s = 9.11 ± 2 %", absf(dist / sink - 9.11) <= 0.02 * 9.11, "L/D %.2f" % (dist / sink))

	# Sanity of the other maneuvers: they stay finite and do what the stick says.
	var pull: RefCounted = Maneuvers.fly(session, m.pull_throttle)
	_check("pull + throttle: climbs", pull.value(pull.row_count() - 1, "alt_m") > pull.value(0, "alt_m") + 1.0, "%.1f m" % (pull.value(pull.row_count() - 1, "alt_m") - pull.value(0, "alt_m")))
	var rud: RefCounted = Maneuvers.fly(session, m.rudder_doublet)
	_check("right rudder first: yaw rate goes right first", _max(rud, "r_radps") > 0.2 and rud.value(roundi(0.9 * 240), "r_radps") > 0.0, "%.2f rad/s" % _max(rud, "r_radps"))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _max_slip(trace: RefCounted) -> float:
	var peak := 0.0
	for row in trace.row_count():
		var u: float = trace.value(row, "u_mps")
		var v: float = trace.value(row, "v_mps")
		var w: float = trace.value(row, "w_mps")
		peak = maxf(peak, absf(atan2(v, sqrt(u*u+w*w))))
	return peak
