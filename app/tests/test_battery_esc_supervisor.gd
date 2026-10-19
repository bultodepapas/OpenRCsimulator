# BAT-11: sampled ESC low-voltage-cutoff state machine and cell detection (spec §6).
extends SceneTree

const Supervisor: Script = preload("res://physics/battery/esc_supervisor.gd")

const DT: float = 1.0 / 240.0

var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func near(label: String, actual: float, expected: float, tolerance: float = 1e-12) -> void:
	check(label + " actual=" + str(actual) + " expected=" + str(expected),
		is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


static func profile(mode: String = "soft", recovery: String = "throttle_reset") -> Dictionary:
	return {"mode": mode, "cell_detection": "auto", "detection_max_cell_v": 4.3, "cutoff_per_cell_v": 3.2,
		"soft_limit": 0.5, "soft_ramp_s": 3.0, "debounce_s": 0.5, "recovery": recovery,
		"reset_throttle_max": 0.05, "voltage_filter_s": 0.1}


func _initialize() -> void:
	_validation()
	_cell_detection()
	_debounce_and_soft_ramp()
	_hard_cut_and_recovery()
	_latched_and_off()
	print("BAT-11 ESC supervisor: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _validation() -> void:
	check("valid profile accepted", Supervisor.validate(profile()) == "")
	var fixed: Dictionary = profile()
	fixed.cell_detection = "fixed"
	fixed.fixed_cells = 4
	check("fixed detection accepted", Supervisor.validate(fixed) == "")
	for mutation: Array in [["mode", "gentle"], ["recovery", "auto"], ["soft_limit", 1.0], ["soft_ramp_s", 0.0],
			["voltage_filter_s", 0.001], ["debounce_s", -1.0], ["reset_throttle_max", 0.5], ["cutoff_per_cell_v", NAN],
			["detection_max_cell_v", 0.0]]:
		var bad: Dictionary = profile()
		bad[mutation[0]] = mutation[1]
		check("mutation refused: " + str(mutation), Supervisor.validate(bad) != "")
	fixed.fixed_cells = 4.0
	check("fixed cells must be an integer", Supervisor.validate(fixed) != "")


func _cell_detection() -> void:
	var p: Dictionary = profile()
	check("full 4S detected as 4", Supervisor.detect_cells(p, 16.8) == 4)
	check("storage 4S detected as 4", Supervisor.detect_cells(p, 15.3) == 4)
	check("full 3S detected as 3", Supervisor.detect_cells(p, 12.6) == 3)
	check("4S at 3.2 V/cell misdetected as 3S (modeled behaviour)", Supervisor.detect_cells(p, 12.8) == 3)
	check("exact multiple stays at its count", Supervisor.detect_cells(p, 4.3 * 4.0) == 4)
	var fixed: Dictionary = profile()
	fixed.cell_detection = "fixed"
	fixed.fixed_cells = 6
	check("fixed count ignores voltage", Supervisor.detect_cells(fixed, 12.0) == 6)
	near("cutoff voltage", Supervisor.cutoff_voltage(profile(), 4), 12.8)


## Run n samples at a constant sensed voltage and throttle; return the last [limit, phase, timer].
func _run(p: Dictionary, state: PackedFloat64Array, samples: int, voltage: float, throttle: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = state
	for _i: int in samples:
		out = Supervisor.step(p, out[0], int(out[1]), out[2], 4, voltage, throttle, DT)
	return out


func _debounce_and_soft_ramp() -> void:
	var p: Dictionary = profile()
	var normal := PackedFloat64Array([1.0, 0.0, 0.0])
	var held: PackedFloat64Array = _run(p, normal, 240, 13.0, 1.0)
	check("above threshold stays normal", held == normal)
	var brief: PackedFloat64Array = _run(p, normal, 60, 12.7, 1.0)
	check("short dip stays in debounce with full power", int(brief[1]) == Supervisor.PHASE_DEBOUNCE and brief[0] == 1.0)
	near("debounce timer counts samples", brief[2], 60.0 * DT)
	var recovered: PackedFloat64Array = _run(p, brief, 1, 13.0, 1.0)
	check("recovery during debounce resets", recovered == normal)
	var cut: PackedFloat64Array = _run(p, normal, 120, 12.7, 1.0)
	check("debounce of 0.5 s enters soft cut at sample 120", int(cut[1]) == Supervisor.PHASE_SOFT_CUT and cut[0] == 1.0 and cut[2] == 0.0)
	var mid: PackedFloat64Array = _run(p, cut, 360, 12.7, 1.0)
	near("soft ramp is halfway after 1.5 s", mid[0], 0.75, 1e-12)
	var done: PackedFloat64Array = _run(p, cut, 720, 12.7, 1.0)
	near("soft ramp reaches the soft limit after 3 s", done[0], 0.5)
	var later: PackedFloat64Array = _run(p, done, 240, 13.5, 1.0)
	check("soft cut holds while throttle stays high even if voltage recovers", int(later[1]) == Supervisor.PHASE_SOFT_CUT and later[0] == 0.5)
	var reset: PackedFloat64Array = _run(p, done, 1, 13.5, 0.0)
	check("throttle reset with recovered voltage restores full power", reset == normal)
	var still_low: PackedFloat64Array = _run(p, done, 1, 12.0, 0.0)
	check("throttle reset refused while voltage is still low", int(still_low[1]) == Supervisor.PHASE_SOFT_CUT)


func _hard_cut_and_recovery() -> void:
	var p: Dictionary = profile("hard")
	var normal := PackedFloat64Array([1.0, 0.0, 0.0])
	var cut: PackedFloat64Array = _run(p, normal, 120, 12.0, 1.0)
	check("hard cut removes power after debounce", int(cut[1]) == Supervisor.PHASE_HARD_CUT and cut[0] == 0.0)
	var held: PackedFloat64Array = _run(p, cut, 100, 13.0, 1.0)
	check("hard cut holds with throttle up; timer unchanged", held[0] == 0.0 and held[2] == cut[2])
	check("hard cut resets at idle throttle with recovered voltage", _run(p, held, 1, 13.0, 0.04) == normal)
	var immediate: Dictionary = profile("hard")
	immediate.debounce_s = 0.0
	check("zero debounce cuts on the first low sample", int(_run(immediate, normal, 1, 12.0, 1.0)[1]) == Supervisor.PHASE_HARD_CUT)


func _latched_and_off() -> void:
	var p: Dictionary = profile("soft", "latched")
	var normal := PackedFloat64Array([1.0, 0.0, 0.0])
	var cut: PackedFloat64Array = _run(p, normal, 900, 12.0, 1.0)
	var reset_try: PackedFloat64Array = _run(p, cut, 10, 14.0, 0.0)
	check("latched soft cut never restores in the session", int(reset_try[1]) == Supervisor.PHASE_SOFT_CUT and reset_try[0] == 0.5)
	var off: Dictionary = profile("off")
	check("off mode never limits", _run(off, normal, 600, 5.0, 1.0) == normal)
	check("state names", Supervisor.state_name(off, 3) == "off" and Supervisor.state_name(p, 2) == "soft_cut"
		and Supervisor.state_name(p, 1) == "debounce" and Supervisor.state_name(p, 0) == "normal")
