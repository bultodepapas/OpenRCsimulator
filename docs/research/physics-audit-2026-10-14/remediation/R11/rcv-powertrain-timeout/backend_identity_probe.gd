extends SceneTree

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")


func _initialize() -> void:
	var identity: Dictionary = Vehicle.backend_identity()
	var native_instance: Object = Vehicle._load_native_backend()
	print("R11_RCV_BACKEND_IDENTITY " + JSON.stringify(identity))
	print("R11_RCV_NATIVE_INSTANCE " + str(native_instance != null))
	quit(0 if identity.get("backend", "") == Vehicle.BACKEND_NATIVE and native_instance != null else 1)
