extends SceneTree
## F4U-07: headless production-loader and trim probe for the staged Corsair data (not in the catalog).
## godot --headless --path app --audio-driver Dummy --script <repo>/research/f4u-corsair/F4U-07/probe.gd [-- <json>]
const AircraftData := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const G := 9.80665
## MIL-F-8785C Level 1 bounds as a reference frame, not acceptance: damping ratios carry over; times scale by the
## Froude factor sqrt(1/4.5) for a 1/4.5 model (roll mode 1.0 s, spiral doubling 12 s full size).
const FROUDE_TIME := 0.4714045
const SHORT_PERIOD_ZETA := [0.35, 1.30]
const PHUGOID_ZETA_MIN := 0.04
const DUTCH_ROLL_ZETA_MIN := 0.08
const ROLL_TAU_MAX := 1.0 * FROUDE_TIME
const SPIRAL_DOUBLING_MIN := 12.0 * FROUDE_TIME
var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://").path_join("../research/f4u-corsair/F4U-07/f4u_corsair_250.json").simplify_path()
	var loaded: Dictionary = AircraftData.load_file(path)
	_check("staged v2 file passes production validation", loaded.get("ok", false), "; ".join(loaded.get("errors", PackedStringArray())))
	if not loaded.get("ok", false):
		print("F4U-07 probe: %d checks, %d failed" % [checks, failures])
		quit(1)
		return
	var model: Dictionary = loaded.model
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var inventory_mass := 0.0
	for part: Dictionary in raw.inventory:
		inventory_mass += float(part.mass.value)
	_check("loader keeps identity, span and the inventory flight mass", model.id == "f4u-corsair-250" and absf(float(model.reference.b) - 12.5 / 4.5) < 1e-6
		and absf(float(model.mass_kg) - inventory_mass) < 1e-9, "%s, %.3f m, %.4f kg" % [model.id, model.reference.b, model.mass_kg])
	var throws: Dictionary = model.controls.throw_rad
	var v_start := float(raw.start.level_speed.value)
	var cl_max := float(raw.aero.envelope.CL_max.value)
	var v_stall := sqrt(2.0 * float(model.mass_kg) * G / (1.225 * float(model.reference.S) * cl_max))
	for speed: float in [1.3 * v_stall, v_start, 30.0, 38.0]:
		var t: Dictionary = Trim.solve("level", speed, model, G, throws)
		var ok: bool = t.get("ok", false)
		var detail := "alpha %.2f deg, elevator %.2f of %.1f deg, throttle %.3f, rpm %.0f" % [rad_to_deg(float(t.get("alpha", NAN))),
			rad_to_deg(float(t.get("elevator", NAN))), rad_to_deg(float(throws.elevator)), float(t.get("throttle", NAN)), float(t.get("rpm", NAN))]
		_check("level trim at %.1f m/s inside the control envelope" % speed, ok and absf(float(t.elevator)) < 0.9 * float(throws.elevator)
			and float(t.throttle) >= 0.0 and float(t.throttle) <= 1.0, detail)
	var glide: Dictionary = Trim.solve("glide", 1.4 * v_stall, model, G, throws)
	_check("power-off glide trim at 1.4 Vs", glide.get("ok", false), "gamma %.2f deg, elevator %.2f deg" % [rad_to_deg(float(glide.get("gamma", NAN))), rad_to_deg(float(glide.get("elevator", NAN)))])
	# Flare authority: the power-off glide near the stall must trim inside the elevator throw. Closer than about
	# 1.08 Vs the steady solve enters the stall blend and stops converging, which is not an authority limit.
	for factor: float in [1.15, 1.10]:
		var flare: Dictionary = Trim.solve("glide", factor * v_stall, model, G, throws)
		_check("power-off flare trim at %.2f Vs inside the elevator throw" % factor, flare.get("ok", false)
			and absf(float(flare.elevator)) < float(throws.elevator), "alpha %.2f deg, elevator %.2f of %.1f deg" % [rad_to_deg(float(flare.get("alpha", NAN))),
			rad_to_deg(float(flare.get("elevator", NAN))), rad_to_deg(float(throws.elevator))])
	# Top speed: the level-trim throttle reaches 1. A plausibility band for giant warbirds, not a measurement (CARF: never
	# noticeably exceed 200 km/h).
	var lo := v_start
	var hi := 90.0
	var hi_trim: Dictionary = Trim.solve("level", hi, model, G, throws)
	if hi_trim.get("ok", false) and float(hi_trim.throttle) < 1.0:
		lo = hi
	for _i in 40:
		var mid := 0.5 * (lo + hi)
		var t: Dictionary = Trim.solve("level", mid, model, G, throws)
		if t.get("ok", false) and float(t.throttle) < 1.0:
			lo = mid
		else:
			hi = mid
	_check("full-throttle level speed inside the giant-warbird band (40-65 m/s)", lo > 40.0 and lo < 65.0, "%.1f m/s (%.0f km/h)" % [lo, lo * 3.6])
	# Flight modes of the simulated equations (physics/flight_modes.gd, the same Jacobian test_modes.gd checks).
	for speed: float in [1.3 * v_stall, v_start, 30.0, 38.0]:
		var r: Dictionary = FlightModes.analyze(model, speed)
		if not r.get("ok", false):
			_check("modes found at %.1f m/s" % speed, false, str(r.get("message", "")))
			continue
		var spiral: float = -1.0 / float(r.spiral_tau)
		var doubling: float = log(2.0) / spiral if spiral > 0.0 else INF
		print("modes %.1f m/s: short period %.2f Hz z %.2f | phugoid %.3f Hz z %.3f | roll tau %.3f s | dutch roll %.2f Hz z %.3f | spiral %+.4f 1/s (doubling %s)"
			% [speed, r.short_period.f_hz, r.short_period.zeta, r.phugoid.f_hz, r.phugoid.zeta, r.roll_tau, r.dutch_roll.f_hz, r.dutch_roll.zeta, spiral,
			"stable" if spiral <= 0.0 else "%.1f s" % doubling])
		_check("%.1f m/s short period damping inside %.2f-%.2f" % [speed, SHORT_PERIOD_ZETA[0], SHORT_PERIOD_ZETA[1]],
			r.short_period.zeta >= SHORT_PERIOD_ZETA[0] and r.short_period.zeta <= SHORT_PERIOD_ZETA[1], "%.3f" % r.short_period.zeta)
		_check("%.1f m/s phugoid and dutch roll damped (>= %.2f, >= %.2f)" % [speed, PHUGOID_ZETA_MIN, DUTCH_ROLL_ZETA_MIN],
			r.phugoid.zeta >= PHUGOID_ZETA_MIN and r.dutch_roll.zeta >= DUTCH_ROLL_ZETA_MIN, "%.3f, %.3f" % [r.phugoid.zeta, r.dutch_roll.zeta])
		_check("%.1f m/s roll mode faster than %.2f s, spiral doubling slower than %.1f s" % [speed, ROLL_TAU_MAX, SPIRAL_DOUBLING_MIN],
			r.roll_tau > 0.0 and r.roll_tau <= ROLL_TAU_MAX and doubling >= SPIRAL_DOUBLING_MIN, "%.3f s, %s" % [r.roll_tau, str(doubling)])
	print("F4U-07 probe: %d checks, %d failed (1-g stall %.1f m/s, start %.0f m/s)" % [checks, failures, v_stall, v_start])
	quit(1 if failures else 0)
