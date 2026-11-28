extends SceneTree
## NK-7l: GlowVoice.render_telemetry rendered whole by the native kernel (nk_glow_voice_render.hpp) equals the GDScript
## preparation with the native loop, and the pure GDScript voice, block for block: the PCM bytes and every voice state
## field. Telemetry comes from glow flights of the 2-stroke 61FX and the 4-stroke FS64V through the pump's own
## snapshot_for_render (anchored blocks on new revisions, extrapolated repeats), then from crafted cases: an engine
## stop and restart, a family switch, missing counters, malformed source vibration, an empty tank, odd blade counts
## and frame sizes, and a non-bool `running` (which the native render refuses). The native render serves the flight
## blocks; a one-sample change is detected. Skips (passes) without a verified library with the render.

const Rig := preload("res://audio/flight_audio.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const GlowVoice := preload("res://audio/glow_voice.gd")
const Pump := preload("res://audio/glow_audio_pump.gd")

var _checks := 0
var _failures := 0
var _field: Dictionary


class Owner extends Node3D:
	var session: Node
	var field := {}
	var aircraft_id := ""
	var workshop_trial := {}
	var _field_node: Node3D
	var _airplane := {}
	var _lighting := {}
	var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)


## Detached glow telemetry of one flight, one entry per frame of four ticks.
func _telemetry(path: String, id: String, frames: int) -> Array:
	var session: Node = Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.cost_observations_enabled = true
	session.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	session.setup(path, id)
	session.set_process(false)
	session.set_physics_process(false)
	session.set_field(_field)
	session.reset()
	var owner := Owner.new()
	owner.session = session
	owner.aircraft_id = id
	owner.field = _field
	var plane := Node3D.new()
	owner.add_child(plane)
	owner._airplane = {root = plane, model_manifest = {bindings = {controls = {}}}, hinges = {}}
	owner._camera = Camera3D.new()
	owner.add_child(owner._camera)
	root.add_child(owner)
	var audio: Node = Rig.new()
	owner.add_child(audio)
	audio.configure(owner)
	audio.set_process(false)
	if not bool(session.glow_state().get("running", false)):
		session.glow_start()
	var out: Array = []
	for frame in frames:
		session.sim.inputs[3] = [0.85, 0.3, 1.0][(frame / 120) % 3]
		for k in 4:
			session.sim.step()
		var glow: Dictionary = audio.snapshot().get("glow", {})
		if not glow.is_empty():
			out.append(Pump._detached_telemetry(glow))
	owner.free()
	session.free()
	return out


func _voices() -> Array:
	var native: Variant = GlowVoice.new()
	var prepared: Variant = GlowVoice.new()
	prepared.native_render_enabled = false
	var script: Variant = GlowVoice.new()
	script.native_render_enabled = false
	script.native_loop_enabled = false
	return [native, prepared, script]


## One block through all three voices; "" when every PCM and voice state agrees.
func _block(voices: Array, snapshot: Dictionary, frames: int) -> String:
	var pcm: Array = []
	var states: Array = []
	for voice: Variant in voices:
		pcm.append(var_to_bytes(voice.render_telemetry(snapshot.duplicate(true), frames)))
		states.append(var_to_bytes([voice._voice_state(), voice.last_family]))
	if pcm[0] != pcm[1] or states[0] != states[1]:
		return "native render %s / prepared %s" % [str(bytes_to_var(states[0])), str(bytes_to_var(states[1]))]
	if pcm[1] != pcm[2] or states[1] != states[2]:
		return "prepared %s / GDScript %s" % [str(bytes_to_var(states[1])), str(bytes_to_var(states[2]))]
	return ""


## The pump's block schedule over a telemetry sequence: a new revision per entry, two or three blocks each.
func _stream(label: String, voices: Array, sequence: Array) -> Dictionary:
	var stats := {blocks = 0, mismatched = 0, first = ""}
	var revision := 0
	var rendered := -1
	var queued := 0
	for i: int in sequence.size():
		revision += 1
		for block: int in (2 + i % 2):
			var snapshot: Dictionary = Pump.snapshot_for_render(sequence[i], revision, rendered, queued)
			rendered = revision
			var frames: int = [256, 256, 300, 1, 255][(i + block) % 5]
			var detail := _block(voices, snapshot, frames)
			stats.blocks += 1
			if not detail.is_empty():
				stats.mismatched += 1
				if stats.first.is_empty():
					stats.first = "%s block %d: %s" % [label, stats.blocks, detail]
			queued = (queued + frames * 3) % 900
	return stats


