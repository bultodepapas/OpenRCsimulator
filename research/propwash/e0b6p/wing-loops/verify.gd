# Manufactured equivalence sweep; copied into a disposable project by run.py.
extends SceneTree
const Base: Script = preload("res://physics/aero.gd")
const Candidate: Script = preload("res://tests/wing_loops/aero.gd")
const Data: Script = preload("res://physics/aircraft_data.gd")
const Catalog: Script = preload("res://app_state/aircraft_catalog.gd")
const Air: Script = preload("res://physics/air_data.gd")

var failures: int = 0
var comparisons: int = 0
var scalars: int = 0
var requests: Array[Dictionary] = []


func _initialize() -> void:
	for id: String in Catalog.ids():
		var loaded: Dictionary = Data.load_file(str(Catalog.entry(id).data))
		if not loaded.get("ok", false):
			print("FAIL: model did not load: ", id)
			quit(1)
			return
		for coupled: bool in [false, true]:
			for twist_on: bool in [false, true]:
				var model: Dictionary = loaded.model.duplicate(true)
				if not coupled:
					model.envelope.erase("induced_map")
				if twist_on:
					var incidence: PackedFloat64Array = PackedFloat64Array()
					for i: int in model.envelope.station_ys.size():
						incidence.append(0.017 * float(i - 2))
					model.surfaces.station_incidence = incidence
				else:
					model.surfaces.erase("station_incidence")
				for i: int in 64:
					var angle: float = -PI + TAU * float(i) / 63.0
					var speed: float = 0.0 if i == 0 else (3.0 + float(i % 13) * 3.1)
					var s: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, -100.0,
						speed * cos(angle), 0.0 if i == 0 else 2.0 * sin(float(i)), speed * sin(angle),
						1.0, 0.0, 0.0, 0.0, 0.0 if i == 0 else 0.7 * sin(float(i)),
						0.0 if i == 0 else -0.4 * cos(float(i)), 0.0 if i == 0 else 1.3 * sin(float(i) * 0.3)])
					var d: Dictionary = {elevator = 0.0 if i == 0 else 0.31 * sin(float(i)),
						rudder = -0.0 if i == 0 else -0.2 * cos(float(i)),
						aileron_left = -0.0 if i == 0 else -0.24 * cos(float(i) * 0.8),
						aileron_right = 0.0 if i == 0 else 0.29 * sin(float(i) * 0.6)}
					var rho: float = 1.02 + float(i % 11) * 0.025
					var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), rho)
					var held: float = 0.31 if model.surfaces.horizontal.has("free_slope") else NAN
					requests.append({s = s, air = air, d = d, model = model, rho = rho, held = held})
	var base_hash: HashingContext = HashingContext.new()
	var candidate_hash: HashingContext = HashingContext.new()
	base_hash.start(HashingContext.HASH_SHA256)
	candidate_hash.start(HashingContext.HASH_SHA256)
	for r: Dictionary in requests:
		_compare(PackedFloat64Array([Base.wing_lift_coefficient(r.s, r.air, r.d, r.model)]),
			PackedFloat64Array([Candidate.wing_lift_coefficient(r.s, r.air, r.d, r.model)]), base_hash, candidate_hash)
		for lag: float in [NAN, r.held]:
			_compare(Base._local_loads(r.s, r.air, r.d, r.model, r.rho, lag),
				Candidate._local_loads(r.s, r.air, r.d, r.model, r.rho, lag), base_hash, candidate_hash)
			_compare(Base.loads(r.s, r.air, r.d, r.model, r.rho, lag),
				Candidate.loads(r.s, r.air, r.d, r.model, r.rho, lag), base_hash, candidate_hash)
	var timing: Array[Dictionary] = []
	if failures == 0:
		for local: bool in [false, true]:
			_measure(false, local)
			_measure(true, local)
			var baseline: Array[float] = []
			var candidate: Array[float] = []
			for pair: int in 9:
				var old: float
				var new: float
				if pair % 2 == 0:
					old = _measure(false, local)
					new = _measure(true, local)
				else:
					new = _measure(true, local)
					old = _measure(false, local)
				baseline.append(old)
				candidate.append(new)
			timing.append({function = "local_loads" if local else "wing_lift_coefficient",
				baseline_us_per_call = baseline, candidate_us_per_call = candidate})
	var report: Dictionary = {format = "openrc-wing-loop-equivalence v1", failures = failures,
		requests = requests.size(), comparisons = comparisons, scalars = scalars,
		baseline_sha256 = base_hash.finish().hex_encode(), candidate_sha256 = candidate_hash.finish().hex_encode(),
		timing = timing}
	var output: FileAccess = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t", false, true) + "\n")
	output.close()
	print("Wing-loop comparisons: ", comparisons, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _compare(a: PackedFloat64Array, b: PackedFloat64Array, old: HashingContext, new: HashingContext) -> void:
	comparisons += 1
	scalars += a.size()
	var valid: bool = a.size() == b.size()
	for v: float in a:
		valid = is_finite(v) and valid
	for v: float in b:
		valid = is_finite(v) and valid
	valid = valid and a.to_byte_array() == b.to_byte_array()
	if not valid:
		failures += 1
	old.update(a.to_byte_array())
	new.update(b.to_byte_array())


func _measure(candidate: bool, local: bool) -> float:
	var implementation: Script = Candidate if candidate else Base
	var started: int = Time.get_ticks_usec()
	for r: Dictionary in requests:
		if local:
			implementation._local_loads(r.s, r.air, r.d, r.model, r.rho, r.held)
		else:
			implementation.wing_lift_coefficient(r.s, r.air, r.d, r.model)
	return float(Time.get_ticks_usec() - started) / float(requests.size())
