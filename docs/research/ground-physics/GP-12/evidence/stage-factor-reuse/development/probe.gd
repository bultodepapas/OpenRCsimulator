extends SceneTree
const Old = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/baseline.gd")
const New = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/candidate.gd")
const M = preload("res://physics/math3d.gd")
var checks := 0
var failed := 0
func check(label: String, value: bool) -> void:
	checks += 1
	if not value:
		failed += 1
		printerr("FAIL ", label)
func _call(script: Script, args: Array) -> Dictionary:
	return script._evaluate_carrier.callv(args)
func _initialize() -> void:
	var cases: Array = []
	for count in [1,4,8,17]:
		for variant in 6:
			var axial := PackedFloat64Array()
			var transverse := PackedFloat64Array()
			var spin := PackedFloat64Array()
			var axes := PackedFloat64Array()
			var rates := PackedFloat64Array()
			var accelerations := PackedFloat64Array()
			var external := PackedFloat64Array()
			var internal := PackedFloat64Array()
			for i in count:
				axial.append(.01+.002*i)
				transverse.append(.006+.001*i)
				spin.append(0.0 if variant>=3 and i==0 else 10.0+i-variant)
				var axis := M.v3(float(1+i%2),float((i+variant)%3),float(1+variant%2))
				axes.append_array(M.scale(axis,1.0/M.norm(axis)))
				rates.append_array(M.v3(.01*variant,-.02*i,.03*variant))
				accelerations.append_array(M.v3(.04*i,.01*variant,-.01*i))
				external.append_array(M.v3(.03*variant,-.02*i,.01))
				internal.append(.1*variant-.03*i)
			var holds: Array = []
			if variant>=3:
				holds.append({rotor_index=0,capacity_nm=100.0 if variant<5 else 0.000001})
			var args: Array = [PackedFloat64Array([1.2+.1*variant,1.5,1.8,.02,-.03,.04]),axial,transverse,
				M.v3(.1*variant,-.3,.2),spin,axes,rates,accelerations,M.v3(.3,-.2,.1),external,internal,holds]
			var original := var_to_bytes(args)
			var expected := _call(Old,args)
			var actual := _call(New,args)
			check("complete moving/held result identical",var_to_bytes(expected)==var_to_bytes(actual))
			check("fixture args immutable",original==var_to_bytes(args))
			check("expected domain",expected.ok if variant<5 else not expected.ok)
			cases.append({args=args,expected=expected})
	# Refusal paths must still use the same gates and failure envelopes.
	for column in [0,1,3,4,5,6,7,8,9,10]:
		var args: Array = cases[0].args.duplicate(true)
		args[column]=PackedFloat64Array()
		var expected := _call(Old,args)
		check("malformed shapes still refuse byte exactly",not expected.ok and var_to_bytes(expected)==var_to_bytes(_call(New,args)))
		cases.append({args=args,expected=expected})
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-stage-factor/returns.bin",FileAccess.WRITE)
	f.store_buffer(var_to_bytes(cases));f.close()
	print("Stage factor reuse: ",checks," checks, ",failed," failed")
	quit(1 if failed else 0)
