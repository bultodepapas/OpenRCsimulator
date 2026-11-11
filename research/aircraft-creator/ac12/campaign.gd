extends SceneTree
## AC-12 numerical-domain campaign driver (research, not a test). Preregistration, tolerances and
## results: docs/research/aircraft-creator/AC-12-numerical-campaign.md.
##
## Every case is an in-domain Aircraft Creator definition compiled by the unchanged Compiler and flown
## by the unchanged FlightSession from its trimmed airborne start, with the same open-loop input tape at
## 240 Hz (production), 480 Hz and 960 Hz. The tick is changed the way tests/test_creator_flight.gd
## does it: Engine.physics_ticks_per_second before the session is set up. Samples are compared at the
## common 240 Hz instants. Software verification of the integration step, not physical validation.
##
## Run (repository root, pinned engine):
##   <engine> --headless --path app --audio-driver Dummy --script <abs>/research/aircraft-creator/ac12/campaign.gd -- --list
##   <engine> ... campaign.gd -- --out=<dir> [--only=C01,C02]

const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const R := preload("res://workshop/creator/result.gd")
const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const RATES: Array[int] = [240, 480, 960]
const SAMPLE_HZ := 240
const DURATION_S := 6.0
const TAPES: PackedStringArray = ["pitch_doublet", "roll_doublet", "rudder_kick", "throttle_step"]
## Preregistered tolerances of the estimated 240 Hz error against the refined limit, per metric.
const TOLERANCES := {
	"position_m": 0.10, "attitude_deg": 0.5, "rates_dps": 2.0, "airspeed_mps": 0.05,
	"rotor_rpm": 20.0, "current_a": 0.2, "charge_fraction": 0.002,
}
## Differences below these floors are numerical noise: no convergence ratio is formed from them.
const FLOORS := {
	"position_m": 1e-7, "attitude_deg": 1e-7, "rates_dps": 1e-6, "airspeed_mps": 1e-8,
	"rotor_rpm": 1e-5, "current_a": 1e-7, "charge_fraction": 1e-10,
}
## A refinement must shrink the difference at least to this share (0.5 = first order, 0.0625 = fourth).
const MAX_RATIO := 0.75
const METRICS: PackedStringArray = ["position_m", "attitude_deg", "rates_dps", "airspeed_mps", "rotor_rpm", "current_a", "charge_fraction"]
const STRUCTURE_IDS: PackedStringArray = ["item_wing_airframe", "item_fuselage_airframe", "item_stabilizer_elevator", "item_fin_rudder"]
const GRAVITY := 9.80665

var Variants: GDScript


