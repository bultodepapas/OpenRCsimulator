extends SceneTree
## NK-7g: FlightAudio.snapshot() is byte-identical with GlowAudioState.native_keys on and off. Three glow installations
## (two two-strokes and a four-stroke) fly 900 frames of four ticks each: idle, full and half throttle, a
## pitch-up, then the engine cut and the propeller winding down. Every frame compares the whole snapshot; the native
## key set answers while the engine runs, and the snapshot assembles the keys itself once it stops. A 1e-7 change to
## one GDScript-assembled value is detected. Skips (passes) without the verified library.

const Rig := preload("res://audio/flight_audio.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GlowAudioState := preload("res://audio/glow_audio_state.gd")
const FRAMES := 900

var _checks := 0
var _failures := 0


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


func _rig(path: String, id: String) -> Array:
	var session: Node = Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup_stage_backend("native")
	session.setup(path, id)
	session.set_process(false)
	session.set_physics_process(false)
	var owner := Owner.new()
	owner.session = session
	owner.aircraft_id = id
	owner.field = FieldLoader.load_from().field
	var plane := Node3D.new()
	owner.add_child(plane)
	owner._airplane = {root = plane, model_manifest = {bindings = {controls = {}}}, hinges = {}}
	owner._camera = Camera3D.new()
	owner.add_child(owner._camera)
	root.add_child(owner)
	owner._camera.global_position = Vector3(20.0, 2.0, 30.0)
	var audio: Node = Rig.new()
	owner.add_child(audio)
	audio.configure(owner)
	audio.set_process(false)
	if not bool(session.glow_state().get("running", false)):
		session.glow_start()
	return [session, owner, audio]


func _run() -> void:
	if not load("res://sim/native_stage.gd").library_status().get("ok", false) \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"stage_glow_audio_keys"):
		print("NK7G_SKIP no native library with the glow audio keys")
		quit(0)
		return
	root.audio_listener_enable_3d = true
	var mutation_seen := false
	for aircraft: Array in [["res://data/aircraft/stik_glow_61fx_2t.json", "stik-glow-61fx-2t"],
			["res://data/aircraft/stik_glow_fs64v_4t.json", "stik-glow-fs64v-4t"],
			["res://data/aircraft/stik_glow_55ax_2t.json", "stik-glow-55ax-2t"]]:
		var rig := _rig(aircraft[0], aircraft[1])
		var session: Node = rig[0]
		var audio: Node = rig[2]
		var mismatched := 0
		var first := ""
		var native_frames := 0
		var assembled_frames := 0
		for frame: int in FRAMES:
			session.sim.inputs[3] = [0.0, 1.0, 0.5][(frame / 150) % 3] if frame < 600 else 0.0
			session.sim.inputs[1] = 0.3 if frame >= 300 and frame < 360 else 0.0
			if frame == 600:
				session.engine_running = false
			for k: int in 4:
				session.sim.step()
			GlowAudioState.native_keys_enabled = true
			var native: Dictionary = audio.snapshot()
			var keys: Dictionary = GlowAudioState.native_keys(session, true, 1.0, 0.5)
			if keys.is_empty():
				assembled_frames += 1
			else:
				native_frames += 1
			GlowAudioState.native_keys_enabled = false
			var reference: Dictionary = audio.snapshot()
			GlowAudioState.native_keys_enabled = true
			if var_to_bytes(native) != var_to_bytes(reference):
				mismatched += 1
				if first.is_empty():
					first = "frame %d: %s vs %s" % [frame, native.get("glow", native), reference.get("glow", reference)]
			if not mutation_seen and frame == 100 and reference.has("glow") and reference.glow is Dictionary:
				var altered: Dictionary = reference.duplicate(true)
				altered.glow.firing_fraction = float(altered.glow.firing_fraction) + 1e-7
				mutation_seen = var_to_bytes(altered) != var_to_bytes(native)
		_check("%s: the snapshot is byte-identical with the native glow keys on and off (%d native, %d assembled frames)" % [
			aircraft[1], native_frames, assembled_frames], mismatched == 0 and native_frames > 300 and assembled_frames > 50,
			first)
		rig[1].free()
		session.free()
	_check("a 1e-7 change to one assembled glow value is detected", mutation_seen)
	print("native glow audio keys: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)
