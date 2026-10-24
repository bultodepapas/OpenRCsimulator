## Full-result differential and paired timing probe for Glow feed-stage scalar reuse.
## godot --headless --audio-driver Dummy --path app --script <probe> -- --reference=<before.gd> --candidate=<draft.gd> --output=<report.json> [--correctness-only]
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Flight := preload("res://physics/glow/flight.gd")
const Life := preload("res://physics/glow/lifecycle.gd")
const RB := preload("res://physics/rigid_body.gd")
const SAVE_META := &"_probe_saved_prepared"
const AIRCRAFT := [
	{"id":"55AX","path":"res://data/aircraft/stik_glow_55ax_2t.json"},
	{"id":"FS64V","path":"res://data/aircraft/stik_glow_fs64v_4t.json"},
	{"id":"61FX","path":"res://data/aircraft/stik_glow_61fx_2t.json"},
	{"id":"Extra","path":"res://data/aircraft/gp_extra_300s_60.json"},
]
const BATCHES := 9
const CALLS := 100
const WARMUPS := 8
var _failures := 0
var _comparisons := 0
var _checksum := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var opt := _options()
	if not opt.ok: printerr(opt.error); quit(1); return
	if FileAccess.file_exists(opt.output): printerr("refusing existing output: ",opt.output); quit(1); return
	var rs := _load_script(opt.reference)
	var cs := _load_script(opt.candidate)
	if rs == null or cs == null: quit(1); return
	var control := _float_control()
	if not control: _failures += 1
	var alt55: Node = _session(str(AIRCRAFT[0].path))
	var alt64: Node = _session(str(AIRCRAFT[1].path))
	await process_frame
	if not _freeze(alt55) or not _freeze(alt64):
		_failures += 1
	var reports: Array[Dictionary] = []
	for aircraft: Dictionary in AIRCRAFT:
		var ro: Node = _session(str(aircraft.path))
		var co: Node = _session(str(aircraft.path))
		await process_frame
		var ref_frozen := _freeze(ro)
		var candidate_frozen := _freeze(co)
		if not ro.is_flyable() or not co.is_flyable() or not ref_frozen or not candidate_frozen:
			_failures += 1; reports.append({"id":aircraft.id,"complete":false,"error":"session setup failed"})
			ro.queue_free(); co.queue_free(); continue
		_sync(ro,co)
		var install: Dictionary = ro.aircraft.model.propulsion.glow
		var case_result := _cases(ro)
		if not case_result.ok:
			_failures += 1
			reports.append({"id":aircraft.id,"complete":false,"error":case_result.error})
			ro.queue_free(); co.queue_free(); continue
		var cases: Array[Dictionary] = case_result.cases
		var alt: Node = alt64 if aircraft.id == "55AX" else alt55
		var point_r := Callable(rs,"point"); var point_c := Callable(cs,"point")
		var eval_r := Callable(rs,"evaluate"); var eval_c := Callable(cs,"evaluate")
		var scenarios: Array[Dictionary] = []
		var expected_ids: Array[String] = ["feed_main","maneuver_0","maneuver_1","stopped","fuel_starved","cut","failure_invalid_nan","stale_identity"]
		if str(case_result.feed_line_status) == "covered": expected_ids.append("feed_line")
		if not install.has("fuel_feed"): expected_ids.append("non_feed_main")
		var observed_ids: Array[String] = []
		var scenarios_complete := true
		for s: Dictionary in cases:
			_apply(ro,s); _apply(co,s)
			if s.id == "stale_identity":
				_swap_meta(alt,ro); _swap_meta(alt,co)
			var body: PackedFloat64Array = s.body
			var values: PackedFloat64Array = s.values
			var pre_ref := _input_fingerprint(ro,body,values,0.0)
			var pre_candidate := _input_fingerprint(co,body,values,0.0)
			if pre_ref != pre_candidate:
				_failures += 1; scenarios_complete = false
			var checks: Array[Dictionary] = []
			checks.append(_check("point_uncoupled",point_r,[ro,body,values,0.0,false],point_c,[co,body,values,0.0,false],s.id!="failure_invalid_nan"))
			checks.append(_check("point_coupled",point_r,[ro,body,values,0.0,true],point_c,[co,body,values,0.0,true],s.id!="failure_invalid_nan"))
			checks.append(_check("evaluate",eval_r,[body,values,0.0,ro],eval_c,[body,values,0.0,co],s.id!="failure_invalid_nan"))
			if s.id == "failure_invalid_nan":
				checks.append(_check("evaluate_wrong_size",eval_r,[body,s.short_values,0.0,ro],eval_c,[body,s.short_values,0.0,co],false))
			var post_ref := _input_fingerprint(ro,body,values,0.0)
			var post_candidate := _input_fingerprint(co,body,values,0.0)
			var unchanged := pre_ref == post_ref and pre_candidate == post_candidate
			if not unchanged:
				_failures += 1; scenarios_complete = false
			for check: Dictionary in checks:
				if not bool(check.passed): scenarios_complete = false
			observed_ids.append(str(s.id))
			scenarios.append({"id":s.id,"pre_reference_sha256":pre_ref,"pre_candidate_sha256":pre_candidate,
				"post_reference_sha256":post_ref,"post_candidate_sha256":post_candidate,
				"owners_match":pre_ref==pre_candidate,"owners_unchanged":unchanged,"checks":checks})
			if s.id == "stale_identity": _restore_meta(ro); _restore_meta(co)
		for expected_id: String in expected_ids:
			if not observed_ids.has(expected_id):
				_failures += 1; scenarios_complete = false
		var report := {"id":aircraft.id,"path":aircraft.path,"has_fuel_feed":install.has("fuel_feed"),
			"feed_line_coverage":case_result.feed_line_status,
			"non_feed_control_available":not install.has("fuel_feed"),
			"scenarios":scenarios,"complete":scenarios_complete}
		if opt.bench:
			_apply(ro,cases[0]); _apply(co,cases[0])
			var bench_pre_ref := _input_fingerprint(ro,cases[0].body,cases[0].values,0.0)
			var bench_pre_candidate := _input_fingerprint(co,cases[0].body,cases[0].values,0.0)
			report.benchmark = _bench(point_r,point_c,eval_r,eval_c,ro,co,cases[0])
			var bench_post_ref := _input_fingerprint(ro,cases[0].body,cases[0].values,0.0)
			var bench_post_candidate := _input_fingerprint(co,cases[0].body,cases[0].values,0.0)
			report.benchmark.owners_match = bench_pre_ref == bench_pre_candidate
			report.benchmark.owners_unchanged = bench_pre_ref == bench_post_ref and bench_pre_candidate == bench_post_candidate
			if not report.benchmark.owners_match or not report.benchmark.owners_unchanged:
				_failures += 1; report.complete = false
		reports.append(report); ro.queue_free(); co.queue_free()
	alt55.queue_free(); alt64.queue_free()
	var paths := [opt.reference,opt.candidate,str(get_script().resource_path),"res://physics/glow/flight.gd","res://sim/flight_session.gd","res://physics/glow/fuel_feed.gd"]
	var hashes := {}
	for path: String in paths: hashes[path] = _sha(path)
	for aircraft: Dictionary in AIRCRAFT: hashes[aircraft.path] = _sha(aircraft.path)
	var result := {"format":"openrc-glow-feed-reuse-probe v1",
		"complete":_failures==0 and reports.size()==AIRCRAFT.size() and _all_aircraft_complete(reports),
		"correctness_only":not opt.bench,"comparator_nan_signed_zero_control":control,
		"engine":Engine.get_version_info(),"os":OS.get_name(),"processor":OS.get_processor_name(),
		"seed":20261024,"source_sha256":hashes,"comparison_count":_comparisons,
		"failures":_failures,"checksum":_checksum,"aircraft":reports}
	var file := FileAccess.open(opt.output,FileAccess.WRITE)
	if file == null: printerr("cannot write output: ",error_string(FileAccess.get_open_error())); quit(1); return
	file.store_string(JSON.stringify(result,"\t")+"\n"); file.flush()
	var error: Error = file.get_error(); file.close()
	if error != OK: printerr("write failed: ",error_string(error)); quit(1); return
	print("Glow feed probe: comparisons=%d failures=%d -> %s" % [_comparisons,_failures,opt.output])
	quit(0 if result.complete else 1)
