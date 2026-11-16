extends SceneTree
var Audit: GDScript
const Bytes := preload("res://workshop/creator/bytes.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	Audit = load((get_script() as Script).resource_path.get_base_dir().path_join("refinement_audit.gd"))
	if Audit == null or not Audit.can_instantiate():
		printerr("FAIL: audit module does not compile")
		quit(1)
		return
	var audit: SceneTree = Audit.new()
	var row := PackedFloat64Array()
	row.resize(Audit.ROW_WIDTH)
	row[6] = 1.0
	var samples := [row.duplicate(),row.duplicate()]
	check("valid exact-width rows",Audit.validate_samples(samples,2).is_empty())
	for wrong: Variant in [null,false,{},"",[],[row],[row,row,row],[Array(row),row]]:
		check("wrong shape is refused",not Audit.validate_samples(wrong,2).is_empty())
	for count: int in [-1,0,1441]:
		check("invalid required sample count is refused",not Audit.validate_samples(samples,count).is_empty())
	for bad: float in [NAN,INF,-INF]:
		var damaged: PackedFloat64Array = row.duplicate()
		damaged[Audit.ROW_WIDTH-1] = bad
		check("nonfinite diagnostic is refused",not Audit.validate_samples([row,damaged],2).is_empty())
	check("partial comparison never reaches prefix metrics",not audit.checked_differences(samples,[row],2).ok)
	var identical: Dictionary = audit.checked_differences(samples,samples,2)
	check("identical samples have zero differences",identical.ok and identical.metrics.values().all(func(value: float) -> bool: return value == 0.0))
	var moved: PackedFloat64Array = row.duplicate()
	moved[0] = 3.0
	moved[1] = 4.0
	moved[Audit.RB.RATE] = deg_to_rad(2.0)
	moved[Audit.RB.SIZE] = 0.05
	moved[Audit.RB.SIZE+1] = 20.0
	moved[Audit.RB.SIZE+2] = 0.2
	moved[Audit.RB.SIZE+3] = 2.0
	var other := [row.duplicate(),moved]
	var known: Dictionary = audit.checked_differences(samples,other,2)
	check("independent 3-4-5 position oracle",known.ok and known.metrics.position_m == 5.0)
	check("independent angular-rate oracle",is_equal_approx(known.metrics.rates_dps,2.0))
	check("independent telemetry oracles",known.metrics.airspeed_mps == 0.05 and known.metrics.rotor_rpm == 20.0 and known.metrics.current_a == 0.2)
	check("charge uses the finer run denominator",known.metrics.charge_fraction == 1.0)
	var overflow: PackedFloat64Array = row.duplicate()
	overflow[0] = 1e308
	check("finite input with overflowing derived error is refused",not audit.checked_differences(samples,[row,overflow],2).ok)
	var packed: PackedByteArray = Audit._pack([PackedFloat64Array([1.0,-2.0,-0.0])])
	check("explicit known little-endian IEEE754 encoding",packed.hex_encode() == "000000000000f03f00000000000000c00000000000000080")
	check("every value survives exact packing",packed.decode_double(0) == 1.0 and packed.decode_double(8) == -2.0)
	var negative_zero := PackedByteArray([0,0,0,0,0,0,0,128]).to_float64_array()
	var positive_zero := PackedByteArray([0,0,0,0,0,0,0,0]).to_float64_array()
	check("signed zero is retained",Audit._pack([positive_zero]).hex_encode() == "0000000000000000" and Audit._pack([negative_zero]).hex_encode() == "0000000000000080")
	check("supported fixed cell",Audit.valid_specification({case_id = "C15",tape = "roll_doublet",calibrate = true}))
	for invalid: Dictionary in [{},{case_id = "C01",tape = "typo",calibrate = false},
		{case_id = "C01",tape = "pitch_doublet",calibrate = "true"},
		{case_id = [],tape = "pitch_doublet",calibrate = true},
		{case_id = "C01",tape = "pitch_doublet",calibrate = false,extra = 1}]:
		check("invalid or broadened specification refused",not Audit.valid_specification(invalid))
	var baseline := {status = "ok",complete = true,solver_changed = false,mode = "exact",
		first_tick = 0,final_tick = 1440,rows = 1441}
	check("full exact baseline is accepted",Audit.full_baseline_replay(baseline))
	check("non-dictionary replay is refused",not Audit.full_baseline_replay(null))
	var prefix: Dictionary = baseline.merged({final_tick = 719,rows = 720},true)
	check("normally completed exact prefix is refused",not Audit.full_baseline_replay(prefix))
	for changed: Dictionary in [{first_tick = 1},{final_tick = 1439},{rows = 1440},
		{rows = 1442,final_tick = 1441},{status = "error"},{complete = false},
		{solver_changed = true},{mode = "candidate"}]:
		check("incomplete or changed replay is refused",not Audit.full_baseline_replay(baseline.merged(changed,true)))
	for field: String in ["rows","first_tick","final_tick"]:
		var missing: Dictionary = baseline.duplicate()
		missing.erase(field)
		check("missing replay extent is refused",not Audit.full_baseline_replay(missing))
		missing[field] = str(baseline[field])
		check("noninteger replay extent is refused",not Audit.full_baseline_replay(missing))
	audit.free()
	print("AC12 audit contracts: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)


func check(label: String,ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
