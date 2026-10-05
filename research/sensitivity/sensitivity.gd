# D10 sensitivity sweep and D8b validation table (plan review #3 tools; kept outside app/ so test.sh never runs them).
# Each unknown is varied in the aircraft DATA (the loader re-derives stall start, κ, inertia…), then the airplane is
# analysed (flight modes) and flown (scripted maneuvers through the real loop).
# Run (repo root): $(app/get-godot.sh) --headless --path app --script "$PWD/research/sensitivity/sensitivity.gd"
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Scenarios := preload("res://sim/scenarios.gd")

const OUTPUTS := ["SP Hz", "SP ζ", "roll τ s", "DR Hz", "DR ζ", "spiral τ s", "roll °/s", "stall m/s", "glide L/D"]

var _session: Node


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Scenarios.AIRCRAFT))


## Measures one variant. post(model) may edit the derived model (inertia entries).
func _measure(raw: Dictionary, post := Callable()) -> Array:
	var data := AD.validate_and_derive(raw)
	if not data.ok:
		return []
	if post.is_valid():
		post.call(data.model)
	var m := FlightModes.analyze(data.model, 15.0)
	_session._apply(data)
	var roll: RefCounted = Maneuvers.fly(_session, Maneuvers.all().roll_15_coordinated)
	var p_max := 0.0
	for r in roll.row_count():
		p_max = maxf(p_max, roll.value(r, "p_radps"))
	var slow: RefCounted = Maneuvers.fly(_session, Maneuvers.all().slow_flight)
	var stall := 0.0
	for r in slow.row_count():
		if slow.value(r, "alt_m") < Maneuvers.SLOW_FLIGHT.altitude - 0.5:
			stall = slow.value(r, "speed_mps")
			break
	var glide: RefCounted = Maneuvers.fly(_session, Maneuvers.all().glide_15)
	var last: int = glide.row_count() - 1
	var r0 := last - 960
	var dn: float = glide.value(last, "north_m") - glide.value(r0, "north_m")
	var de: float = glide.value(last, "east_m") - glide.value(r0, "east_m")
	var sink: float = glide.value(r0, "alt_m") - glide.value(last, "alt_m")
	var ld := sqrt(dn * dn + de * de) / sink
	return [m.short_period.f_hz, m.short_period.zeta, m.roll_tau, m.dutch_roll.f_hz, m.dutch_roll.zeta, m.spiral_tau, rad_to_deg(p_max), stall, ld]


func _initialize() -> void:
	_session = FlightSession.new()
	_session.setup()
	root.add_child(_session)
	var base := _measure(_raw())

	# D8b: the sim against the University of Minnesota's flight-identified Ultra Stick 120 (Froude-scaled, same CL).
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	var eq := FlightModes.analyze(model, 13.8)
	print("## D8b validation: sim at 13.8 m/s (same CL as the US120 trim) vs Froude-scaled US120 flight identification\n")
	print("| Mode | US120 band | Ugly Stik sim | Ratio |\n| --- | --- | --- | --- |")
	print("| Short period | 1.30 Hz, ζ 0.55 | %.2f Hz, ζ %.2f | %.2f× |" % [eq.short_period.f_hz, eq.short_period.zeta, eq.short_period.f_hz / 1.30])
	print("| Roll τ | 0.116 s | %.3f s | %.2f× faster |" % [eq.roll_tau, 0.116 / eq.roll_tau])
	print("| Dutch roll | 0.57 Hz, ζ 0.31 | %.2f Hz, ζ %.2f | %.2f× |" % [eq.dutch_roll.f_hz, eq.dutch_roll.zeta, eq.dutch_roll.f_hz / 0.57])
	print("| Spiral | stable, τ 4.3 s | %s, τ %.1f s | — |\n" % ["stable" if eq.spiral_tau > 0 else "unstable", eq.spiral_tau])
	var a: Dictionary = model.aero
	var dr: float = deg_to_rad(model.controls.throw_deg.rudder)
	print("Full-rudder steady sideslip (linear): β = Cnδr·δr / Cnβ = %.0f°\n" % rad_to_deg(absf(a.Cndr) * dr / a.Cnb))

	# D10: each unknown ±20 % (CG ±0.02 m ≈ 6.6 % MAC).
	var cases := [
		["Clp", func(r: Dictionary, k: float) -> void: r.aero.coefficients.Clp.value *= k],
		["Cmq", func(r: Dictionary, k: float) -> void: r.aero.coefficients.Cmq.value *= k],
		["Cma", func(r: Dictionary, k: float) -> void: r.aero.coefficients.Cma.value *= k],
		["Cnb", func(r: Dictionary, k: float) -> void: r.aero.coefficients.Cnb.value *= k],
		["Cnr", func(r: Dictionary, k: float) -> void: r.aero.coefficients.Cnr.value *= k],
		["CD0", func(r: Dictionary, k: float) -> void: r.aero.coefficients.CD0.value *= k],
		["CL_max", func(r: Dictionary, k: float) -> void: r.aero.envelope.CL_max.value *= k],
		["servo time", func(r: Dictionary, k: float) -> void: r.controls.servo_full_throw_time.value *= k],
		["mass (all parts)", func(r: Dictionary, k: float) -> void:
			for part in r.inventory:
				part.mass.value *= k],
		["CG (±0.02 m)", func(r: Dictionary, k: float) -> void: r.balance.plan_cg.value[0] += 0.1 * (k - 1.0)],
	]
	var inertia_cases := [["Ixx", 0], ["Iyy", 1], ["Izz", 2]]
	var rows := []
	for c in cases:
		var res := []
		for k in [0.8, 1.2]:
			var raw := _raw()
			c[1].call(raw, k)
			res.append(_measure(raw))
		rows.append([c[0], res])
	for c in inertia_cases:
		var res := []
		for k in [0.8, 1.2]:
			var idx: int = c[1]
			res.append(_measure(_raw(), func(m: Dictionary) -> void:
				var j: PackedFloat64Array = m.inertia.duplicate()
				j[idx] *= k
				m.inertia = j))
		rows.append([c[0], res])
	print("## D10 sensitivity: % change of each output for the parameter at −20 % / +20 %\n")
	print("Baseline: " + ", ".join(range(OUTPUTS.size()).map(func(i): return "%s %.3f" % [OUTPUTS[i], base[i]])) + "\n")
	print("| Parameter | " + " | ".join(OUTPUTS) + " | largest |")
	print("| --- " + "| --- ".repeat(OUTPUTS.size() + 1) + "|")
	var ranked := []
	for row in rows:
		var cells := []
		var worst := 0.0
		for i in OUTPUTS.size():
			var parts := []
			for side in 2:
				if row[1][side].is_empty():
					parts.append("refused") # the loader rejected the variant (e.g. mass outside its plausible range)
				else:
					var pct: float = 100.0 * (row[1][side][i] - base[i]) / base[i]
					parts.append("%+.0f" % pct)
					worst = maxf(worst, absf(pct))
			cells.append(" / ".join(parts))
		ranked.append([worst, "| %s | %s | %.0f %% |" % [row[0], " | ".join(cells), worst]])
	ranked.sort_custom(func(x, y): return x[0] > y[0])
	for r in ranked:
		print(r[1])
	quit()
