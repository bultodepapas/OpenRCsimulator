## AFC-03-R2: real Main restore must never rebuild or resume a removed fleet.
extends SceneTree

const Main := preload("res://main.gd")
const Config := preload("res://ai/companions/config.gd")
const Profiles := preload("res://ai/companions/profile_loader.gd")
const SceneryDamage := preload("res://sim/scenery_damage.gd")

class TestFlight extends Main:
	func _user_args() -> Dictionary:
		return {"quick-flight": true, "start": "airborne", "soundscape": "off", "physics-backend": "gdscript_reference"}

var _checks := 0
var _failures := 0

func _initialize() -> void:
	Profiles.accept_current_solver_for_tests()
	_run.call_deferred()

func _check(label: String, valid: bool) -> void:
	_checks += 1
	if not valid:
		_failures += 1
		printerr("FAIL ", label)

func _frames() -> void:
	await process_frame
	await process_frame

func _restored(flight: Node, tick: int) -> bool:
	return flight.companion_status().active == 0 and flight.session.sim.tick == tick \
		and flight.session.sim.paused and not flight.session.input_enabled \
		and flight.session.pause_reason == flight.session.CHECKPOINT_RESTORED_REASON \
		and not flight._companions_reset_pending and not flight.session.holds.has("companions-reset")