func _initialize() -> void:
	Variants = load((get_script() as Script).resource_path.get_base_dir().path_join("variants.gd"))
	var out := ""
	var only := PackedStringArray()
	var list := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.substr(6)
		elif argument.begins_with("--only="):
			only = argument.substr(7).split(",")
		elif argument == "--list":
			list = true
	var cases: Array = _cases()
	var results := []
	for case: Array in cases:
		var id: String = case[0]
		if not only.is_empty() and not only.has(id):
			continue
		var definition: Dictionary = case[2]
		if definition.is_empty():
			print("%s %s: NOT BUILT (no balance or mass solution)" % [id, case[1]])
			continue
		var compiled: Dictionary = Compiler.compile_candidate(definition)
		if not compiled.ok:
			print("%s %s: REFUSED %s" % [id, case[1], str(R.texts(compiled))])
			continue
		var candidate: RefCounted = compiled.value
		var s: Dictionary = candidate.summary()
		var controls: Dictionary = definition["controls"]
		print("%s %s | span %.3f m, AR %.2f, taper %.2f, dihedral %.2f deg, mass %.3f kg, W/S %.2f kg/m2, SM %.3f, T/W %.2f, Vh %.3f, Vv %.4f, level %.2f m/s, throws %s/%s/%s deg, servo %.2f s, thrust angles %s, charge %.2f, sha %s" % [
			id, case[1], float(definition["wing"]["span"]), s.aspect_ratio, float(definition["wing"]["tip_chord"]) / float(definition["wing"]["root_chord"]),
			float(definition["wing"]["dihedral_deg"]), s.mass_kg, s.wing_loading_kg_m2, s.static_margin, s.thrust_to_weight, s.tail_volume_h,
			s.tail_volume_v, s.level_speed_mps, str(controls["aileron_deg"]), str(controls["elevator_deg"]), str(controls["rudder_deg"]),
			float(controls["servo_time_s"]), str(definition["equipment"]["thrust_angles_deg"]), float(definition["battery"]["initial_soc"]),
			candidate.raw_sha256().substr(0, 12)])
		if list:
			continue
		for tape: String in TAPES:
			var entry: Dictionary = _refine(candidate, tape)
			entry["case"] = id
			entry["tape"] = tape
			entry["record_sha256"] = candidate.raw_sha256()
			results.append(entry)
			_report(id, tape, entry)
	Engine.physics_ticks_per_second = 240
	if not out.is_empty() and not list:
		DirAccess.make_dir_recursive_absolute(out)
		var name := "campaign-%s.json" % ("all" if only.is_empty() else "-".join(only))
		var file := FileAccess.open(out.path_join(name), FileAccess.WRITE)
		file.store_string(JSON.stringify({"tolerances": TOLERANCES, "max_ratio": MAX_RATIO, "duration_s": DURATION_S,
			"rates_hz": RATES, "engine": Engine.get_version_info().string, "results": results}, "  "))
		file.close()
		print("results written to ", out.path_join(name))
	quit(0)


# --- Cases --------------------------------------------------------------------------------------

## [id, description, definition]. The construction of every case is part of the preregistration.
func _cases() -> Array:
	var template: Dictionary = Definition.template()
	var margin: float = float(Compiler.summarize(template).static_margin)
	var cases := []
	cases.append(["C01", "template", template])
	var interior: Dictionary = Variants.tapered(0.8)
	interior["wing"]["dihedral_deg"] = 3.0
	interior["controls"] = {"aileron_deg": 15.0, "elevator_deg": 15.0, "rudder_deg": 20.0, "servo_time_s": 0.2}
	cases.append(["C02", "interior: taper 0.8, dihedral 3, margin 0.18, modest throws", Variants.balanced(interior, 0.18)])
	cases.append(["C03", "edge: aft balance, margin 0.085", Variants.balanced(template, 0.085)])
	cases.append(["C04", "edge: forward balance, margin 0.295", Variants.balanced(template, 0.295)])
	cases.append(["C05", "edge: aspect ratio 4", Variants.balanced(Variants.aspect(4.0), margin)])
	cases.append(["C06", "edge: aspect ratio 7", Variants.balanced(Variants.aspect(7.0), margin)])
	cases.append(["C07", "edge: span 2.2 m", Variants.balanced(Variants.scaled(2.2 / 1.5), margin)])
	cases.append(["C08", "edge: span 1.0 m (thrust/weight bound)", Variants.balanced(Variants.scaled(1.0 / 1.5), margin)])
	cases.append(["C09", "edge: taper 0.6", Variants.balanced(Variants.tapered(0.6), margin)])
	cases.append(["C10", "edge: flat wing, dihedral 0", _with(template, "wing", "dihedral_deg", 0.0)])
	cases.append(["C11", "edge: dihedral 8", _with(template, "wing", "dihedral_deg", 8.0)])
	var light: Dictionary = Variants.balanced(_lightened(template, 1.97), margin)
	cases.append(["C12", "edge: lightest build, thrust/weight 1.97", light])
	cases.append(["C13", "edge: heavy, wing loading 7.9", _loaded(template, 7.9)])
	var stiff: Dictionary = light.duplicate(true)
	if not stiff.is_empty():
		stiff["controls"] = {"aileron_deg": 30.0, "elevator_deg": 30.0, "rudder_deg": 35.0, "servo_time_s": 0.05}
	cases.append(["C14", "stiff A: lightest build, thrust/weight 1.97, fastest servos, largest throws", stiff])
	cases.append(["C15", "stiff B: span 0.9 m, AR 4.5, thrust/weight 1.97, margin 0.29, fastest servos, largest throws", _small_fast()])
	var slender: Dictionary = Variants.aspect(7.0)
	var mean: float = 0.5 * (float(slender["wing"]["root_chord"]) + float(slender["wing"]["tip_chord"]))
	slender["wing"]["root_chord"] = 2.0 * mean / 1.6
	slender["wing"]["tip_chord"] = 0.6 * float(slender["wing"]["root_chord"])
	slender["wing"]["dihedral_deg"] = 0.0
	slender["inventory"] = []
	slender["inventory"] = Definition.propose_airframe_inventory(slender)
	slender["controls"] = {"aileron_deg": 30.0, "elevator_deg": 30.0, "rudder_deg": 35.0, "servo_time_s": 0.5}
	cases.append(["C16", "adverse: AR 7, taper 0.6, flat wing, margin 0.085, largest throws, slowest servos", Variants.balanced(slender, 0.085)])
	var forward: Dictionary = Variants.aspect(4.0)
	forward["wing"]["dihedral_deg"] = 8.0
	forward["equipment"]["thrust_angles_deg"] = [5.0, 5.0]
	forward["battery"]["initial_soc"] = 0.2
	cases.append(["C17", "adverse: AR 4, heavy 7.9, margin 0.295, dihedral 8, thrust angles 5/5, charge 0.2",
		_loaded(Variants.balanced(forward, 0.295), 7.9)])
	return cases


