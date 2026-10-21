## AFC-09 research classifier for the unchanged external-sortie approach gate envelope.
## It reports readiness only; it does not steer, reset state, or initiate a go-around.
extends RefCounted

const TARGET_HEIGHT_M := 6.0
const HEIGHT_TOLERANCE_M := 0.5
const TARGET_AIRSPEED_MPS := 12.0
const AIRSPEED_TOLERANCE_MPS := 0.5
const CROSS_TRACK_TOLERANCE_M := 1.0
const GATE_POSITION_TOLERANCE_M := 0.25
const HEADING_TOLERANCE_RAD := 0.13962634015954636 # 8 degrees
const BANK_TOLERANCE_RAD := 0.08726646259971647 # 5 degrees
const SINK_TOLERANCE_MPS := 1.0


static func classify(metrics: Dictionary) -> Dictionary:
	var reasons: PackedStringArray = []
	var altitude: float = _number(metrics, "altitude_m")
	var airspeed: float = _number(metrics, "airspeed_mps")
	var north: float = _number(metrics, "north_m")
	var runway_north: float = _number(metrics, "runway_center_north_m")
	var east: float = _number(metrics, "east_m")
	var expected_east: float = _number(metrics, "expected_east_m")
	var yaw: float = _number(metrics, "yaw_rad")
	var expected_heading: float = _number(metrics, "expected_heading_rad")
	var bank: float = _number(metrics, "bank_rad")
	var sink: float = _number(metrics, "sink_mps")
	var ground_speed: float = _number(metrics, "ground_speed_mps")
	if not is_finite(altitude) or absf(altitude - TARGET_HEIGHT_M) > HEIGHT_TOLERANCE_M:
		reasons.append("altitude")
	if not is_finite(airspeed) or absf(airspeed - TARGET_AIRSPEED_MPS) > AIRSPEED_TOLERANCE_MPS:
		reasons.append("airspeed")
	if not is_finite(north) or not is_finite(runway_north) \
			or absf(north - runway_north) > CROSS_TRACK_TOLERANCE_M:
		reasons.append("cross_track")
	if not is_finite(east) or not is_finite(expected_east) \
			or absf(east - expected_east) > GATE_POSITION_TOLERANCE_M:
		reasons.append("gate_position")
	if not is_finite(yaw) or not is_finite(expected_heading) \
			or absf(wrapf(yaw - expected_heading, -PI, PI)) > HEADING_TOLERANCE_RAD:
		reasons.append("heading")
	if not is_finite(bank) or absf(bank) > BANK_TOLERANCE_RAD:
		reasons.append("bank")
	if not is_finite(sink) or absf(sink) > SINK_TOLERANCE_MPS:
		reasons.append("sink")
	if not is_finite(ground_speed):
		reasons.append("ground_speed")
	var prediction_valid: Variant = metrics.get("gate_prediction_valid", false)
	if typeof(prediction_valid) != TYPE_BOOL or not prediction_valid:
		reasons.append("gate_prediction")
	return {ready = reasons.is_empty(), reasons = Array(reasons)}


static func _number(metrics: Dictionary, key: String) -> float:
	var value: Variant = metrics.get(key, NAN)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	return float(value)