func _run() -> void:
	var flight := TestFlight.new()
	flight.interactive_start = true
	flight.companion_config = Config.defaults()
	flight.companion_config.enabled = true
	flight.companion_config.seed = 20261020
	root.add_child(flight)
	flight.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	_check("production Main admits a real companion", flight.companion_status().active == 1)
	flight.remove_companions_now()
	var saved: Dictionary = flight.checkpoint()
	_check("Remove allows a real tick-zero paired checkpoint", not saved.is_empty()
		and saved.physics.simulation.tick == 0 and flight.companion_config.enabled)
	if saved.is_empty():
		_close(flight)
		_finish()
		return
	var manager_id: int = flight.companions.get_instance_id()
	_check("tick-zero player checkpoint restores", flight.restore_checkpoint(saved).ok)
	await _frames()
	_check("restore preserves empty roster and recorded-input pause", _restored(flight, 0))
	_check("restore does not replace the removed manager", flight.companions.get_instance_id() == manager_id)
	_check("restore does not manufacture a restart refusal", not flight.companion_status().has("error")
		or str(flight.companion_status().error).is_empty())
	if OS.get_cmdline_user_args().has("--baseline"):
		_close(flight)
		_finish()
		return
	# A queued successful start may be superseded by an immediate tick-zero restore.
	flight.remove_companions_now()
	flight.session.reset()
	var queued: Dictionary = flight.session.last_transition()
	_check("accepted restart queues companion work", flight._companions_reset_pending)
	_check("restore supersedes the queued restart", flight.restore_checkpoint(saved).ok)
	flight.call("_restart_companions", int(queued.generation), flight.session.get_instance_id())
	await _frames()
	_check("stale start callback cannot rebuild or resume restore", _restored(flight, 0))
	# A nonzero restore has exactly the same lifecycle semantics.
	flight.session.sim.set_paused(false)
	for _tick in 24:
		flight.session.sim.step()
	flight.session.sim.set_paused(true)
	var later: Dictionary = flight.checkpoint()
	_check("nonzero checkpoint fixture saves", not later.is_empty() and later.physics.simulation.tick == 24)
	_check("nonzero player checkpoint restores", flight.restore_checkpoint(later).ok)
	await _frames()
	_check("nonzero restore remains paused without a restart error", _restored(flight, 24)
		and (not flight.companion_status().has("error") or str(flight.companion_status().error).is_empty()))
	# Two accepted restarts coalesce around the latest generation and hold.
	flight.session.reset()
	var first: Dictionary = flight.session.last_transition()
	var malformed: Dictionary = saved.duplicate(true)
	malformed.payload_sha256 = "invalid"
	_check("rejected restore does not invalidate accepted start work", not flight.restore_checkpoint(malformed).ok
		and flight._companions_reset_pending and flight.session.last_transition() == first)
	flight.session.reset()
	var second: Dictionary = flight.session.last_transition()
	flight.call("_restart_companions", int(first.generation), flight.session.get_instance_id())
	_check("stale start cannot release the latest restart hold", flight._companions_reset_pending
		and flight.session.holds.has("companions-reset") and flight.session.sim.paused)
	flight.call("_restart_companions", int(second.generation), flight.session.get_instance_id() + 1)
	_check("another session identity cannot finish this restart", flight._companions_reset_pending
		and flight.session.holds.has("companions-reset"))
	await _frames()
	_check("latest restart rebuilds exactly one live roster", flight.companion_status().active == 1
		and not flight._companions_reset_pending and not flight.session.holds.has("companions-reset")
		and not flight.session.sim.paused and second.generation > first.generation)
	# Debug rewind bypasses Main's facade and restores the player Session directly.
	var direct: Dictionary = flight.session.checkpoint()
	var capture: String = ProjectSettings.globalize_path("res://../tmp/afc-r10-capture-%d" % Time.get_ticks_usec())
	_check("direct restore capture starts at common tick zero", flight.companions.start_recording(capture).ok)
	for _tick in 24:
		flight.session.sim.step()
	_check("direct restore fixture advances both clocks", flight.session.sim.tick == 24
		and flight.companions.agents[0].session.sim.tick == 24)
	_check("paired facade still refuses a live roster", not flight.restore_checkpoint(saved).ok)
	_check("direct Session restore is accepted", flight.session.restore_checkpoint(direct))
	await _frames()
	_check("direct restore removes the old fleet and preserves replay pause", _restored(flight, 0))
	var capture_status: Dictionary = flight.companions.recording_status()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(capture.path_join("summary.json")))
	_check("direct restore closes fleet capture at its old common tick", capture_status.complete
		and manifest is Dictionary and manifest.complete and manifest.final_tick == 24)
	# A restore from inside an agent's stepped observer must not free its stack.
	flight.session.reset()
	await _frames()
	var reentrant: Dictionary = flight.session.checkpoint()
	var reentrant_capture: String = capture + "-reentrant"
	_check("reentrant restore capture starts", flight.companions.start_recording(reentrant_capture).ok)
	var active_agent: Node = flight.companions.agents[0]
	var retired: WeakRef = weakref(active_agent)
	var restored_inside := [false]
	active_agent.session.sim.stepped.connect(func(_tick: int, _time: float, _state: PackedFloat64Array,
			_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
		restored_inside[0] = flight.session.restore_checkpoint(reentrant), CONNECT_ONE_SHOT)
	flight.session.sim.step()
	_check("restore during an agent tick removes the roster safely", restored_inside[0]
		and flight.companion_status().active == 0 and flight.session.sim.tick == 0
		and not flight.companions._advancing)
	await _frames()
	_check("retired active agent is disposed after its stack unwinds", retired.get_ref() == null)
	_check("interrupted common tick cannot claim a complete capture", not flight.companions.recording_status().active
		and not flight.companions.recording_status().complete)
	# Damage mirroring also notifies listeners synchronously while advancing.
	flight.session.reset()
	await _frames()
	var before_damage: Dictionary = flight.session.checkpoint()
	var mirrored_agent: Node = flight.companions.agents[0]
	var mirrored_ref: WeakRef = weakref(mirrored_agent)
	var restored_from_damage := [false]
	mirrored_agent.session.scenery_damage_changed.connect(func() -> void:
		restored_from_damage[0] = flight.session.restore_checkpoint(before_damage), CONNECT_ONE_SHOT)
	var proxy: Dictionary = {}
	for item: Dictionary in flight.session.collision_world().get("proxies", []):
		if str(item.get("damage_profile", "none")) != "none" and not str(item.get("damage_id", "")).is_empty():
			proxy = item
			break
	_check("real Club world supplies a damageable proxy", not proxy.is_empty())
	if not proxy.is_empty():
		var profile: String = str(proxy.damage_profile)
		var energy: float = SceneryDamage.threshold_j(profile) * 1.1
		flight.session._scenery_damage = {str(proxy.damage_id): {
			profile = profile, state = SceneryDamage.impact_state(profile, energy), tick = 1, energy_j = energy,
			point_ned = PackedFloat64Array([proxy.north, proxy.east, proxy.down]),
			normal_ned = PackedFloat64Array([0, 0, -1]), velocity_ned = PackedFloat64Array([0, 0, 1]), obstacle_id = str(proxy.id)}}
		flight.session.scenery_damage_changed.emit()
		flight.session.sim.step()
		_check("restore during damage mirroring cancels the old fleet callback", restored_from_damage[0]
			and flight.companion_status().active == 0 and flight.companions.accepted_ticks == 0
			and not flight.companions._advancing and flight.session.sim.tick == 0)
		await _frames()
		_check("damage listener's retired session is disposed safely", mirrored_ref.get_ref() == null)
	# Remove after an accepted start wins over its still-queued roster creation.
	flight.session.reset()
	flight.remove_companions_now()
	await _frames()
	_check("Remove before deferred completion prevents respawn", flight.companion_status().active == 0
		and not flight._companions_reset_pending and not flight.session.holds.has("companions-reset"))
	# Explicit pause after the accepted reset survives deferred completion.
	flight.session.reset()
	flight.session._failsafe("explicit pause after accepted start")
	await _frames()
	_check("deferred completion preserves a later explicit pause", flight.session.sim.paused
		and flight.session.pause_reason == "explicit pause after accepted start"
		and not flight.session.holds.has("companions-reset"))
	flight.remove_companions_now()
	flight.session.reset()
	flight.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames()
	_check("actual focus-out cannot be undone by deferred completion", flight.session.sim.paused
		and not flight.session.holds.has("companions-reset") and not flight._companions_reset_pending)
	flight.remove_companions_now()
	flight.session.reset()
	await _frames()
	_check("a later reset while unfocused cannot resume automatically", flight.session.sim.paused
		and not flight._companions_reset_pending and not flight.session.holds.has("companions-reset"))
	flight.remove_companions_now()
	flight.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	# Weather selection is a pending configuration, not an accepted flight start.
	flight.session.reset()
	var weather: Dictionary = flight.session.weather_configuration()
	weather.speed_mps = 0.25
	_check("weather selection fixture is accepted", flight.session.setup_weather(weather))
	await _frames()
	_check("pending weather does not rebuild or resume companions", flight.companion_status().active == 0
		and not flight._companions_reset_pending and not flight.session.holds.has("companions-reset")
		and flight.session.sim.paused)
	# A committed start with a publication fault cannot authorize resume.
	var corrupt: Callable = func() -> void: flight.session.sim.mass *= 2.0
	flight.session.resetting.connect(corrupt, CONNECT_ONE_SHOT)
	flight.session.reset()
	await _frames()
	_check("accepted reset observer fault never resumes or rebuilds", flight.session.sim.paused
		and not flight.session.sim.fault_reason.is_empty() and not flight.session.start_error.is_empty()
		and flight.companion_status().active == 0 and not flight._companions_reset_pending
		and not flight.session.holds.has("companions-reset"))
	_close(flight)
	_finish()

func _close(flight: Node) -> void:
	flight.recorder.detach()
	if flight._engine_audio != null:
		flight._engine_audio.stop()
		flight._engine_audio.stream = null
	flight.free()

func _finish() -> void:
	print("companion restore lifecycle: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
