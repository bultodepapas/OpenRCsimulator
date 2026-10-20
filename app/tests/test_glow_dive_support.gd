# NITRO-61FX-R1: a full-throttle vertical dive stays inside the MAX-61FX profile's numerical support. Before the two
# inferred windmill knots (24,000 / 32,000 rpm, no indicated work) the Extra 300S left the 20,000 rpm support in a
# knife-edge dive and the kernel faulted ("RK joint stage evaluation is nonfinite"). Both 61FX airframes dive from
# 30 m/s at 800 m with the elevator holding -80 deg of pitch. This checks numerical support and the windmill limit
# only; it does not validate the engine above its 17,000 rpm practical range.
# Run: godot --headless --path . --script res://tests/test_glow_dive_support.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const AIRCRAFT := ["gp-extra-300s-60", "stik-glow-61fx-2t"]
const DIVE_PITCH_DEG := -80.0
const SUPPORT_RPM := 32000.0

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _initialize() -> void:
	for id: String in AIRCRAFT:
		var session := FlightSession.new()
		session.setup(Catalog.entry(id).data)
		root.add_child(session)
		_check("%s loads with its 61FX glow installation" % id, session.aircraft.ok
			and not session.aircraft.model.get("propulsion", {}).get("glow", {}).is_empty())
		if not session.aircraft.ok:
			session.free()
			continue
		# Full throttle from the start; the elevator pushes over and holds the dive attitude (PD on pitch).
		var dive := { mode = "level", speed = 30.0, altitude = 800.0, duration = 12.0,
			sticks = func(_t: float, s: PackedFloat64Array) -> Dictionary:
				var pitch := rad_to_deg(M.q_to_euler(s.slice(RB.ATT, RB.ATT + 4))[1])
				var q: float = s[RB.RATE + 1]
				var out := Maneuvers._hands_off()
				out.pitch = clampf(0.05 * (DIVE_PITCH_DEG - pitch) - 0.3 * q, -1.0, 1.0)
				out.roll = clampf(-0.5 * s[RB.RATE], -1.0, 1.0)
				out.throttle_delta = 1.0
				return out }
		var trace: RefCounted = Maneuvers.fly(session, dive)
		var peak_rpm := 0.0
		var peak_speed := 0.0
		var finite := true
		for r in trace.row_count():
			peak_rpm = maxf(peak_rpm, trace.value(r, "engine_rpm"))
			peak_speed = maxf(peak_speed, trace.value(r, "speed_mps"))
			for column in ["alt_m", "speed_mps", "engine_rpm", "q_radps"]:
				finite = finite and is_finite(trace.value(r, column))
		var last: int = trace.row_count() - 1
		_check("%s dive: no simulation fault" % id, session.sim.fault_reason.is_empty(), session.sim.fault_reason)
		_check("%s dive: all ticks recorded and finite" % id, finite and last == roundi(12.0 / session.sim.dt()),
			"%d rows" % trace.row_count())
		_check("%s dive: steeper than 70 deg and faster than its 41 m/s-class level Vmax" % id,
			trace.value(last, "pitch_deg") < -70.0 and peak_speed > 45.0,
			"pitch %.1f deg, peak %.1f m/s" % [trace.value(last, "pitch_deg"), peak_speed])
		_check("%s dive: rpm above the former 20,000 rpm support yet inside the windmill support" % id,
			peak_rpm > 20000.0 and peak_rpm < SUPPORT_RPM, "peak %.0f rpm" % peak_rpm)
		session.free()
	print("NITRO-61FX-R1 dive support: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