func _with(definition: Dictionary, group: String, key: String, value: Variant) -> Dictionary:
	var d: Dictionary = definition.duplicate(true)
	d[group][key] = value
	return d


## The four structure items (wing, fuselage, stabilizer, fin) made lighter by one factor until the static
## thrust is `ratio` times the weight: a lighter build the player states (kind manual).
func _lightened(definition: Dictionary, ratio: float) -> Dictionary:
	var low := 0.05
	var high := 1.0
	if float(Compiler.summarize(_scaled_structure(definition, low)).get("thrust_to_weight", 0.0)) < ratio:
		return {}
	for iteration: int in 60:
		var middle: float = 0.5 * (low + high)
		if float(Compiler.summarize(_scaled_structure(definition, middle)).thrust_to_weight) > ratio:
			low = middle
		else:
			high = middle
	return _scaled_structure(definition, high)


func _scaled_structure(definition: Dictionary, factor: float) -> Dictionary:
	var d: Dictionary = definition.duplicate(true)
	for item: Dictionary in d["inventory"]:
		if STRUCTURE_IDS.has(item["id"]):
			item["mass"] = float(item["mass"]) * factor
			item["kind"] = "manual"
	return d


## A payload at the centre of mass (the balance is unchanged) until the wing loading is `loading` kg/m2.
func _loaded(definition: Dictionary, loading: float) -> Dictionary:
	if definition.is_empty():
		return {}
	var summary: Dictionary = Compiler.summarize(definition)
	var extra: float = loading * float(summary.wing_area_m2) - float(summary.mass_kg)
	if extra <= 0.0:
		return {}
	return Variants.with_mass(definition, "item_research_payload", extra, summary.cg_m)


