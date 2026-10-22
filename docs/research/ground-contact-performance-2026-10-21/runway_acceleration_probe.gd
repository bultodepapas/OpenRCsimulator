# Deterministic runway acceleration diagnostic. This is a test-only probe, not a calibration or realism claim.
# Run from the repository root in PowerShell:
# wsl.exe -e bash -lc 'cd /mnt/c/DEVELOPMENT/OpenRCsimulator && app/.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --audio-driver Dummy --script /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/ground-contact-performance-2026-10-21/runway_acceleration_probe.gd'
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RATE := 240
const SAMPLE_TICKS := [0, 120, 240, 480]
const AIRCRAFT := [
	{"id": "gp-extra-300s-60", "path": "res://data/aircraft/gp_extra_300s_60.json"},
	{"id": "p51d-mustang-120", "path": "res://data/aircraft/p51d_mustang_120.json"},
]

var _cases: Array[Dictionary] = []
var _errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.physics_ticks_per_second = RATE
	var loaded := FieldLoader.load_from()
	if not loaded.get("ok", false):
		_errors.append("default field failed: " + str(loaded.get("errors", [])))
		_finish()
		return
	for aircraft: Dictionary in AIRCRAFT:
		for profile in ["immediate", "ramp2s"]:
			_run_case(aircraft, str(profile), loaded.field)
	_finish()

func _run_case(aircraft: Dictionary, profile: String, field: Dictionary) -> void:
	var session := Flight.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup(str(aircraft.path), str(aircraft.id))
	if not session.is_flyable() or not session.set_field(field):
		_errors.append("setup failed for %s: %s %s" % [aircraft.id, session.start_error, session.surface_error])
		session.free()
		return
	session.start_choice = Flight.START_RUNWAY
	session.reset()
	if not session.is_flyable() or not session.start_error.is_empty():
		_errors.append("runway setup failed for %s: %s" % [aircraft.id, session.start_error])
		session.free()
		return
	if session.glow_is_active() and not session.glow_start():
		_errors.append("glow start failed for %s" % aircraft.id)
		session.free()
		return
	var dt: float = session.sim.dt()
	var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	inputs[0] = 0.0
	inputs[1] = 0.0
	inputs[2] = 0.0
	inputs[3] = 1.0 if profile == "immediate" else 0.0
	session.sim.inputs = inputs
	var samples: Array[Dictionary] = []
	samples.append(_sample(session, 0, dt))
	for tick in range(1, RATE * 2 + 1):
		if profile == "ramp2s":
			inputs = session.sim.inputs.duplicate()
			inputs[3] = float(tick) / float(RATE * 2)
			session.sim.inputs = inputs
		session.sim.step()
		session._physics_process(dt)
		if tick in SAMPLE_TICKS:
			samples.append(_sample(session, tick, dt))
		if not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
			_errors.append("%s %s stopped at tick %d: fault=%s crash=%s" % [aircraft.id, profile, tick,
				session.sim.fault_reason, str(session.crash)])
			break
	_cases.append({
		"aircraft_id": str(aircraft.id),
		"throttle_profile": profile,
		"engine_running": session.engine_running,
		"samples": samples,
		"complete_2s": session.sim.tick == RATE * 2 and session.sim.fault_reason.is_empty() and session.crash.is_empty(),
	})
	session.free()

func _sample(session: Node, tick: int, dt: float) -> Dictionary:
	var state: PackedFloat64Array = session.sim.state
	return {
		"tick": tick,
		"time_s": float(tick) * dt,
		"throttle_command": float(session.sim.inputs[3]),
		"rpm": float(session.sim.aux[Flight.AUX_RPM]),
		"speed_mps": _speed(state),
		"forward_body_mps": float(state[RB.VEL]),
		"stuck_wheels": Array(_anchor_flags(session)),
		"fault": session.sim.fault_reason,
		"crash": str(session.crash.get("reason", "")),
	}

func _anchor_flags(session: Node) -> PackedFloat64Array:
	var flags := PackedFloat64Array()
	for index in session.anchor_count():
		flags.append(session.sim.aux[Flight.AUX_ANCHORS + index * Ground.ANCHOR_STRIDE + 2])
	return flags

func _speed(state: PackedFloat64Array) -> float:
	return sqrt(state[RB.VEL] * state[RB.VEL] + state[RB.VEL + 1] * state[RB.VEL + 1] + state[RB.VEL + 2] * state[RB.VEL + 2])

func _finish() -> void:
	var report := {
		"format": "openrc-runway-acceleration-probe v1",
		"tick_rate_hz": RATE,
		"field": "default",
		"controls": "zero roll/pitch/yaw",
		"engine_start": "Extra glow_start() before stepping; P-51 runway-start engine state",
		"ramp_definition": "throttle command increases linearly from 0 to 1 over 480 ticks (2 simulated seconds)",
		"cases": _cases,
		"errors": _errors,
	}
	print("RUNWAY_ACCELERATION_PROBE_JSON " + JSON.stringify(report))
	quit(1 if not _errors.is_empty() else 0)
