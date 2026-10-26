extends SceneTree

const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const Patterns := preload("res://render/lighting/lighting_patterns.gd")
const LightingPolicy := preload("res://render/lighting/lighting_policy.gd")

const PRESENTED_FPS: Array[int] = [30, 60, 144]
const RUN_SECONDS := 24.0
const SEQUENCE_CYCLE_SECONDS := 12.0
const LONG_CLOCK_SECONDS := 864000.125
const PHASE_TOLERANCE := 1e-9

class ScriptClock:
	extends RefCounted
	var seconds := 0.0

	func set_frame(frame: int, fps: int) -> float:
		seconds = float(frame) / float(fps)
		return seconds

	func set_seconds(value: float) -> float:
		seconds = value
		return seconds


var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var profile := _accepted_festival_profile()
	_check("Festival timing profile validates after shortening each cue", not profile.is_empty())
	if profile.is_empty():
		_finish()
		return
	_check("accepted sequence contains four cues in a 12-second cycle", _sequence_seconds(profile) == SEQUENCE_CYCLE_SECONDS)
	LightingPolicy.apply({
		"aircraft_lighting_quality": "high",
		"aircraft_lighting_reduced_flashes": false,
		"aircraft_lighting_show_vfx": false,
	})
	var rates: Array[Dictionary] = []
	for fps: int in PRESENTED_FPS:
		rates.append(await _run_rate(fps, profile))
	var valid := rates.size() == PRESENTED_FPS.size()
	for result: Dictionary in rates:
		valid = valid and bool(result.get("ok", false))
	_check("real rig produced complete logical samples at 30, 60, and 144 FPS", valid)
	if valid:
		for index in range(1, rates.size()):
			_check("%d FPS shader cue and phase state matches 30 FPS at every common half-second timestamp" % rates[index].fps,
				_same_samples(rates[0].samples, rates[index].samples))
			_check("%d FPS reaches the same bounded long-clock state" % rates[index].fps,
				_same_sample(rates[0].long_sample, rates[index].long_sample))
		_check("two complete sequence cycles and every cue were sampled", _saw_two_cycles_and_all_cues(rates[0].samples))
	print("FW-RGB-05 lighting frame rates: %d checks, %d failures (%d simulated seconds per rate)" % [
		_checks, _failures, int(RUN_SECONDS)])
	quit(1 if _failures > 0 else 0)


func _run_rate(fps: int, source_profile: Dictionary) -> Dictionary:
	var stage := Node3D.new()
	stage.name = "LightingFrameRate_%d" % fps
	root.add_child(stage)
	await process_frame
	var aircraft := _make_aircraft(stage)
	var rig := Rig.new()
	rig.name = "AircraftLightingRig"
	stage.add_child(rig)
	var configure: Dictionary = rig.configure(aircraft, source_profile.duplicate(true))
	_check("%d FPS real lighting rig accepts synthetic aircraft geometry" % fps, bool(configure.get("ok", false)))
	if not bool(configure.get("ok", false)):
		stage.free()
		return {"fps": fps, "ok": false}
	var binding := _strip_binding(rig, "strip_left")
	var material: ShaderMaterial = binding.get("material") as ShaderMaterial
	_check("%d FPS uses the real Festival strip shader binding" % fps,
		not binding.is_empty() and is_instance_valid(material) and material.shader == load("res://render/lighting/rgb_strip.gdshader"))
	if binding.is_empty() or not is_instance_valid(material):
		rig.dispose()
		stage.free()
		return {"fps": fps, "ok": false}

	var clock := ScriptClock.new()
	var samples: Array[Dictionary] = []
	var expected_matches := true
	var frames_per_sample := fps / 2
	var final_frame := int(RUN_SECONDS * float(fps))
	for frame in range(final_frame + 1):
		var seconds := clock.set_frame(frame, fps)
		rig.advance(seconds, {"effects_allowed": false, "distance_m": 100.0, "exposure": 10000.0, "maneuver": 0.0, "throttle": 0.5})
		if frame % frames_per_sample == 0:
			var sample := _capture_strip_state(rig, binding, material, seconds, int(frame / frames_per_sample))
			expected_matches = expected_matches and bool(sample.uniforms_match)
			samples.append(sample)
	_check("%d FPS actual pattern settings, extras, palette, phase, and signature match the logical Festival cue at all common samples" % fps,
		expected_matches and samples.size() == int(RUN_SECONDS * 2.0) + 1)

	# A paused render may execute at any wall-frame rate while its simulation presentation clock holds.
	var held_clock := clock.seconds
	var held_sample := _capture_strip_state(rig, binding, material, held_clock, -1)
	var simulated_render_elapsed := 0.0
	var pause_stable := true
	for render_delta: float in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0, 0.2, 0.0001]:
		simulated_render_elapsed += render_delta
		rig.advance(clock.seconds, {"effects_allowed": false, "distance_m": 100.0, "exposure": 10000.0, "maneuver": 0.0, "throttle": 0.5})
		var current := _capture_strip_state(rig, binding, material, held_clock, -1)
		pause_stable = pause_stable and _same_sample(held_sample, current)
	_check("%d FPS held scripted clock keeps shader cues and phase fixed across render deltas" % fps,
		pause_stable and simulated_render_elapsed > 0.0)

	clock.set_seconds(LONG_CLOCK_SECONDS)
	rig.advance(clock.seconds, {"effects_allowed": false, "distance_m": 100.0, "exposure": 10000.0, "maneuver": 0.0, "throttle": 0.5})
	var long_sample := _capture_strip_state(rig, binding, material, clock.seconds, -1)
	_check("%d FPS ten-day scripted clock keeps shader phase finite and bounded" % fps,
		is_finite(float(long_sample.phase)) and float(long_sample.phase) >= 0.0 and float(long_sample.phase) < 1.0)
	_check("%d FPS ten-day clock selects a valid wrapped cue" % fps,
		int(long_sample.sequence_cycle) >= 0 and int(long_sample.cue_index) >= 0 and int(long_sample.cue_index) < source_profile.sequence.size())
	rig.dispose()
	stage.free()
	return {"fps": fps, "ok": expected_matches and pause_stable and samples.size() == int(RUN_SECONDS * 2.0) + 1,
		"samples": samples, "long_sample": long_sample}