func _options() -> Dictionary:
	var out := {"reference":"","candidate":"","output":"","bench":true}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String=args[i]
		if a=="--correctness-only": out.bench=false
		elif a in ["--reference","--candidate","--output"]:
			i+=1
			if i>=args.size(): return {"ok":false,"error":"missing value for "+a}
			out[a.trim_prefix("--")]=args[i]
		elif a.begins_with("--reference="): out.reference=a.trim_prefix("--reference=")
		elif a.begins_with("--candidate="): out.candidate=a.trim_prefix("--candidate=")
		elif a.begins_with("--output="): out.output=a.trim_prefix("--output=")
		else: return {"ok":false,"error":"unknown option "+a}
		i+=1
	for key: String in ["reference","candidate","output"]:
		if str(out[key]).is_empty(): return {"ok":false,"error":"--"+key+" is required"}
	out.ok=true
	return out
func _load_script(path: String) -> GDScript:
	if not FileAccess.file_exists(path): printerr("missing script: ",path); return null
	var script := GDScript.new()
	script.source_code=FileAccess.get_file_as_string(path)
	if script.reload()!=OK: printerr("script reload failed: ",path); return null
	return script
func _session(path: String) -> Node:
	var owner: Node=Session.new(); owner.setup(path); owner.input_enabled=false
	owner.set_physics_process(false)
	if not owner.configure_external_driver(): owner.set_meta(&"_probe_driver_setup_failed",true)
	if owner.sim != null:
		owner.sim.set_physics_process(false)
		owner.sim.set_paused(true)
	root.add_child(owner); return owner