## Smallest span of the domain. At 0.9 m the wing loading and thrust/weight bounds only admit aspect
## ratios below 4.66 with this power package: AR 4.5, balanced to margin 0.29, then loaded at the centre
## of mass to thrust/weight 1.97.
func _small_fast() -> Dictionary:
	var d: Dictionary = Variants.scaled(0.9 / 1.5)
	d["wing"]["span"] = 0.9 # exactly the bound: 1.5 × 0.6 rounds just below it
	d["wing"]["root_chord"] = 0.2
	d["wing"]["tip_chord"] = 0.2
	d["inventory"] = []
	d["inventory"] = Definition.propose_airframe_inventory(d)
	d["controls"] = {"aileron_deg": 30.0, "elevator_deg": 30.0, "rudder_deg": 35.0, "servo_time_s": 0.05}
	d = Variants.balanced(d, 0.29)
	if d.is_empty():
		return {}
	var summary: Dictionary = Compiler.summarize(d)
	var target: float = float(summary.static_thrust_n) / (1.97 * GRAVITY)
	var extra: float = target - float(summary.mass_kg)
	return Variants.with_mass(d, "item_research_payload", extra, summary.cg_m) if extra > 0.0 else d


# --- Tapes and flight ---------------------------------------------------------------------------

## Stick input added to the trimmed inputs at `time` seconds: [roll, pitch, yaw, throttle]. Every edge is
## a multiple of 0.25 s, so all three step sizes switch at the same instants. `throttle` is absolute
## when the returned flag is set.
func _tape(tape: String, time: float, trimmed: PackedFloat64Array) -> PackedFloat64Array:
	var inputs: PackedFloat64Array = trimmed.duplicate()
	match tape:
		"pitch_doublet":
			if time >= 0.5 and time < 1.0:
				inputs[1] += 0.3
			elif time >= 1.0 and time < 1.5:
				inputs[1] -= 0.3
		"roll_doublet":
			if time >= 0.5 and time < 1.0:
				inputs[0] += 0.3
			elif time >= 1.0 and time < 1.5:
				inputs[0] -= 0.3
		"rudder_kick":
			if time >= 0.5 and time < 1.0:
				inputs[2] += 0.5
		"throttle_step":
			if time >= 0.5 and time < 3.0:
				inputs[3] = 1.0
	return inputs


## One flight at `rate` Hz. Returns {ok, fault, samples}: samples[k] at t = (k + 1)/240 s holds
## [13 body states, airspeed, rotor rpm, battery current A, consumed charge C].
func _fly(candidate: RefCounted, tape: String, rate: int) -> Dictionary:
	Engine.physics_ticks_per_second = rate
	var session: Node = Session.new()
	session.physics_enabled = true
	session.input_enabled = false
	session.rate_profile = "full"
	session.crash_auto_restart = false
	session.start_choice = Session.START_AIRBORNE
	session.setup("", candidate.aircraft_id(), candidate.flight_data())
	if not session.is_flyable():
		var refusal: String = session.start_error
		session.free()
		return {ok = false, fault = "start refused: " + refusal, samples = []}
	var trimmed: PackedFloat64Array = session.sim.inputs.duplicate()
	var every: int = rate / SAMPLE_HZ
	var samples := []
	var fault := ""
	for tick: int in int(DURATION_S * rate):
		session.sim.inputs = _tape(tape, float(tick) / float(rate), trimmed)
		session.sim.step()
		if not session.sim.fault_reason.is_empty() or not Session.Sim.state_is_valid(session.sim.state):
			fault = "fault at tick %d: %s" % [tick, session.sim.fault_reason]
			break
		if (tick + 1) % every == 0:
			var state: PackedFloat64Array = session.sim.state
			var electric: Dictionary = session.electrical_state()
			var row: PackedFloat64Array = state.duplicate()
			row.append(float(session.air_data(state).V))
			row.append(float(session.sim.aux[Session.AUX_RPM]))
			row.append(float(electric.get("pack_current_a", electric.get("battery_current_a", NAN))))
			row.append(float(electric.get("consumed_charge_c", NAN)))
			samples.append(row)
	var result := {ok = fault.is_empty(), fault = fault, samples = samples, trim_rpm = float(session.start.rpm),
		trim_speed = float(session.start.V)}
	session.free()
	return result


