extends "res://tests/test_aircraft_ground_unloaded.gd"
const Draft:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp/step_null.gd")
func _read_result(name:String)->Dictionary:
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp/"+name,FileAccess.READ)
	var result:Dictionary=bytes_to_var(f.get_buffer(f.get_length()));f.close();return result
func _initialize()->void:
	_fixture();_prepare_composition();_prepare_quality()
	var a:=_read_result("drop-candidate-0.25.bin")
	var b:=_read_result("drop-production-0.25.bin")
	var timings:={candidate_elapsed_ms=a.elapsed_ms,production_elapsed_ms=b.elapsed_ms}
	a.erase("elapsed_ms");b.erase("elapsed_ms")
	var equal:=var_to_bytes(a)==var_to_bytes(b)
	check("complete accepted final frame and receipt-summary bytes match",equal)
	lift_start=b.lift_start;lift_duration=b.lift_duration;lift_ratio=b.lift_ratio;brake_start=b.brake_start
	_bind()
	var next_a:=Draft.advance(a.state,a.time_s,a.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,_options(),_gate,_policy)
	var next_b:=Candidate.advance(b.state,b.time_s,b.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,_options(),_gate,_policy)
	check("complete continued Step result bytes match",var_to_bytes(next_a)==var_to_bytes(next_b))
	check("both continued steps independently accept",next_a.ok and next_b.ok,str(next_b))
	if next_a.ok and next_b.ok:check("complete continued accepted receipt bytes match",var_to_bytes(next_a.integration_receipt)==var_to_bytes(next_b.integration_receipt))
	var report:={accepted_archive_equal_excluding_elapsed=equal,continued_result_equal=var_to_bytes(next_a)==var_to_bytes(next_b),continued_accept=next_b.ok,
		continued_candidate=next_a,continued_production=next_b,timings=timings,
		limitation="full180archives retain frame and accumulated/last receipt summary; full transient receipt comparison is the independently accepted following tick"}
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp/production-comparison.bin",FileAccess.WRITE)
	f.store_buffer(var_to_bytes(report));f.close()
	f=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp/production-comparison.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print("Production gentle comparison: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
