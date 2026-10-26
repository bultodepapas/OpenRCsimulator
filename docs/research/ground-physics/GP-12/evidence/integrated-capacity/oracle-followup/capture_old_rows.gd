## Read-only execution of the pinned PREPROMOTION owner/row builder.
extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/tests/test_aircraft_ground_unloaded.gd"
func _initialize()->void:
	_fixture()
	_prepare_composition()
	_prepare_quality()
	_bind()
	var cases:Array=[]
	var downs:=[-1.0,-.2,-.15,-.1]
	var banks:=[0.0,.15]
	var brakes:Array=[PackedFloat64Array([0.0,0.0,0.0]),PackedFloat64Array([.7,.2,0.0])]
	for d in downs.size():
		for b in banks.size():
			var state:=_initial(downs[d],3.0,.2,0.0)
			var q:=M.q_from_euler(banks[b],.02,.1)
			for i in 4:state[RB.ATT+i]=q[i]
			var point:=_snapshot(state,0.0)
			check("original row input valid",point.ok,str(point))
			if not point.ok:continue
			for k in brakes.size():
				var brake:PackedFloat64Array=brakes[k]
				var pin:=var_to_bytes([traction,state,live.cg_body_m,point.physical.ground,brake])
				var original:=Traction.evaluate(traction,state.slice(0,RB.SIZE),live.cg_body_m,point.physical.ground,brake)
				check("original old row result valid and input immutable",original.ok and pin==var_to_bytes([traction,state,live.cg_body_m,point.physical.ground,brake]))
				cases.append({id="down_%d/bank_%d/brake_%d"%[d,b,k],state=state.slice(0,RB.SIZE),ground=point.physical.ground.duplicate(true),brake=brake.duplicate(),expected_bytes=var_to_bytes(original)})
	var oracle:={format="openrc-frozen-traction-legacy-rows v1",law="fixed-hub-wheel-material-impulse-rows-v1",prepared=traction.duplicate(true),cg_body_m=live.cg_body_m.duplicate(),cases=cases}
	check("original sixteen row cases captured",cases.size()==16)
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/test-oracle-followup/production/app/tests/fixtures/ground_contact_capacity_legacy_rows.bin",FileAccess.WRITE)
	check("new isolated oracle output opens",f!=null)
	if f!=null:f.store_buffer(var_to_bytes(oracle));f.close()
	print("Original legacy row capture: ",checks," checks, ",failed," failed")
	quit(1 if failed else 0)
