## Native stopped-glow rejection diagnostics against a real catalog stage.
## The default command requires the verified installed library; no fallback is
## accepted. The finite trial below was sampled from a gusty runway flight and
## is checked independently with the reference equations on every run.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const GlowAdapter := preload("res://sim/native/glow_stage_adapter.gd")
const Glow := preload("res://physics/glow/flight.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")

const AIRCRAFT := "stik-glow-61fx-2t"
const TRIAL_TIME := 3.6416666666666666
const TICK_TIME := 873.0 * (1.0 / 240.0)
const TRIAL_BODY := [15.00018658360478, -46.99345852420144, -0.23058795293583081,
	0.005059075209472748, -0.00007854796513037385, -0.0022652909870471607,
	0.7067939419427115, 0.01871457760784292, -0.020933506222868832, 0.7068619925666132,
	-0.00031754830948633263, -0.018325934780416386, -0.00014507207548599148]
const TRIAL_AUX := [0.0, 0.017460267118981534, 0.10734315145241612, 0.015740651481846415,
	15.179377496096636, -47.12431220216347, 1.0, 14.81937859654821, -47.12429746475896, 1.0,
	14.999371515393248, -46.77311629659676, 1.0, -1.805834203496064]
const TRIAL_INPUTS := [0.017460267118981534, 0.10734315145241612, 0.015740651481846415, 0.0]
const TRIAL_VALUES := [0.0, 0.299922, 384.8666308211922, 0.0, 0.015047755417653411, 0.0,
	0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 1.15, 0.0, 0.0, -0.7002099621611043, 0.0, 0.0, 1.0,
	0.0006194857881414969, 0.0007114703649769596, 0.00036840290282689206]

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_run.call_deferred()


func _session() -> Node:
	var session: Node = Session.new()
	session.input_enabled = true
	session.physics_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup(Catalog.data_for(AIRCRAFT), AIRCRAFT)
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not session.is_flyable() or not session.glow_is_active() or not field.get("ok", false) \
			or not lake.get("ok", false) or not session.setup_weather(WindConfig.preset("gusty")) \
			or not session.set_field(field.field) or not session.set_lake_context(lake.lake):
		printerr("FAIL cannot prepare the reference glow session")
		session.free()
		return null
	session.start_choice = Session.START_RUNWAY
	session.reset()
	if session.sim.paused or not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
		printerr("FAIL reference runway reset: ", session.pause_reason)
		session.free()
		return null
	session.sim.aux = PackedFloat64Array(TRIAL_AUX)
	session.sim.inputs = PackedFloat64Array(TRIAL_INPUTS)
	session.engine_running = false
	return session


func _reference_detail(session: Node, body: PackedFloat64Array, values: PackedFloat64Array) -> Dictionary:
	var prop: Dictionary = session.aircraft.model.propulsion
	var install: Dictionary = prop.glow
	var state: Dictionary = Glow.unpack(values, install)
	var air: Dictionary = session.air_data(body, TRIAL_TIME)
	var ambient: Dictionary = Glow._environment(session, body)
	var hub: Dictionary = Propulsion.stage_air_velocity(body, air, prop)
	if state.is_empty() or not hub.get("ok", false) or not ambient.get("ok", false): return {}
	var hub_air: PackedFloat64Array = hub.velocity_body
	var rpm: float = maxf(0.0, values[0])
	var blade: Dictionary = Glow.Blade.evaluate_prepared(session.get_meta(Glow.PROPELLER_EVALUATOR_META, null),
		rpm, M.dot(hub_air, prop.axis), ambient.rho_kgm3)
	var mass_context: Dictionary = Glow._stage_mass_context(session, values)
	if not blade.get("ok", false) or not mass_context.get("ok", false): return {}
	var mass: Dictionary = mass_context.properties
	var frame: Dictionary = Glow._airframe(session, body, values, air, hub_air, rpm, blade, ambient.rho_kgm3)
	var coast: Dictionary = Glow.Source.evaluate(install.profile, 0.001,
		Glow.admission_at(install, state.air_fraction, 0.001), values[12],
		1.225 * float(ambient.engine_charge_ratio), false)
	if frame.is_empty() or not coast.get("ok", false): return {}
	var force: PackedFloat64Array = frame.external.slice(0, 3)
	var torque: PackedFloat64Array = M.sub(frame.external.slice(3, 6), M.cross(mass.cg_body_m, force))
	var omega: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var alpha: PackedFloat64Array = RB.inertia_mul(mass.inverse,
		M.sub(torque, M.cross(omega, RB.inertia_mul(mass.inertia, omega))))
	var axial: float = M.dot(prop.axis, alpha)
	var load: float = blade.torque_nm
	var inertia: float = prop.rotor_inertia
	return {rpm = values[0], demand_nm = -load - inertia * axial, friction_nm = -float(coast.shaft_torque_nm),
		prop_load_torque_nm = load, axial_acceleration_rad_s2 = axial, rotor_inertia_kg_m2 = inertia}