func _freeze(owner: Node) -> bool:
	if owner.sim == null: return false
	owner.set_process(false); owner.set_physics_process(false)
	owner.sim.set_physics_process(false); owner.sim.set_paused(true)
	return not owner.get_meta(&"_probe_driver_setup_failed",false) and not owner.is_processing() \
		and not owner.is_physics_processing() and not owner.sim.is_physics_processing() and owner.sim.paused
func _sync(a: Node,b: Node) -> void:
	b.sim.state=a.sim.state.duplicate(); b.sim.previous=a.sim.previous.duplicate()
	b.sim.continuous=a.sim.continuous.duplicate(); b.sim.inputs=a.sim.inputs.duplicate()
	b.sim.aux=a.sim.aux.duplicate(); b.sim.modes=a.sim.modes.duplicate()
	b.sim.tick=a.sim.tick; b.sim.mass=a.sim.mass; b.sim.inertia=a.sim.inertia.duplicate()
	b.sim.gravity=a.sim.gravity; b.sim.set_paused(a.sim.paused)
func _case(id: String,body: PackedFloat64Array,values: PackedFloat64Array,throttle: float,mode: int) -> Dictionary:
	return {"id":id,"body":body,"values":values,"throttle":throttle,"engine_mode":mode}
func _cases(owner: Node) -> Dictionary:
	var body: PackedFloat64Array=owner.sim.state.duplicate()
	var values: PackedFloat64Array=owner.sim.continuous.duplicate()
	var main:=values.duplicate(); main[Flight.SOURCE_MODE_INDEX]=float(Flight.MODE_MAIN_TANK)
	var throttle: float=owner.sim.inputs[3]; var mode: int=owner.sim.modes[0]
	var cases: Array[Dictionary]=[_case("feed_main",body,main,throttle,mode)]
	var rng:=RandomNumberGenerator.new(); rng.seed=20261024
	for sample: int in 2:
		var moved:=body.duplicate()
		for axis: int in 3:
			moved[RB.VEL+axis]+=rng.randf_range(-14.0,19.0)
			moved[RB.RATE+axis]+=rng.randf_range(-1.7,1.7)
		cases.append(_case("maneuver_%d"%sample,moved,main,0.25 if sample==0 else 0.82,mode))
	var stopped:=main.duplicate()
	stopped[0]=0.0; stopped[5]=0.0; stopped[7]=0.0; stopped[8]=float(Flight.REASONS.find("not_started")); stopped[11]=0.0
	cases.append(_case("stopped",body,stopped,throttle,0))
	var starved:=stopped.duplicate(); starved[Flight.SOURCE_MODE_INDEX]=float(Flight.MODE_STARVED)
	starved[8]=float(Flight.REASONS.find("fuel_starved"))
	cases.append(_case("fuel_starved",body,starved,throttle,0))
	var cut:=Life.cut(Flight.unpack(main,owner.aircraft.model.propulsion.glow))
	if not cut.get("ok",false): return {"ok":false,"error":"required cut fixture failed: "+str(cut.get("message","unknown error"))}
	cases.append(_case("cut",body,Flight.put_state(main,cut.state),throttle,0))
	var invalid:=main.duplicate(); invalid[12]=NAN
	var bad:=_case("failure_invalid_nan",body,invalid,throttle,mode)
	bad.short_values=invalid.duplicate(); bad.short_values.resize(bad.short_values.size()-1); cases.append(bad)
	cases.append(_case("stale_identity",body,main,throttle,mode))
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	var feed_line_status := "skipped: installation has no feed_line"
	if install.has("feed_line") and values[Flight.LINE_FUEL_INDEX]>0.0:
		var line:=values.duplicate(); line[Flight.SOURCE_MODE_INDEX]=float(Flight.MODE_FEED_LINE)
		cases.append(_case("feed_line",body,line,throttle,mode))
		feed_line_status="covered"
	elif install.has("feed_line"):
		feed_line_status="skipped: initialized feed-line mass is not positive"
	if not install.has("fuel_feed"): cases.append(_case("non_feed_main",body,main,throttle,mode))
	return {"ok":true,"cases":cases,"feed_line_status":feed_line_status}
