# D6e-R4: the launch trim throttle. Home and Quick Flight trim every airplane for level flight at 50 % throttle, in
# the air and as the runway start's flying trim; the reference trim (trim_throttle NAN) stays the fixture of tests,
# golden flights and the technical route. The owner's procedure is flown twice from the runway: with the cruise trim
# the Stik holds its height at half throttle, with the reference trim it climbs away.
# Run: godot --headless --path app --script res://tests/test_trim_throttle.gd
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Weather = preload("res://physics/wind_config.gd")
const RB = preload("res://physics/rigid_body.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const STIK_ID := "jensen-das-ugly-stik-60"
const HOLD_SECONDS := 40.0 # after the throttle is brought back: the climb rate is averaged over the second half
var checks := 0
var failures := 0
var _pitch_raw := 0.0


func _initialize() -> void:
	call_deferred("run")


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))


func make(path: String, id: String, choice: String, trim: float, field: Dictionary = {}) -> Node:
	var s = Session.new()
	s.start_choice = choice
	s.trim_throttle = trim
	s.crash_auto_restart = false
	s.setup(path, id)
	root.add_child(s)
	s.set_physics_process(false)
	s.sim.set_physics_process(false)
	s.radio.connected = false
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = _pitch_raw, yaw = 0.0, throttle = 0.0}
	if not field.is_empty():
		s.set_field(field)
		s.reset()
	return s


func fly(s: Node, ticks: int) -> void:
	for i in ticks:
		s._physics_process(s.sim.dt())
		if s.sim.paused:
			break
		s.sim.step()


func airborne(s: Node) -> bool:
	for c in s.gear_compressions(s.sim.state):
		if c > 0.0:
			return false
	return true


func speed(s: Node) -> float:
	var st: PackedFloat64Array = s.sim.state
	return sqrt(st[RB.VEL] ** 2 + st[RB.VEL + 1] ** 2 + st[RB.VEL + 2] ** 2)


## The owner's procedure: full throttle and up elevator until airborne plus three seconds, then sticks centred and the
## throttle brought back to `throttle`. Returns the mean climb rate over the second half of the hold and the speeds.
func takeoff_and_hold(s: Node, throttle: float) -> Dictionary:
	var dt: float = s.sim.dt()
	s.commands.throttle = 1.0
	_pitch_raw = 0.35
	var airborne_t := -1.0
	for _tick in roundi(20.0 / dt):
		fly(s, 1)
		if s.sim.paused or not s.crash.is_empty():
			break
		if airborne(s):
			if airborne_t < 0.0:
				airborne_t = s.sim.time()
			elif s.sim.time() - airborne_t > 3.0:
				break
	_pitch_raw = 0.0
	s.commands.throttle = throttle
	var t0: float = s.sim.time()
	var h_mid := NAN
	var v_mid := NAN
	while s.sim.time() - t0 < HOLD_SECONDS and not s.sim.paused and s.crash.is_empty():
		fly(s, 1)
		if is_nan(h_mid) and s.sim.time() - t0 >= 0.5 * HOLD_SECONDS:
			h_mid = -s.sim.state[RB.POS + 2]
			v_mid = speed(s)
	var h_end: float = -s.sim.state[RB.POS + 2]
	var span: float = s.sim.time() - t0 - 0.5 * HOLD_SECONDS
	return {airborne_t = airborne_t, climb_rate = (h_end - h_mid) / span if span > 0.0 else NAN, h_mid = h_mid,
		h_end = h_end, v_mid = v_mid, v_end = speed(s), crashed = not s.crash.is_empty() or s.sim.paused}


