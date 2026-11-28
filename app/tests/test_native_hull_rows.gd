extends SceneTree
## NK-6f: the hull-scrape observation's contact diagnostics (HullContact.loads for a prepared hull,
## loads_at_properties for finite fuel) from the installed native stage (FlightSession._native_hull_scrape_diagnostics).
## - Random endpoint states touching the field and the lake, with the live mass properties and perturbed ones (not ok,
##   NaN, mismatched inverse, a non-physical tensor): every native answer equals the reference rows bit for bit, and the
##   stage refuses wherever the reference refuses or its diagnostics are unavailable (a lake-covered sample).
## - Flights into a nose-over publish identical hull-scrape observations on every tick with and without the answer, and
##   the native stage answered while the hull touched.
## - Refusals: the hook off, outside the published endpoint, a derived session class.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const SAMPLES := 3000
const FLEET := ["f4u-corsair-250", "jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "turbo-lumber-evolution"]

class DerivedSession extends "res://sim/flight_session.gd":
	pass

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _run() -> void:
	_rng.seed = 61626
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var fleet: Array = []
	for id: String in FLEET:
		var probe := _session(id)
		if probe == null:
			continue
		if probe.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE and probe._native_stage._hull_rows_bound:
			fleet.append(id)
		else:
			print("NK6F_SKIP %s: %s" % [id, str(probe.stage_backend_status())])
		probe.free()
	if fleet.is_empty():
		print("NK6F_HULL_ROWS_SKIP no native session")
		print("native hull rows: %d checks, %d failed" % [_checks, _failures])
		quit(0)
		return
	print("NK6F_FLEET ", fleet)
	for id: String in fleet:
		_direct(id)
		_pair(id)
	_refusals(fleet[0])
	print("native hull rows: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, derived := false) -> Node:
	var s: Node = DerivedSession.new() if derived else Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.start_choice = Flight.START_RUNWAY
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.reset()
	if not s.is_flyable():
		s.free()
		return null
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


## The reference's diagnostics for `state`: [ok, diagnostics].
func _reference(s: Node, state: PackedFloat64Array, finite: bool, properties: Dictionary) -> Array:
	var diagnostics := {}
	if finite:
		var sampled: Dictionary = HullContact.loads_at_properties(state, s._hull_contact, properties, diagnostics)
		return [bool(sampled.ok), diagnostics]
	HullContact.loads(state, s._hull_contact, [], diagnostics)
	return [true, diagnostics]


## The session's rows from a native answer, or null for a refusal.
func _native(s: Node, state: PackedFloat64Array, finite: bool, properties: Dictionary) -> Variant:
	var packed: PackedFloat64Array = Flight._packed_mass_properties(properties) if finite else PackedFloat64Array()
	if finite and packed.is_empty():
		return null
	var answer: PackedFloat64Array = s._native_stage.hull_scrape_rows(state, packed)
	if answer.size() < 2 or answer[0] != 1.0:
		return null
	var points: PackedFloat64Array = s._hull_contact.points
	var rows: Array = []
	for k in int(answer[1]):
		var at := 2 + 6 * k
		var point := int(answer[at])
		var f_n: float = answer[at + 2]
		var f_e: float = answer[at + 3]
		var vn: float = answer[at + 4]
		var ve: float = answer[at + 5]
		rows.append({index = point, point_ned = HullContact._point_ned(state, points.slice(3 * point, 3 * point + 3)),
			normal_force_n = answer[at + 1], tangent_force_ned_n = PackedFloat64Array([f_n, f_e, 0.0]),
			relative_tangent_velocity_ned_mps = PackedFloat64Array([vn, ve, 0.0]),
			friction_power_w = -(f_n * vn + f_e * ve)})
	return {available = true, reason = "", rows = rows}


func _touching_state(origin: PackedFloat64Array, bounds: PackedFloat64Array) -> PackedFloat64Array:
	var s := origin.duplicate()
	if not bounds.is_empty():
		if bounds.size() == 4:
			s[0] = _rng.randf_range(bounds[0] - 5.0, bounds[1] + 5.0) # [north min, north max, east min, east max]
			s[1] = _rng.randf_range(bounds[2] - 5.0, bounds[3] + 5.0)
	else:
		s[0] += _rng.randf_range(-30.0, 30.0)
		s[1] += _rng.randf_range(-30.0, 30.0)
	s[2] = _rng.randf_range(-0.5, 2.5) if not bounds.is_empty() else s[2] + _rng.randf_range(-0.4, 0.6)
	var q := M.q_mul(PackedFloat64Array([origin[6], origin[7], origin[8], origin[9]]),
		M.q_from_euler(_rng.randf_range(-0.9, 0.9), _rng.randf_range(-1.2, 0.6), _rng.randf_range(-3.1, 3.1)))
	for axis in 4:
		s[6 + axis] = q[axis]
	for axis in 3:
		s[3 + axis] = _rng.randf_range(-12.0, 12.0)
		s[10 + axis] = _rng.randf_range(-3.0, 3.0)
	return s


func _perturbed(properties: Dictionary, kind: int) -> Dictionary:
	var p := properties.duplicate(true)
	match kind:
		1: p.ok = false
		2: p.mass_kg = NAN
		3:
			var inverse: PackedFloat64Array = p.inverse
			inverse[0] *= 1.001
			p.inverse = inverse
		4:
			var inertia: PackedFloat64Array = p.inertia
			inertia[0] = -inertia[0]
			p.inertia = inertia
		5: p.mass_kg = -1.0
	return p


func _direct(id: String) -> void:
	var s := _session(id)
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.3}
	for i in 120:
		_tick(s)
	var finite: bool = s.finite_fuel_is_active()
	var live: Dictionary = s.mass_properties() if finite else {}
	var origin: PackedFloat64Array = s.sim.state.duplicate()
	var lake_bounds: PackedFloat64Array = s._hull_contact.get("lake_bounds_ne_m", PackedFloat64Array())
	var stats := {answered = 0, rows = 0, refused_with_reason = 0, refused_conservative = 0, mismatched = 0, covered = 0}
	var first := ""
	for i in SAMPLES:
		var state := _touching_state(origin, lake_bounds if i % 4 == 0 else PackedFloat64Array())
		var kind := 0 if not finite or i % 6 != 5 else 1 + (i / 6) % 5
		var properties := _perturbed(live, kind) if finite else {}
		var reference := _reference(s, state, finite, properties)
		var available: bool = reference[0] and bool(reference[1].get("available", false))
		if reference[0] and not bool(reference[1].get("available", false)):
			stats.covered += 1
		var native: Variant = _native(s, state, finite, properties)
		if native == null:
			stats["refused_with_reason" if not available else "refused_conservative"] += 1
			continue
		stats.answered += 1
		stats.rows += native.rows.size()
		if not available or var_to_bytes(native) != var_to_bytes(reference[1]):
			stats.mismatched += 1
			if first.is_empty():
				first = "native %s reference %s at %s " % [str(native).left(300), str(reference).left(300), str(state)]
	_check(id + ": every native answer equals the reference rows", stats.mismatched == 0, first + str(stats))
	_check(id + ": the stage answered touching states with rows", stats.answered > SAMPLES / 3 and stats.rows > SAMPLES / 3,
		str(stats))
	_check(id + ": conservative refusals stay rare", stats.refused_conservative <= SAMPLES / 20, str(stats))
	_check(id + ": lake-covered samples were exercised", stats.covered > 0 or lake_bounds.is_empty(), str(stats))
	print("NK6F_DIRECT %s %s" % [id, str(stats)])
	s.free()


## Full power with the stick forward tips the aircraft onto its nose; both sessions publish the same observation.
func _pair(id: String) -> void:
	var a := _session(id)
	var b := _session(id)
	b.native_hull_rows_enabled = false
	var raw := func() -> Dictionary: return {roll = 0.0, pitch = -1.0, yaw = 0.0, throttle = 1.0}
	a.read_raw = raw
	b.read_raw = raw
	var same := true
	var touching := 0
	var usec_native := 0
	var usec_reference := 0
	var first := ""
	for i in 2400:
		_tick(a)
		_tick(b)
		if not a.crash.is_empty() or not b.crash.is_empty():
			break
		var t0 := Time.get_ticks_usec()
		var oa: Dictionary = a.hull_scrape_observation()
		var t1 := Time.get_ticks_usec()
		var ob: Dictionary = b.hull_scrape_observation()
		var t2 := Time.get_ticks_usec()
		if not oa.get("contacts", []).is_empty():
			touching += 1
			usec_native += t1 - t0
			usec_reference += t2 - t1
		if var_to_bytes(oa) != var_to_bytes(ob) or var_to_bytes(a.sim.state) != var_to_bytes(b.sim.state):
			same = false
			if first.is_empty():
				first = "tick %d: %s vs %s" % [a.sim.tick, str(oa).left(300), str(ob).left(300)]
	_check(id + ": the nose-over publishes identical hull-scrape observations", same, first)
	print("NK6F_PAIR %s touching=%d answered=%d observation us native %.1f reference %.1f" % [id, touching,
		a.native_hull_row_answers, float(usec_native) / maxi(1, touching), float(usec_reference) / maxi(1, touching)])
	if touching > 0:
		_check(id + ": the native stage answered while the hull touched", a.native_hull_row_answers >= touching,
			str([touching, a.native_hull_row_answers]))
	a.free()
	b.free()


func _refusals(id: String) -> void:
	var s := _session(id)
	s.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = -1.0, yaw = 0.0, throttle = 1.0}
	for i in 480:
		_tick(s)
	var diagnostics := {}
	var finite: bool = s.finite_fuel_is_active()
	var properties: Dictionary = s.mass_properties() if finite else {}
	s.native_hull_rows_enabled = false
	_check(id + ": the hook off refuses", not s._native_hull_scrape_diagnostics(finite, properties, diagnostics))
	s.native_hull_rows_enabled = true
	var tick: int = s._native_facts_tick
	s._native_facts_tick = -1
	_check(id + ": outside the published endpoint refuses", not s._native_hull_scrape_diagnostics(finite, properties, diagnostics))
	s._native_facts_tick = tick
	s.free()
	var derived := _session(id, true)
	derived.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = -1.0, yaw = 0.0, throttle = 1.0}
	for i in 480:
		_tick(derived)
	var derived_properties: Dictionary = derived.mass_properties() if finite else {}
	_check(id + ": a derived session class refuses", not derived._native_hull_scrape_diagnostics(finite, derived_properties, {}))
	derived.free()
