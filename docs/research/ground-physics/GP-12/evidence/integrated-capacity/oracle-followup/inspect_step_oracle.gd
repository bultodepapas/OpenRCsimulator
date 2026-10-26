extends SceneTree
func _initialize()->void:
	var base:="C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/test-oracle-followup/"
	var data:Array=bytes_to_var(FileAccess.get_file_as_bytes(base+"production/app/tests/fixtures/ground_contact_capacity_legacy_steps.bin"))
	var rows:Array=[]
	for row:Dictionary in data:
		rows.append({fixture=row.fixture,law=row.law,ok=row.original_result.ok,status=row.original_result.status,
			state_present=row.original_result.has("state"),receipt_present=row.original_result.has("integration_receipt"),
			reason=row.original_result.get("reason","")})
		print("ORIGINAL_ORACLE ",JSON.stringify(rows[-1]))
	var f:=FileAccess.open(base+"original-step-outcomes.json",FileAccess.WRITE);f.store_string(JSON.stringify(rows,"\t",true,true));f.close()
	print("Original Step outcome inspection complete")
	quit()
