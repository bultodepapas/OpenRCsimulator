extends SceneTree
const C := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/candidate/contact_capacity.gd")
const S := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/candidate/aircraft_ground_step.gd")
const E := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/candidate/aircraft_ground_electric.gd")
func _initialize() -> void:
	print("SHAFT_DRAFT_PARSED ", C.CAPTURE_LAW, " ", S.INTEGRATED_CAPACITY_LAW, " ", E.CAPACITY_LAW)
	quit()