func _context(session: Node, native: Object) -> bool:
	return GlowAdapter.set_context(session, native, session.sim.aux, session.sim.inputs, TICK_TIME)


func _packed_equal(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	return var_to_bytes(left) == var_to_bytes(right)


func _reported(native: Object, body: PackedFloat64Array, values: PackedFloat64Array) -> Dictionary:
	var result: Dictionary = native.stage(body, values, TRIAL_TIME)
	if not result.is_empty(): return {}
	return native.stage_rejection_diagnostic()


func _run() -> void:
	var session := _session()
	if session == null:
		quit(1)
		return
	var body := PackedFloat64Array(TRIAL_BODY)
	var values := PackedFloat64Array(TRIAL_VALUES)
	var reference: Dictionary = Glow.evaluate(body, values, TRIAL_TIME, session)
	var point: Dictionary = Glow.point(session, body, values, TRIAL_TIME, true)
	var expected := _reference_detail(session, body, values)
	_check("reference stage reaches the rejected feed endpoint", reference.is_empty() and not point.get("ok", false) \
		and str(point.get("message", "")) == "Glow feed factor endpoint evaluation failed")
	_check("reference stopped rotor requires reverse torque beyond finite static friction", not expected.is_empty() \
		and expected.rpm == 0.0 and is_finite(expected.demand_nm) and is_finite(expected.friction_nm) \
		and expected.friction_nm >= 0.0 and expected.demand_nm < -expected.friction_nm)
	var healthy := values.duplicate()
	healthy[0] = 500.0
	var healthy_reference: Dictionary = Glow.evaluate(body, healthy, TRIAL_TIME, session)
	_check("moving reference control stage is accepted", not healthy_reference.is_empty())
	var direct := values.duplicate()
	direct[18] = 0.0
	var direct_reference: Dictionary = Glow.evaluate(body, direct, TRIAL_TIME, session)
	_check("source-off reference reaches the same reverse refusal", direct_reference.is_empty())
	if _failures != 0:
		session.free()
		quit(1)
		return
	print("NK3_GLOW_REJECTION_REFERENCE fixture=pass")
	var status: Dictionary = NativeStage.library_status()
	_check("canonical installed library passes receipt verification", status.get("ok", false))
	if not status.get("ok", false):
		printerr("FAIL native library: ", status.get("reason", "unknown"))
		session.free()
		quit(1)
		return
	var native: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
	_check("native class exposes both diagnostic methods", native != null \
		and native.has_method("set_stage_rejection_diagnostics") and native.has_method("stage_rejection_diagnostic"))
	if native == null or not native.has_method("set_stage_rejection_diagnostics") \
			or not native.has_method("stage_rejection_diagnostic"):
		session.free()
		quit(1)
		return
	var config: Dictionary = GlowAdapter.config_for(session)
	var prepared: Dictionary = native.prepare_stage(config)
	_check("actual native glow stage prepares", prepared.get("ok", false))
	if not prepared.get("ok", false):
		printerr("FAIL native stage prepare: ", prepared.get("error", "unknown"))
		session.free()
		quit(1)
		return
	native.reset_stage_stats(false)
	_check("disabled context installs", _context(session, native))
	var healthy_disabled: Dictionary = native.stage(body, healthy, TRIAL_TIME)
	var rejected_disabled: Dictionary = native.stage(body, values, TRIAL_TIME)
	var disabled_stats: Dictionary = native.stage_stats()
	_check("disabled diagnostics preserve accepted and refused reference results", \
		var_to_bytes(healthy_disabled) == var_to_bytes(healthy_reference) \
		and var_to_bytes(rejected_disabled) == var_to_bytes(reference) \
		and native.stage_rejection_diagnostic().is_empty())
	native.reset_stage_stats(false)
	native.set_stage_rejection_diagnostics(true)
	_check("enabling does not create a stale record", native.stage_rejection_diagnostic().is_empty())
	_check("enabled context installs", _context(session, native))
	var healthy_enabled: Dictionary = native.stage(body, healthy, TRIAL_TIME)
	_check("enabled successful stage remains byte-identical", var_to_bytes(healthy_enabled) == var_to_bytes(healthy_disabled) \
		and native.stage_rejection_diagnostic().is_empty())
	var diagnostic := _reported(native, body, values)
	var enabled_stats: Dictionary = native.stage_stats()
	_check("diagnostic mode preserves evaluator counters", disabled_stats.stage_calls == enabled_stats.stage_calls \
		and disabled_stats.context_calls == enabled_stats.context_calls)
	_check("actual refused stage reports a feed endpoint branch", diagnostic.get("code", "") == "glow_stopped_reverse_drive" \
		and diagnostic.get("origin", "") == "feed_endpoint" and diagnostic.get("feed_factor", -1.0) == 0.0)
	if not diagnostic.has_all(["body", "continuous", "stage_time", "aux", "inputs", "deflections", "tick_time",
			"brake", "throttle", "engine_running", "injected_cut", "stage_call", "context_call", "rpm", "demand_nm",
			"friction_nm", "prop_load_torque_nm", "axial_acceleration_rad_s2", "rotor_inertia_kg_m2"]):
		printerr("FAIL diagnostic payload is incomplete")
		session.free()
		quit(1)
		return
	var actual_numbers := PackedFloat64Array([diagnostic.rpm, diagnostic.demand_nm, diagnostic.friction_nm,
		diagnostic.prop_load_torque_nm, diagnostic.axial_acceleration_rad_s2, diagnostic.rotor_inertia_kg_m2])
	var expected_numbers := PackedFloat64Array([expected.rpm, expected.demand_nm, expected.friction_nm,
		expected.prop_load_torque_nm, expected.axial_acceleration_rad_s2, expected.rotor_inertia_kg_m2])
	_check("diagnostic scalars equal the independent reference equations", _packed_equal(actual_numbers, expected_numbers))
	_check("diagnostic records exact rejected trial and consumed context", _packed_equal(diagnostic.body, body) \
		and _packed_equal(diagnostic.continuous, values) and diagnostic.stage_time == TRIAL_TIME \
		and _packed_equal(diagnostic.aux, session.sim.aux) and _packed_equal(diagnostic.inputs, session.sim.inputs) \
		and diagnostic.tick_time == TICK_TIME and not diagnostic.engine_running and not diagnostic.injected_cut \
		and diagnostic.stage_call == enabled_stats.stage_calls and diagnostic.context_call == enabled_stats.context_calls)
	var d: Dictionary = session._deflections(session.sim.aux)
	var expected_deflections := PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)])
	_check("diagnostic includes actual deflections, brake and throttle", _packed_equal(diagnostic.deflections, expected_deflections) \
		and diagnostic.brake == 0.0 and diagnostic.throttle == session.propulsion_throttle())
	var changed_body: PackedFloat64Array = diagnostic.body
	changed_body[0] += 1.0
	diagnostic.body = changed_body
	var changed_inputs: PackedFloat64Array = diagnostic.inputs
	changed_inputs[0] += 1.0
	diagnostic.inputs = changed_inputs
	diagnostic.code = "changed"
	var detached: Dictionary = native.stage_rejection_diagnostic()
	_check("getter returns detached data", detached.get("code", "") == "glow_stopped_reverse_drive" \
		and _packed_equal(detached.body, body) and _packed_equal(detached.inputs, session.sim.inputs))
	native.stage(body, healthy, TRIAL_TIME)
	_check("a subsequent successful evaluation clears the refusal", native.stage_rejection_diagnostic().is_empty())
	_check("refusal can be observed again", not _reported(native, body, values).is_empty())
	native.stage(body.slice(0, 12), values, TRIAL_TIME)
	_check("malformed body evaluation clears the refusal", native.stage_rejection_diagnostic().is_empty())
	_check("refusal before nonfinite check", not _reported(native, body, values).is_empty())
	var nonfinite := values.duplicate()
	nonfinite[2] = NAN
	native.stage(body, nonfinite, TRIAL_TIME)
	_check("nonfinite continuous input cannot inherit a reason", native.stage_rejection_diagnostic().is_empty())
	_check("refusal before malformed continuous check", not _reported(native, body, values).is_empty())
	var shortened := values.duplicate()
	shortened.resize(shortened.size() - 1)
	native.stage(body, shortened, TRIAL_TIME)
	_check("malformed continuous input cannot inherit a reason", native.stage_rejection_diagnostic().is_empty())
	_check("refusal before nonfinite time check", not _reported(native, body, values).is_empty())
	native.stage(body, values, NAN)
	_check("nonfinite stage time cannot inherit a reason", native.stage_rejection_diagnostic().is_empty())
	_check("refusal before invalid tick context", not _reported(native, body, values).is_empty())
	_check("invalid tick context clears the refusal", not native.set_tick_context(PackedFloat64Array(), session.sim.inputs,
		expected_deflections, TICK_TIME) and native.stage_rejection_diagnostic().is_empty())
	_check("valid context restored", _context(session, native))
	_check("refusal before unrelated helicopter handoff", not _reported(native, body, values).is_empty())
	_check("invalid helicopter handoff clears the refusal", not native.set_heli_tick_context({}) \
		and native.stage_rejection_diagnostic().is_empty())
	_check("glow context restored after helicopter handoff", _context(session, native))
	var nonfinite_inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	nonfinite_inputs[0] = NAN
	var nonfinite_context: bool = native.set_tick_context(session.sim.aux, nonfinite_inputs, expected_deflections, TICK_TIME) \
		and native.set_glow_context(session.propulsion_throttle(), session.engine_running, session.failure_power_cut_active())
	_check("unrelated nonfinite context is accepted only for the negative control", nonfinite_context)
	native.stage(body, values, TRIAL_TIME)
	_check("nonfinite context cannot be classified as a finite refusal", native.stage_rejection_diagnostic().is_empty())
	_check("finite context restored", _context(session, native))
	var signed_zero := values.duplicate()
	signed_zero[0] = -0.0
	var signed_zero_diagnostic := _reported(native, body, signed_zero)
	_check("negative zero is a stopped rotor and keeps its float64 sign", \
		signed_zero_diagnostic.get("code", "") == "glow_stopped_reverse_drive" \
		and _packed_equal(PackedFloat64Array([signed_zero_diagnostic.get("rpm", 1.0)]), PackedFloat64Array([signed_zero[0]])) \
		and not _packed_equal(PackedFloat64Array([signed_zero[0]]), PackedFloat64Array([0.0])))
	var moving_left := values.duplicate()
	moving_left[0] = -0.001
	var left_reference: Dictionary = Glow.evaluate(body, moving_left, TRIAL_TIME, session)
	var left_native: Dictionary = native.stage(body, moving_left, TRIAL_TIME)
	_check("negative trial RPM is not labelled as stopped reverse drive", \
		var_to_bytes(left_native) == var_to_bytes(left_reference) and native.stage_rejection_diagnostic().is_empty())
	var direct_diagnostic := _reported(native, body, direct)
	_check("source-off direct refusal is classified only at its actual coupling", direct_reference.is_empty() \
		and direct_diagnostic.get("code", "") == "glow_stopped_reverse_drive" \
		and direct_diagnostic.get("origin", "") == "direct" and not direct_diagnostic.has("feed_factor"))
	native.reset_stage_stats(false)
	_check("resetting statistics clears the refusal", native.stage_rejection_diagnostic().is_empty())
	_check("refusal before prepare guard", not _reported(native, body, values).is_empty())
	var refused: Dictionary = native.prepare_stage({})
	_check("failed reprepare clears stale diagnostics", not refused.get("ok", false) \
		and native.stage_rejection_diagnostic().is_empty())
	_check("original stage prepares again", native.prepare_stage(config).get("ok", false) and _context(session, native))
	_check("refusal before disabling diagnostics", not _reported(native, body, values).is_empty())
	native.set_stage_rejection_diagnostics(false)
	_check("disabling clears diagnostics and leaves refusal unchanged", native.stage_rejection_diagnostic().is_empty() \
		and var_to_bytes(native.stage(body, values, TRIAL_TIME)) == var_to_bytes(reference) \
		and native.stage_rejection_diagnostic().is_empty())
	session.free()
	print("NK3_GLOW_REJECTION checks=%d failures=%d" % [_checks, _failures])
	if _failures == 0:
		print("NK3_GLOW_REJECTION_NATIVE verdict=pass")
	quit(0 if _failures == 0 else 1)
