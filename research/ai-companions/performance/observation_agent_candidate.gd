## AFC-00-R5 promotion draft: preserve the snapshot contract while avoiding full Air.compute output.
extends "res://ai/companions/agent.gd"

const ObservationAirdata := preload("res://../research/ai-companions/performance/observation_airdata_runtime_candidate.gd")


func observation() -> Dictionary:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var wind: PackedFloat64Array = session.wind_at(session.sim.time())
	return {
		id = "companion-%d" % slot_id,
		slot = slot_id,
		state = state,
		airspeed_m_s = ObservationAirdata.airspeed_m_s(state, wind),
		wind_ned = wind,
		ground_clearance_m = -state[2] - float(session.environment.ground(state[0], state[1])[0]),
		trim = _accepted_trim.duplicate(),
		turbulence_rms_m_s = _weather_rms.duplicate(),
		is_player = false,
	}
