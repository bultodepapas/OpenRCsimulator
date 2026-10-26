## Existing default-field regression; no candidate force, source or scene edits.
extends SceneTree
const H = preload("res://physics/hull_contact.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
var checks:=0
var failed:=0
func check(label:String,ok:bool)->void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL ",label)
func _initialize()->void:call_deferred("_run")
func _run()->void:
	var main:Node=load("res://main.tscn").instantiate()
	main.aircraft_id="jensen-das-ugly-stik-60"
	main.landscape_id="club_field"
	root.add_child(main)
	main.set_process(false)
	main.session.set_physics_process(false)
	main.session.sim.set_physics_process(false)
	main.session.input_enabled=false
	main.session.engine_running=false
	await process_frame
	var f:Node=main.session
	check("actual default Main installs valid soft hull plus lake",f.is_flyable() and f.soft_hull_contacts and not f.lake_context().is_empty())
	var q:=M.q_from_euler(0.,0.,deg_to_rad(40.))
	var hull:PackedFloat64Array=f.aircraft.model.crash_hull
	var extent:float=-INF
	for i in range(0,hull.size(),3):extent=maxf(extent,M.q_rotate(q,hull.slice(i,i+3))[2])
	var state:=RB.make_state(M.v3(0,0,.001-extent),M.q_rotate(M.q_conj(q),M.v3(5,0,0)),q,M.v3(0,0,0))
	check("actual body fixture reset accepted",f.sim.reset(state))
	var all_dry:=true
	for i in range(0,hull.size(),3):
		var point:=H._point_ned(f.sim.state,hull.slice(i,i+3))
		all_dry=all_dry and not H._lake_sample(f._hull_contact,point).get("covered",false)
	check("authoritative HullContact samples choose dry branch for every probe",all_dry)
	var loads:=H.loads(f.sim.state,f._hull_contact)
	check("same actual force owner has loaded sliding friction",not loads.is_empty() and loads[0]<0.)
	var packet:Dictionary=f.hull_scrape_observation()
	check("dry default-field packet should be available",packet.available)
	check("dry loaded source should expose friction rows",not packet.contacts.is_empty())
	f.sim.set_paused(false)
	f.sim.step();f.sim.step()
	check("accepted dry default brush should queue before render",main._crash_director.audio.hull_scrape_diagnostics().queued>0)
	print("DEFAULT_HULL_DEFECT ",{packet=packet,force=Array(loads),all_authoritative_samples_dry=all_dry,accepted_mode=main._crash_director.audio.accepted_hull_observation_enabled()})
	root.remove_child(main);main.free()
	await process_frame
	print("Default-field dry hull defect: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