func _apply(owner: Node,s: Dictionary) -> void:
	owner.sim.state=s.body.duplicate(); owner.sim.continuous=s.values.duplicate()
	owner.sim.inputs=owner.sim.inputs.duplicate(); owner.sim.inputs[3]=s.throttle
	owner.sim.modes=owner.sim.modes.duplicate(); owner.sim.modes[0]=s.engine_mode
func _swap_meta(source: Node,target: Node) -> void:
	var saved: Dictionary={}
	for key: StringName in [Flight.EVALUATOR_META,Flight.PROPELLER_EVALUATOR_META,Flight.EVALUATOR_IDENTITY_META]:
		saved[key]=target.get_meta(key); target.set_meta(key,source.get_meta(key))
	target.set_meta(SAVE_META,saved)
func _restore_meta(owner: Node) -> void:
	var saved: Dictionary=owner.get_meta(SAVE_META,{})
	for key: Variant in saved: owner.set_meta(key,saved[key])
	owner.remove_meta(SAVE_META)
func _check(label: String,rf: Callable,ra: Array,cf: Callable,ca: Array,expect_ok: bool=true) -> Dictionary:
	var a: Variant=rf.callv(ra); var b: Variant=cf.callv(ca)
	var diff:=_diff(a,b,"$"); var aok:=_ok(a); var bok:=_ok(b)
	var passed := diff.is_empty() and aok == expect_ok and bok == expect_ok
	_comparisons+=1; _checksum+=int(aok)+int(bok)
	if not passed:
		_failures+=1; printerr("MISMATCH ",label,": ",diff if not diff.is_empty() else "unexpected success/failure")
	return {"operation":label,"equal":diff.is_empty(),"passed":passed,"mismatch":diff,"reference_ok":aok,"candidate_ok":bok}
func _ok(v: Variant) -> bool:
	return v is Dictionary and (bool(v.get("ok",false)) or (v.has("loads") and v.has("derivative")))
func _diff(a: Variant,b: Variant,path: String) -> String:
	if typeof(a)!=typeof(b): return "%s type %s != %s"%[path,type_string(typeof(a)),type_string(typeof(b))]
	if a is Dictionary:
		if a.size()!=b.size(): return path+" dictionary size differs"
		for k: Variant in a:
			if not b.has(k): return path+" missing "+str(k)
			var d:=_diff(a[k],b[k],path+"."+str(k))
			if not d.is_empty(): return d
		return ""
	if a is Array:
		if a.size()!=b.size(): return path+" array size differs"
		for i: int in a.size():
			var d:=_diff(a[i],b[i],path+"[%d]"%i)
			if not d.is_empty(): return d
		return ""
	if a is PackedFloat64Array: return "" if a.to_byte_array()==b.to_byte_array() else path+" float64 bytes differ"
	if a is PackedFloat32Array or a is PackedInt32Array or a is PackedInt64Array or a is PackedByteArray or a is PackedStringArray:
		return "" if var_to_bytes(a)==var_to_bytes(b) else path+" packed bytes differ"
	if typeof(a)==TYPE_FLOAT:
		return "" if PackedFloat64Array([a]).to_byte_array()==PackedFloat64Array([b]).to_byte_array() else path+" float bytes differ"
	return "" if a==b else path+" values differ"
