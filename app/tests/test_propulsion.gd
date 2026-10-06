# D5: propulsion against hand calculations from the data, the measured table, and the engine lag.
# Run: godot --headless --path . --script res://tests/test_propulsion.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const AD := preload("res://physics/aircraft_data.gd")
const P := preload("res://physics/propulsion.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _initialize() -> void:
	var r := AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	_check("data with propulsion loads", r.ok, str(r.errors))
	var prop: Dictionary = r.model.propulsion
	var rho := 1.225
	var D := 0.3048

	# Static thrust at full rpm: T = Ct(0)·ρ·n²·D⁴ (hand) ≈ 41.2 N, T/W ≈ 1.46.
	var n: float = prop.max_rpm / 60.0
	var hand := 0.1130 * rho * n * n * pow(D, 4)
	var still := P.loads(M.v3(0, 0, 0), prop.max_rpm, prop, rho)
	_check("static thrust = Ct0·ρ·n²·D⁴ ≈ 41 N", absf(still[0] - hand) < 1e-9 and absf(hand - 41.2) < 0.2, "%.2f N" % still[0])
	_check("T/W ≈ 1.46 (balanced virtual reference build)", absf(still[0] / (r.model.mass_kg * 9.80665) - 1.46) < 0.02, "%.2f" % (still[0] / (r.model.mass_kg * 9.80665)))
	# The derivation is self-consistent: static prop power = assumed engine power at that rpm (1398 W × rpm/16000).
	var power := 0.0471 * rho * n * n * n * pow(D, 5)
	_check("static power balance closes", absf(power - 1397.5 * prop.max_rpm / 16000.0) < 1.0, "%.0f W" % power)

	# Table: exact at knots, linear between, J < 0 uses J = 0, beyond the data extrapolates to the floor.
	_check("Ct at a knot", absf(P.coefficient(prop.ct, 0.550, P.CT_FLOOR) - 0.0437) < 1e-12)
	_check("Ct between knots", absf(P.coefficient(prop.ct, 0.5, P.CT_FLOOR) - lerpf(0.0633, 0.0537, (0.5 - 0.457) / (0.504 - 0.457))) < 1e-12)
	_check("Ct for J < 0 = static", P.coefficient(prop.ct, -0.3, P.CT_FLOOR) == 0.1130)
	var beyond := P.coefficient(prop.ct, 1.0, P.CT_FLOOR)
	_check("Ct beyond the data goes negative (windmill drag), floored", beyond < 0.0 and beyond >= P.CT_FLOOR, str(beyond))

	# Thrust falls with airspeed and crosses zero near J ≈ 0.77 (≈ 43 m/s at full rpm).
	var t15 := P.loads(M.v3(15, 0, 0), prop.max_rpm, prop, rho)[0]
	var t40 := P.loads(M.v3(40, 0, 0), prop.max_rpm, prop, rho)[0]
	var t50 := P.loads(M.v3(50, 0, 0), prop.max_rpm, prop, rho)[0]
	_check("thrust falls with airspeed", still[0] > t15 and t15 > t40 and t40 > 0.0, "%.1f > %.1f > %.1f N" % [still[0], t15, t40])
	_check("past zero-thrust speed the prop drags", t50 < 0.0, "%.2f N at 50 m/s" % t50)

	# Torque reaction: rolls left under power (clockwise prop from behind), nothing when stopped.
	_check("power rolls the airplane left (Mx < 0)", still[3] < 0.0, "%.3f N·m" % still[3])
	var stopped := P.loads(M.v3(15, 0, 0), 0.0, prop, rho)
	_check("stopped engine: no loads", stopped[0] == 0.0 and stopped[3] == 0.0)

	# Engine lag: after one time constant the rpm covers 63.2 % of a step; exact regardless of step size.
	var lag: float = prop.lag
	var rpm := P.rpm_step(prop.idle_rpm, 1.0, lag, prop)
	var frac: float = (rpm - prop.idle_rpm) / (prop.max_rpm - prop.idle_rpm)
	_check("63.2 % of the step after τ", absf(frac - (1.0 - exp(-1.0))) < 1e-12, "%.4f" % frac)
	var fine: float = prop.idle_rpm
	for i in 60:
		fine = P.rpm_step(fine, 1.0, lag / 60.0, prop)
	_check("lag is exact: 60 small steps = 1 big step", absf(fine - rpm) < 1e-9, "%.6f vs %.6f" % [fine, rpm])
	_check("throttle 0 → idle, throttle clamps", P.target_rpm(0.0, prop) == prop.idle_rpm and P.target_rpm(3.0, prop) == prop.max_rpm)

	# Finite everywhere (any airspeed, including backwards and very fast).
	var finite := true
	for u in [-30.0, -1.0, 0.0, 0.01, 10.0, 60.0, 200.0]:
		for x in P.loads(M.v3(u, 3, -2), 4000.0, prop, rho):
			finite = finite and is_finite(x)
	_check("finite at any airspeed", finite)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
