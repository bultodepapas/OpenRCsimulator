# NITRO-06: known-answer and property checks of the carburettor flow-restriction law (physics/glow/carburetor.gd).
# Run: godot --headless --path app --audio-driver Dummy --script res://tests/test_glow_carburetor.gd
extends SceneTree

const Carb := preload("res://physics/glow/carburetor.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(label: String, actual: float, expected: float, tolerance: float) -> void:
	_check(label, is_finite(actual) and absf(actual - expected) <= tolerance, "got %s, expected %s" % [String.num(actual, 15), String.num(expected, 15)])


func _initialize() -> void:
	# Constants of the isentropic nozzle for γ = 1.4 (Heywood §7.6.2), recomputed here from the definition.
	var g := 1.4
	_near("critical pressure ratio", Carb.CRITICAL_RATIO, pow(2.0 / (g + 1.0), g / (g - 1.0)), 1e-15)
	_near("choked flow function", Carb.PSI_CHOKED, sqrt(g) * pow(2.0 / (g + 1.0), (g + 1.0) / (2.0 * (g - 1.0))), 1e-15)
	# g(r): 1 when choked, continuous at r_c, decreasing to 0 at r = 1 (independent scalar reference values).
	_near("g choked", Carb.flow_function(0.3), 1.0, 0.0)
	_near("g continuous at r_c", Carb.flow_function(Carb.CRITICAL_RATIO + 1e-12), 1.0, 1e-9)
	_near("g(0.6)", Carb.flow_function(0.6), 0.988585008850183, 1e-12)
	_near("g(0.8)", Carb.flow_function(0.8), 0.818804239195763, 1e-12)
	_near("g(0.9)", Carb.flow_function(0.9), 0.617148313960041, 1e-12)
	_near("g(0.99)", Carb.flow_function(0.99), 0.205426085356801, 1e-12)
	_near("g(1)", Carb.flow_function(1.0), 0.0, 0.0)
	var previous := 2.0
	var monotone := true
	for i in range(0, 101):
		var value := Carb.flow_function(0.5 + 0.005 * i)
		monotone = monotone and value <= previous + 1e-15
		previous = value
	_check("g decreases", monotone)
	# r(y): identity when choked, the root of r = y g(r) above, 1 in the limit, monotone.
	_near("r(0.1) choked", Carb.charge_ratio(0.1), 0.1, 0.0)
	_near("r(0.3) choked", Carb.charge_ratio(0.3), 0.3, 0.0)
	_near("r(0.6)", Carb.charge_ratio(0.6), 0.594218413575806, 1e-12)
	_near("r(1.0)", Carb.charge_ratio(1.0), 0.807458329555176, 1e-12)
	_near("r(2.0)", Carb.charge_ratio(2.0), 0.944416909333698, 1e-12)
	_near("r(5.0)", Carb.charge_ratio(5.0), 0.990703797849156, 1e-12)
	_near("r(20)", Carb.charge_ratio(20.0), 0.999414247311794, 1e-12)
	_check("r(y) solves r = y g(r)", absf(Carb.charge_ratio(1.3) - 1.3 * Carb.flow_function(Carb.charge_ratio(1.3))) < 1e-13)
	_check("r(1e6) is near 1", Carb.charge_ratio(1.0e6) > 0.9999)
	_check("r rejects negative and nonfinite y", is_nan(Carb.charge_ratio(-1.0)) and is_nan(Carb.charge_ratio(NAN)) and is_nan(Carb.charge_ratio(INF)))
	previous = -1.0
	monotone = true
	for i in range(0, 200):
		var value := Carb.charge_ratio(0.05 * i)
		monotone = monotone and value >= previous
		previous = value
	_check("r increases with y", monotone)
	# Lens of two equal circles: 1 aligned, 0 apart, 0.391 at one radius; its inverse round-trips.
	_near("lens(0)", Carb.lens_fraction(0.0), 1.0, 0.0)
	_near("lens(0.25)", Carb.lens_fraction(0.25), 0.685037642474293, 1e-12)
	_near("lens(0.5)", Carb.lens_fraction(0.5), 0.391002218955771, 1e-12)
	_near("lens(0.75)", Carb.lens_fraction(0.75), 0.144293612814388, 1e-12)
	_near("lens(0.9)", Carb.lens_fraction(0.9), 0.037386073468499, 1e-12)
	_near("lens(1)", Carb.lens_fraction(1.0), 0.0, 0.0)
	for idle in [0.002, 0.01, 0.05, 0.3, 0.9]:
		var u: float = Carb.idle_offset(idle)
		_near("idle offset round-trips %.3f" % idle, Carb.lens_fraction(u), idle, 1e-12)
	_check("idle offset rejects the ends", is_nan(Carb.idle_offset(0.0)) and is_nan(Carb.idle_offset(1.0)) and is_nan(Carb.idle_offset(NAN)))
	var u_idle: float = Carb.idle_offset(0.01)
	_near("opening at idle", Carb.opening(0.0, u_idle), 0.01, 1e-12)
	_near("opening at full", Carb.opening(1.0, u_idle), 1.0, 0.0)
	_near("opening clamps the servo", Carb.opening(1.5, u_idle), 1.0, 0.0)
	_check("opening grows with the servo", Carb.opening(0.25, u_idle) < Carb.opening(0.5, u_idle) and Carb.opening(0.5, u_idle) < Carb.opening(0.75, u_idle))
	_near("half travel is a half-offset lens", Carb.opening(0.5, u_idle), Carb.lens_fraction(0.5 * u_idle), 1e-15)
	_near("travel exponent keeps the barrel more closed at mid travel", Carb.opening(0.5, u_idle, 0.5), Carb.lens_fraction(u_idle * sqrt(0.5)), 1e-15)
	_near("travel exponent leaves the ends alone (idle)", Carb.opening(0.0, u_idle, 0.5), 0.01, 1e-12)
	_near("travel exponent leaves the ends alone (full)", Carb.opening(1.0, u_idle, 0.5), 1.0, 0.0)
	_check("travel exponent must be positive", is_nan(Carb.opening(0.5, u_idle, 0.0)) and is_nan(Carb.opening(0.5, u_idle, -1.0)))
	# Capacity and demand in SI; a 2.03e-5 m² effective area passes about 4.0e-3 m³/s choked.
	_near("capacity", Carb.capacity_m3_s(2.03e-5), 2.03e-5 * Carb.PSI_CHOKED * sqrt(Carb.R_AIR * Carb.T_REFERENCE_K), 1e-18)
	_near("demand 2T", Carb.demand_m3_s(6000.0, 0.8, 1.0e-5, 1.0), 1.0e-5 * 0.8 * 100.0, 1e-18)
	_near("demand 4T breathes once per two revolutions", Carb.demand_m3_s(6000.0, 0.8, 1.0e-5, 2.0), 0.5 * 1.0e-5 * 0.8 * 100.0, 1e-18)
	_check("demand rejects invalid inputs", is_nan(Carb.demand_m3_s(-1.0, 0.8, 1e-5, 1.0)) and is_nan(Carb.demand_m3_s(1.0, 0.8, 0.0, 1.0)))
	# Admission: 1 wide open at every speed, 1 at rest, choked 1/rpm at a small opening, and the balance it claims.
	var capacity: float = Carb.capacity_m3_s(2.03e-5)
	var displacement := 9.95e-6
	for rpm in [1000.0, 5000.0, 12000.0, 18000.0]:
		_near("wide open admits 1 at %.0f rpm" % rpm, Carb.admission(1.0, rpm, 0.9, displacement, 1.0, capacity), 1.0, 0.0)
	_near("rest admits 1", Carb.admission(0.01, 0.0, 0.9, displacement, 1.0, capacity), 1.0, 0.0)
	var small_low: float = Carb.admission(0.01, 3000.0, 0.6, displacement, 1.0, capacity)
	var small_high: float = Carb.admission(0.01, 9000.0, 0.6, displacement, 1.0, capacity)
	var x_low: float = Carb.demand_m3_s(3000.0, 0.6, displacement, 1.0) / capacity
	var x_high: float = Carb.demand_m3_s(9000.0, 0.6, displacement, 1.0) / capacity
	_check("small opening is choked at both speeds", 0.01 / x_low < Carb.CRITICAL_RATIO and 0.01 / x_high < Carb.CRITICAL_RATIO, "%g %g" % [0.01 / x_low, 0.01 / x_high])
	_near("choked charge falls as 1/rpm (ratio of speeds × wide-open ratios)", small_low / small_high,
		3.0 * Carb.charge_ratio(1.0 / x_high) / Carb.charge_ratio(1.0 / x_low), 1e-12)
	var open_fraction := 0.3
	var rpm_mid := 8000.0
	var x_mid: float = Carb.demand_m3_s(rpm_mid, 0.85, displacement, 1.0) / capacity
	var r_mid: float = Carb.charge_ratio(open_fraction / x_mid)
	_near("restricted flow balances demand: r x = a g(r)", r_mid * x_mid, open_fraction * Carb.flow_function(r_mid), 1e-12)
	_near("admission is the ratio to wide open", Carb.admission(open_fraction, rpm_mid, 0.85, displacement, 1.0, capacity),
		r_mid / Carb.charge_ratio(1.0 / x_mid), 1e-15)
	var a_prev := 0.0
	monotone = true
	for i in range(1, 101):
		var value: float = Carb.admission(0.01 * i, 7000.0, 0.8, displacement, 1.0, capacity)
		monotone = monotone and value >= a_prev
		a_prev = value
	_check("admission grows with the opening", monotone)
	a_prev = 2.0
	monotone = true
	for i in range(1, 40):
		var value: float = Carb.admission(0.05, 500.0 * i, 0.8, displacement, 1.0, capacity)
		monotone = monotone and value <= a_prev
		a_prev = value
	_check("admission falls with speed at a fixed opening", monotone)
	_check("admission rejects invalid inputs", is_nan(Carb.admission(0.0, 5000.0, 0.8, displacement, 1.0, capacity))
		and is_nan(Carb.admission(1.5, 5000.0, 0.8, displacement, 1.0, capacity))
		and is_nan(Carb.admission(0.5, 5000.0, 0.8, displacement, 1.0, 0.0))
		and is_nan(Carb.admission(0.5, NAN, 0.8, displacement, 1.0, capacity)))
	print("Glow carburettor: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
