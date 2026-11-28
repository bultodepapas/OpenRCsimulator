extends SceneTree
## NK-9a: the statistics detector with its speed window in the native kernel equals the GDScript detector. Real
## accepted-tick samples (Corsair, glow Stik 61FX and electric Stik 6S climbing, turning and diving) are fed, with
## injected speed spikes, position jumps, invalid and non-float values, incident and ground-contact flags, speeds over
## the cap and tick gaps, to a native and a reference detector. After every sample their events, snapshots and flight
## records are byte-identical. Mid-stream snapshots restore into fresh detectors: a canonical one keeps the native
## window, a JSON round trip (sorted keys) keeps the GDScript one, and both continue equal. Skips (passes) without the
## verified library.

const Session := preload("res://sim/flight_session.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
const Detector := preload("res://statistics/detector.gd")

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)


func _samples(path: String, id: String) -> Array:
	var s: Node = Session.new()
	s.input_enabled = false
	s.crash_auto_restart = false
	s.cost_observations_enabled = true
	s.setup_stage_backend("native")
	s.setup(path, id)
	root.add_child(s)
	s.set_process(false)
	s.set_physics_process(false)
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	var out: Array = []
	var adapter: RefCounted = Adapter.new()
	adapter.configure(s, id, func(sample: Dictionary) -> void: out.append(sample))
	adapter.attach()
	for i: int in 3600:
		s.sim.inputs[3] = [0.9, 0.6, 1.0, 0.3][(i / 600) % 4]
		s.sim.inputs[1] = [0.08, 0.0, -0.15, 0.2][(i / 450) % 4]
		s.sim.inputs[0] = 0.3 if (i / 300) % 5 == 2 else 0.0
		s.sim.step()
	adapter.detach()
	var profile: Dictionary = adapter.profile
	s.free()
	return [out, profile]


## A copy of the stream with faults injected at seeded places.
func _perturbed(stream: Array) -> Array:
	var out: Array = []
	var gap := 0
	for i: int in stream.size():
		var sample: Dictionary = stream[i].duplicate(true)
		if i == stream.size() - 200:
			gap += 3 # one tick gap near the end: the detector marks a lasting discontinuity
		sample.tick = int(sample.tick) + gap
		# Faults only once the flight has started; contact flags rarely, so the window keeps refilling between them.
		var fault: int = _rng.randi_range(0, 39) if i >= 1200 else -1
		if fault in [6, 7] and _rng.randi_range(0, 9) != 0:
			fault = -1
		match fault:
			0: sample.tas = float(sample.tas) + 40.0 # acceleration spike
			1: sample.position = PackedFloat64Array([sample.position[0] + 30.0, sample.position[1], sample.position[2]])
			2: sample.tas = NAN
			3: sample.groundspeed = 2 # an int, still valid
			4: sample.velocity_ned = [1, 2, 3] # an Array of ints
			5: sample.position = PackedFloat64Array([1.0, 2.0])
			6: sample.incident = true
			7: sample.ground_contact = true
			8: sample.tas = 1.0e6 # over the cap
			9: sample.velocity_ned = PackedFloat64Array([0.0, -0.0, INF])
			10: sample.erase("velocity_ned")
			11: sample.tas = -0.0
		out.append(sample)
	return out


func _detector(profile: Dictionary, native: bool) -> RefCounted:
	Detector.native_speed_enabled = native
	var d: RefCounted = Detector.new()
	d.configure(profile, true)
	Detector.native_speed_enabled = true
	return d


func _restored(snapshot: Dictionary, native: bool) -> RefCounted:
	Detector.native_speed_enabled = native
	var d: RefCounted = Detector.new()
	var ok: bool = d.restore(snapshot)
	Detector.native_speed_enabled = true
	return d if ok else null


