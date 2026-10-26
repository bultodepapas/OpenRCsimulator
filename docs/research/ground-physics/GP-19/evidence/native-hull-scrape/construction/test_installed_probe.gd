## Exercises probe fixture owner through actual Main/Session; Dummy only, no PCM claim.
extends "C:/DEVELOPMENT/OpenRCsimulator/tools/audio/gameplay_probe.gd"
var checks := 0
var failed := 0
func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok: failed += 1;printerr("FAIL ",label," ",detail)
func advance(count: int) -> void:
	for _i in count:
		if not scene.session.crash.is_empty() or not scene.session.sim.fault_reason.is_empty():break
		scene.session._physics_process(scene.session.sim.dt())
		scene.session.sim.step()
func render_once() -> void:
	scene._render_pose(scene._current_pose(),scene.session.surfaces(),0.0)
	scene._crash_director.update(1./60.)
	_record_hull_render()
func _run() -> void:
	_hull_review=false;args={}
	check("legacy timeline unchanged without opt-in",_stage_at(0)==0 and _stage_at(4)==1 and _stage_at(7)==2 and _stage_at(10)==3 and _stage_at(11)==4 and _stage_at(13)==5 and _stage_at(15)==6)
	args={"wildlife-review":true}
	check("legacy wildlife timeline unchanged",_stage_at(100)==0)
	_hull_review=true;args={"hull-scrape-review":true}
	scene=load("res://main.tscn").instantiate()
	scene.aircraft_id=HULL_REVIEW_IDS[0]
	scene.start_choice="airborne"
	scene.landscape_id="club_field"
	root.add_child(scene)
	scene.set_process(false)
	scene.session.set_physics_process(false)
	scene.session.sim.set_physics_process(false)
	await process_frame
	print("HULL_ROUTE_FLAGS ", {"sim":scene.session.sim!=null,"director":scene._crash_director!=null,"enabled":scene._crash_director._audio_enabled,"accepted":scene._crash_director.audio.accepted_hull_observation_enabled(),"flyable":scene.session.is_flyable(),"soft":scene.session.soft_hull_contacts,"lake":not scene.session.lake_context().is_empty()})
	check("actual Main/Session/Director fixture prepares",_prepare_hull_review())
	_hull_start_usec=Time.get_ticks_usec()
	_enter_hull_phase(0);advance(8);render_once()
	check("actual airborne sample has no loaded friction",_hull_accepted.filter(func(row):return row.phase==0).all(func(row):return row.loaded_contacts==0 and row.friction_power_w==0.0 and row.queued==0))
	elapsed=1.0;_enter_hull_phase(1)
	var initial: Dictionary=_hull_accepted.back()
	check("actual accepted opening overlap is geometric with zero clamped load",initial.phase==1 and initial.geometric_contacts>0 and initial.loaded_contacts==0 and initial.friction_power_w==0.0,str(initial))
	advance(240);render_once()
	check("opening source never creates a scrape grain",_hull_accepted.filter(func(row):return row.phase==1).all(func(row):return row.friction_power_w==0.0 and row.queued==0))
	elapsed=2.0;_enter_hull_phase(2);advance(18)
	check("actual accepted brush carries nonzero force-owner power and IDs",_hull_accepted.any(func(row):return row.phase==2 and row.tick>0 and row.friction_power_w>0 and not row.contact_ids.is_empty()))
	check("actual brief brush queues before render",scene._crash_director.audio.hull_scrape_diagnostics().queued>0)
	render_once()
	check("actual Main render drains planned brush grain",scene._crash_director.audio.hull_scrape_diagnostics().emitted>0 and scene._crash_director.audio.hull_scrape_diagnostics().queued==0)
	for _i in 462:
		advance(1)
		if _i%4==0:render_once()
	check("whole intended brush interval continues without early terminal",scene.session.crash.is_empty() and scene.session.sim.fault_reason.is_empty())
	elapsed=4.0;_enter_hull_phase(3);render_once()
	check("pause boundary is explicit without fake physics advancement",_hull_accepted.back().clock_origin=="pause_notification" and _hull_accepted.back().paused and scene._crash_director.audio.hull_scrape_diagnostics().queued==0)
	elapsed=5.0;_enter_hull_phase(4);advance(2);render_once()
	check("resume produces actual unpaused accepted step",_hull_accepted.any(func(row):return row.phase==4 and row.clock_origin=="accepted_step" and not row.paused))
	var generation: int=scene.session.statistics_generation
	elapsed=6.0;_enter_hull_phase(5);advance(2);render_once()
	check("public reset commits exactly one new generation",scene.session.statistics_generation==generation+1 and _hull_phases.back().reset_accepted)
	check("public reset keeps crash queue clear",scene._crash_director.audio.hull_scrape_diagnostics().queued==0)
	elapsed=7.0;_enter_hull_phase(6);advance(30);render_once()
	check("actual nose-in physics supplies terminal decision",not scene.session.crash.is_empty() and _hull_accepted.any(func(row):return row.phase==6 and row.terminal))
	check("real Director owns exclusive terminal layers",scene._crash_director.audio._primary_played and scene._crash_director.audio.hull_scrape_diagnostics().queued==0 and scene._crash_director.audio.hull_scrape_diagnostics().tagged_voices==0)
	check("all source fixtures remain supported",_hull_failures.is_empty() and scene.session.sim.fault_reason.is_empty() and not _hull_truncated,str(_hull_failures))
	check("source identity includes actual physical/audio/asset chain",_hull_source_before.size()>=18 and _hull_source_before.has("res://physics/hull_contact.gd") and _hull_source_before==_hull_source_identity())
	root.remove_child(scene);scene.free()
	await process_frame
	print("Hull native probe fixtures: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
