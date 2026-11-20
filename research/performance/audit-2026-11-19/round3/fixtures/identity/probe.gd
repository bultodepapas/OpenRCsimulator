extends SceneTree
const Nitro := preload("res://physics/ground_vehicle/nitro_dynamics.gd")
const Body := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const CALLS := 240
func _initialize() -> void:
	var nitro := Nitro.backend_identity()
	var body := Body.backend_identity()
	var valid := str(nitro.source_sha256).length() == 64 and str(body.source_sha256).length() == 64
	print("R3_IDENTITY_BEGIN nitro")
	for _i in CALLS:
		valid = Nitro.backend_identity() == nitro and valid
	print("R3_IDENTITY_END nitro")
	print("R3_IDENTITY_BEGIN body")
	for _i in CALLS:
		valid = Body.backend_identity() == body and valid
	print("R3_IDENTITY_END body")
	print("IDENTITY_JSON ", JSON.stringify({"calls_per_case": CALLS, "identities_equal": valid,
		"body_backend": body.backend, "engine": Engine.get_version_info().string}))
	print("IDENTITY_PROBE_COMPLETE expected_observation=", valid)
	quit(0 if valid else 1)
