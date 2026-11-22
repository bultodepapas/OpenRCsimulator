extends SceneTree
const Data := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Wake := preload("res://physics/slipstream.gd")
const Prop := preload("res://physics/propulsion.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var model_result: Dictionary = Data.load_file("res://r4_candidate.json")
	if not model_result.ok:
		print("R4_CONTROL_FAIL loader: ", model_result.errors)
		quit(1)
		return
	var model: Dictionary = model_result.model
	var s := PackedFloat64Array([0.0, 0.0, -20.0, 12.0, 0.5, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var rho := 1.225
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), rho)
	var d := {elevator=0.0, aileron_left=0.0, aileron_right=0.0, rudder=0.0}
	var prop: Dictionary = model.propulsion
	var tq: PackedFloat64Array = Prop.thrust_torque(air.v_air, 5000.0, prop, rho)
	var wake: Dictionary = Wake.wake(air.v_air, tq[0], tq[1], prop, rho)
	var immersion: Dictionary = Wake.immersion(prop.slipstream.pieces[0], wake, prop.slipstream.hub, prop,
		air.v_air, air.V, model)
	var stopped: Variant = Wake.stage_loads(s, air, d, model, 0.0, rho, NAN, PackedFloat64Array(), 1, PackedFloat64Array())
	# Diagnostic shim only: inserting an empty absent-tail dictionary is not a source-admitted model or proposed fix.
	# It lets the same real component reach its vertical-only force calculation for comparison.
	var shim: Dictionary = model.duplicate(true)
	shim.surfaces.horizontal = {}
	var recovered: Variant = Wake.stage_loads(s, air, d, shim, 5000.0, rho, NAN, PackedFloat64Array(), 1, PackedFloat64Array())
	var magnitude := 0.0
	if recovered is PackedFloat64Array and recovered.size() == 6:
		for c: float in recovered:
			magnitude += absf(c)
	var passed: bool = not model.surfaces.has("horizontal") and tq[0] > 0.0 and wake.dv > 0.0 and immersion.area > 0.0 \
		and stopped is PackedFloat64Array and stopped == PackedFloat64Array([0,0,0,0,0,0]) \
		and recovered is PackedFloat64Array and recovered.size() == 6 and magnitude > 1.0e-8
	print("R4_COMPONENT_CONTROLS ", JSON.stringify({rpm=5000.0, air=air.v_air, tq=tq, wake=wake,
		immersed_area_m2=immersion.area, stopped=stopped, shimmed_5000_rpm=recovered, shim_abs_sum=magnitude,
		shim_scope="local in-memory empty-horizontal dictionary; no loader/session/native validity"}))
	print("R4_CONTROLS_COMPLETE ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
