extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

const CASES := [
	{
		"name": "D11g current regenerated values",
		"Cmq": -8.009,
		"CLq": 2.003,
		"Cnr": -0.1335,
	},
	{
		"name": "D11g preserved pre-regeneration values",
		"Cmq": -7.944,
		"CLq": 1.977,
		"Cnr": -0.1354,
	},
	{
		"name": "new Cmq/CLq with old Cnr",
		"Cmq": -8.009,
		"CLq": 2.003,
		"Cnr": -0.1354,
	},
	{
		"name": "old Cmq/CLq with new Cnr",
		"Cmq": -7.944,
		"CLq": 1.977,
		"Cnr": -0.1335,
	},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saved_hz: int = Engine.physics_ticks_per_second
	for hz in [240, 480]:
		for coeffs in CASES:
			_run_case(int(hz), coeffs)
	Engine.physics_ticks_per_second = saved_hz
	quit()


func _run_case(hz: int, coeffs: Dictionary) -> void:
	Engine.physics_ticks_per_second = hz
	var session: Node = Session.new()
	session.setup()
	session.reset()
	root.add_child(session)
	var model_id := str(session.aircraft.model.id)
	session.aircraft.model.aero.Cmq = float(coeffs.Cmq)
	session.aircraft.model.aero.CLq = float(coeffs.CLq)
	session.aircraft.model.aero.Cnr = float(coeffs.Cnr)
	var maneuver: Dictionary = Maneuvers.all().rudder_doublet.duplicate()
	var trace: RefCounted = Maneuvers.fly(session, maneuver)
	var expected_rows := 3 * hz + 1
	var dt := float(trace.value(1, "t_s") - trace.value(0, "t_s"))
	var at_3s := roundi(3.0 / dt)
	var yaw_at_3s := rad_to_deg(float(trace.value(at_3s, "r_radps")))
	var peak_yaw_deg_s := 0.0
	for row in trace.row_count():
		peak_yaw_deg_s = maxf(peak_yaw_deg_s, absf(rad_to_deg(float(trace.value(row, "r_radps")))))
	print("case=%s hz=%d aircraft=%s model_Cmq=%.6f model_CLq=%.6f model_Cnr=%.6f rows=%d expected_rows=%d dt=%.12f r_at_3s_deg_s=%.9f r_final_deg_s=%.9f peak_abs_r_deg_s=%.9f" % [
		str(coeffs.name), hz, model_id,
		float(coeffs.Cmq), float(coeffs.CLq), float(coeffs.Cnr),
		trace.row_count(), expected_rows, dt, yaw_at_3s,
		rad_to_deg(float(trace.value(trace.row_count() - 1, "r_radps"))),
		peak_yaw_deg_s,
	])
	if trace.row_count() != expected_rows or at_3s != 3 * hz:
		printerr("invalid capture shape or 3 s sample for %s at %d Hz" % [str(coeffs.name), hz])
		quit(2)
	session.free()