## The detector test's eviction fixture (String-keyed samples): rules overrides (16 samples, a 0.5 s window), a dt burst
## that evicts several entries in one tick, signed zeros, a NaN speed, and speeds over a profile cap of 3 m/s, compared
## native against GDScript after every tick.
func _synthetic() -> void:
	var profile := {"landing_available": true, "main_indices": PackedInt32Array([0, 1]),
		"stop_indices": PackedInt32Array([0, 1, 2]), "clearance_m": 0.25, "rest_height_m": 0.25, "rest_pitch_rad": 0.0,
		"speed_cap_mps": 3.0, "initial_tick": 0, "rules": {liftoff_clearance_s = 0.03125,
		speed_exclusion_after_activation_s = 0.03125, speed_window_s = 0.5, max_speed_samples = 16}}
	var negative_zero_bytes := PackedFloat64Array([0.0]).to_byte_array()
	negative_zero_bytes[7] = 0x80
	var negative_zero: float = negative_zero_bytes.to_float64_array()[0]
	var native := _detector(profile, true)
	var reference := _detector(profile, false)
	var mismatched := 0
	var first := ""
	var count_eviction := false
	var multi_eviction := false
	for tick: int in range(1, 601):
		var dt := 0.125 if tick in [160, 161, 162] else 1.0 / 64.0
		var speed: float = 0.125 if tick % 4 == 0 else (negative_zero if tick % 2 == 0 else 0.0)
		if tick % 97 == 0:
			speed = 5.0
		var sample := {"tick": tick, "dt": dt, "supported": false, "intended_support": false, "stop_support": false,
			"clearance_ok": true, "controlled": true, "ground_speed_3d": 0.0, "angular_speed": 0.0,
			"tas": NAN if tick == 300 else speed, "groundspeed": speed, "position": PackedFloat64Array([0.0, 0.0, 0.0]),
			"velocity_ned": PackedFloat64Array([0.0, 0.0, 0.0]), "incident": false, "terminal": false,
			"ground_contact": false, "valid": true}
		var before: int = reference.snapshot().speed_window.size()
		var a: Array = native.observe(sample.duplicate(true))
		var b: Array = reference.observe(sample.duplicate(true))
		var current: Dictionary = reference.snapshot()
		count_eviction = count_eviction or (tick < 160 and before == 16 and current.speed_window.size() == 16)
		multi_eviction = multi_eviction or (before > 0 and current.speed_window.size() < before - 1)
		if var_to_bytes(a) != var_to_bytes(b) or _state(native) != _state(reference):
			mismatched += 1
			if first.is_empty():
				first = "tick %d" % tick
	var counts: Dictionary = reference.snapshot().speed_reject_counts
	_check("the eviction fixture with rules overrides is equal after every tick (count eviction %s, multi-entry eviction %s, rejections %s)" % [
		count_eviction, multi_eviction, counts], native._native_speed != null and mismatched == 0 and count_eviction \
		and multi_eviction and counts.has("speed_cap"), first)


func _state(d: RefCounted) -> PackedByteArray:
	return var_to_bytes([d.snapshot(), d.flight])


func _run() -> void:
	if not load("res://sim/native_stage.gd").library_status().get("ok", false) \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"stats_speed_collect"):
		print("NK9A_SKIP no native library with the statistics speed window")
		quit(0)
		return
	_rng.seed = 9191
	var mutation_seen := false
	for aircraft: Array in [["res://data/aircraft/f4u_corsair_250.json", "f4u-corsair-250"],
			["res://data/aircraft/stik_glow_61fx_2t.json", "stik-glow-61fx-2t"],
			["res://data/aircraft/stik_electric_6s.json", "stik-electric-6s"]]:
		var recorded: Array = _samples(aircraft[0], aircraft[1])
		var profile: Dictionary = recorded[1]
		for stream: Array in [recorded[0], _perturbed(recorded[0])]:
			var native := _detector(profile, true)
			var reference := _detector(profile, false)
			var bound: bool = native._native_speed != null and reference._native_speed == null
			var mismatched := 0
			var first := ""
			var events := 0
			var restored_native := 0
			var restored_reference := 0
			for i: int in stream.size():
				var sample: Dictionary = stream[i]
				var a: Array = native.observe(sample.duplicate(true))
				var b: Array = reference.observe(sample.duplicate(true))
				events += b.size()
				if var_to_bytes(a) != var_to_bytes(b) or _state(native) != _state(reference):
					mismatched += 1
					if first.is_empty():
						first = "sample %d" % i
				if i % 700 == 350:
					# Mid-stream restores: canonical snapshots keep the native window, JSON ones the GDScript one.
					var snapshot: Dictionary = reference.snapshot()
					var through_json: Variant = JSON.parse_string(JSON.stringify(snapshot)) if i % 1400 == 350 else snapshot
					var next_native := _restored(through_json, true)
					var next_reference := _restored(through_json, false)
					if next_native == null or next_reference == null:
						mismatched += 1
						if first.is_empty():
							first = "restore refused at %d" % i
						continue
					native = next_native
					reference = next_reference
					if native._native_speed != null:
						restored_native += 1
					else:
						restored_reference += 1
				if not mutation_seen and i == 1000 and not native.snapshot().speed_window.is_empty():
					var altered: Dictionary = reference.snapshot()
					altered.speed_window_s = float(altered.speed_window_s) + 1e-9
					mutation_seen = var_to_bytes(altered) != var_to_bytes(native.snapshot())
			var counts: Dictionary = reference.snapshot().speed_reject_counts
			_check("%s %s: native and reference detectors equal after every sample (%d samples, %d events, rejections %s, %d native and %d GDScript restores)" % [
				aircraft[1], "perturbed" if stream != recorded[0] else "recorded", stream.size(), events, counts,
				restored_native, restored_reference], bound and mismatched == 0 and restored_native > 0 and restored_reference > 0,
				first)
	_synthetic()
	_check("a 1e-9 change to the window's span is detected", mutation_seen)
	print("native stats speed: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)
