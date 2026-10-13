## Hub kinematics must use the same fixed-datum arm as the thrust moment.
extends SceneTree
const Fixture := preload("res://tests/test_glow_flight_physics.gd")
const Aircraft := preload("res://physics/aircraft_data.gd")
const Flight := preload("res://physics/glow/flight.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	for name: String in ["55ax_2t", "fs64v_4t", "55ax_2t_apc_13x6", "fs64v_4t_apc_13x6"]:
		var aircraft := Aircraft.load_file("res://data/aircraft/stik_glow_" + name + ".json")
		_check(aircraft.ok, name + " loads")
		if not aircraft.ok: continue
		var model: Dictionary=aircraft.model
		# Synthetic oblique installation with a nonzero arm in every coordinate.
		model.propulsion.offset=PackedFloat64Array([-.37,.08,.06])
		model.propulsion.axis=M.scale(PackedFloat64Array([1.,.07,-.04]),1./sqrt(1.+.07*.07+.04*.04))
		var owner=Fixture.FlightOwner.new()
		owner.aircraft={model=model}
		owner.sim={inputs=PackedFloat64Array([0.,0.,0.,.6]),aux=PackedFloat64Array([6000.]),gravity=0.}
		var values:=Flight.initial(owner,PackedFloat64Array([6000.]))
		for case: Dictionary in [
			{label="static",v=PackedFloat64Array([0.,0.,0.]),w=PackedFloat64Array([0.,0.,0.])},
			{label="translation",v=PackedFloat64Array([16.,-2.,3.]),w=PackedFloat64Array([0.,0.,0.])},
			{label="pitch yaw roll",v=PackedFloat64Array([16.,-2.,3.]),w=PackedFloat64Array([.8,-1.3,2.1])},
			{label="opposite rotation",v=PackedFloat64Array([16.,-2.,3.]),w=PackedFloat64Array([-.8,1.3,-2.1])},
			{label="reverse inflow",v=PackedFloat64Array([-9.,1.,-2.]),w=PackedFloat64Array([.8,-1.3,2.1])},
		]:
			var body:=RB.make_state(PackedFloat64Array([0.,0.,0.]),case.v,PackedFloat64Array([1.,0.,0.,0.]),case.w)
			var body_before:=body.to_byte_array()
			var values_before:=values.to_byte_array()
			var point: Dictionary=Flight.point(owner,body,values,0.)
			var label: String=name+" "+case.label
			_check(point.get("ok",false),label+" evaluates")
			if not point.get("ok",false): continue
			# Independent vector rigid-body transport, unlike the scalar implementation.
			var hub:=PackedFloat64Array([.37,.08,-.06])
			var expected_velocity: PackedFloat64Array=M.add(case.v,M.cross(case.w,hub))
			var expected: Dictionary=Blade.evaluate(6000.,M.dot(expected_velocity,model.propulsion.axis),1.225,model.propulsion.glow.propeller)
			_check(expected.ok,label+" independent blade input evaluates")
			if not expected.ok: continue
			_near(point.propeller.thrust_n,expected.thrust_n,label+" thrust samples hub")
			_near(point.propeller.torque_nm,expected.torque_nm,label+" torque samples hub")
			_near(point.propeller.thrust_power_w,expected.thrust_power_w,label+" work samples hub")
			var loads:=Propulsion.loads_from_thrust_torque(case.v,6000.,model.propulsion,1.225,point.propeller.thrust_n,0.)
			var datum_power: float=M.dot(loads.slice(0,3),case.v)+M.dot(loads.slice(3,6),case.w)
			_near(datum_power,point.propeller.thrust_power_w,label+" force and arm moment close hub power")
			_check(body.to_byte_array()==body_before and values.to_byte_array()==values_before,label+" observer preserves state")
			if M.norm(case.w)>0.:
				var old:=Blade.evaluate(6000.,M.dot(case.v,model.propulsion.axis),1.225,model.propulsion.glow.propeller)
				_check(absf(old.thrust_n-point.propeller.thrust_n)>1e-5,label+" detects omitted hub rotation")
			else:
				_check(point.propeller==expected,label+" zero-rate static/translation loads remain identical")
		# Fuel removal changes CM, not the body-fixed datum or the attached hub.
		var moving:=RB.make_state(PackedFloat64Array([0.,0.,0.]),PackedFloat64Array([16.,-2.,3.]),PackedFloat64Array([1.,0.,0.,0.]),PackedFloat64Array([.8,-1.3,2.1]))
		var full:=Flight.point(owner,moving,values,0.)
		values[1]*=.25
		var partial:=Flight.point(owner,moving,values,0.)
		_check(full.ok and partial.ok and full.propeller==partial.propeller,name+" moving fuel CG cannot move the hub datum")
		owner.free()
	print("Glow hub inflow: %d checks, %d failed" % [checks,failures])
	quit(1 if failures else 0)

func _near(actual: float,expected: float,label: String) -> void:
	_check(is_finite(actual) and absf(actual-expected)<=1e-10*maxf(1.,absf(expected)),label)

func _check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		printerr("FAIL "+label)
