extends SceneTree
const Flight := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-restore-transaction/flight_session.gd")
func _initialize() -> void:
	var f := Flight.new()
	f.input_enabled = false
	f.setup()
	var before: PackedByteArray = var_to_bytes(f.checkpoint())
	var bad: Dictionary = f.checkpoint()
	bad.format = []
	var result: bool = f.restore_checkpoint(bad)
	print("Malformed restore completed ", {accepted = result, transaction_active = f._reset_transaction_active,
		unchanged = before == var_to_bytes(f.checkpoint())})
	f.free()
	quit()