## The largest difference between two runs over the common instants, per metric.
func _differences(a: Array, b: Array) -> Dictionary:
	var out := {}
	for metric: String in METRICS:
		out[metric] = 0.0
	for index: int in mini(a.size(), b.size()):
		var x: PackedFloat64Array = a[index]
		var y: PackedFloat64Array = b[index]
		out["position_m"] = maxf(out["position_m"], M.norm(M.v3(x[RB.POS] - y[RB.POS], x[RB.POS + 1] - y[RB.POS + 1], x[RB.POS + 2] - y[RB.POS + 2])))
		var dot: float = absf(x[RB.ATT] * y[RB.ATT] + x[RB.ATT + 1] * y[RB.ATT + 1] + x[RB.ATT + 2] * y[RB.ATT + 2] + x[RB.ATT + 3] * y[RB.ATT + 3])
		var cross := M.v3(0.0, 0.0, 0.0)
		# Angle between the two attitudes from the vector part of the relative quaternion (accurate near zero).
		var relative: PackedFloat64Array = M.q_mul(M.q_conj(M.quat(x[RB.ATT], x[RB.ATT + 1], x[RB.ATT + 2], x[RB.ATT + 3])),
			M.quat(y[RB.ATT], y[RB.ATT + 1], y[RB.ATT + 2], y[RB.ATT + 3]))
		cross = M.v3(relative[1], relative[2], relative[3])
		out["attitude_deg"] = maxf(out["attitude_deg"], rad_to_deg(2.0 * atan2(M.norm(cross), dot)))
		out["rates_dps"] = maxf(out["rates_dps"], rad_to_deg(M.norm(M.v3(x[RB.RATE] - y[RB.RATE], x[RB.RATE + 1] - y[RB.RATE + 1], x[RB.RATE + 2] - y[RB.RATE + 2]))))
		out["airspeed_mps"] = maxf(out["airspeed_mps"], absf(x[RB.SIZE] - y[RB.SIZE]))
		out["rotor_rpm"] = maxf(out["rotor_rpm"], absf(x[RB.SIZE + 1] - y[RB.SIZE + 1]))
		out["current_a"] = maxf(out["current_a"], absf(x[RB.SIZE + 2] - y[RB.SIZE + 2]))
	if not a.is_empty() and not b.is_empty():
		var last_a: PackedFloat64Array = a[a.size() - 1]
		var last_b: PackedFloat64Array = b[b.size() - 1]
		out["charge_fraction"] = absf(last_a[RB.SIZE + 3] - last_b[RB.SIZE + 3]) / maxf(absf(last_b[RB.SIZE + 3]), 1e-9)
	return out


## Three flights and the preregistered verdict per metric.
func _refine(candidate: RefCounted, tape: String) -> Dictionary:
	var runs := {}
	var faults := PackedStringArray()
	for rate: int in RATES:
		runs[rate] = _fly(candidate, tape, rate)
		if not runs[rate].ok:
			faults.append("%d Hz: %s" % [rate, runs[rate].fault])
	var entry := {"faults": Array(faults), "metrics": {}, "pass": faults.is_empty()}
	if not faults.is_empty():
		return entry
	var coarse: Dictionary = _differences(runs[240].samples, runs[480].samples)
	var fine: Dictionary = _differences(runs[480].samples, runs[960].samples)
	var excursion: Dictionary = _excursion(runs[960].samples)
	entry["excursion"] = excursion
	for metric: String in METRICS:
		var e1: float = coarse[metric]
		var e2: float = fine[metric]
		var verdict := {"e_240_480": e1, "e_480_960": e2, "tolerance": TOLERANCES[metric]}
		if e1 <= FLOORS[metric]:
			verdict["ratio"] = 0.0
			verdict["order"] = 0.0
			verdict["error_240"] = e1
			verdict["converges"] = true
			verdict["noise_floor"] = true
		else:
			var ratio: float = e2 / e1
			verdict["ratio"] = ratio
			verdict["order"] = -log(maxf(ratio, 1e-12)) / log(2.0)
			verdict["converges"] = ratio <= MAX_RATIO
			verdict["error_240"] = e1 / (1.0 - ratio) if ratio < 1.0 else INF
			verdict["noise_floor"] = false
		verdict["pass"] = bool(verdict["converges"]) and float(verdict["error_240"]) <= float(TOLERANCES[metric])
		if is_inf(float(verdict["error_240"])):
			verdict["error_240"] = -1.0 # JSON has no infinity: -1 marks "not converging, no estimate"
		entry["metrics"][metric] = verdict
		entry["pass"] = bool(entry["pass"]) and bool(verdict["pass"])
	return entry


