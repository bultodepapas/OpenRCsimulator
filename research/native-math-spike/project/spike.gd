# NK-1 math identity spike harness (research only). Run through ../run.py.
# GDScript results are the reference; the extension evaluates the same inputs with std:: and with
# godot-cpp UtilityFunctions and compares bit patterns.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const EXTENSION := "res://openrc_math_spike.gdextension"
const SEED := 20261027
const NO_WRAPPER := [15, 16] # fmod, floor: math3d.gd has no wrapper.

var count := 1000000
var batches := 5
var out_path := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--batches="):
			batches = int(arg.trim_prefix("--batches="))
	var status := GDExtensionManager.load_extension(EXTENSION)
	if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
		push_error("extension load failed: %d" % status)
		quit(1)
		return
	if not ClassDB.class_exists("OpenRCMathSpike"):
		push_error("OpenRCMathSpike class missing")
		quit(1)
		return
	var spike: Object = ClassDB.instantiate("OpenRCMathSpike")
	var names: PackedStringArray = spike.function_names()
	var results := {
		"engine": Engine.get_version_info(),
		"debug_build": OS.is_debug_build(),
		"build_info": spike.build_info(),
		"count": count,
		"batches": batches,
		"seed": SEED,
		"rows": [],
		"variants": [],
	}
	if not _comparator_sanity(spike):
		quit(1)
		return
	results["comparator_sanity"] = true
	results["literal_negative_zero"] = _literal_negative_zero()
	var sin_inputs := {}
	var pow_inputs := {}
	for fn in names.size():
		var inputs: Dictionary = spike.generate_inputs(fn, count, SEED)
		if fn == 1:
			sin_inputs = inputs
		elif fn == 9:
			pow_inputs = inputs
		results["rows"].append(_measure(spike, fn, names[fn], inputs))
		print("row %s done" % names[fn])
	results["variants"] = _variants(spike, sin_inputs, pow_inputs)
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "  ") + "\n")
		file.close()
	print("OPENRC_MATH_SPIKE_OK")
	quit(0)


# The comparator must flag a one-ulp change and a sign-of-zero change.
func _comparator_sanity(spike: Object) -> bool:
	var base := PackedFloat64Array([1.0, 0.0, 2.5])
	var bytes := base.to_byte_array()
	bytes.encode_s64(0, bytes.decode_s64(0) + 1)
	bytes.encode_s64(8, 1 << 63) # -0.0; see _literal_negative_zero()
	var bumped := bytes.to_float64_array()
	var report: Dictionary = spike.compare(base, bumped, base, PackedFloat64Array())
	var same: Dictionary = spike.compare(base, base.duplicate(), base, PackedFloat64Array())
	if int(report["identical"]) != 1 or int(report["finite_diff"]) != 1 or int(report["max_ulp"]) != 1 \
			or int(report["zero_sign_only"]) != 1 or int(same["identical"]) != 3:
		push_error("comparator sanity failed: %s / %s" % [report, same])
		return false
	return true


# Bit patterns of GDScript's -0.0 literal and of a runtime negation, as hex.
func _literal_negative_zero() -> Dictionary:
	var zero := 0.0
	var runtime := -zero
	var literal := -0.0
	return {
		"literal": "0x" + String.num_uint64(PackedFloat64Array([literal]).to_byte_array().decode_s64(0), 16).lpad(16, "0"),
		"runtime": "0x" + String.num_uint64(PackedFloat64Array([runtime]).to_byte_array().decode_s64(0), 16).lpad(16, "0"),
	}


func _measure(spike: Object, fn: int, fn_name: String, inputs: Dictionary) -> Dictionary:
	var a: PackedFloat64Array = inputs["a"]
	var b: PackedFloat64Array = inputs["b"]
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(a.to_byte_array())
	if not b.is_empty():
		hashing.update(b.to_byte_array())
	var row := {
		"fn": fn_name,
		"random_count": inputs["random_count"],
		"edge_count": inputs["edge_count"],
		"input_sha256": hashing.finish().hex_encode(),
	}
	var gd := _gd_direct(fn, a, b)
	var std_out: PackedFloat64Array = spike.eval_std(fn, a, b)
	var util_out: PackedFloat64Array = spike.eval_utility(fn, a, b)
	row["std"] = spike.compare(gd, std_out, a, b)
	row["utility"] = spike.compare(gd, util_out, a, b)
	row["std_bytes_equal"] = gd.to_byte_array() == std_out.to_byte_array()
	row["utility_bytes_equal"] = gd.to_byte_array() == util_out.to_byte_array()
	if fn not in NO_WRAPPER:
		row["math3d"] = spike.compare(gd, _gd_math3d(fn, a, b), a, b)
	row["ns_gd_direct"] = _time_gd(false, fn, a, b)
	row["ns_gd_math3d"] = _time_gd(true, fn, a, b) if fn not in NO_WRAPPER else null
	row["ns_std"] = spike.time_route(0, fn, a, b, batches)
	row["ns_utility"] = spike.time_route(1, fn, a, b, batches)
	return row