func _run() -> void:
	var probe: Variant = GlowVoice.new()
	if not NativeStage.library_status().get("ok", false) or probe._native_render() == null:
		print("NK7L_SKIP no native library with the glow voice render")
		quit(0)
		return
	_field = FieldLoader.load_from().field
	var two_stroke := _telemetry("res://data/aircraft/stik_glow_61fx_2t.json", "stik-glow-61fx-2t", 420)
	var four_stroke := _telemetry("res://data/aircraft/stik_glow_fs64v_4t.json", "stik-glow-fs64v-4t", 420)
	_check("the flights give telemetry", two_stroke.size() > 300 and four_stroke.size() > 300,
		"%d / %d" % [two_stroke.size(), four_stroke.size()])
	for flight: Array in [["2-stroke 61FX", two_stroke], ["4-stroke FS64V", four_stroke]]:
		var voices := _voices()
		var stats := _stream(flight[0], voices, flight[1])
		_check("%s: every block equals the prepared and GDScript voices (%d blocks)" % [flight[0], stats.blocks],
			stats.mismatched == 0, stats.first)
		_check("%s: the native render served the blocks" % flight[0],
			voices[0].native_render_answers == stats.blocks and voices[1].native_render_answers == 0,
			"%d of %d" % [voices[0].native_render_answers, stats.blocks])
	# Crafted cases on the 2-stroke telemetry.
	var base: Dictionary = two_stroke[two_stroke.size() / 2]
	var cases: Array = []
	var stopped := base.duplicate(true)
	stopped.running = false
	cases.append(["engine stop", [base, stopped, stopped, base, base]])
	cases.append(["family switch", [base, four_stroke[four_stroke.size() / 2], base]])
	var unanchored := base.duplicate(true)
	for key: String in ["opportunity_count", "fire_count", "firing_accumulator"]:
		unanchored.erase(key)
	cases.append(["phase without counters", [unanchored, unanchored]])
	var bare := {family = "glow_2t", rpm = 9000}
	cases.append(["bare telemetry", [bare, bare]])
	var empty_tank := base.duplicate(true)
	empty_tank.fuel_kg = 0.0
	cases.append(["empty tank", [empty_tank, empty_tank]])
	for broken: Array in [["ok", false], ["family", "glow_4t"], ["alpha_rad_s2", 1.0], ["omega_rad_s", 1.0],
			["cycle_revolutions", 2], ["order_1x_force_peak_n", -1.0]]:
		var malformed := base.duplicate(true)
		if malformed.get("source_vibration") is Dictionary:
			var source: Dictionary = malformed.source_vibration.duplicate(true)
			source[broken[0]] = broken[1]
			malformed.source_vibration = source
		cases.append(["source vibration %s" % broken[0], [malformed]])
	for blades: Variant in [3.0, 0, 20]:
		var odd := base.duplicate(true)
		odd.blade_count = blades
		cases.append(["blade count %s" % str(blades), [odd]])
	var no_load := base.duplicate(true)
	no_load.erase("load")
	cases.append(["throttle as load", [no_load]])
	var no_max := base.duplicate(true)
	no_max.max_rpm = 0.0
	cases.append(["no maximum", [no_max]])
	var named := base.duplicate(true)
	named.family = &"glow_2t"
	cases.append(["family as a StringName", [named]])
	var numeric_running := base.duplicate(true)
	numeric_running.running = 1
	cases.append(["numeric running (refused)", [numeric_running]])
	var silent := {family = "glow_prop", rpm = 9000.0}
	cases.append(["no glow family", [base, silent, base]])
	var mismatched := 0
	var first := ""
	var served := ""
	for case: Array in cases:
		var voices := _voices()
		var stats := _stream(case[0], voices, case[1])
		for frames: int in [0, -3]:
			var detail := _block(voices, case[1][0], frames)
			if not detail.is_empty():
				stats.mismatched += 1
				stats.first = "%s frames %d: %s" % [case[0], frames, detail]
		mismatched += stats.mismatched
		if first.is_empty():
			first = stats.first
		# Every block is native except the refused case's (its empty blocks return before `running` is read).
		var expected: int = 2 if str(case[0]).ends_with("(refused)") else stats.blocks + 2
		if voices[0].native_render_answers != expected and served.is_empty():
			served = "%s: %d native of %d" % [case[0], voices[0].native_render_answers, expected]
	_check("every crafted case equals the prepared and GDScript voices (%d cases)" % cases.size(), mismatched == 0, first)
	_check("the native render answered every crafted block it does not refuse", served.is_empty(), served)
	# A one-sample change is detected.
	var voices := _voices()
	var pcm: PackedVector2Array = voices[0].render_telemetry(base.duplicate(true), 64)
	var reference: PackedVector2Array = voices[1].render_telemetry(base.duplicate(true), 64)
	var altered := pcm.duplicate()
	altered[10] = altered[10] + Vector2(1e-6, 0.0)
	_check("a one-sample change is detected", var_to_bytes(pcm) == var_to_bytes(reference)
		and var_to_bytes(altered) != var_to_bytes(reference))
	print("native glow voice render: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)
