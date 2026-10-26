extends "res://tests/test_hull_scrape_session.gd"
const CandidateSession:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-lake/draft/flight_session.gd")
func session(path:=STIK)->Node:
	var f:=CandidateSession.new()
	f.input_enabled=false;f.crash_auto_restart=false;f.soft_hull_contacts=true
	f.setup(path);f.set_process(false);f.set_physics_process(false);f.engine_running=false
	return f
func _run()->void:
	var lake:=Lake.load_from()
	for path:String in [STIK,GLOW]:
		var f:=session(path)
		check("actual source admitted",f.is_flyable())
		check("actual field and configured lake installed",f.set_field(Field.load_from().field) and f.set_lake_context(lake.lake))
		if f.finite_fuel_is_active():f.sim.continuous[1]*=.5
		check("same actual wingtip accepted reset",f.sim.reset(body(f)))
		var before:=var_to_bytes(f.checkpoint())
		var dry:Dictionary=f.hull_scrape_observation()
		check("configured lake outside coverage has real dry loaded rows",dry.available and not dry.contacts.is_empty(),str(dry))
		check("observation physical checkpoint exact",before==var_to_bytes(f.checkpoint()))
		var key:PackedByteArray=f._hull_scrape_cache_key.duplicate()
		var detached:Dictionary=f.hull_scrape_observation()
		detached.contacts[0].friction_power_w=-99.0
		check("cached packet fully detached",f.hull_scrape_observation().contacts[0].friction_power_w>=0.0)
		f._lake.id+="-observed-mutation"
		check("same-clock lake identity mutation invalidates key",f.hull_scrape_observation().available and f._hull_scrape_cache_key!=key)
		if f.finite_fuel_is_active():
			var previous:float=f.hull_scrape_observation().contacts[0].normal_force_n
			f.sim.continuous[1]=f.aircraft.model.propulsion.glow.initial_fuel_kg
			check("sameclock actual fuel owner changes force and cache",f.hull_scrape_observation().contacts[0].normal_force_n!=previous)
		f.free()
	print("Independent dry lake Session complete: ",checks," checks, ",failed," failed")
	quit(1 if failed else 0)