## How far the manoeuvre took the airplane (960 Hz run): proves the tape excited it, and gives scale.
func _excursion(samples: Array) -> Dictionary:
	var first: PackedFloat64Array = samples[0]
	var bank := 0.0
	var pitch_low := INF
	var pitch_high := -INF
	var speed_low := INF
	var speed_high := 0.0
	var rpm_high := 0.0
	var rate_high := 0.0
	for row: PackedFloat64Array in samples:
		var euler := M.q_to_euler(M.quat(row[RB.ATT], row[RB.ATT + 1], row[RB.ATT + 2], row[RB.ATT + 3]))
		bank = maxf(bank, absf(rad_to_deg(euler[2])))
		pitch_low = minf(pitch_low, rad_to_deg(euler[1]))
		pitch_high = maxf(pitch_high, rad_to_deg(euler[1]))
		speed_low = minf(speed_low, row[RB.SIZE])
		speed_high = maxf(speed_high, row[RB.SIZE])
		rpm_high = maxf(rpm_high, row[RB.SIZE + 1])
		rate_high = maxf(rate_high, rad_to_deg(M.norm(M.v3(row[RB.RATE], row[RB.RATE + 1], row[RB.RATE + 2]))))
	var last: PackedFloat64Array = samples[samples.size() - 1]
	return {"bank_max_deg": bank, "pitch_min_deg": pitch_low, "pitch_max_deg": pitch_high, "airspeed_min_mps": speed_low,
		"airspeed_max_mps": speed_high, "rpm_max": rpm_high, "rate_max_dps": rate_high,
		"path_m": M.norm(M.v3(last[RB.POS] - first[RB.POS], last[RB.POS + 1] - first[RB.POS + 1], last[RB.POS + 2] - first[RB.POS + 2])),
		"charge_c": last[RB.SIZE + 3]}


func _report(id: String, tape: String, entry: Dictionary) -> void:
	if not (entry["faults"] as Array).is_empty():
		print("  %s %s: FAIL %s" % [id, tape, str(entry["faults"])])
		return
	var parts := PackedStringArray()
	for metric: String in METRICS:
		var v: Dictionary = entry["metrics"][metric]
		parts.append("%s %s err %.3e (e1 %.3e, e2 %.3e, order %.2f)" % [metric, "ok" if v["pass"] else "FAIL", float(v["error_240"]),
			float(v["e_240_480"]), float(v["e_480_960"]), float(v["order"])])
	var x: Dictionary = entry["excursion"]
	print("  %s %s: %s | bank %.0f deg, pitch %.0f..%.0f deg, airspeed %.1f..%.1f m/s, rpm max %.0f, rate max %.0f deg/s | %s" % [id, tape,
		"PASS" if entry["pass"] else "FAIL", x["bank_max_deg"], x["pitch_min_deg"], x["pitch_max_deg"], x["airspeed_min_mps"],
		x["airspeed_max_mps"], x["rpm_max"], x["rate_max_dps"], "; ".join(parts)])
