# HELI-25 render audit: accepted-tick rotor phase and endpoint diagnostics.
# Run: Godot --headless --path app --script res://tests/test_heli_render_audit.gd
extends SceneTree

const Session := preload("res://sim/helicopter_flight_session.gd")
const FlightMain := preload("res://helicopter_main.gd")
const Model := preload("res://aircraft/hx700_model.gd")
const RotorVisual := preload("res://render/rotor/heli_rotor_visual.gd")
const Flight := preload("res://physics/rotorcraft/flight_dynamics.gd")
const Math3D := preload("res://physics/math3d.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Recorder := preload("res://sim/rotorcraft_recorder.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session: Node = Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	root.add_child(session)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var prepared: bool = session.setup() and loaded.ok and session.set_field(loaded.field)
	_check("session preset and field load for render telemetry", prepared)
	if not prepared:
		_finish()
		return

	var model_a: Dictionary = Model.build()
	var model_b: Dictionary = Model.build()
	_check("two independent visual source instances build", not model_a.is_empty() and not model_b.is_empty())
	if model_a.is_empty() or model_b.is_empty():
		_finish()
		return
	root.add_child(model_a.root)
	root.add_child(model_b.root)
	var visual_a = RotorVisual.attach(model_a, root)
	var visual_b = RotorVisual.attach(model_b, root)
	_check("two rotor visual adapters attach", visual_a != null and visual_b != null)
	if visual_a == null or visual_b == null:
		_finish()
		return

	var live = FlightMain.new()
	var capture = FlightMain.new()
	live.session = session
	live.recorder = Recorder.new(session.sim)
	live._rotors = visual_a
	capture.session = session
	capture.recorder = Recorder.new(session.sim)
	capture._rotors = visual_b
	session.resetting.connect(live._on_session_resetting)
	session.resetting.connect(capture._on_session_resetting)
	session.sim.stepped.connect(live._on_sim_stepped)
	session.sim.stepped.connect(capture._on_sim_stepped)
	_check("hover reset seeds accepted-tick render telemetry", session.reset()
		and live._rotor_phase_tick == 0 and capture._rotor_phase_tick == 0)
	if not session.is_flyable():
		_finish()
		return
	var checkpoint: Dictionary = session.checkpoint()

	_test_envelope_flags(session)
	_test_variable_rpm_and_render_rates(session, live, capture, model_a, model_b, visual_a, visual_b)
	_test_zero_drive_and_pause(session, live, capture, visual_a)
	_test_reset_and_checkpoint_rebase(session, live, capture, checkpoint)
	_check("accepted flight advances to nonzero authoritative rotor phase",session.reset())
	for tick: int in 3: session.sim.step()
	var spinning_checkpoint: Dictionary=session.checkpoint()
	for tick: int in 2: session.sim.step()
	_check("nonzero rotor phase restores from checkpoint",session.restore_checkpoint(spinning_checkpoint).ok)
	live._ensure_rotor_phase_current()
	_check("renderer retains saved phase instead of resetting it",live._rotor_phase_current.to_byte_array()==spinning_checkpoint.shaft_phase.to_byte_array() and live._rotor_phase_current[0]!=0.0)
	_test_instance_isolation(visual_a, visual_b, model_a, model_b)
	var legacy_state := {"omega_rad_s":2.0,"tail_omega_rad_s":3.0}
	visual_a.update(legacy_state,0.1)
	var legacy_before: Basis = model_a.main_rotor_pivot.basis
	visual_a.update(legacy_state,0.1)
	_check("legacy delta-time API continues accumulating phase", not legacy_before.is_equal_approx(model_a.main_rotor_pivot.basis))

	live.recorder.detach()
	capture.recorder.detach()
	live.free()
	capture.free()
	visual_a.queue_free()
	visual_b.queue_free()
	model_a.root.queue_free()
	model_b.root.queue_free()
	session.queue_free()
	await process_frame
	_finish()


func _test_variable_rpm_and_render_rates(session: Node, live: Variant, capture: Variant,
		model_a: Dictionary, model_b: Dictionary, visual_a: Variant, visual_b: Variant) -> void:
	var dt: float = session.sim.dt()
	_emit_tick(session, 0, 30.0)
	for tick: int in range(1, 241):
		var omega: float = 30.0 + 30.0 * float(tick) / 240.0
		_emit_tick(session, tick, omega)
	var context: Dictionary = session.aircraft.context
	var expected_main: float = 45.0 * float(context.main_model.rotation_sense)
	var expected_tail: float = 45.0 * float(context.tail_model.tail_to_main_speed_ratio) \
		* float(context.tail_model.rotation_sense)
	_check("variable RPM integrates the fixed-tick trapezoid exactly",
		absf(live._rotor_phase_current[0] - expected_main) < 1e-11
		and absf(live._rotor_phase_current[1] - expected_tail) < 1e-11,
		"main %.12f / %.12f; tail %.12f / %.12f" % [live._rotor_phase_current[0], expected_main,
			live._rotor_phase_current[1], expected_tail])
	var phase_before_reads: PackedFloat64Array = live._rotor_phase_current.duplicate()
	for rate: int in [30, 60, 144]:
		for frame: int in rate:
			var fraction: float = float((frame % 4) + 1) / 4.0
			var phase: PackedFloat64Array = live._rotor_phase_at_fraction(fraction)
			visual_a.update(live._rotor_state, phase[0], phase[1])
		_check("%d Hz rendering reads phase without accumulating wall-clock rotation" % rate,
			live._rotor_phase_current.to_byte_array() == phase_before_reads.to_byte_array())
	_check("capture and live presentation agree at the same accepted tick",
		capture._rotor_phase_current.to_byte_array() == live._rotor_phase_current.to_byte_array()
		and capture._rotor_phase_tick == live._rotor_phase_tick)
	var previous: Dictionary=live._rotor_state_previous
	var current: Dictionary=live._rotor_state
	var half_pose: Dictionary=live._rotor_state_at_fraction(0.5)
	_check("rotor telemetry interpolates with body and shaft phase", half_pose.omega_rad_s ==
		float(previous.omega_rad_s)+(float(current.omega_rad_s)-float(previous.omega_rad_s))*0.5)
	var endpoint_phase: PackedFloat64Array = live._rotor_phase_at_fraction(1.0)
	var halfway_phase: PackedFloat64Array = live._rotor_phase_at_fraction(0.5)
	visual_a.update(live._rotor_state, endpoint_phase[0], endpoint_phase[1])
	visual_b.update(capture._rotor_state, endpoint_phase[0], endpoint_phase[1])
	_check("captured rotor pose uses the accepted endpoint phase",
		((model_a.main_rotor_pivot as Node3D).basis.x - (model_b.main_rotor_pivot as Node3D).basis.x).length() < 1e-6
		and absf(endpoint_phase[0] - halfway_phase[0]) <= 61.0 * dt / 2.0 + 1e-12)


func _test_zero_drive_and_pause(session: Node, live: Variant, capture: Variant, visual: Variant) -> void:
	_emit_tick(session, 0, 60.0)
	for tick: int in range(1, 241):
		_emit_tick(session, tick, 60.0 * (1.0 - float(tick) / 240.0))
	var expected: float = 30.0 * float(session.aircraft.context.main_model.rotation_sense)
	_check("RPM falling to zero retains the integrated spin history",
		absf(live._rotor_phase_current[0] - expected) < 1e-11
		and float(live._rotor_state.omega_rad_s) == 0.0)
	var phase_before_pause: PackedFloat64Array = live._rotor_phase_current.duplicate()
	session.sim.set_paused(true)
	for frame: int in 144:
		var phase: PackedFloat64Array = live._rotor_phase_at_fraction(float(frame % 4) / 3.0)
		visual.update(live._rotor_state, phase[0], phase[1])
	_check("paused rendering leaves rotor phase fixed",
		live._rotor_phase_current.to_byte_array() == phase_before_pause.to_byte_array()
		and capture._rotor_phase_current.to_byte_array() == phase_before_pause.to_byte_array())
	var blur: Node = visual.get_node("propeller_blur")
	blur.update(0.0)
	var originals: Array[MeshInstance3D] = []
	for surface: Dictionary in blur.measured.surfaces:
		var source: MeshInstance3D = surface.node
		if not originals.has(source):
			originals.append(source)
	_check("zero-drive crossfade returns to authored main blades",
		originals.all(func(node: MeshInstance3D) -> bool: return node.visible)
		and not (blur.get_node("analytic_rotor_disc") as MeshInstance3D).visible)


func _test_reset_and_checkpoint_rebase(session: Node, live: Variant, capture: Variant, checkpoint: Dictionary) -> void:
	_check("ordinary reset rebases presentation phase to neutral", session.reset()
		and live._rotor_phase_tick == 0 and capture._rotor_phase_tick == 0
		and live._rotor_phase_current[0] == 0.0 and live._rotor_phase_current[1] == 0.0)
	_emit_tick(session, 0, 0.0)
	_emit_tick(session, 1, 20.0)
	_check("first tick after reset starts from the new accepted RPM",
		absf(live._rotor_phase_current[0] - 10.0 * session.sim.dt() * float(session.aircraft.context.main_model.rotation_sense)) < 1e-11)
	_check("compatible checkpoint restores after render-only phase advances", session.restore_checkpoint(checkpoint).ok)
	live._ensure_rotor_phase_current()
	capture._ensure_rotor_phase_current()
	var restored_speed: float = float(session.sim.continuous[0])
	_check("checkpoint restore rebases display phase and seeds saved shaft speed",
		live._rotor_phase_tick == session.sim.tick and capture._rotor_phase_tick == session.sim.tick
		and live._rotor_phase_current[0] == 0.0 and live._rotor_phase_current[1] == 0.0
		and is_equal_approx(live._rotor_omega_previous[0], restored_speed * float(session.aircraft.context.main_model.rotation_sense)))


func _test_envelope_flags(session: Node) -> void:
	var context: Dictionary = session.aircraft.context
	var body: PackedFloat64Array = session.sim.state.duplicate()
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	var wind: PackedFloat64Array = PackedFloat64Array([1.1, -0.7, 0.2])
	var attitude: PackedFloat64Array = Math3D.q_from_euler(0.46, -0.10, 0.08)
	for index: int in 4:
		body[6 + index] = attitude[index]
	body[3] = 2.2
	body[4] = 0.4
	body[5] = -0.2
	body[10] = 0.03
	body[11] = -0.02
	body[12] = 0.01
	continuous[0] = float(context.main_model.omega_nominal_rad_s)
	continuous[1] = 0.04
	continuous[2] = -0.03
	_check("cached envelope flags match Flight.evaluate under rotated wind and body rates",
		_flags_match_flight(body, continuous, context, wind, session))
	var threshold_state: PackedFloat64Array = body.duplicate()
	threshold_state[6] = 1.0
	threshold_state[7] = 0.0
	threshold_state[8] = 0.0
	threshold_state[9] = 0.0
	threshold_state[3] = 0.15 * (continuous[0] * float(context.main_model.rotor_radius_m))
	threshold_state[4] = 0.0
	threshold_state[5] = 0.0
	threshold_state[10] = 0.0
	threshold_state[11] = 0.0
	threshold_state[12] = 0.0
	_check("strict advance-ratio equality boundary matches Flight.evaluate",
		_flags_match_flight(threshold_state, continuous, context, PackedFloat64Array([0.0, 0.0, 0.0]), session)
		and not FlightMain.main_rotor_envelope_flags(threshold_state, continuous, context,
			PackedFloat64Array([0.0, 0.0, 0.0])).within_identified_advance_ratio)
	var parked: PackedFloat64Array = continuous.duplicate()
	var calm_body: PackedFloat64Array=threshold_state.duplicate()
	calm_body[3]=0.0
	for fraction: float in [.03,.06,.09]:
		var startup: PackedFloat64Array=continuous.duplicate()
		startup[0]=fraction*context.main_model.omega_nominal_rad_s
		_check("startup envelope metadata matches flight at %.2f nominal RPM"%fraction,
			_flags_match_flight(calm_body,startup,context,PackedFloat64Array([0,0,0]),session)
			and FlightMain.main_rotor_envelope_flags(calm_body,startup,context,PackedFloat64Array([0,0,0])).within_identified_advance_ratio==(fraction>=.08))
	parked[0] = 0.0
	_check("zero-RPM presentation keeps the advance-ratio warning false like Flight.evaluate",
		_flags_match_flight(body, parked, context, wind, session)
		and not FlightMain.main_rotor_envelope_flags(body, parked, context, wind).within_identified_advance_ratio)
	var flap_boundary: PackedFloat64Array = continuous.duplicate()
	flap_boundary[1] = PI / 18.0
	flap_boundary[2] = 0.0
	_check("strict small-flap boundary behavior matches Flight.evaluate",
		_flags_match_flight(body, flap_boundary, context, wind, session)
		and not FlightMain.main_rotor_envelope_flags(body, flap_boundary, context, wind).within_small_flap_angle_range)


func _flags_match_flight(body: PackedFloat64Array, continuous: PackedFloat64Array,
		context: Dictionary, wind: PackedFloat64Array, session: Node) -> bool:
	var state: PackedFloat64Array = body.duplicate()
	state.append_array(continuous)
	var inputs: PackedFloat64Array = session.sim.inputs
	var sticks: PackedFloat64Array = PackedFloat64Array([-inputs[1], inputs[0], inputs[2], 2.0 * inputs[3] - 1.0])
	var reference: Dictionary = Flight.evaluate(state, context, sticks, session.flight_mode,
		session.trainer_enabled, session.zero_drive_hold, wind, false, PackedFloat64Array(),
		session._trim, session._height_over_radius(state))
	if not reference.get("ok", false):
		return false
	var expected: Dictionary = reference.aero.main_rotor
	var actual: Dictionary = FlightMain.main_rotor_envelope_flags(body, continuous, context, wind)
	return actual.within_identified_advance_ratio == expected.within_identified_advance_ratio \
		and actual.within_small_flap_angle_range == expected.within_small_flap_angle_range


func _test_instance_isolation(visual_a: Variant, visual_b: Variant, model_a: Dictionary, model_b: Dictionary) -> void:
	var blur_a: Node = visual_a.get_node("propeller_blur")
	var blur_b: Node = visual_b.get_node("propeller_blur")
	var source_material: BaseMaterial3D = blur_a.measured.surfaces[0].material as BaseMaterial3D
	var material_a: BaseMaterial3D = blur_a._fade_materials[0]
	var material_b: BaseMaterial3D = blur_b._fade_materials[0]
	_check("rotor instances own their fade materials and disc meshes",
		material_a != source_material and material_b != source_material and material_a != material_b
		and (blur_a.get_node("analytic_rotor_disc") as MeshInstance3D).mesh != (blur_b.get_node("analytic_rotor_disc") as MeshInstance3D).mesh)
	var state: Dictionary = {"omega_rad_s": 90.0, "tail_omega_rad_s": 420.0, "a1": 0.0, "b1": 0.0, "collective": 0.0}
	visual_a.update(state, 1.25, 4.5)
	visual_b.update(state, 0.0, 0.0)
	_check("updating one aircraft leaves the other rotor pose unchanged",
		((model_b.main_rotor_pivot as Node3D).basis.x - model_b.main_rotor_rest.x).length() < 1e-6
		and ((model_b.tail_rotor_pivot as Node3D).basis.x - model_b.tail_rotor_rest.x).length() < 1e-6)
	_check("rotor presentation does not mutate source blade materials",
		float(source_material.albedo_color.a) == 1.0)


func _emit_tick(session: Node, tick: int, omega_rad_s: float) -> void:
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	continuous[0] = omega_rad_s
	session.sim.continuous = continuous
	session.sim.stepped.emit(tick, float(tick) * session.sim.dt(), session.sim.state,
		session.sim.last_loads, session.sim.inputs, session.sim.aux)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
