extends RefCounted

const FlightSession := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-lake/draft/flight_session.gd")

## Model nodes needed by crash presentation. Physics ownership remains in the session.
class ModelBindings extends RefCounted:
	var root: Node3D
	var propeller: Node3D
	var empty := true

	func has_aircraft() -> bool:
		return not empty and is_instance_valid(root)


var session: FlightSession
var model_bindings: ModelBindings
var field: Dictionary = {}
var aircraft_id := ""
var workshop_trial: Dictionary = {}
var aircraft_data_path := ""
var cg_model := Vector3.ZERO
var pose_provider: Callable
var wind_provider: Callable
var shadow: MeshInstance3D
var sun: DirectionalLight3D
var propeller_blur: Node3D


func is_valid() -> bool:
	var raw_bytes: Variant = workshop_trial.get("raw_bytes") if not workshop_trial.is_empty() else PackedByteArray()
	var trial_bytes_valid: bool = workshop_trial.is_empty() or raw_bytes is PackedByteArray
	return is_instance_valid(session) and session.has_signal("resetting") \
		and model_bindings != null and model_bindings.has_aircraft() \
		and not aircraft_data_path.is_empty() \
		and (not workshop_trial.is_empty() or FileAccess.file_exists(aircraft_data_path)) \
		and trial_bytes_valid and pose_provider.is_valid() and wind_provider.is_valid()


func current_pose() -> Dictionary:
	var value: Variant = pose_provider.call()
	return value if value is Dictionary else {}


func render_wind(time_s: float) -> Vector3:
	var value: Variant = wind_provider.call(time_s)
	return value if value is Vector3 else Vector3.ZERO
