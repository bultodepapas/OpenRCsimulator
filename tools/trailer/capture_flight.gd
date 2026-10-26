## Live production-flight frame capture for trailer source shots.
## Run outside the app scene: Godot --path app --fixed-fps 60 --script <absolute path> -- --out-dir=<absolute path>.
## For real-time --frametimes measurements, omit --fixed-fps and Movie Maker; see README.md.
## This driver instantiates the real main scene and never changes app/ sources or physics.
extends SceneTree

const MainScene := preload("res://main.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const WorldConditions := preload("res://render/world/conditions.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const CameraSettings := preload("res://render/camera/camera_settings.gd")
const Magnifier := preload("res://render/camera/magnifier.gd")
const Exposure := preload("res://render/world/exposure.gd")
const LightingPolicy := preload("res://render/lighting/lighting_policy.gd")
const AircraftLightingRig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const LightingProfile := preload("res://render/lighting/lighting_profile.gd")
const FrameSamples := preload("res://render/frame_samples.gd")
const ViewportColor := preload("res://render/viewport_color.gd")
const StockSmoke := preload("res://render/smoke/stock_profile.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const WorkloadAudit := preload("lighting_workload_audit.gd")

const DEFAULT_FPS := 60
const DEFAULT_WIDTH := 1920
const DEFAULT_HEIGHT := 1080
const MAX_CRASH_PREROLL_S := 30.0
const CRASH_CLIP_APPROACH_FRAMES := 120
const CRASH_CLIP_POST_IMPACT_FRAMES := 360
const CRASH_RESTART_AFTER_IMPACT_FRAMES := 240
const AUDIO_TEARDOWN_TIMEOUT_USEC := 2_000_000
const AUDIO_MIX_AGE_JITTER_USEC := 2_000

var _options: Dictionary = {}
var _main: Node
var _director: Node
var _out_dir := ""
var _shot := "stik-bank"
var _fps := DEFAULT_FPS
var _width := DEFAULT_WIDTH
var _height := DEFAULT_HEIGHT
var _seconds := 4.0
var _frame_count := 0
var _image_count := 0
var _sample_every := 1
var _save_images := true
var _failure := ""
var _preserved_report: Dictionary = {}
var _preserved_crash: Dictionary = {}
var _preserved_prop_strike: Dictionary = {}
var _impact_preroll_frames := -1
var _restart_result := false
var _restart_frame := -1
var _restart_movie_frame := -1
var _restart_tick_before := -1
var _restart_tick_after := -1
var _details_frame := -1
var _report_layer_hidden_before_impact := false
var _report_layer_reveal_frame := -1
var _realtime := false
var _performance_options: Dictionary = {}
var _performance_done := false
var _performance_exit := -1
var _performance_elapsed_s := 0.0
var _performance_budget_samples: Array[Dictionary] = []
var _lighting_profile_input_path := ""
var _lighting_profile_input_sha256 := ""
var _lighting_profile_data: Dictionary = {}
var _lighting_smoke_preset := ""
var _lighting_smoke_profile_sha256 := ""
var _lighting_smoke_evidence_start: Dictionary = {}
var _lighting_flight := "workshop"
var _normal_requested_companions := -1
var _lighting_profile_applied := false
var _normal_physics_attach_guard: Dictionary = {"checked": false, "passed": false, "reason": "not run"}
var _workload_audit: RefCounted
var _workload_audit_usec := 0


func _initialize() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	root.size = Vector2i(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	root.msaa_3d = Viewport.MSAA_4X
	call_deferred("_run")


func _run() -> void:
	_options = _parse_options(OS.get_cmdline_user_args())
	_lighting_flight = str(_options.get("lighting-flight", "workshop"))
	_realtime = _options.has("frametimes")
	var lighting_options := validate_lighting_profile_options(_options)
	if not bool(lighting_options.get("ok", false)):
		push_error(str(lighting_options.get("error", "Invalid lighting profile options.")))
		quit(2)
		return
	if _options.has("lighting-profile"):
		var profile_input := read_lighting_profile_file(str(_options["lighting-profile"]))
		if not bool(profile_input.get("ok", false)):
			push_error("Lighting profile refused: " + str(profile_input.get("error", "invalid input")))
			quit(2)
			return
		_lighting_profile_data = profile_input.profile
		_lighting_profile_input_path = str(_options["lighting-profile"]).replace("\\", "/").simplify_path()
		_lighting_profile_input_sha256 = str(profile_input.sha256)
	# Mobile world rendering needs HDR. The pinned engine's Movie Maker corrupts
	# RGBAH-to-sRGB conversion; use this harness's correctly encoded PNG sequence.
	if RenderingServer.get_current_rendering_method() == "mobile" and not Engine.get_write_movie_path().is_empty():
		push_error("Mobile HDR movie capture is unavailable on the pinned engine; capture PNG frames and encode them with FFmpeg.")
		quit(2)
		return
	_out_dir = str(_options.get("out-dir", ""))
	if _out_dir.is_empty():
		push_error("capture_flight requires --out-dir=<absolute path>")
		quit(2)
		return
	if not _out_dir.is_absolute_path():
		push_error("--out-dir must be an absolute path")
		quit(2)
		return
	if _options.has("lighting-profile") and lighting_profile_collides_with_manifest(_lighting_profile_input_path, _out_dir):
		push_error("--lighting-profile must not point to the capture manifest path.")
		quit(2)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(_out_dir)
	if directory_error != OK:
		push_error("Could not create capture directory: %s (%s)" % [_out_dir, error_string(directory_error)])
		quit(1)
		return
	_fps = int(_options.get("fps", DEFAULT_FPS))
	_width = int(_options.get("width", DEFAULT_WIDTH))
	_height = int(_options.get("height", DEFAULT_HEIGHT))
	_seconds = float(_options.get("seconds", 4.0))
	_shot = str(_options.get("shot", "stik-bank"))
	if _realtime and not _validate_performance_options():
		quit(2)
		return
	if str(_options.get("lighting-workload-audit", "off")) == "on":
		_workload_audit = WorkloadAudit.new()
	_sample_every = maxi(1, int(_options.get("sample-every", 1)))
	_save_images = not OS.get_cmdline_user_args().has("--movie-only")
	if _realtime:
		_save_images = false
	if _fps != 60 or _width != 1920 or _height != 1080 or _seconds <= 0.0:
		push_error("Trailer capture requires 1920x1080, 60 fps, and a positive duration")
		quit(2)
		return
	TranslationServer.set_locale("en")
	_main = MainScene.new()
	if _realtime:
		if not _main.has_signal("frame_time_report_written") or not _main.get_property_list().any(
				func(property: Dictionary) -> bool: return str(property.get("name", "")) == "frametimes_route"):
			push_error("Real-time capture requires the current Main collector hook; refresh the prepared runtime.")
			_main.free()
			quit(2)
			return
		_main.frametimes_auto_quit = false
		_main.frametimes_route = "director-flight"
		_main.frame_time_report_written.connect(_on_frame_time_report_written)
	_main.name = "Main"
	_main.interactive_start = true
	_main.aircraft_id = str(_options.get("aircraft", "jensen-das-ugly-stik-60"))
	# Workshop remains the default frozen-trial route. The normal route owns a preset
	# only in this renderer harness and leaves Main's workshop_trial empty.
	if _options.has("lighting-preset") or _options.has("lighting-profile"):
		var lighting: Dictionary = _lighting_profile_data.duplicate(true) if _options.has("lighting-profile") \
			else Presentation.LightingProfile.preset(str(_options["lighting-preset"]))
		if _options.has("lighting-preset") and str(_options["lighting-preset"]) == "off":
			lighting = Presentation.LightingProfile.defaults()
			lighting.selection = "disabled"
		_lighting_profile_data = lighting.duplicate(true)
		if _lighting_flight == "workshop":
			var prepared := freeze_lighting_trial(_main.aircraft_id, lighting, _effective_lighting_smoke_mode())
			if not prepared.get("ok", false):
				push_error("Lighting capture trial refused: " + str(prepared.get("errors", [])))
				_main.free()
				quit(2)
				return
			_main.workshop_trial = prepared.trial
			_lighting_smoke_preset = str(prepared.smoke_preset)
			_lighting_smoke_profile_sha256 = str(prepared.get("smoke_profile_sha256", ""))
	_main.start_choice = str(_options.get("start", "airborne"))
	if _shot == "lighting-pilot":
		_main.camera_preferences = CameraSettings.normalized({
			"camera_view": "pilot", "camera_auto_zoom": false, "camera_magnifier": "on"})
	_main.overlays_enabled = _shot == "controls"
	if _options.has("sky"):
		_main.sky_config = SkyConfig.for_preset(str(_options.sky))
	elif _shot == "storm":
		_main.sky_config = SkyConfig.for_preset("electrical_storm")
	_main.accident_archive_path = _out_dir.path_join("incident-%d.json" % Time.get_ticks_usec())
	_main.user_args = PackedStringArray([
		"--accident-report=on",
		"--crash-effects=on",
		"--smoke-pump=on",
		"--failures=0",
		"--failure-seed=0",
	])
	if _lighting_flight == "normal":
		if _effective_lighting_smoke_mode() == "off":
			_main.user_args.append("--smoke=off")
		_main.user_args.append_array(_normal_companion_args(OS.get_cmdline_user_args()))
	if _options.has("alt"):
		_main.user_args.append("--alt=" + str(_options.alt))
	if _options.has("sky"):
		_main.user_args.append("--sky=" + str(_options.sky))
	for key: String in ["wind-speed", "wind-from", "gust-speed", "gust-up", "gust-duration", "gust-period", "gust-delay", "time_of_day", "landscape"]:
		if _options.has(key):
			_main.user_args.append("--%s=%s" % [key, str(_options[key])])
	if _realtime:
		_main.user_args.append_array(PackedStringArray([
			"--frametimes=" + str(_performance_options.path),
			"--warmup=" + str(_performance_options.warmup_s),
			"--t=" + str(_performance_options.sample_s),
			"--frametimes-max-frames=" + str(_performance_options.max_frames),
			"--case=rgb-" + str(_options["lighting-preset"]), "--frame-diagnostics",
		]))
	root.add_child(_main)
	if _realtime:
		# Exclude a connected radio before the first awaited frame, not only when the director attaches.
		if _main.session != null:
			_main.session.input_enabled = false
		LightingPolicy.apply({"aircraft_lighting_quality": str(_options.get("lighting-quality", "standard")),
			"aircraft_lighting_reduced_flashes": false, "aircraft_lighting_show_vfx": true})
	# Hide only the presentation CanvasLayer before the real flight input starts; the incident ledger remains live.
	if _main._accident_report != null:
		_main._accident_report.visible = false
		_report_layer_hidden_before_impact = true
	if not bool(_main.startup_complete):
		await _main.startup_finished
	await process_frame
	await RenderingServer.frame_post_draw
	if not _main.startup_error.is_empty() or _main.session == null or not _main.session.is_flyable():
		_failure = str(_main.startup_error)
		if _failure.is_empty() and _main.session != null:
			_failure = str(_main.session.start_error)
		await _abort_live_capture("Production flight startup failed: " + _failure, 1)
		return
	if _lighting_flight == "normal":
		var normal_flight: Dictionary = _validate_normal_flight()
		if not bool(normal_flight.get("ok", false)):
			await _abort_live_capture(str(normal_flight.get("error", "Normal flight was refused.")), 1)
			return
		_normal_requested_companions = int(_main.companion_config.count) if bool(_main.companion_config.enabled) else 0
		var companion_admission: Dictionary = _validate_companion_admission("startup")
		if not bool(companion_admission.get("ok", false)):
			await _abort_live_capture(str(companion_admission.get("error", "Companions were not fully admitted.")), 1)
			return
		var smoke_setup: Dictionary = _verify_normal_smoke()
		if not bool(smoke_setup.get("ok", false)):
			await _abort_live_capture(str(smoke_setup.get("error", "Normal-flight smoke setup was refused.")), 1)
			return
		var lighting_setup: Dictionary = _install_normal_lighting()
		if not bool(lighting_setup.get("ok", false)):
			await _abort_live_capture(str(lighting_setup.get("error", "Normal-flight lighting setup was refused.")), 1)
			return
	else:
		_lighting_profile_applied = is_instance_valid(_main._rgb_lighting) \
			and str(_main._rgb_lighting.budget_info().get("selection", "inherit")) != "inherit"
		_lighting_smoke_evidence_start = _main._smoke_evidence().duplicate(true)
	if _main._accident_report == null:
		await _abort_live_capture("Crash capture requires the native accident report CanvasLayer.", 1)
		return
	if not _report_layer_hidden_before_impact:
		_main._accident_report.visible = false
		_report_layer_hidden_before_impact = true
	if _main._panel != null:
		_main._panel.visible = _shot == "controls"
	if _main._hud != null:
		_main._hud.visible = _shot == "controls"
	if _shot != "lighting-pilot":
		_main._rig.set_view("chase")
		_main._rig.auto_zoom = false
		_main._camera.fov = 38.0
	var director_path: String = get_script().resource_path.get_base_dir().path_join("flight_director.gd")
	if _options.has("director-script"):
		director_path = str(_options["director-script"])
		if not director_path.is_absolute_path():
			await _abort_live_capture("--director-script must be an absolute path", 2)
			return
	var director_script: Script = load(director_path) as Script
	if director_script == null:
		await _abort_live_capture("Could not load external flight director at " + director_path, 1)
		return
	_director = director_script.new()
	if _realtime:
		_director.record_tick_evidence = false
	_director.name = "TrailerFlightDirector"
	_director.configure(_main, _shot, _seconds, _fps)
	if _director.has_method("configuration_error"):
		var director_error: String = str(_director.configuration_error())
		if not director_error.is_empty():
			await _abort_live_capture("Flight director refused capture: " + director_error, 2)
			return
	root.add_child(_director)
	# Let the real world, interpolated airplane, particles, and camera finish one full presented interval.
	await process_frame
	await RenderingServer.frame_post_draw
	if _realtime:
		await _measure_realtime()
	elif _shot == "crash":
		await _capture_crash_report()
	else:
		await _capture_frames(int(round(_seconds * _fps)), 0)
	if _lighting_flight == "normal" and _failure.is_empty():
		var final_admission: Dictionary = _validate_companion_admission("capture completion")
		if not bool(final_admission.get("ok", false)):
			_failure = str(final_admission.get("error", "Companion workload was lost during capture."))
			push_error(_failure)
	_write_manifest(_failure.is_empty())
	await _teardown_live_scene()
	quit(1 if not _failure.is_empty() else 0)


func _effective_lighting_smoke_mode() -> String:
	if _options.has("lighting-smoke"):
		return str(_options["lighting-smoke"])
	return "off"


func _normal_companion_args(arguments: PackedStringArray) -> PackedStringArray:
	var forwarded := PackedStringArray()
	for arg: String in arguments:
		if arg in ["--companions", "--companions-seed"] \
				or arg.begins_with("--companions=") or arg.begins_with("--companions-seed="):
			forwarded.append(arg)
	return forwarded


func _validate_normal_flight() -> Dictionary:
	if not _main.workshop_trial.is_empty() or not _main.session.workshop_identity.is_empty() \
			or not _main.session.workshop_presentation_identity.is_empty():
		return {"ok": false, "error": "Normal lighting capture unexpectedly entered a Workshop trial."}
	if not _main.session.physics_enabled or not _main.session.is_flyable() \
			or _main.session.sim.paused or not _main.session.holds.is_empty():
		return {"ok": false, "error": "Normal lighting capture requires a live, unpaused physics flight."}
	return {"ok": true}


func _validate_companion_admission(stage: String) -> Dictionary:
	if _main == null or not is_instance_valid(_main) or _main.session == null:
		return {"ok": false, "error": "Companion admission cannot be observed during %s." % stage}
	var config: Dictionary = _main.companion_config
	var requested := _normal_requested_companions if _normal_requested_companions >= 0 else (int(config.get("count", 0)) if bool(config.get("enabled", false)) else 0)
	var status: Dictionary = _main.companion_status()
	var active := int(status.get("active", 0))
	var airborne := int(status.get("airborne", 0))
	var faulted := int(status.get("faulted", 0))
	var crashed := int(status.get("crashed", 0))
	var status_requested := int(status.get("requested", 0))
	var admission_error := str(status.get("error", ""))
	if active != requested or status_requested != requested \
			or (requested > 0 and (airborne != requested or faulted > 0 or crashed > 0)) \
			or not admission_error.is_empty():
		return {"ok": false, "error": "Companions were not fully admitted at %s: requested %d, active %d, airborne %d, faulted %d, crashed %d; %s" % [
			stage, requested, active, airborne, faulted, crashed,
			admission_error if not admission_error.is_empty() else "status counts did not match"]}
	return {"ok": true, "status": status}


func _verify_normal_smoke() -> Dictionary:
	var bindings: Dictionary = _main._airplane.get("customization_bindings", {})
	var propulsion: Dictionary = _main.session.aircraft.model.propulsion
	var stock_profile: Dictionary = StockSmoke.for_aircraft(bindings, propulsion)
	if not stock_profile.is_empty():
		_lighting_smoke_preset = StockSmoke.preset_id(bindings, propulsion)
		_lighting_smoke_profile_sha256 = _sha256_json(stock_profile)
	var evidence: Dictionary = _main._smoke_evidence()
	if _effective_lighting_smoke_mode() == "off":
		if is_instance_valid(_main._profile_smoke) or is_instance_valid(_main._smoke) or _smoke_evidence_active(evidence):
			return {"ok": false, "error": "Normal lighting-smoke=off left a smoke renderer active."}
		_lighting_smoke_evidence_start = evidence.duplicate(true)
		return {"ok": true, "evidence": evidence}
	if stock_profile.is_empty() or not _main._stock_smoke_profile:
		return {"ok": false, "error": "The selected stock aircraft has no supported production stock-smoke profile."}
	if not is_instance_valid(_main._profile_smoke) or str(evidence.get("mode", "")) != "stock" \
			or str(evidence.get("preset", "")) != _lighting_smoke_preset or bool(evidence.get("disabled", false)):
		return {"ok": false, "error": "Production stock-smoke selection did not create the requested live renderer."}
	_lighting_smoke_evidence_start = evidence.duplicate(true)
	return {"ok": true, "evidence": evidence}


static func _smoke_evidence_active(evidence: Dictionary) -> bool:
	var mode := str(evidence.get("mode", "none"))
	if mode in ["stock", "profile"]:
		return not bool(evidence.get("disabled", false)) and bool(evidence.get("requested", true))
	return mode == "legacy" and bool(evidence.get("active", false))


func _install_normal_lighting() -> Dictionary:
	if _lighting_profile_data.is_empty():
		return {"ok": false, "error": "Normal lighting capture has no validated preset profile."}
	if is_instance_valid(_main._rgb_lighting):
		return {"ok": false, "error": "Normal inherited flight already owns an RGB lighting rig; refusing duplicate installation."}
	var aircraft_root: Node3D = _main._airplane.get("root") as Node3D
	if not is_instance_valid(aircraft_root):
		return {"ok": false, "error": "Normal flight has no live stock aircraft render root."}
	var simulation: Node = _main.session.sim
	var tick_before := int(simulation.tick)
	var time_before := float(simulation.time())
	var state_before: PackedFloat64Array = simulation.state.duplicate()
	var aux_before: PackedFloat64Array = simulation.aux.duplicate()
	var rig: Node3D = AircraftLightingRig.new()
	rig.name = "AircraftLightingRig"
	_main.add_child(rig)
	_main._lighting_reacts_to_airspeed = false
	for zone: Dictionary in _lighting_profile_data.get("zones", []):
		_main._lighting_reacts_to_airspeed = _main._lighting_reacts_to_airspeed \
			or str(zone.get("reactive", {}).get("source", "none")) == "airspeed"
	var configured: Dictionary = rig.configure(aircraft_root, _lighting_profile_data)
	if not bool(configured.get("ok", false)):
		rig.queue_free()
		return {"ok": false, "error": "Normal RGB renderer refused the approved preset: " + "; ".join(PackedStringArray(configured.get("errors", [])))}
	_main._rgb_lighting = rig
	for luminous: VisualInstance3D in rig.luminous_nodes():
		luminous.layers |= Magnifier.LAYER
	_main._update_aircraft_lights(time_before)
	_lighting_profile_applied = true
	var tick_after := int(simulation.tick)
	var time_after := float(simulation.time())
	var state_after: PackedFloat64Array = simulation.state.duplicate()
	var aux_after: PackedFloat64Array = simulation.aux.duplicate()
	var state_unchanged := _packed_float64_equal(state_before, state_after)
	var aux_unchanged := _packed_float64_equal(aux_before, aux_after)
	_normal_physics_attach_guard = {
		checked = true,
		tick_before = tick_before,
		tick_after = tick_after,
		tick_unchanged = tick_before == tick_after,
		time_before_s = time_before,
		time_after_s = time_after,
		time_unchanged = time_before == time_after,
		state_unchanged = state_unchanged,
		aux_unchanged = aux_unchanged,
		passed = tick_before == tick_after and time_before == time_after and state_unchanged and aux_unchanged,
	}
	if not bool(_normal_physics_attach_guard.passed):
		return {"ok": false, "error": "Renderer-only RGB installation changed simulation tick, time, state, or auxiliary state."}
	return {"ok": true, "warnings": configured.get("warnings", []), "budget": rig.budget_info()}


func _presentation_identity(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return {}
	var identity := _profile_identity(profile)
	identity.source = "profile-file" if not _lighting_profile_input_sha256.is_empty() else "preset"
	identity.input_sha256 = _lighting_profile_input_sha256
	identity.applied = _lighting_profile_applied
	return identity


static func _profile_identity(profile: Dictionary) -> Dictionary:
	return {
		"format": str(profile.get("format", "")),
		"version": int(profile.get("version", 0)),
		"selection": str(profile.get("selection", "")),
		"preset_id": str(profile.get("preset_id", "")),
		"preset_revision": int(profile.get("preset_revision", 0)),
		"canonical_sha256": _sha256_json(profile),
	}


static func _sha256_json(value: Variant) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(JSON.stringify(value, "", true, true).to_utf8_buffer()) != OK:
		return ""
	return hashing.finish().hex_encode()


static func _packed_float64_equal(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for index: int in left.size():
		if left[index] != right[index]:
			return false
	return true


func _normal_companion_evidence() -> Dictionary:
	if _main == null or not is_instance_valid(_main):
		return {}
	var status: Dictionary = _main.companion_status()
	var config: Dictionary = _main.companion_config.duplicate(true)
	var requested := _normal_requested_companions if _normal_requested_companions >= 0 else (int(config.get("count", 0)) if bool(config.get("enabled", false)) else 0)
	var active := int(status.get("active", 0))
	var admission_error := str(status.get("error", ""))
	return {
		"configured": config,
		"requested": requested,
		"admitted": active == requested and int(status.get("requested", 0)) == requested \
			and (requested == 0 or int(status.get("airborne", 0)) == requested) \
			and int(status.get("faulted", 0)) == 0 and int(status.get("crashed", 0)) == 0 \
			and admission_error.is_empty(),
		"source_identity": status.get("profile_identity", {}).duplicate(true),
		"status": status,
	}


func _abort_live_capture(message: String, exit_code: int) -> void:
	_failure = message
	push_error(_failure)
	_write_manifest(false)
	await _teardown_live_scene()
	quit(exit_code)


func _teardown_live_scene() -> void:
	# Main's exit hooks own renderer/audio disposal. Stop the director first because
	# its process callback reads the still-live scene.
	if is_instance_valid(_director):
		_director.free()
	if is_instance_valid(_main):
		_main.queue_free()
	var teardown_error: String = await _wait_for_audio_teardown()
	if not teardown_error.is_empty():
		_failure = teardown_error if _failure.is_empty() else _failure + "\n" + teardown_error
		push_error(teardown_error)
		_mark_manifest_incomplete(teardown_error)


## Main's exit hooks stop audio; the driver must mix before main-thread playback cleanup.
func _wait_for_audio_teardown() -> String:
	var started_usec := Time.get_ticks_usec()
	var deadline_usec := started_usec + AUDIO_TEARDOWN_TIMEOUT_USEC
	while is_instance_valid(_main):
		if Time.get_ticks_usec() >= deadline_usec:
			return "Main scene did not exit before the audio teardown watchdog expired."
		await process_frame
	# Keep one post-stop baseline: fast Movie Maker frames can each be shorter
	# than the jitter tolerance. Cumulative elapsed time still exposes a new mix.
	var before := _audio_mix_age_sample()
	var waited_frames := 0
	while Time.get_ticks_usec() < deadline_usec:
		await process_frame
		waited_frames += 1
		var after := _audio_mix_age_sample()
		if audio_mix_reset_between(before, after):
			# Let a subsequent AudioServer.update release the stopped playback list.
			await process_frame
			if Time.get_ticks_usec() >= deadline_usec:
				break
			print("FLIGHT_CAPTURE_AUDIO_DRAIN frames=", waited_frames + 1,
				" wall_usec=", Time.get_ticks_usec() - started_usec)
			return ""
	return "No completed post-stop audio mix and cleanup were observed before the teardown watchdog expired."


func _audio_mix_age_sample() -> Dictionary:
	# This supported API locks the driver internally; never wrap it in AudioServer.lock().
	var query_start_usec := Time.get_ticks_usec()
	var age_usec := roundi(AudioServer.get_time_since_last_mix() * 1_000_000.0)
	var query_end_usec := Time.get_ticks_usec()
	return {"start_usec": query_start_usec, "end_usec": query_end_usec, "age_usec": age_usec}


static func audio_mix_reset_between(previous: Dictionary, current: Dictionary) -> bool:
	# A lower elapsed bound excludes query latency from apparent clock resets.
	var elapsed_lower_bound_usec := maxi(int(current.start_usec) - int(previous.end_usec), 0)
	return int(current.age_usec) + AUDIO_MIX_AGE_JITTER_USEC < int(previous.age_usec) + elapsed_lower_bound_usec


func _mark_manifest_incomplete(teardown_error: String) -> void:
	var manifest_path := _out_dir.path_join("manifest.json")
	var input_file := FileAccess.open(manifest_path, FileAccess.READ)
	if input_file == null:
		push_error("Could not read the manifest after audio teardown failure.")
		return
	var parsed: Variant = JSON.parse_string(input_file.get_as_text())
	input_file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Could not parse the manifest after audio teardown failure.")
		return
	var manifest: Dictionary = parsed
	manifest.complete = false
	var existing_error := str(manifest.get("capture_error", ""))
	manifest.capture_error = teardown_error if existing_error.is_empty() else existing_error + "\n" + teardown_error
	var output_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if output_file == null:
		push_error("Could not update the manifest after audio teardown failure.")
		return
	output_file.store_string(JSON.stringify(manifest, "\t"))
	output_file.close()


## Reuses Main's monotonic collector. This mode never invokes Movie Maker or image readback.
func _validate_performance_options() -> bool:
	# Godot strips processed engine flags from OS.get_cmdline_args(). The checked
	# runner's complete command must additionally prove absence of --fixed-fps.
	if not Engine.get_write_movie_path().is_empty() or _options.has("movie-file"):
		push_error("Real-time lighting measurement cannot use Movie Maker.")
		return false
	if not is_equal_approx(Engine.time_scale, 1.0):
		push_error("Real-time lighting measurement requires Engine.time_scale=1.")
		return false
	if _options.has("director-script") \
			or _shot not in ["lighting-pass", "lighting-pilot"] or not _options.has("lighting-preset"):
		push_error("Real-time lighting measurement requires a native display, a lighting preset (or off), and the built-in lighting-pass/pilot director.")
		return false
	if str(_options.get("lighting-quality", "standard")) not in ["low", "standard", "high"]:
		push_error("--lighting-quality must be low, standard or high.")
		return false
	var options := _options.duplicate()
	options["warmup"] = str(_options.get("warmup", "10"))
	options["t"] = str(_options.get("t", "60"))
	_performance_options = FrameSamples.options(options)
	if not _performance_options.get("ok", false):
		push_error(str(_performance_options.get("error", "Invalid frame-time options")))
		return false
	var path := str(_performance_options.path)
	var manifest_path := _out_dir.path_join("manifest.json").replace("\\", "/").simplify_path()
	var report_path := path.replace("\\", "/").simplify_path()
	if OS.get_name() == "Windows":
		manifest_path = manifest_path.to_lower()
		report_path = report_path.to_lower()
	if report_path == manifest_path:
		push_error("Frame-time report and capture manifest must have distinct paths.")
		return false
	if not path.is_absolute_path() or FileAccess.file_exists(path) or FileAccess.file_exists(_out_dir.path_join("manifest.json")):
		push_error("Real-time measurement requires a new absolute frametimes path and a fresh manifest destination.")
		return false
	if DisplayServer.get_name() == "headless":
		push_error("Real-time lighting measurement requires a native display.")
		return false
	_seconds = float(_performance_options.warmup_s) + float(_performance_options.sample_s)
	return true


func _on_frame_time_report_written(exit_code: int) -> void:
	_performance_done = true
	_performance_exit = exit_code


func _measure_realtime() -> void:
	if _performance_done:
		_failure = "Frame-time collector completed before the flight workload was initialized; increase warmup."
		push_error(_failure)
		return
	var started_usec := Time.get_ticks_usec()
	var last_progress_usec := started_usec
	var next_budget_usec := started_usec
	var last_tick := int(_main.session.sim.tick)
	# Unlike a 60 Hz movie, an uncapped renderer may present between two 240 Hz ticks.
	# Repeated ticks are allowed only within a short progress window; pauses still fail immediately.
	while not _performance_done:
		await process_frame
		await RenderingServer.frame_post_draw
		var now_usec := Time.get_ticks_usec()
		var sim: Node = _main.session.sim
		_performance_elapsed_s = float(now_usec - started_usec) / 1000000.0
		if sim.paused or not sim.fault_reason.is_empty() or not _main.session.crash.is_empty() \
				or sim.tick < last_tick or (sim.tick == last_tick and now_usec - last_progress_usec > 250000):
			_failure = "Real-time lighting measurement interrupted: tick=%d paused=%s fault=%s holds=%s" % [
				sim.tick, sim.paused, sim.fault_reason, str(_main.session.holds)]
		elif root.get_visible_rect().size != Vector2(1920, 1080):
			_failure = "Real-time lighting measurement requires an actual 1920x1080 viewport."
		elif _performance_elapsed_s > _seconds + 10.0:
			_failure = "Frame-time collector did not complete within its bounded wall-time window."
		if _failure.is_empty() and _lighting_flight == "normal":
			var admission := _validate_companion_admission("presented frame")
			if not admission.ok:
				_failure = str(admission.error)
		if not _failure.is_empty():
			push_error(_failure)
			if _main._frametimes_active:
				_main._finish_frame_time(1)
			break
		if sim.tick > last_tick:
			last_progress_usec = now_usec
		last_tick = sim.tick
		_frame_count += 1
		if _workload_audit != null:
			var audit_started_usec := Time.get_ticks_usec()
			var audit_rig: Node = _main.get("_rgb_lighting")
			if not is_instance_valid(audit_rig) or not _workload_audit.record(audit_rig.budget_info(), int(sim.tick), _frame_count - 1, _performance_elapsed_s):
				_failure = "Lighting workload audit failed: " + str(_workload_audit.report().get("failure", "missing rig"))
				push_error(_failure)
				if _main._frametimes_active:
					_main._finish_frame_time(1)
				break
			_workload_audit_usec += Time.get_ticks_usec() - audit_started_usec
		# One bounded budget sample per wall second; Main owns all per-frame timing metrics.
		if now_usec >= next_budget_usec:
			var rig: Node = _main.get("_rgb_lighting")
			_performance_budget_samples.append({"wall_s": _performance_elapsed_s, "tick": sim.tick,
				"budget": rig.budget_info() if is_instance_valid(rig) else {}, "world_exposure": Exposure.last,
				"smoke": _main._smoke_evidence()})
			next_budget_usec = now_usec + 1000000
	if _performance_exit != OK and _failure.is_empty():
		_failure = "Frame-time collector failed with exit code %d." % _performance_exit
		push_error(_failure)
	if not FileAccess.file_exists(str(_performance_options.path)) and _failure.is_empty():
		_failure = "Frame-time collector produced no report."
		push_error(_failure)


func _capture_crash_report() -> void:
	var preroll := 0
	while _main.session.crash.is_empty() and preroll < int(MAX_CRASH_PREROLL_S * _fps):
		await process_frame
		await RenderingServer.frame_post_draw
		preroll += 1
	if _main.session.crash.is_empty():
		_failure = "No physical crash occurred within %.1f s; no report clip was captured." % MAX_CRASH_PREROLL_S
		push_error(_failure)
		return
	_impact_preroll_frames = preroll
	# The movie writer runs from process launch. Retain a 2s approach plus 6s aftermath in the source,
	# so the editor can cut a truthful 8s beat around this actual impact. Restart is the final 2s.
	await _capture_frames(CRASH_CLIP_POST_IMPACT_FRAMES, preroll)


func _capture_frames(count: int, preroll: int) -> void:
	var previous_lighting_tick := -1
	var lighting_capture_requested := _lighting_capture_requested()
	for index: int in range(count):
		if _shot == "crash" and index == 60:
			# Let the viewer see the actual impact and wreck for one second before revealing the native report.
			_main._accident_report.visible = true
			_report_layer_reveal_frame = index
			if not _main.controller_action("details"):
				_failure = "Native accident report details action was unavailable at the scheduled reveal frame."
				push_error(_failure)
				return
			_details_frame = index
		if _shot == "crash" and index == CRASH_RESTART_AFTER_IMPACT_FRAMES:
			_preserved_report = _main._accident_incident.report.duplicate(true) if _main._accident_incident != null else {}
			_preserved_crash = _main.session.crash.duplicate(true)
			_preserved_prop_strike = _main.session.prop_strike.duplicate(true)
			_restart_tick_before = int(_main.session.sim.tick)
			_restart_frame = index
			_restart_movie_frame = int(_options.get("writer-lead-frames", 3)) + preroll + index
			_restart_result = bool(_main.controller_action("restart"))
			if not _restart_result:
				_failure = "Native accident report did not accept the restart action after the incident snapshot."
				push_error(_failure)
				return
			_restart_tick_after = int(_main.session.sim.tick)
			_director.resume_after_report_restart()
		await process_frame
		await RenderingServer.frame_post_draw
		if lighting_capture_requested:
			var sim: Node = _main.session.sim
			if sim.paused or not sim.fault_reason.is_empty() or not _main.session.crash.is_empty() \
					or (previous_lighting_tick >= 0 and sim.tick <= previous_lighting_tick):
				_failure = "Lighting capture interrupted: tick=%d paused=%s fault=%s holds=%s" % [
					sim.tick, sim.paused, sim.fault_reason, str(_main.session.holds)]
				push_error(_failure)
				return
			previous_lighting_tick = sim.tick
		var director_record_count_before := _director_frame_record_count() if lighting_capture_requested else -1
		_director.record_presented_frame(index, preroll)
		if lighting_capture_requested and not _ensure_lighting_frame_evidence(index, director_record_count_before):
			return
		_frame_count += 1
		if not _save_images:
			if index % _fps == 0:
				print("FLIGHT_CAPTURE_FRAME ", index, " tick=", _main.session.sim.tick)
			continue
		if index % _sample_every != 0 and index != count - 1:
			continue
		var image: Image = root.get_texture().get_image()
		image = ViewportColor.display_image(image, root.use_hdr_2d)
		if image.get_width() != _width or image.get_height() != _height:
			_failure = "Rendered frame size was %dx%d, expected %dx%d" % [image.get_width(), image.get_height(), _width, _height]
			push_error(_failure)
			return
		var frame_path := _out_dir.path_join("frame_%05d.png" % index)
		var save_error := image.save_png(frame_path)
		if save_error != OK:
			_failure = "Could not save frame %s: %s" % [frame_path, error_string(save_error)]
			push_error(_failure)
			return
		_image_count += 1
		if index % _fps == 0:
			print("FLIGHT_CAPTURE_FRAME ", index, " tick=", _main.session.sim.tick)


func _lighting_capture_requested() -> bool:
	return _options.has("lighting-preset") or _options.has("lighting-profile") or _shot in ["lighting-pass", "lighting-pilot"]


func _director_frame_record_count() -> int:
	if not is_instance_valid(_director):
		return -1
	var records: Variant = _director.get("frame_records")
	return records.size() if typeof(records) == TYPE_ARRAY else -1


func _ensure_lighting_frame_evidence(frame_index: int, record_count_before: int) -> bool:
	if _lighting_flight == "normal":
		var admission := _validate_companion_admission("presented frame")
		if not admission.ok:
			return _lighting_capture_failure(str(admission.error))
	if record_count_before < 0:
		return _lighting_capture_failure("Lighting capture director has no readable frame_records array.")
	var records: Variant = _director.get("frame_records")
	if typeof(records) != TYPE_ARRAY or records.size() != record_count_before + 1:
		return _lighting_capture_failure("Lighting capture director did not append exactly one record for frame %d." % frame_index)
	var record_index: int = records.size() - 1
	var record_value: Variant = records[record_index]
	if typeof(record_value) != TYPE_DICTIONARY:
		return _lighting_capture_failure("Lighting capture director's frame %d record is not a dictionary." % frame_index)
	var record: Dictionary = record_value
	if typeof(record.get("frame")) != TYPE_INT or int(record.frame) != frame_index:
		return _lighting_capture_failure("Lighting capture director's last record does not match frame %d." % frame_index)
	var current_tick: int = int(_main.session.sim.tick)
	if typeof(record.get("sim_tick")) != TYPE_INT or int(record.sim_tick) != current_tick:
		return _lighting_capture_failure("Lighting capture director's frame %d record does not match live tick %d." % [frame_index, current_tick])
	var lighting: Variant = _main.get("_rgb_lighting")
	if not is_instance_valid(lighting) or not lighting.has_method("budget_info"):
		return _lighting_capture_failure("Lighting capture has no live RGB lighting budget source.")
	var budget_value: Variant = lighting.call("budget_info")
	if typeof(budget_value) != TYPE_DICTIONARY or budget_value.is_empty():
		return _lighting_capture_failure("Lighting capture's live RGB budget information is missing or invalid.")
	var actual_exposure: float = Exposure.last
	if not is_finite(actual_exposure):
		return _lighting_capture_failure("Lighting capture's live world exposure is not finite.")
	if record.has("aircraft_lighting"):
		if typeof(record.aircraft_lighting) != TYPE_DICTIONARY or record.aircraft_lighting != budget_value:
			return _lighting_capture_failure("Frame %d records aircraft_lighting inconsistent with the live RGB budget." % frame_index)
	else:
		record["aircraft_lighting"] = budget_value.duplicate(true)
	if record.has("world_exposure"):
		var recorded_exposure: Variant = record.world_exposure
		if typeof(recorded_exposure) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(recorded_exposure)) \
				or float(recorded_exposure) != actual_exposure:
			return _lighting_capture_failure("Frame %d records world_exposure inconsistent with the live world exposure." % frame_index)
	else:
		record["world_exposure"] = actual_exposure
	# The director's older `smoke` field describes legacy exhaust only. Preserve it,
	# and expose the production profile renderer separately for RGB smoke workloads.
	record["smoke_effects"] = _main._smoke_evidence()
	records[record_index] = record
	_director.set("frame_records", records)
	return true


func _lighting_capture_failure(message: String) -> bool:
	_failure = message
	push_error(_failure)
	return false


func _write_manifest(ok: bool) -> void:
	var workload_audit_script: Script = WorkloadAudit
	var session: Node = _main.session if _main != null else null
	var current_report: Dictionary = _main._accident_incident.report.duplicate(true) if _main != null and _main._accident_incident != null else {}
	var report: Dictionary = _preserved_report if not _preserved_report.is_empty() else current_report
	var archive_path := str(_main.accident_archive_path) if _main != null else ""
	var lead_frames := int(_options.get("writer-lead-frames", 3))
	var impact_movie_frame := lead_frames + _impact_preroll_frames if _impact_preroll_frames >= 0 else -1
	var clip_start_frame := maxi(0, impact_movie_frame - CRASH_CLIP_APPROACH_FRAMES) if impact_movie_frame >= 0 else -1
	var manifest := {
		format = "openrc-lighting-performance-capture v1" if _realtime else "openrc-trailer-flight-capture v1",
		measurement_mode = "realtime-director-flight" if _realtime else "offline-movie",
		complete = ok and _failure.is_empty(),
		shot = _shot,
		aircraft_id = str(_main.aircraft_id) if _main != null else "",
		landscape = {"requested": str(_options.get("landscape", Landscapes.DEFAULT_ID)),
			"resolved": str(_main.landscape_id) if _main != null else "",
			"field_path": str(_main.field_path) if _main != null else "",
			"field_sha256": FileAccess.get_sha256(_main.field_path) if _main != null and FileAccess.file_exists(_main.field_path) else ""},
		width = _width,
		height = _height,
		fps = 0 if _realtime else _fps,
		frames = _frame_count,
		images_saved = _image_count,
		image_sample_every = _sample_every,
		image_sequence_enabled = _save_images,
		movie_file = str(_options.get("movie-file", "")),
		movie_writer_lead_frames_expected = lead_frames,
		movie_writer_cleanup_frames_expected = -1,
		movie_writer_cleanup_frame_policy = "Variable: observe post-stop audio mix and cleanup; measure the encoded file's actual frame count.",
		movie_impact_frame_estimate = impact_movie_frame,
		movie_eight_second_clip_start_frame_estimate = clip_start_frame,
		movie_eight_second_clip_end_frame_estimate_exclusive = impact_movie_frame + CRASH_CLIP_POST_IMPACT_FRAMES if impact_movie_frame >= 0 else -1,
		movie_clip_approach_available_seconds_estimate = float(impact_movie_frame - clip_start_frame) / float(_fps) if impact_movie_frame >= 0 else 0.0,
		movie_clip_approach_frames_target = CRASH_CLIP_APPROACH_FRAMES,
		movie_clip_post_impact_frames_target = CRASH_CLIP_POST_IMPACT_FRAMES,
		seconds = _performance_elapsed_s if _realtime else float(_frame_count) / float(_fps),
		engine = Engine.get_version_info().string,
		fixed_fps_argument_required = 0 if _realtime else 60,
		performance = {"enabled": _realtime, "report_path": str(_performance_options.get("path", "")),
			"report_sha256": FileAccess.get_sha256(str(_performance_options.path)) if _realtime and FileAccess.file_exists(str(_performance_options.path)) else "",
			"collector_exit": _performance_exit, "requested": _performance_options,
			"budget_samples": _performance_budget_samples, "tick_recording": not _realtime,
			"quality": LightingPolicy.quality, "reduced_flashes": LightingPolicy.reduced_flashes,
			"show_vfx": LightingPolicy.show_vfx, "engine_time_scale": Engine.time_scale,
			"movie_writer_path": Engine.get_write_movie_path(),
			"qualification": "ineligible: per-frame workload audit adds observer cost" if _workload_audit != null else "unverified: requires matching command receipt, uncontended repeated runs and acceptance review",
			"workload_audit": _workload_audit.report() if _workload_audit != null else {"enabled": false},
			"workload_audit_observer_usec": _workload_audit_usec,
			"workload_audit_source_sha256": FileAccess.get_sha256(workload_audit_script.resource_path),
			"timing_scope": "Instrumented Main FrameSamples intervals; sample duration is report.actual_sample_s. Manifest seconds covers this harness loop, including warmup.",
			"command_validation": "Qualification requires the checked runner command with no --fixed-fps; Godot removes processed flags from OS.get_cmdline_args()."},
		physics_ticks_per_second = Engine.physics_ticks_per_second,
		physical_flight = session != null and session.physics_enabled and session.is_flyable(),
		simulation_paused = session.sim.paused if session != null else false,
		simulation_fault = session.sim.fault_reason if session != null else "",
		session_holds = session.holds.duplicate(true) if session != null else {},
		start_choice = str(session.start_choice) if session != null else "",
		soft_hull_contacts = bool(session.soft_hull_contacts) if session != null else false,
		sky_config = _main.sky_config.duplicate(true) if _main != null else {},
		world_conditions = WorldConditions.resolve(),
		field_world_lighting = bool(_main._field_world_lighting) if _main != null else false,
		lighting_config = _main.lighting_config.duplicate(true) if _main != null else {},
		lighting_flight = _lighting_flight,
		lighting_preset = str(_options.get("lighting-preset", "profile-file" if _options.has("lighting-profile") else "inherit")),
		lighting_profile_input_path = _lighting_profile_input_path,
		lighting_profile_input_sha256 = _lighting_profile_input_sha256,
		lighting_profile_identity = _presentation_identity(_lighting_profile_data),
		lighting_profile_runtime = _main._rgb_lighting.budget_info() \
			if _main != null and is_instance_valid(_main._rgb_lighting) else {},
		lighting_attach_physics_guard = _normal_physics_attach_guard.duplicate(true),
		lighting_smoke = {"requested": str(_options.get("lighting-smoke", "off")),
			"effective": _effective_lighting_smoke_mode(),
			"request_was_explicit": _options.has("lighting-smoke"),
			"preset": _lighting_smoke_preset,
			"profile_sha256": _lighting_smoke_profile_sha256,
			"at_start": _lighting_smoke_evidence_start.duplicate(true),
			"at_report": _main._smoke_evidence() if _main != null else {}},
		flight_companions = _normal_companion_evidence(),
		capture_script_sha256 = FileAccess.get_sha256(get_script().resource_path),
		director_script_sha256 = FileAccess.get_sha256(_director.get_script().resource_path) if is_instance_valid(_director) else "",
		main_source_sha256 = FileAccess.get_sha256("res://main.gd"),
		customization_registry_sha256 = FileAccess.get_sha256("res://data/aircraft_customization.json"),
		camera_preferences = _main.camera_preferences.duplicate(true) if _main != null else {},
		root_msaa_3d = root.msaa_3d,
		root_hdr_2d = root.use_hdr_2d,
		image_color_space = "srgb",
		workshop_identity = session.workshop_identity.duplicate(true) if session != null else {},
		workshop_presentation_identity = session.workshop_presentation_identity.duplicate(true) if session != null else {},
		director_script = str(_options.get("director-script", "tools/trailer/flight_director.gd")),
		weather_config = session.weather_configuration() if session != null else {},
		flight_tick_end = int(session.sim.tick) if session != null else -1,
		flight_time_end_s = float(session.sim.time()) if session != null else 0.0,
		crash = _preserved_crash if not _preserved_crash.is_empty() else (session.crash.duplicate(true) if session != null and not session.crash.is_empty() else {}),
		prop_strike = _preserved_prop_strike if not _preserved_prop_strike.is_empty() else (session.prop_strike.duplicate(true) if session != null else {}),
		accident_report = report,
		incident_snapshot_preserved_before_restart = not _preserved_report.is_empty(),
		report_canvas_layer_hidden_before_impact = _report_layer_hidden_before_impact,
		report_canvas_layer_reveal_frame_after_impact = _report_layer_reveal_frame,
		native_report_details_expanded_frame = _details_frame,
		restart = {
			action = "native_accident_report_restart",
			accepted = _restart_result,
			capture_frame = _restart_frame,
			movie_frame_estimate = _restart_movie_frame,
			tick_before = _restart_tick_before,
			tick_immediately_after_reset = _restart_tick_after,
		},
		accident_archive_path = archive_path,
		capture_error = _failure,
		frame_records = _director.frame_records if _director != null else [],
		physics_ticks = _director.tick_records if _director != null else [],
	}
	var file := FileAccess.open(_out_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write capture manifest")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("FLIGHT_CAPTURE_MANIFEST ", _out_dir.path_join("manifest.json"))


static func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var options := {}
	for arg: String in arguments:
		if not arg.begins_with("--"):
			continue
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
		else:
			options[pair[0]] = true
	return options


static func validate_lighting_profile_options(options: Dictionary) -> Dictionary:
	var lighting_flight := str(options.get("lighting-flight", "workshop"))
	if lighting_flight not in ["workshop", "normal"]:
		return {"ok": false, "error": "--lighting-flight must be workshop or normal."}
	if str(options.get("lighting-workload-audit", "off")) not in ["off", "on"]:
		return {"ok": false, "error": "--lighting-workload-audit must be off or on."}
	if options.has("lighting-workload-audit") and not options.has("frametimes"):
		return {"ok": false, "error": "--lighting-workload-audit requires the real-time --frametimes route."}
	if options.has("landscape") and (typeof(options.landscape) != TYPE_STRING or not Landscapes.has(options.landscape)):
		return {"ok": false, "error": "--landscape must name a registered landscape: " + ", ".join(Landscapes.ids())}
	if lighting_flight == "workshop":
		for companion_option: String in ["companions", "companions-seed", "companions-record"]:
			if options.has(companion_option):
				return {"ok": false, "error": "This capture route does not admit flight companions; a supplied companion option cannot be ignored as a full-scene workload."}
	else:
		if options.has("companions-record"):
			return {"ok": false, "error": "Companion recording is not supported by the lighting workload route; use the dedicated companion recorder separately."}
		if options.has("lighting-profile"):
			return {"ok": false, "error": "--lighting-flight=normal accepts validated presets only; --lighting-profile requires the Workshop trial route."}
		if not options.has("lighting-preset"):
			return {"ok": false, "error": "--lighting-flight=normal requires --lighting-preset=<id>."}
		var preset_id := str(options.get("lighting-preset", ""))
		if preset_id != "off" and (preset_id == "custom" or LightingProfile.preset(preset_id).is_empty()):
			return {"ok": false, "error": "Normal lighting flight requires an approved immutable preset id or off."}
	if str(options.get("lighting-smoke", "off")) not in ["off", "stock"]:
		return {"ok": false, "error": "--lighting-smoke must be off or stock."}
	if options.has("lighting-smoke") and not options.has("lighting-preset") and not options.has("lighting-profile"):
		return {"ok": false, "error": "--lighting-smoke requires an explicit lighting preset or profile."}
	if options.has("lighting-profile") and options.has("lighting-preset"):
		return {"ok": false, "error": "Use either --lighting-profile or --lighting-preset, not both."}
	if options.has("lighting-profile") and options.has("frametimes"):
		return {"ok": false, "error": "--lighting-profile is supported for offline captures only, not --frametimes."}
	if options.has("lighting-profile") and str(options.get("lighting-profile", "")).strip_edges().is_empty():
		return {"ok": false, "error": "--lighting-profile requires an absolute JSON file path."}
	return {"ok": true, "error": ""}


## Uses stock authored outlets through the ordinary frozen Workshop profile, without a second smoke system.
static func freeze_lighting_trial(aircraft_id: String, lighting: Dictionary, smoke_mode := "off") -> Dictionary:
	if smoke_mode not in ["off", "stock"]:
		return {"ok": false, "errors": ["--lighting-smoke must be off or stock."]}
	var described := Customization.describe(aircraft_id)
	if lighting.is_empty() or not bool(described.get("ok", false)):
		return {"ok": false, "errors": ["Capture requires validated lighting and an admitted aircraft companion."]}
	var profile := Presentation.defaults(described.bindings)
	profile.lighting = lighting.duplicate(true)
	var payload := {"base_id": aircraft_id,
		"base_bytes": FileAccess.get_file_as_bytes(Catalog.entry(aircraft_id).data),
		"recipe": {}, "presentation_profile": profile}
	var frozen := Trial.freeze(payload)
	if not bool(frozen.get("ok", false)):
		return frozen
	if smoke_mode == "off":
		return {"ok": true, "trial": frozen, "smoke_preset": "", "smoke_profile_sha256": ""}
	var propulsion: Dictionary = frozen.data.model.propulsion
	var stock := StockSmoke.for_aircraft(described.bindings, propulsion)
	if stock.is_empty() or stock.get("smoke", []).is_empty():
		return {"ok": false, "errors": ["This aircraft has no supported stock smoke profile; smoke workload was not substituted."]}
	profile.smoke = stock.smoke.duplicate(true)
	profile.visual_seed = stock.visual_seed
	payload.presentation_profile = profile
	var with_smoke := Trial.freeze(payload)
	if not bool(with_smoke.get("ok", false)):
		return with_smoke
	if with_smoke.identity != frozen.identity or with_smoke.data != frozen.data:
		return {"ok": false, "errors": ["Adding stock smoke changed the physical trial; capture refused."]}
	return {"ok": true, "trial": with_smoke, "smoke_preset": StockSmoke.preset_id(described.bindings, propulsion),
		"smoke_profile_sha256": _sha256_json(stock)}


static func read_lighting_profile_file(path: String) -> Dictionary:
	if path.is_empty() or not path.is_absolute_path():
		return {"ok": false, "error": "--lighting-profile must be an absolute path."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "lighting profile file could not be opened."}
	var byte_count := file.get_length()
	if byte_count <= 0:
		file.close()
		return {"ok": false, "error": "lighting profile file is empty."}
	if byte_count > Presentation.LightingProfile.MAX_PROFILE_BYTES:
		file.close()
		return {"ok": false, "error": "lighting profile file exceeds %d bytes." % Presentation.LightingProfile.MAX_PROFILE_BYTES}
	var bytes := file.get_buffer(byte_count)
	file.close()
	if bytes.size() != byte_count:
		return {"ok": false, "error": "lighting profile file could not be read completely."}
	var source := bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes:
		return {"ok": false, "error": "lighting profile file is not valid UTF-8."}
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return {"ok": false, "error": "lighting profile JSON is invalid: %s" % parser.get_error_message()}
	var checked: Dictionary = Presentation.LightingProfile.validate(parser.data)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "error": "lighting profile is invalid: %s" % "; ".join(PackedStringArray(checked.get("errors", [])))}
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return {"ok": false, "error": "lighting profile input hash could not be computed."}
	return {"ok": true, "profile": checked.profile, "sha256": hashing.finish().hex_encode()}


static func lighting_profile_collides_with_manifest(profile_path: String, out_dir: String) -> bool:
	var input_path := profile_path.replace("\\", "/").simplify_path()
	var manifest_path := out_dir.path_join("manifest.json").replace("\\", "/").simplify_path()
	if OS.get_name() == "Windows":
		input_path = input_path.to_lower()
		manifest_path = manifest_path.to_lower()
	return input_path == manifest_path
