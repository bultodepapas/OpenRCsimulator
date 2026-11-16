extends "refinement_audit.gd"
## New-law campaign, never a migration or an automatic flight qualification.
## Registration: docs/research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md.
const ServoLaw := preload("res://physics/slew_trajectory.gd")
const Vehicle := preload("res://sim/vehicle_model.gd")
const CAMPAIGN_ID := "ac12-normalized-slew-arrivals-local-v1-20261116"


func registered_cells() -> Array:
	var cells: Array = []
	for index: int in range(1,18):
		for tape: String in TAPES:
			cells.append("C%02d/%s" % [index,tape])
	return cells


func audited_definition(value: Dictionary) -> Dictionary:
	var selected := value.duplicate(true)
	selected.format = Definition.SERVO_FORMAT
	selected.servo_integration = ServoLaw.LAW
	return selected


func candidate_is_admitted(candidate: RefCounted,definition: Dictionary) -> bool:
	return definition.get("format")==Definition.SERVO_FORMAT and definition.get("servo_integration")==ServoLaw.LAW \
		and candidate.flight_data().get("model",{}).get("controls",{}).get("servo_integration")==ServoLaw.LAW


func session_is_admitted(session: Node,_candidate: RefCounted) -> bool:
	if not session.servo_reference_selected() or session.sim.model.callback_protocol!=Vehicle.PROTOCOL_JOINT_INTERVAL_LOCAL \
		or session.sim.model.identity.get("servo_integration")!=ServoLaw.LAW:
		return false
	var header := {metadata=session.trace_meta(),checkpoint=session.checkpoint(),aircraft=session.aircraft,
		stage_backend=session.stage_backend_identity(),layout={state=13,loads=6,inputs=session.sim.inputs.size(),
		aux=session.sim.aux.size(),continuous=session.sim.continuous.size(),modes=session.sim.modes.size()}}
	var declared: Dictionary = LogReader.recorded_servo_declaration(header)
	return declared.ok and declared.declared


func baseline_replay_is_admitted(report: Dictionary) -> bool:
	var group: Variant = report.get("servo_integration")
	if not group is Dictionary or group.get("checkpoint_migration")!="none" \
		or not group.get("recorded") is Dictionary or group.get("recorded")!=group.get("replay"):
		return false
	return group.recorded.get("law")==ServoLaw.LAW and group.recorded.get("protocol")==Vehicle.PROTOCOL_JOINT_INTERVAL_LOCAL


func _source_context() -> Dictionary:
	var value := super._source_context()
	# A selecting entrypoint may inherit this intermediate module from outside res://.
	# Pin it explicitly; the generic audit already pins the entrypoint and its own owner.
	value.sources["servo_arrival_campaign.gd"] = FileAccess.get_sha256(_folder().path_join("servo_arrival_campaign.gd"))
	value.campaign_id = CAMPAIGN_ID
	value.servo_integration_law = ServoLaw.LAW
	value.servo_interval_protocol = Vehicle.PROTOCOL_JOINT_INTERVAL_LOCAL
	return value