func _time_gd(wrapper: bool, fn: int, a: PackedFloat64Array, b: PackedFloat64Array) -> Dictionary:
	var samples: Array[float] = []
	var _warm := _gd_math3d(fn, a, b) if wrapper else _gd_direct(fn, a, b)
	for k in batches:
		var t0 := Time.get_ticks_usec()
		var _out := _gd_math3d(fn, a, b) if wrapper else _gd_direct(fn, a, b)
		samples.append(float(Time.get_ticks_usec() - t0) * 1000.0 / float(a.size()))
	samples.sort()
	var mid := samples.size() / 2
	var median: float = samples[mid] if samples.size() % 2 == 1 else 0.5 * (samples[mid - 1] + samples[mid])
	return {"median_ns": median, "min_ns": samples[0], "batches": samples.size()}


func _variants(spike: Object, sin_inputs: Dictionary, pow_inputs: Dictionary) -> Array:
	var rows := []
	var x: PackedFloat64Array = sin_inputs["a"]
	var p: PackedFloat64Array = pow_inputs["a"]
	var n := x.size()
	var ref_sin := PackedFloat64Array()
	var ref_cos := PackedFloat64Array()
	ref_sin.resize(n)
	ref_cos.resize(n)
	for i in n:
		ref_sin[i] = sin(x[i])
		ref_cos[i] = cos(x[i])
	var m := p.size()
	var ref_pow := {}
	for exponent: float in [2.0, 0.5, 3.5, 1.0 / 1.4]:
		var r := PackedFloat64Array()
		r.resize(m)
		for i in m:
			r[i] = pow(p[i], exponent)
		ref_pow[exponent] = r
	var names: PackedStringArray = spike.variant_names()
	var refs := [ref_sin, ref_cos, ref_pow[2.0], ref_pow[0.5], ref_pow[3.5], ref_pow[1.0 / 1.4]]
	for v in names.size():
		var inputs := x if v < 2 else p
		var report: Dictionary = spike.compare(refs[v], spike.eval_variant(v, inputs), inputs, PackedFloat64Array())
		report["variant"] = names[v]
		rows.append(report)
	return rows


static func _gd_direct(fn: int, a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var n := a.size()
	var out := PackedFloat64Array()
	out.resize(n)
	match fn:
		0:
			for i in n: out[i] = a[i]
		1:
			for i in n: out[i] = sin(a[i])
		2:
			for i in n: out[i] = cos(a[i])
		3:
			for i in n: out[i] = tan(a[i])
		4:
			for i in n: out[i] = asin(a[i])
		5:
			for i in n: out[i] = acos(a[i])
		6:
			for i in n: out[i] = atan(a[i])
		7:
			for i in n: out[i] = atan2(a[i], b[i])
		8:
			for i in n: out[i] = sqrt(a[i])
		9:
			for i in n: out[i] = pow(a[i], b[i])
		10:
			for i in n: out[i] = exp(a[i])
		11:
			for i in n: out[i] = log(a[i])
		12:
			for i in n: out[i] = sinh(a[i])
		13:
			for i in n: out[i] = cosh(a[i])
		14:
			for i in n: out[i] = tanh(a[i])
		15:
			for i in n: out[i] = fmod(a[i], b[i])
		16:
			for i in n: out[i] = floorf(a[i])
	return out


static func _gd_math3d(fn: int, a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var n := a.size()
	var out := PackedFloat64Array()
	out.resize(n)
	match fn:
		0:
			for i in n: out[i] = a[i]
		1:
			for i in n: out[i] = M.sin_(a[i])
		2:
			for i in n: out[i] = M.cos_(a[i])
		3:
			for i in n: out[i] = M.tan_(a[i])
		4:
			for i in n: out[i] = M.asin_(a[i])
		5:
			for i in n: out[i] = M.acos_(a[i])
		6:
			for i in n: out[i] = M.atan_(a[i])
		7:
			for i in n: out[i] = M.atan2_(a[i], b[i])
		8:
			for i in n: out[i] = M.sqrt_(a[i])
		9:
			for i in n: out[i] = M.pow_(a[i], b[i])
		10:
			for i in n: out[i] = M.exp_(a[i])
		11:
			for i in n: out[i] = M.log_(a[i])
		12:
			for i in n: out[i] = M.sinh_(a[i])
		13:
			for i in n: out[i] = M.cosh_(a[i])
		14:
			for i in n: out[i] = M.tanh_(a[i])
	return out
