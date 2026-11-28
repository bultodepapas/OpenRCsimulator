extends SceneTree
## NK-7i: flight audio's per-frame wind and air data from the native stage at the published endpoint equal
## FlightSession.wind_at(sim.time()) and air_data(sim.state). The P-51, the glow Stik 61FX and the electric Stik 6S fly
## 600 frames of four ticks each on the production field: calm, gusty, turbulent and spatial weather, throttle and pitch
## changes. Every frame the whole FlightAudio.snapshot() is byte-identical with the native answer on and off; the
## native answer serves calm, gusty and turbulent frames, and spatial weather keeps the reference. A 1e-9 change to the
## native wind is detected. Skips (passes) without the verified library.

const Rig := preload("res://audio/flight_audio.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Weather := preload("res://physics/wind_config.gd")
const FRAMES := 600

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


func _weather(name: String) -> Variant:
	match name:
		"gusty": return Weather.preset("gusty")
		"turbulent": return Weather.preset("turbulent")
		"spatial": return Weather.spatial_defaults()
	return null


func _rig(path: String, id: String, weather: String) -> Array:
	var session: Node = Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.cost_observations_enabled = true
	session.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	session.setup(path, id)
	session.set_process(false)
	session.set_physics_process(false)
	session.set_field(_field)
	var config: Variant = _weather(weather)
	if config != null and not session.setup_weather(config):
		session.free()
		return []
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
	owner._camera.global_position = Vector3(20.0, 2.0, 30.0)
	var audio: Node = Rig.new()
	owner.add_child(audio)
	audio.configure(owner)
	audio.set_process(false)
	if session.glow_is_active() and not bool(session.glow_state().get("running", false)):
		session.glow_start()
	return [session, owner, audio]


func _run() -> void:
	if not NativeStage.library_status().get("ok", false) \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"stage_endpoint_air"):
		print("NK7I_SKIP no native library with the endpoint air")
		quit(0)
		return
	root.audio_listener_enable_3d = true
	_field = FieldLoader.load_from().field
	var mutation_seen := false
	for aircraft: Array in [["res://data/aircraft/p51d_mustang_120.json", "p51d-mustang-120"],
			["res://data/aircraft/stik_glow_61fx_2t.json", "stik-glow-61fx-2t"],
			["res://data/aircraft/stik_electric_6s.json", "stik-electric-6s"]]:
		for weather: String in ["calm", "gusty", "turbulent", "spatial"]:
			var rig := _rig(aircraft[0], aircraft[1], weather)
			if rig.is_empty():
				_check("%s %s: a native session" % [aircraft[1], weather], false)
				continue
			var session: Node = rig[0]
			var audio: Node = rig[2]
			var mismatched := 0
			var first := ""
			var native_frames := 0
			for frame: int in FRAMES:
				session.sim.inputs[3] = [0.9, 0.4, 1.0][(frame / 200) % 3]
				session.sim.inputs[1] = 0.15 if (frame / 100) % 3 == 1 else 0.0
				for k: int in 4:
					session.sim.step()
				session.native_endpoint_air_enabled = true
				if session.published_endpoint_air().size() == 7:
					native_frames += 1
				var native: Dictionary = audio.snapshot()
				session.native_endpoint_air_enabled = false
				var reference: Dictionary = audio.snapshot()
				session.native_endpoint_air_enabled = true
				if var_to_bytes(native) != var_to_bytes(reference):
					mismatched += 1
					if first.is_empty():
						first = "frame %d: wind %s vs %s, airspeed %s vs %s" % [frame, native.get("wind_direction"),
							reference.get("wind_direction"), native.get("airspeed"), reference.get("airspeed")]
				if not mutation_seen and frame == 50 and native_frames > 0:
					var altered: Dictionary = reference.duplicate(true)
					altered.airspeed = float(altered.airspeed) + 1e-9
					mutation_seen = var_to_bytes(altered) != var_to_bytes(native)
			var expected_native: bool = weather != "spatial"
			_check("%s %s: the snapshot is byte-identical with the native endpoint air on and off (%d native frames)" % [
				aircraft[1], weather, native_frames], mismatched == 0 \
				and (native_frames > FRAMES / 2 if expected_native else native_frames == 0), first)
			rig[1].free()
			session.free()
	_check("a 1e-9 change to the airspeed is detected", mutation_seen)
	print("native endpoint air: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)
