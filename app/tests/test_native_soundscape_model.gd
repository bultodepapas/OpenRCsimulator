extends SceneTree
## NK-7a: the native kernel's soundscape model functions equal the GDScript reference bit for bit on random inputs:
## SoundscapeModel doppler, targets (glow, electric, turbine with its exhaust directivity, other kinds),
## humidity_molar_pct, absorption_cutoff_hz and screening, Wildlife.activity and PowertrainAudio.distance_gain,
## including clamps, degenerate rays and the edges of every smoothstep. Skips (passes) without the verified library.

const Model := preload("res://audio/soundscape_model.gd")
const Wildlife := preload("res://audio/wildlife.gd")
const PowertrainAudio := preload("res://audio/powertrain_audio.gd")
const KINDS: Array[String] = ["glow_prop", "electric_prop", "turbine", "ducted_fan"]
const TARGET_KEYS: Array[String] = ["motor_gain", "prop_gain", "motor_pitch", "prop_pitch", "air_gain", "wind_low",
	"wind_high", "foliage", "bird_activity"]
const ACTIVITY_KEYS: Array[String] = ["bird", "crow", "owl", "dog", "cricket"]

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# The verified library loads through NativeStage (a native flight does this before its audio runs).
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_exists(&"OpenRCNativeKernel"):
		print("NK7A_SKIP no native library")
		quit(0)
		return
	var kernel: Object = ClassDB.instantiate(&"OpenRCNativeKernel")
	if kernel == null or not kernel.has_method(&"sound_targets"):
		print("NK7A_SKIP library without the soundscape model")
		quit(0)
		return
	_rng.seed = 7071
	_doppler(kernel)
	_targets(kernel)
	_humidity_and_absorption(kernel)
	_screening(kernel)
	_activity_and_distance(kernel)
	print("native soundscape model: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _same(a: float, b: float) -> bool:
	return var_to_bytes(a) == var_to_bytes(b)


func _vector(span: float) -> Vector3:
	return Vector3(_rng.randf_range(-span, span), _rng.randf_range(-span, span), _rng.randf_range(-span, span))


func _pick(values: Array) -> Variant:
	return values[_rng.randi() % values.size()]


func _doppler(kernel: Object) -> void:
	var mismatched := 0
	for i: int in 20000:
		var source := _vector(800.0)
		var listener: Vector3 = source if i % 97 == 0 else _vector(800.0)
		var source_velocity := _vector(_pick([0.0, 10.0, 80.0, 400.0]))
		var listener_velocity := _vector(_pick([0.0, 5.0, 40.0]))
		var speed: float = _pick([343.0, 250.0, 420.0, _rng.randf_range(290.0, 390.0)])
		var reference: float = Model.doppler(source, listener, source_velocity, listener_velocity, speed)
		var answer: float = kernel.sound_doppler(source, listener, source_velocity, listener_velocity, speed)
		if not _same(reference, answer):
			mismatched += 1
			if mismatched <= 3:
				printerr("NK7A_DOPPLER ", reference, " vs ", answer)
	_check("native doppler equals the model's", mismatched == 0, str(mismatched))


func _snapshot(i: int) -> Dictionary:
	var rpm: float = _pick([0.0, 25.0, 30.0, 31.0, 1200.0, -50.0, _rng.randf_range(0.0, 30000.0),
		_rng.randf_range(0.0, 120000.0)])
	var source := _vector(500.0)
	var listener: Vector3 = source if i % 61 == 0 else _vector(500.0)
	var exhaust: Vector3 = Vector3.ZERO if i % 53 == 0 else _vector(1.0)
	if i % 41 == 0:
		exhaust = (listener - source) * _pick([1.0, -1.0, 0.001]) # on the axis, either way
	return {
		rpm = rpm,
		max_rpm = _pick([0.0, 0.5, 12000.0, 82320.0, _rng.randf_range(1.0, 130000.0)]),
		load = _rng.randf_range(-0.3, 1.3),
		throttle = _rng.randf_range(-0.3, 1.3),
		airspeed = _pick([0.0, 55.0, 82.5, _rng.randf_range(-10.0, 200.0)]),
		wind_speed = _pick([0.0, 6.0, 14.0, 18.0, 35.0, _rng.randf_range(-5.0, 50.0)]),
		running = _rng.randf() > 0.15,
		blades = _rng.randi_range(1, 6),
		sun_elevation = _pick([-6.0, 3.0, _rng.randf_range(-40.0, 90.0)]),
		kind = KINDS[i % KINDS.size()],
		jet_velocity = _pick([0.0, _rng.randf_range(0.0, 900.0)]),
		jet_velocity_max = _pick([0.0, 1.0, _rng.randf_range(1.0, 800.0)]),
		exhaust_direction = exhaust,
		listener = listener,
		source = source,
	}


func _targets(kernel: Object) -> void:
	var mismatched := 0
	var turbines := 0
	for i: int in 40000:
		var s := _snapshot(i)
		var reference: Dictionary = Model.targets(s)
		var values := PackedFloat64Array([s.rpm, s.max_rpm, s.load, s.throttle, s.airspeed, s.wind_speed,
			1.0 if s.running else 0.0, float(s.blades), s.sun_elevation, float(KINDS.find(s.kind)), s.jet_velocity,
			s.jet_velocity_max])
		var answer: PackedFloat64Array = kernel.sound_targets(values, s.exhaust_direction, s.listener, s.source)
		var ok: bool = answer.size() == 10
		if ok:
			for k: int in TARGET_KEYS.size():
				ok = ok and _same(float(reference[TARGET_KEYS[k]]), answer[k])
			if s.kind == "turbine":
				turbines += 1
				ok = ok and _same(float(reference.exhaust_angle_deg), answer[9])
		if not ok:
			mismatched += 1
			if mismatched <= 3:
				printerr("NK7A_TARGETS ", s, " ", reference, " vs ", answer)
	_check("native targets equal the model's (%d turbines)" % turbines, mismatched == 0 and turbines > 5000,
		str(mismatched))
	var malformed: PackedFloat64Array = kernel.sound_targets(PackedFloat64Array([1.0]), Vector3.ZERO, Vector3.ZERO,
		Vector3.ZERO)
	_check("a malformed targets request answers empty", malformed.is_empty())


func _humidity_and_absorption(kernel: Object) -> void:
	var humidity_mismatched := 0
	var cutoff_mismatched := 0
	var bracketed := 0
	for i: int in 6000:
		var temperature_k: float = _pick([288.15, 273.16, _rng.randf_range(170.0, 340.0)])
		var pressure_pa: float = _pick([101325.0, _rng.randf_range(8000.0, 125000.0)])
		var relative: float = _pick([0.0, 50.0, 100.0, _rng.randf_range(-10.0, 120.0)])
		var reference_h: float = Model.humidity_molar_pct(relative, temperature_k, pressure_pa)
		var answer_h: float = kernel.sound_humidity(relative, temperature_k, pressure_pa)
		if not _same(reference_h, answer_h):
			humidity_mismatched += 1
			if humidity_mismatched <= 3:
				printerr("NK7A_HUMIDITY ", [relative, temperature_k, pressure_pa], " ", reference_h, " vs ", answer_h)
		var path: float = _pick([0.0, -5.0, 1.0, _rng.randf_range(0.0, 200.0), _rng.randf_range(0.0, 6000.0)])
		var humidity: float = _pick([0.0, -1.0, reference_h, _rng.randf_range(0.0, 5.0)])
		var reference_c: float = Model.absorption_cutoff_hz(path, temperature_k, pressure_pa, humidity)
		var answer_c: float = kernel.sound_absorption_cutoff(path, temperature_k, pressure_pa, humidity)
		bracketed += int(reference_c > 20.0 and reference_c < 16000.0)
		if not _same(reference_c, answer_c):
			cutoff_mismatched += 1
			if cutoff_mismatched <= 3:
				printerr("NK7A_CUTOFF ", [path, temperature_k, pressure_pa, humidity], " ", reference_c, " vs ", answer_c)
	_check("native humidity equals the model's", humidity_mismatched == 0, str(humidity_mismatched))
	_check("native absorption cutoff equals the model's (%d solved inside the bracket)" % bracketed,
		cutoff_mismatched == 0 and bracketed > 1000, str(cutoff_mismatched))


func _screening(kernel: Object) -> void:
	var mismatched := 0
	var screened := 0
	for i: int in 8000:
		var source := _vector(300.0)
		var listener := _vector(300.0)
		var canopies: Array[AABB] = []
		var boxes := PackedFloat32Array()
		for b: int in _rng.randi_range(0, 8):
			var along: Vector3 = listener.lerp(source, _rng.randf())
			var size := Vector3(_rng.randf_range(0.0, 30.0), _rng.randf_range(0.0, 30.0), _rng.randf_range(0.0, 30.0))
			var box := AABB(along - size * _rng.randf() + _vector(20.0), size)
			canopies.append(box)
			boxes.append_array([box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z])
		var reference: float = Model.screening(source, listener, canopies)
		var answer: float = kernel.sound_screening(source, listener, boxes)
		screened += int(reference > 0.0)
		if not _same(reference, answer):
			mismatched += 1
			if mismatched <= 3:
				printerr("NK7A_SCREENING ", reference, " vs ", answer)
	_check("native screening equals the model's (%d screened)" % screened, mismatched == 0 and screened > 1000,
		str(mismatched))


func _activity_and_distance(kernel: Object) -> void:
	var mismatched := 0
	for i: int in 20000:
		var sun: float = _pick([-10.0, -5.0, -2.0, 4.0, 22.0, -22.0, _rng.randf_range(-60.0, 90.0)])
		var wind: float = _pick([0.0, 5.0, 16.0, 25.0, -3.0, _rng.randf_range(-5.0, 40.0)])
		var temperature: float = _pick([8.0, 18.0, _rng.randf_range(-20.0, 40.0)])
		var reference: Dictionary = Wildlife.activity({sun_elevation = sun, wind_speed = wind, temperature_c = temperature})
		var answer: PackedFloat64Array = kernel.sound_activity(sun, wind, temperature)
		var ok: bool = answer.size() == 5
		for k: int in ACTIVITY_KEYS.size():
			ok = ok and _same(float(reference[ACTIVITY_KEYS[k]]), answer[k])
		var distance: float = _pick([0.0, 3.0, 1200.0, 1500.0, -1.0, _rng.randf_range(0.0, 2000.0)])
		ok = ok and _same(PowertrainAudio.distance_gain(distance), kernel.sound_distance_gain(distance))
		if not ok:
			mismatched += 1
			if mismatched <= 3:
				printerr("NK7A_ACTIVITY ", [sun, wind, temperature, distance], " ", reference, " vs ", answer)
	_check("native wildlife activity and powertrain distance gain equal the reference", mismatched == 0, str(mismatched))


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