func _float_control() -> bool:
	# Construct the sign bit at runtime; constant folding/Variant serialization
	# can canonicalize a literal -0.0 before this comparator is exercised.
	var negative_zero: float=PackedByteArray([0,0,0,0,0,0,0,128]).decode_double(0)
	var a: Dictionary={"nan":NAN,"zero":0.0,"negative_zero":negative_zero,"packed":PackedFloat64Array([NAN,0.0,negative_zero])}
	var b:=a.duplicate(true); var c:=a.duplicate(true); c.negative_zero=0.0
	return _diff(a,b,"$control").is_empty() and not _diff(a,c,"$control").is_empty()
func _bench(pr: Callable,pc: Callable,er: Callable,ec: Callable,ro: Node,co: Node,s: Dictionary) -> Dictionary:
	var body: PackedFloat64Array=s.body; var values: PackedFloat64Array=s.values
	var ops=[
		{"id":"point_coupled","r":pr,"c":pc,"ra":[ro,body,values,0.0,true],"ca":[co,body,values,0.0,true]},
		{"id":"evaluate","r":er,"c":ec,"ra":[body,values,0.0,ro],"ca":[body,values,0.0,co]}]
	for i: int in WARMUPS:
		for op: Dictionary in ops: op.r.callv(op.ra); op.c.callv(op.ca)
	var result: Dictionary={}
	for op: Dictionary in ops:
		var r: Array[float]=[]; var c: Array[float]=[]; var order: Array[String]=[]
		for batch: int in BATCHES:
			if batch%2==0:
				order.append("reference_then_candidate"); r.append(_measure(op.r,op.ra)); c.append(_measure(op.c,op.ca))
			else:
				order.append("candidate_then_reference"); c.append(_measure(op.c,op.ca)); r.append(_measure(op.r,op.ra))
		result[op.id]={"calls_per_batch":CALLS,"batch_order":order,"reference_us_per_call":r,
			"candidate_us_per_call":c,"reference_median_us":_median(r),"candidate_median_us":_median(c)}
	return {"warmup_calls_per_operation":WARMUPS,"batches":BATCHES,"results":result}
func _measure(f: Callable,args: Array) -> float:
	var start:=Time.get_ticks_usec()
	for i: int in CALLS: _checksum+=int(_ok(f.callv(args)))
	return float(Time.get_ticks_usec()-start)/float(CALLS)
func _median(values: Array[float]) -> float:
	var sorted: Array[float]=values.duplicate(); sorted.sort(); return sorted[sorted.size()/2]
func _input_fingerprint(owner: Node,body: PackedFloat64Array,values: PackedFloat64Array,call_time: float) -> String:
	var sim: Node=owner.sim
	var hash:=HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	var arrays := [sim.state.to_byte_array(),sim.previous.to_byte_array(),sim.continuous.to_byte_array(),
		sim.inputs.to_byte_array(),sim.aux.to_byte_array(),sim.modes.to_byte_array(),sim.inertia.to_byte_array(),
		body.to_byte_array(),values.to_byte_array()]
	for bytes: PackedByteArray in arrays: hash.update(bytes)
	for scalar: Variant in [sim.tick,sim.time(),sim.mass,sim.gravity,sim.paused,owner.engine_running,call_time]:
		hash.update(var_to_bytes(scalar))
	return hash.finish().hex_encode()
func _all_aircraft_complete(reports: Array[Dictionary]) -> bool:
	if reports.size() != AIRCRAFT.size(): return false
	for report: Dictionary in reports:
		if not bool(report.get("complete",false)): return false
	return true
func _sha(path: String) -> String:
	if not FileAccess.file_exists(path): return ""
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null: return ""
	var hash:=HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	hash.update(file.get_buffer(file.get_length())); file.close(); return hash.finish().hex_encode()


