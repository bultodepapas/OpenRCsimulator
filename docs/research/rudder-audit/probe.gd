# Diagnostic harness, outside app/: no production tuning. Run from the repo root:
# $(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/rudder-audit/probe.gd"
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

func _initialize() -> void:
	var session := Session.new()
	session.setup()
	root.add_child(session)
	# Counterfactual only; the app's data file is never written.
	var scale := OS.get_environment("RUDDER_CNDR_SCALE")
	if not scale.is_empty():
		assert(scale.is_valid_float() and float(scale) > 0.0)
		session.aircraft.model.aero.Cndr *= float(scale)
	var trace: RefCounted = Maneuvers.fly(session, Maneuvers.all().rudder_doublet)
	var beta_max := 0.0
	var roll_max := 0.0
	var yaw_rate_max := 0.0
	for row in trace.row_count():
		var u: float = trace.value(row, "u_mps")
		var v: float = trace.value(row, "v_mps")
		var w: float = trace.value(row, "w_mps")
		beta_max = maxf(beta_max, absf(rad_to_deg(atan2(v, sqrt(u*u + w*w)))))
		roll_max = maxf(roll_max, absf(trace.value(row, "roll_deg")))
		yaw_rate_max = maxf(yaw_rate_max, absf(rad_to_deg(trace.value(row, "r_radps"))))
	# Engineering screening limit, NOT an independently validated Ugly Stik flight limit.
	# A short rudder doublet should not leave the existing 15–25 degree sideslip blend region.
	var ok := beta_max <= 25.0
	print("RUDDER_SCREEN %s beta_peak=%.3f deg roll_peak=%.3f deg r_peak=%.3f deg/s" % ["PASS" if ok else "FAIL", beta_max, roll_max, yaw_rate_max])
	var out := OS.get_environment("RUDDER_AUDIT_OUT")
	if not out.is_empty():
		assert(trace.save(out.path_join("probe.csv")) == OK)
	session.free()
	quit(0 if ok else 1)
