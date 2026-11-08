## F6: a Nitro checkpoint also binds the changed ground-vehicle body law.
extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(label: String, passed: bool) -> void:
	checks += 1
	if passed:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func run() -> void:
	check("reference backend selected", Vehicle.set_backend_override_for_tests("gdscript_reference"))
	var session := Session.new()
	root.add_child(session)
	var prepared: bool = session.prepare_default({}, "monster-car-2")
	check("Nitro session prepares", prepared)
	if prepared:
		var initial: PackedFloat64Array = session.state_snapshot()
		var current: Dictionary = session.checkpoint()
		check("Nitro checkpoint binds v6 and restores unchanged", not current.is_empty()
			and str(current.solver_identity.solver_version).ends_with("+" + Vehicle.SOLVER_VERSION)
			and session.can_restore_checkpoint(current) and session.restore_checkpoint(current)
			and session.state_snapshot().to_byte_array() == initial.to_byte_array())
		var legacy: Dictionary = current.duplicate(true)
		legacy.solver_identity.solver_version = str(legacy.solver_identity.solver_version).replace("rk4-v6", "rk4-v5")
		legacy.solver_identity.backend_identity.solver_version = str(legacy.solver_identity.backend_identity.solver_version).replace("rk4-v6", "rk4-v5")
		legacy.solver_identity.backend_identity.backend_version = str(legacy.solver_identity.backend_identity.backend_version).replace("rk4-v6", "rk4-v5")
		legacy.checkpoint_sha256 = session._checkpoint_hash(legacy)
		check("self-hashed simulated v5 Nitro identity is refused atomically", not session.can_restore_checkpoint(legacy)
			and not session.restore_checkpoint(legacy) and session.tick == 0
			and session.state_snapshot().to_byte_array() == initial.to_byte_array()
			and session.control_tape_snapshot().is_empty())
		legacy.solver_identity.erase("backend_identity")
		legacy.checkpoint_sha256 = session._checkpoint_hash(legacy)
		check("legacy identity without backend cannot bypass v5 refusal", not session.can_restore_checkpoint(legacy)
			and not session.restore_checkpoint(legacy) and session.state_snapshot().to_byte_array() == initial.to_byte_array())
	session.free()
	print("Nitro F6 identity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
