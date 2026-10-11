# G3b: accepted-state observer, target queue and whole-flight noninterference.
extends SceneTree

const Sound := preload("res://render/engine_sound.gd")
const Flight := preload("res://sim/flight_session.gd")
const MODELS := ["res://data/aircraft/jensen_ugly_stik_60.json",
	"res://data/aircraft/gp_extra_300s_60.json", "res://data/aircraft/p51d_mustang_120.json",
	"res://data/aircraft/sebart_avanti_s_a200.json"]
var _count := 0
var _failures := 0


func _check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_run.call_deferred()


func _flight(path: String) -> Node:
	var flight := Flight.new()
	flight.setup(path)
	root.add_child(flight)
	flight.input_enabled = false
	flight.set_physics_process(false)
	flight.sim.set_physics_process(false)
	flight.reset()
	return flight


func _run() -> void:
	# An outstanding playback can outlive its node while the mixer finishes a fade.
	# This is a lifetime oracle, not a check against a production helper's return value.
	var source_parent := Node3D.new()
	root.add_child(source_parent)
	var source_player: AudioStreamPlayer3D = Sound.create(source_parent)
	var source_weak: WeakRef = weakref(source_player.stream)
	var retained_playback := source_player.get_stream_playback()
	source_parent.free()
	_check("playback retains its source after node removal", source_weak.get_ref() != null)
	retained_playback = null
	_check("source releases without a reference cycle", source_weak.get_ref() == null)
	for path in MODELS:
		for fps in [30, 60, 144]:
			var quiet := _flight(path)
			var audible := _flight(path)
			_check("valid fleet start", quiet.start.ok and audible.start.ok)
			var parent := Node3D.new()
			root.add_child(parent)
			var player: AudioStreamPlayer3D = Sound.create(parent, audible.sim, audible.aircraft.model.propulsion.max_rpm)
			audible.reset()
			var restore_point: Dictionary = audible.sim.checkpoint()
			var snapshot_ok: bool = player.snapshot_tick == 0 and player.snapshot_rpm == audible.sim.aux[0]
			var state_ok := true
			for tick in 480:
				# A shared deterministic stick/throttle tape, sampled at actual physics ticks.
				for flight in [quiet, audible]:
					flight.commands = {"roll": 0.1 if tick >= 120 and tick < 180 else 0.0,
						"pitch": 0.04 if tick >= 240 and tick < 300 else 0.0, "yaw": 0.0,
						"throttle": 0.8 if tick >= 60 and tick < 240 else 0.4}
					flight.sim.inputs = flight._inputs()
					flight.sim.step()
				snapshot_ok = snapshot_ok and player.snapshot_tick == audible.sim.tick \
					and player.snapshot_time == audible.sim.time() and player.snapshot_rpm == audible.sim.aux[0]
				if int((tick + 1) * fps / 240.0) != int(tick * fps / 240.0):
					Sound.update(player, 0.0, -1.0, audible.aircraft.model.propulsion.max_rpm)
				state_ok = state_ok and var_to_bytes(quiet.sim.checkpoint()) == var_to_bytes(audible.sim.checkpoint())
			_check("%s/%d exact full simulation state with audio" % [path.get_file(), fps], state_ok)
			_check("%s/%d observes every accepted endpoint" % [path.get_file(), fps], snapshot_ok)
			_check("queue remains within device-aware target", player.queued_frames <= player.target_frames)
			_check("observer uses detached RPM rather than caller argument", player.voice.frequency > 0.0)

			var original_playback := player.get_stream_playback()
			var saved: Dictionary = restore_point
			_check("restore fixture actually rewinds the flight", saved.tick < audible.sim.tick)
			audible.sim.set_paused(true)
			player.stream_paused = true
			var held: float = player.voice.phase
			Sound.update(player, 0.0, 9999.0, 20000.0)
			_check("pause holds oscillator", player.voice.phase == held)
			# Restoring while already paused emits no stepped event. First resumed refill must read
			# the restored endpoint and discard both old queued sound and oscillator history.
			_check("restore accepted", audible.sim.restore_checkpoint(saved))
			audible.sim.set_paused(false)
			player.stream_paused = false
			Sound.update(player, 0.0, -1.0, audible.aircraft.model.propulsion.max_rpm)
			_check("resume replaces old playback queue", player.get_stream_playback() != original_playback)
			_check("resume samples restored RPM", player.snapshot_rpm == saved.aux[0])
			_check("resume samples restored tick and time", player.snapshot_tick == saved.tick and player.snapshot_time == saved.tick * saved.dt)
			Sound.restart(player)
			audible.reset()
			Sound.update(player, 0.0, -1.0, audible.aircraft.model.propulsion.max_rpm)
			_check("restart resets accepted endpoint", player.snapshot_tick == 0 and player.snapshot_rpm == audible.sim.aux[0])
			parent.free()
			quiet.free()
			audible.free()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
