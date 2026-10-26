extends SceneTree
const Legacy := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp20-brake-input/reader/before.gd")
func _initialize() -> void:
	var reference := {format = "openrc-historical-flight-log-columns v1", cases = {}}
	for width in [4, 5, 6, 7]:
		var layout := {state = 13, loads = 6, inputs = width, aux = 12, continuous = 8, modes = 2, mass = 4}
		reference.cases[str(width)] = {layout = layout, columns = Array(Legacy.columns(layout))}
	var file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp20-brake-input/reader/flight_log_input_columns.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reference, "\t", true, true) + "\n")
	file.close()
	print("Historical input columns frozen: 4 layouts")
	quit()