func run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	check("default field loads", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var field: Dictionary = loaded.field

	# Reference, cruise and the explicit half-power choice.
	var reference := make(STIK, STIK_ID, Session.START_AIRBORNE, NAN)
	check("reference trim stays the default", reference.is_flyable() and not reference.start.has("requested_throttle")
		and is_nan(reference.selected_trim_throttle()) and not reference.cruise_trim_active()
		and reference.trace_meta().launch_trim_throttle == "reference")
	var cruise := make(STIK, STIK_ID, Session.START_AIRBORNE, Session.CRUISE_TRIM_THROTTLE)
	var explicit := make(STIK, STIK_ID, Session.START_HALF_POWER, NAN)
	check("airborne start with the cruise trim is the 50 % level trim", cruise.is_flyable() and cruise.cruise_trim_active()
		and cruise.start.requested_throttle == 0.5 and absf(cruise.start.throttle - 0.5) < 1e-7
		and absf(cruise.commands.throttle - 0.5) < 1e-7 and cruise.trims.pitch == cruise.start.pitch_command)
	check("it equals the explicit half-power start", explicit.is_flyable() and cruise.start.V == explicit.start.V
		and cruise.start.pitch_command == explicit.start.pitch_command and cruise.sim.state == explicit.sim.state)
	check("metadata keeps the selected choice and names the trim throttle", cruise.trace_meta().selected_start_choice == "airborne"
		and cruise.trace_meta().launch_choice == "airborne" and cruise.trace_meta().launch_trim_throttle == "0.5")
	check("the cruise start flies faster than the reference start", cruise.start.V > reference.start.V)
	cruise.adjust_elevator_trim(1.0)
	cruise.reset()
	check("restart restores the solved cruise trim", cruise.trims.pitch == cruise.start.pitch_command and cruise.start.requested_throttle == 0.5)
	cruise.set_start_altitude(45.0)
	check("denser launch atmosphere accepted", cruise.setup_weather(Weather.preset("cool-dense")))
	cruise.reset()
	check("atmosphere refit keeps the selected trim throttle", cruise.is_flyable() and cruise.start.requested_throttle == 0.5
		and absf(cruise.start.throttle - 0.5) < 1e-7 and absf(cruise.sim.state[2] + 45.0) < 1e-9)
	explicit.free()
	cruise.free()

	# Refused selections fail closed; a rotorcraft keeps its reference launch.
	for bad in [1.5, 0.0, -0.25, INF]:
		var refused := make(STIK, STIK_ID, Session.START_AIRBORNE, float(bad))
		check("trim throttle %s is refused before flight" % str(bad), not refused.is_flyable() and refused.sim.paused
			and refused.pause_reason.contains("trim throttle"), refused.pause_reason)
		refused.free()
	var rotorcraft_id := ""
	for id in Catalog.ids():
		if Catalog.is_rotorcraft(id):
			rotorcraft_id = id
			break
	var rotor := make(str(Catalog.entry(rotorcraft_id).data), rotorcraft_id, Session.START_AIRBORNE, Session.CRUISE_TRIM_THROTTLE)
	check("a rotorcraft (%s) keeps its reference launch under the product trim" % rotorcraft_id, not rotorcraft_id.is_empty()
		and not rotor.cruise_trim_active() and not rotor.start.has("requested_throttle"))
	rotor.free()

	# Selection after setup: airborne refits on reset, and the runway start carries the trim.
	var late := make(STIK, STIK_ID, Session.START_AIRBORNE, NAN)
	late.trim_throttle = Session.CRUISE_TRIM_THROTTLE
	late.reset()
	check("a trim throttle selected after setup refits before the airborne launch", late.is_flyable()
		and late.start.requested_throttle == 0.5 and late.trims.pitch == late.start.pitch_command)
	late.free()
	var runway_reference := make(STIK, STIK_ID, Session.START_RUNWAY, NAN, field)
	check("reference runway start is unchanged", runway_reference.is_flyable() and not runway_reference.start.has("requested_throttle")
		and runway_reference.trace_meta().launch_trim_throttle == "reference" and runway_reference.trace_meta().launch_choice == "runway")
	var reference_trim: float = runway_reference.trims.pitch
	runway_reference.trim_throttle = Session.CRUISE_TRIM_THROTTLE
	runway_reference.reset()
	check("a trim throttle selected after the runway setup is solved on reset", runway_reference.is_flyable()
		and runway_reference.start.requested_throttle == 0.5 and runway_reference.trims.pitch == runway_reference.start.pitch_command
		and runway_reference.trims.pitch != reference_trim and runway_reference.trace_meta().launch_trim_throttle == "0.5")
	runway_reference.free()

	# Every runway airplane parks at the threshold with the cruise trim as its flying trim.
	var fleet := []
	for entry in Catalog.airplane_flyable_entries():
		var id: String = str(entry.id)
		if not Session.runway_aircraft_supported(id):
			continue
		var a := make(str(entry.data), id, Session.START_RUNWAY, Session.CRUISE_TRIM_THROTTLE, field)
		check(id + " runway start is trimmed for 50 % throttle", a.is_flyable() and a.start.requested_throttle == 0.5
			and absf(a.start.throttle - 0.5) < 1e-7 and a.trims.pitch == a.start.pitch_command
			and a.trace_meta().launch_choice == "runway" and a.trace_meta().launch_trim_throttle == "0.5", a.start_error)
		check(id + " parks at idle with the elevator at its flying trim", a.is_flyable() and speed(a) < 1e-9
			and a.sim.inputs[3] == 0.0 and a.sim.inputs[1] == clampf(a.trims.pitch, -1.0, 1.0))
		if a.is_flyable():
			fleet.append({id = id, cruise_speed_mps = snappedf(a.start.V, 0.01), elevator_up_deg = snappedf(a.start.pitch_command * a.throws_deg().elevator, 0.01)})
		a.free()
	print("TRIM_THROTTLE_FLEET ", JSON.stringify(fleet))

	# The owner's procedure from the runway, with each trim.
	var results := {}
	for trim in [NAN, Session.CRUISE_TRIM_THROTTLE]:
		var s := make(STIK, STIK_ID, Session.START_RUNWAY, float(trim), field)
		var label: String = "reference" if is_nan(float(trim)) else "cruise"
		check(label + " runway start is flyable", s.is_flyable(), s.start_error)
		if s.is_flyable():
			results[label] = takeoff_and_hold(s, 0.5)
			print("TRIM_THROTTLE_%s " % label.to_upper(), JSON.stringify(results[label]))
		s.free()
	if results.has("reference") and results.has("cruise"):
		var r: Dictionary = results.reference
		var c: Dictionary = results.cruise
		check("both takeoffs lift off and fly the hold without a crash", r.airborne_t > 0.0 and c.airborne_t > 0.0 and not r.crashed and not c.crashed)
		check("the reference-trimmed Stik climbs away at half throttle (%.2f m/s)" % r.climb_rate, r.climb_rate > 0.5)
		check("the cruise-trimmed Stik holds its height at half throttle (%.2f m/s)" % c.climb_rate,
			absf(c.climb_rate) < 0.3 and absf(c.climb_rate) < 0.25 * absf(r.climb_rate))
		check("the cruise-trimmed Stik settles near its trimmed speed (%.1f m/s)" % c.v_end, absf(c.v_end - cruise_speed(fleet)) < 0.15 * cruise_speed(fleet))
	print("TRIM_THROTTLE_CHECKS ", checks, " failures=", failures)
	quit(1 if failures else 0)


func cruise_speed(fleet: Array) -> float:
	for row in fleet:
		if row.id == STIK_ID:
			return float(row.cruise_speed_mps)
	return NAN
