extends "res://tests/test_normal_compliance.gd"

func _initialize() -> void:
	var rows: Array = []
	for exponent: int in [1,2,3]:
		for onset: float in [0.0,.002,.04]:
			var raw := _raw()
			raw.stop_exponent.value=float(exponent)
			raw.damping_onset.value=onset
			var law:=C.prepare(raw)
			var samples:Array=[]
			for x:float in [-.01,0.0,1e-12,.001,.002,.019,.02,.021,.03,.04]:
				for v:float in [-3.0,-.1,0.0,.1,3.0]: samples.append(C.evaluate(law,x,v))
			var bounds:Array=[]
			for xmax:float in [0.0,.001,.02,.025,.04]:bounds.append(C.bounds(law,xmax,3.0))
			rows.append([var_to_bytes(law).hex_encode().sha256_text(),var_to_bytes(samples).hex_encode().sha256_text(),
				var_to_bytes(bounds).hex_encode().sha256_text(),var_to_bytes(C.scalar_substeps(law,.04,3.0,2.0,1.0/240.0)).hex_encode().sha256_text()])
	print("LEGACY_FUNCTION_HASHES ",JSON.stringify(rows))
	var file:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp11-local-envelope/legacy-function-hashes.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({source="unmodified production NormalCompliance",serialization="SHA256 of complete Variant bytes encoded as hex",
		fixture_order="exponent1/2/3 outer; onset0/.002/.04 inner",columns=["prepare","50 evaluate results","5 bounds results","scalar_substeps"],hashes=rows},"\t",true,true))
	file.close()
	print("Legacy function hash capture complete")
	quit(0)
