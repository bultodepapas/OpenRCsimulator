extends SceneTree
## Observations of two suspected gaps, with a valid rotating-servo control case.
const MotionFixture := preload("res://tests/test_creator_clearview_motion.gd")
const Images := preload("res://workshop/creator/clearview/images.gd")

func _initialize() -> void:
	var report := {base_commit = "2a3cf04dbbdaf486b9c9c8e983463d828f90c64a", cases = []}
	for movement: String in ["rotate", "move", "input"]:
		var params: String = MotionFixture._params().replace("controlledPartMovement rotate", "controlledPartMovement " + movement)
		var converted: Dictionary = MotionFixture._convert(MotionFixture._body(),params)
		var row := {case_name = "targeted_servo_" + movement, ok = converted.ok, diagnostics = converted.diagnostics}
		if converted.ok:
			row.prepared = converted.value.receipt.coordinate_frames.prepared.size()
			row.unresolved = converted.value.receipt.coordinate_frames.unresolved
		report.cases.append(row)
	var polls := [0]
	var png := Image.create_from_data(1,1,false,Image.FORMAT_RGBA8,PackedByteArray([255,0,0,128])).save_png_to_buffer()
	var normalized: Dictionary = Images.normalize(png,func() -> bool:
		polls[0] += 1
		return true)
	report.cases.append({case_name = "already_cancelled_png", ok = normalized.ok, callback_polls = polls[0], diagnostics = normalized.diagnostics})
	print("AUDIT_GAPS_JSON: ", JSON.stringify(report,"",true,true))
	print("AUDIT_GAPS_COMPLETE")
	quit(0)
