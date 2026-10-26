extends SceneTree
const Old := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/baseline.gd")
const New := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/candidate.gd")
func _timed(script: Script, args: Array, count: int) -> Dictionary:
	var last := {}
	var started := Time.get_ticks_usec()
	for _i in count: last = script._evaluate_carrier.callv(args)
	return {elapsed_us=Time.get_ticks_usec()-started,last=last}
func _initialize() -> void:
	var cases: Array = bytes_to_var(FileAccess.get_file_as_bytes("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/returns.bin"))
	var args: Array = cases[6].args
	var old := _timed(Old,args,50)
	var next := _timed(New,args,50)
	var pairs: Array = []
	var same := var_to_bytes(old.last)==var_to_bytes(next.last)
	for i in 8:
		if i%2==0:
			old=_timed(Old,args,300);next=_timed(New,args,300)
		else:
			next=_timed(New,args,300);old=_timed(Old,args,300)
		same = same and var_to_bytes(old.last)==var_to_bytes(next.last)
		pairs.append({baseline_us=old.elapsed_us,candidate_us=next.elapsed_us})
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/benchmark.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({format="openrc-rotor-factor-benchmark-v1",loops=300,warmup=50,interleaved_pairs=pairs,complete_returns_equal=same,scope="isolated four-rotor microbenchmark; shared host; no real-time qualification"},"\t"));f.close()
	print("Stage factor benchmark: ",1," checks, ",0 if same else 1," failed")
	quit(0 if same else 1)
