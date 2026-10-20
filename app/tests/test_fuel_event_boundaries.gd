extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const CheckpointJson := preload("res://sim/checkpoint_json.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	for name: String in ["stik_glow_61fx_2t", "stik_glow_fs64v_4t", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var flight := Flight.new()
		flight.input_enabled=false
		flight.setup("res://data/aircraft/"+name+".json")
		check(name+" prepares",flight.is_flyable() and flight.finite_fuel_is_active())
		if not flight.is_flyable(): flight.free(); continue
		var glow: bool=flight.glow_is_active()
		var index: int=1 if glow else flight._liquid_index()
		var floor_mass: float=flight.aircraft.model.propulsion.glow.unusable_fuel_kg if glow else 0.0
		flight.sim.continuous[index]=floor_mass+5e-11
		var original: Dictionary=flight.checkpoint()
		check(name+" tiny positive state is admissible",flight.restore_checkpoint(original))
		var tick: int=flight.sim.tick
		flight.sim.step()
		check(name+" near-zero fuel advances without fault",flight.sim.tick==tick+1 and flight.sim.fault_reason.is_empty())
		check(name+" exhausted source retains floor and stops",flight.sim.continuous[index]==floor_mass and not flight.propulsion_source_running())
		var sample: Dictionary=flight.mass_properties()
		check(name+" exhausted sample is finite",sample.get("ok",false) and is_finite(float(sample.get("mass_kg",NAN))))
		var boundary: PackedByteArray=var_to_bytes([flight.sim.state,flight.sim.continuous,flight.sim.aux,flight.sim.modes])
		check(name+" can repeat tiny-state restore",flight.restore_checkpoint(original))
		flight.sim.step()
		check(name+" boundary replay is exact",var_to_bytes([flight.sim.state,flight.sim.continuous,flight.sim.aux,flight.sim.modes])==boundary)
		for count in 3: flight.sim.step()
		check(name+" coast retains nonnegative floor",flight.sim.continuous[index]==floor_mass and flight.sim.fault_reason.is_empty())
		if glow and floor_mass>0.0:
			var accepted: PackedByteArray=var_to_bytes(flight.checkpoint())
			var invalid: Dictionary=flight.checkpoint()
			invalid.simulation.continuous[index]=0.5*floor_mass
			check(name+" rejects lost residue in native checkpoint transactionally",
				not flight.restore_checkpoint(invalid) and var_to_bytes(flight.checkpoint())==accepted)
			check(name+" rejects lost residue in JSON checkpoint transactionally",
				not flight.restore_checkpoint_json(CheckpointJson.encode(invalid)) and var_to_bytes(flight.checkpoint())==accepted)
		flight.free()
	print("Fuel tiny boundaries: ",checks," checks, ",failures," failed")
	quit(1 if failures else 0)
func check(label: String,ok: bool) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL ",label)
