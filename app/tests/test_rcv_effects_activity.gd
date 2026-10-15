extends SceneTree

const Activity = preload("res://vehicles/ground/ground_scene.gd")
const NEUTRAL := {"throttle":0.0,"steering":0.0,"brake":0.0,"reverse":false,"armed":true}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func make_activity(effects: bool):
	var scene = Activity.new()
	scene.enable_audio = false
	scene.enable_course_visual = false
	scene.enable_vehicle_effects = effects
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	return scene

func _run() -> void:
	TranslationServer.set_locale("es")
	var scene = make_activity(true)
	var reference = make_activity(false)
	check(scene.startup_error.is_empty() and reference.startup_error.is_empty(), "both production-airfield activities start")
	check(scene.session.spawn_id == "start", "default spawn stays on aircraft runway")
	scene.handle_action("sound")
	scene._process(0.0)
	check(scene.enable_audio and scene._wet_effects.audio_enabled, "sound toggle enables the water voice as well as engine audio")
	# An already playing splash must stop, including when muting from the garage.
	scene._wet_effects._audio_player.stream = scene._wet_effects.SPLASH_ONE
	scene._wet_effects._audio_player.play()
	scene.handle_action("sound")
	scene._process(0.0)
	check(not scene.enable_audio and not scene._wet_effects.audio_enabled
		and not scene._wet_effects._audio_player.playing and scene._wet_effects._audio_player.stream == null,
		"muting from the garage stops an active splash and disables new water sound")
	var ready: bool = scene.session.reset("track_rollers") and reference.session.reset("track_rollers")
	scene._after_reset()
	reference._after_reset()
	scene.handle_action("resume")
	reference.handle_action("resume")
	ready = ready and not scene.session.paused and not reference.session.paused
	check(ready, "ordinary circuit spawn resumes")
	var sample := NEUTRAL.duplicate()
	sample.throttle = 0.30
	var equal := true
	var peak_dust := 0
	for i in 360:
		equal = equal and scene.session.tick_once(sample) and reference.session.tick_once(sample)
		if i % 4 == 0:
			scene._last_controls = sample
			scene._process(1.0 / 60.0)
			peak_dust = maxi(peak_dust, scene._effects.diagnostic_snapshot().dust_active_wheels)
		equal = equal and scene.session.state_snapshot().to_byte_array() == reference.session.state_snapshot().to_byte_array()
		equal = equal and scene.session.damage_snapshot().to_byte_array() == reference.session.damage_snapshot().to_byte_array()
	check(equal and scene.session.tick == 360 and reference.session.tick == 360,
		"render effects preserve every physical and damage state byte over 360 ticks")
	var before: Dictionary = scene._effects.diagnostic_snapshot()
	check(peak_dust > 0 and before.grime_amount > 0.0, "accepted dirt drive emits dust and collects grime")
	scene.open_garage()
	var state_before: PackedByteArray = scene.session.state_snapshot().to_byte_array()
	for i in 10: scene._process(0.1)
	var paused: Dictionary = scene._effects.diagnostic_snapshot()
	check(paused.dust_active_wheels == 0 and paused.grime_amount == before.grime_amount, "garage freezes dust and grime")
	check(scene.session.state_snapshot().to_byte_array() == state_before, "paused render never advances physics")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	scene._focused = true
	scene._unhandled_input(key)
	scene._process(0.0)
	check(not scene._effects.headlights_enabled and scene.dashboard.headlights_button.text.contains("apagados"), "L toggles lights and Spanish garage label")
	scene.handle_action("lights")
	check(scene._effects.headlights_enabled, "garage action restores headlights")
	scene._last_controls = {"brake":1.0,"reverse":true,"throttle":0.0}
	scene._process(0.0)
	var lamps: Dictionary = scene._effects.diagnostic_snapshot()
	check(lamps.brake_lights and lamps.reverse_lights, "accepted controls reach brake and reverse lamps")
	# Explicit render/checkpoint fixture; impact generation is covered by test_rcv_damage_session.
	var damage: PackedFloat64Array = scene.session.damage_snapshot()
	damage[0] = 0.65
	damage[9] = 0.4
	check(scene.session._damage.restore_snapshot(damage), "bounded damaged fixture is accepted")
	scene.session._last_telemetry.damage = scene.session.damage_visual_state()
	var checkpoint: Dictionary = scene.session.checkpoint()
	scene.visual.nodes.Body.visible = false
	scene._process(0.0)
	check(scene.dashboard.condition_status.visible and scene.dashboard.condition_status.text.contains("60%"), "damaged HUD shows reduced drive authority")
	check(not scene.visual.nodes.Body.visible, "deformation preserves hidden-body lab inspection")
	scene.handle_action("recover")
	scene._process(0.0)
	check(scene.session.damage_visual_state().stage == "intact" and not scene.dashboard.condition_status.visible
		and scene._effects.diagnostic_snapshot().grime_amount == 0.0 and not scene.session.run_valid,
		"R repairs, cleans and marks the run assisted")
	check(scene.session.restore_checkpoint(checkpoint), "damaged checkpoint restores")
	scene._after_reset()
	scene._process(0.0)
	check(scene.session.damage_visual_state().body_damage == 0.65 and scene.dashboard.condition_status.visible,
		"restore preserves damage through visual reset")
	scene.handle_action("reset")
	scene._process(0.0)
	check(scene.session.damage_visual_state().stage == "intact" and scene.session.run_valid,
		"new run clears damage and assistance")
	scene.free()
	reference.free()
	await process_frame
	print("RCV effects activity: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