func _accepted_festival_profile() -> Dictionary:
	var candidate: Dictionary = Profile.preset("festival")
	if candidate.is_empty():
		return {}
	for index in candidate.sequence.size():
		var cue: Dictionary = candidate.sequence[index]
		cue.duration_ticks = 720 # Three seconds per cue, 12 seconds per complete cycle.
		candidate.sequence[index] = cue
	var checked: Dictionary = Profile.validate(candidate)
	return checked.profile if bool(checked.get("ok", false)) else {}


func _sequence_seconds(profile: Dictionary) -> float:
	var ticks := 0
	for cue: Dictionary in profile.get("sequence", []):
		ticks += int(cue.get("duration_ticks", 0))
	return float(ticks) / Patterns.TICKS_PER_SECOND


func _make_aircraft(parent: Node3D) -> Node3D:
	var aircraft := Node3D.new()
	aircraft.name = "SyntheticLightingAircraft"
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.9)
	body.mesh = box
	aircraft.add_child(body)
	parent.add_child(aircraft)
	return aircraft


func _strip_binding(rig: Node, zone_id: String) -> Dictionary:
	for binding: Dictionary in rig._materials:
		if str(binding.get("kind", "")) == "strip" and str(binding.get("zone_id", "")) == zone_id:
			return binding
	return {}


func _capture_strip_state(rig: Node, binding: Dictionary, material: ShaderMaterial, seconds: float, half_index: int) -> Dictionary:
	var resolved: Dictionary = Patterns.resolve(binding.get("pattern", {}), seconds, rig._profile.get("sequence", []), str(binding.get("zone_id", "")))
	var expected: Dictionary = Patterns.uniforms(resolved.pattern)
	var pattern_settings: Vector4 = material.get_shader_parameter("pattern_settings")
	var pattern_extras: Vector4 = material.get_shader_parameter("pattern_extras")
	var palette: PackedVector4Array = material.get_shader_parameter("palette")
	var phase := float(material.get_shader_parameter("pattern_phase"))
	var uniform_match: bool = pattern_settings == expected.pattern_settings \
		and pattern_extras == expected.pattern_extras \
		and palette == expected.palette \
		and absf(phase - float(resolved.phase)) <= PHASE_TOLERANCE \
		and str(binding.get("pattern_signature", "")) == JSON.stringify(resolved.pattern)
	return {
		"half_index": half_index,
		"seconds": seconds,
		"cue_index": int(resolved.cue_index),
		"sequence_cycle": int(resolved.sequence_cycle),
		"cue_id": str(resolved.get("cue", {}).get("id", "")),
		"pattern_id": str(resolved.pattern.get("id", "")),
		"pattern_settings": pattern_settings,
		"pattern_extras": pattern_extras,
		"palette": palette,
		"phase": phase,
		"uniforms_match": uniform_match,
	}


func _same_samples(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if not _same_sample(first[index], second[index]):
			return false
	return true


func _same_sample(first: Dictionary, second: Dictionary) -> bool:
	return int(first.get("half_index", -2)) == int(second.get("half_index", -3)) \
		and absf(float(first.get("seconds", 0.0)) - float(second.get("seconds", 0.0))) <= PHASE_TOLERANCE \
		and int(first.get("cue_index", -2)) == int(second.get("cue_index", -3)) \
		and int(first.get("sequence_cycle", -2)) == int(second.get("sequence_cycle", -3)) \
		and str(first.get("cue_id", "")) == str(second.get("cue_id", "")) \
		and str(first.get("pattern_id", "")) == str(second.get("pattern_id", "")) \
		and first.get("pattern_settings") == second.get("pattern_settings") \
		and first.get("pattern_extras") == second.get("pattern_extras") \
		and first.get("palette") == second.get("palette") \
		and absf(float(first.get("phase", 0.0)) - float(second.get("phase", 0.0))) <= PHASE_TOLERANCE


func _saw_two_cycles_and_all_cues(samples: Array) -> bool:
	var seen := {}
	var sequence := {}
	for sample: Dictionary in samples:
		var cycle := int(sample.sequence_cycle)
		var cue := int(sample.cue_index)
		seen[cycle] = true
		if cycle < 2:
			sequence["%d:%d" % [cycle, cue]] = true
	return seen.has(0) and seen.has(1) and sequence.size() == 8 \
		and int(samples[24].sequence_cycle) == 1 and int(samples[24].cue_index) == 0 \
		and int(samples[48].sequence_cycle) == 2 and int(samples[48].cue_index) == 0


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL " + label)


func _finish() -> void:
	print("FW-RGB-05 lighting frame rates: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
