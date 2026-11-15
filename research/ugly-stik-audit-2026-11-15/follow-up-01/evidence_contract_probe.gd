# Exercise the production flight card's handling of an explicitly shortened flight.
# This research subclass changes only the safety floor for the power-step cases.
# It does not change production equations, controls, aircraft data or card code.
# Results demonstrate a reporting contract under an injected stop condition, not
# that a stock power-step campaign necessarily reaches its ordinary 60 m floor.
extends "res://../research/flight-test/flight_test.gd"

var _audit_flights: Array[Dictionary] = []


func _fly(name: String, start: Dictionary, seconds: float, pilot: Callable, stop := Callable()) -> Dictionary:
	var request: Dictionary = start.duplicate(true)
	if name == "power_step":
		request.floor = 399.0 # Card starts at 400 m; retain an early clean stop.
	var result: Dictionary = super._fly(name, request, seconds, pilot, stop)
	var record := {"test": name, "requested_duration_s": seconds, "injected_floor_m": request.get("floor", null),
		"ok": result.get("ok", false), "crashed": result.get("crashed", "")}
	if result.get("ok", false):
		var trace: RefCounted = result.trace
		record.case = result.ctx.get("suffix", "")
		record.loop_t_end_s = result.t_end
		record.last_recorded_t_s = trace.value(trace.row_count() - 1, "t_s")
		record.floor_t_s = result.ctx.get("floor_t", null)
		record.rows = trace.row_count()
	_audit_flights.append(record)
	return result


func _write_report() -> void:
	super._write_report()
	print("FOLLOWUP_EVIDENCE_JSON ", JSON.stringify(_finite_json({
		"format": "openrc-audit-card-floor-v1",
		"baseline": "00610ce3df391560dc195444d797bb81f2f83270",
		"scope": "Injected 399 m safety floor in a research subclass; unchanged production flight and metric code.",
		"flights": _audit_flights,
		"power_step": results.get("power_step", {})})))
	print("FOLLOWUP_EVIDENCE_COMPLETE")
