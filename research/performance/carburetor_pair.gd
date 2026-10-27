## NITRO-06-R1/R2/R3: parity and paired timing of the carburettor root solve, an explicit prior
## carburetor.gd (reference, extracted outside app/) versus the working tree. Bytewise by default;
## --max-ulp=N compares positive roots by ulp distance (R3's closed form), still bytewise elsewhere.
## Research-only.
## See research/performance/README.md#carburettor-root-solve-nitro-06-r1.
extends SceneTree

const Candidate := preload("res://physics/glow/carburetor.gd")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ref_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): ref_path = arg.trim_prefix("--reference=")
		elif arg.begins_with("--max-ulp="): _max_ulp = int(arg.trim_prefix("--max-ulp="))
	var reference := GDScript.new()
	reference.source_code = FileAccess.get_file_as_string(ref_path)
	if reference.source_code.is_empty() or reference.reload() != OK:
		push_error("reference script failed to load: " + ref_path)
		quit(2)
		return
	# Demand/capacity ratios: a geometric sweep across the choked, interior and near-ambient range,
	# plus edge values. Floats compare by bytes, so signed zeros and NaN payloads count.
	var ys := PackedFloat64Array([NAN, INF, -INF, -1.0, -0.0, 0.0, 1e-300, Candidate.CRITICAL_RATIO,
		nextafter(Candidate.CRITICAL_RATIO, 1.0), 1.0, 1e300])
	var y := 0.4
	while y < 1.0e4:
		ys.append(y)
		y *= 1.00002
	var mismatches := 0
	for value: float in ys:
		if not _same(reference.charge_ratio(value), Candidate.charge_ratio(value)):
			mismatches += 1
	_check("charge_ratio %s over %d inputs (worst %d ulp)" % ["bytewise equal" if _max_ulp < 0 else "within %d ulp" % _max_ulp,
		ys.size(), _worst_ulp], mismatches == 0, "mismatches=%d" % mismatches)
	# NITRO-06-R2 memo: one glow point solves (restricted, wide-open) twice; replay that pattern so the
	# candidate answers repeats from its memo, and compare every call.
	var repeat_mismatches := 0
	for index: int in range(0, ys.size() - 1, 2):
		for value: float in [ys[index], ys[index + 1], ys[index], ys[index + 1]]:
			if not _same(reference.charge_ratio(value), Candidate.charge_ratio(value)):
				repeat_mismatches += 1
	_check("repeated (memo) charge_ratio calls bytewise equal", repeat_mismatches == 0, "mismatches=%d" % repeat_mismatches)
	# Concurrent callers (launch trim runs on a worker thread): four threads and the main thread
	# interleave repeats through the shared memo; every root must equal the reference's.
	var expected := {}
	var concurrent_inputs := PackedFloat64Array()
	for index: int in range(0, mini(ys.size(), 40000), 7):
		if is_finite(ys[index]) and ys[index] > Candidate.CRITICAL_RATIO:
			concurrent_inputs.append(ys[index])
			expected[ys[index]] = reference.charge_ratio(ys[index])
	_concurrent_inputs = concurrent_inputs
	_concurrent_expected = expected
	if _max_ulp < 0: # a memo shares state between threads; a stateless solve (R3) has nothing to race
		var threads: Array[Thread] = []
		for worker: int in 4:
			var thread := Thread.new()
			thread.start(_hammer.bind(worker))
			threads.append(thread)
		var concurrent_mismatches: int = _hammer(4)
		for thread: Thread in threads:
			concurrent_mismatches += int(thread.wait_to_finish())
		_check("concurrent memo callers bytewise equal (%d inputs, 5 callers)" % concurrent_inputs.size(),
			concurrent_mismatches == 0, "mismatches=%d" % concurrent_mismatches)
	# admission() over an opening × rpm grid with a representative installation.
	var admission_mismatches := 0
	var count := 0
	for oi: int in 101:
		var opening: float = lerpf(0.02, 1.0, oi / 100.0)
		for ni: int in 301:
			var rpm: float = ni * 60.0
			for capacity: float in [0.004, 0.02]:
				count += 1
				if not _same(reference.admission(opening, rpm, 0.85, 1.0e-5, 1.0, capacity),
						Candidate.admission(opening, rpm, 0.85, 1.0e-5, 1.0, capacity)):
					admission_mismatches += 1
	_check("admission %s over %d openings, speeds and capacities (worst %d ulp overall)" % [
		"bytewise equal" if _max_ulp < 0 else "within %d ulp" % _max_ulp, count, _worst_ulp], admission_mismatches == 0,
		"mismatches=%d" % admission_mismatches)
	# Paired timing of the solve over the interior part of the sweep.
	var interior := PackedFloat64Array()
	for value: float in ys:
		if is_finite(value) and value > Candidate.CRITICAL_RATIO and value < 200.0 and interior.size() < 20000:
			interior.append(value)
	var ref_us := PackedFloat64Array()
	var cand_us := PackedFloat64Array()
	for round: int in 12:
		for order: int in 2:
			var use_ref: bool = (round + order) % 2 == 0
			var started := Time.get_ticks_usec()
			for value: float in interior:
				if use_ref: reference.charge_ratio(value)
				else: Candidate.charge_ratio(value)
			var per_call: float = float(Time.get_ticks_usec() - started) / float(interior.size())
			if use_ref: ref_us.append(per_call)
			else: cand_us.append(per_call)
	ref_us.sort()
	cand_us.sort()
	print("TIMING charge_ratio solves=%d reference_median_us=%.2f candidate_median_us=%.2f ratio=%.3f" % [
		interior.size(), ref_us[6], cand_us[6], cand_us[6] / ref_us[6]])
	print("CARBURETOR PAIR failures=", _failures)
	quit(1 if _failures > 0 else 0)


var _concurrent_inputs := PackedFloat64Array()
var _concurrent_expected := {}


## Each caller walks the inputs from its own offset, asking for every value twice in a row
## and then its neighbour, so the memo slots are overwritten by the other callers mid-walk.
func _hammer(worker: int) -> int:
	var mismatches := 0
	var size: int = _concurrent_inputs.size()
	for step: int in size:
		var a: float = _concurrent_inputs[(step * 5 + worker * 997) % size]
		var b: float = _concurrent_inputs[(step * 5 + worker * 997 + 1) % size]
		for value: float in [a, b, a, b]:
			if PackedFloat64Array([Candidate.charge_ratio(value)]) != PackedFloat64Array([_concurrent_expected[value]]):
				mismatches += 1
	return mismatches


var _max_ulp := -1
var _worst_ulp := 0


## Bytewise, or for two finite positive values within _max_ulp (bit patterns of positive doubles are ordered).
func _same(a: float, b: float) -> bool:
	if var_to_bytes(a) == var_to_bytes(b):
		return true
	if _max_ulp < 0 or not is_finite(a) or not is_finite(b) or a <= 0.0 or b <= 0.0:
		return false
	var distance: int = absi(PackedFloat64Array([a]).to_byte_array().decode_s64(0) - PackedFloat64Array([b]).to_byte_array().decode_s64(0))
	_worst_ulp = maxi(_worst_ulp, distance)
	return distance <= _max_ulp


func nextafter(from: float, toward: float) -> float:
	var bytes := PackedFloat64Array([from]).to_byte_array()
	var bits: int = bytes.decode_s64(0)
	bits += 1 if toward > from else -1
	bytes.encode_s64(0, bits)
	return bytes.decode_double(0)


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)
