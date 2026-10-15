## Original identity work over the same current artifact bytes; equations are inherited.
extends "res://sim/ground_vehicle/session.gd"
const BaselineArtifacts := preload("res://../research/rc-monster-truck/monster-car-2/rcv41/baseline_artifacts.gd")

func _backend_identity_for_model(model: Dictionary) -> Dictionary:
	if not _uses_nitro(model): return VehicleDynamics.backend_identity()
	var base: Dictionary = VehicleDynamics.backend_identity()
	var adapter: Dictionary = BaselineArtifacts._reference_implementation_artifact(NitroDynamics.SOURCE_PATH)
	var body_artifact: Dictionary = BaselineArtifacts._reference_implementation_artifact("res://physics/ground_vehicle/vehicle_dynamics.gd")
	var payload := {
		"adapter_source_sha256": str(adapter.get("sha256", "")),
		"body_source_sha256": str(body_artifact.get("sha256", "")),
		"body_backend": base,
	}
	var source_sha256 := NitroDynamics._sha256(JSON.stringify(payload, "", true, true))
	var identity := base.duplicate(true)
	identity["backend_version"] = NitroDynamics.BACKEND_VERSION + "+" + str(base.get("backend_version", ""))
	identity["solver_version"] = NitroDynamics.SOLVER_VERSION + "+" + str(base.get("solver_version", ""))
	identity["source_sha256"] = source_sha256
	identity["implementation_artifact_kind"] = str(adapter.get("kind", "gdscript_source"))
	return identity

func _sha256_field_is_valid(value: Variant, allow_empty: bool) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var digest := str(value)
	if digest.is_empty():
		return allow_empty
	if digest.length() != 64 or digest.to_lower() != digest:
		return false
	for character in digest:
		if not str(character) in "0123456789abcdef":
			return false
	return true
