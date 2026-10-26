extends "res://tests/test_ground_accepted_ticks.gd"

func _run() -> void:
	root.audio_listener_enable_3d = true
	var a := rig()
	var buses := AudioServer.bus_count
	seed(77123)
	var expected_random := randi()
	seed(77123)
	airborne(a)
	var endpoint := snap(40,[contact("main",true)])
	var supplied := var_to_bytes(endpoint)
	a.observe_accepted(endpoint)
	check("accepted capture leaves global RNG sequence untouched",randi()==expected_random)
	check("accepted capture allocates no players/buses and detaches input",a.get_child_count()==0
		and AudioServer.bus_count==buses and supplied==var_to_bytes(endpoint))
	var history := var_to_bytes([a._accepted_states,a._accepted_contacts])
	render(a,40)
	for _i in 5:render(a,40)
	check("repeated rendering never mutates accepted classifier history",history==var_to_bytes([a._accepted_states,a._accepted_contacts]))
	check("same endpoint render drains one cue exactly once",a.touchdown_events==1 and a.accepted_diagnostics().drained==1)
	a.free()
	# A wildly wrong render nominal rate cannot make a stale source-clock cue young.
	a=rig()
	for i in 4:a.observe_accepted(snap(i,[contact()],false,4.0))
	a.observe_accepted(snap(4,[contact("main",true)],false,4.0))
	a.observe_accepted(snap(5,[contact()],false,4.0))
	a.observe_accepted(snap(6,[contact()],false,4.0))
	check("source-age fixture contains a captured cue",a.accepted_diagnostics().queued==1)
	a.update_contacts(6,false,[],0.0,.016,Vector3.ZERO,10000.0)
	check("event age uses authoritative source rate despite mismatched renderer",a.touchdown_events==0
		and a.accepted_diagnostics().discarded==1 and a.accepted_diagnostics().queued==0)
	a.free()
	# Rewind followed by a fresh complete airborne interval before first render.
	a=rig()
	a.observe_accepted(snap(1000,[contact("main",true)]))
	render(a,1000)
	airborne(a)
	a.observe_accepted(snap(40,[contact("main",true)]))
	a.observe_accepted(snap(41,[contact()]))
	history=var_to_bytes([a._accepted_states,a._accepted_contacts])
	render(a,41)
	check("playback rewind preserves new-epoch touchdown while final contact is detached",a.touchdown_events==1)
	check("playback rewind does not rewrite accepted new-epoch state",history==var_to_bytes([a._accepted_states,a._accepted_contacts]))
	a.free()
	# Finite contract extremes normalize gain/pitch without unbounded AudioServer inputs.
	a=rig()
	airborne(a)
	var extreme:=contact("main",true,1e300)
	extreme.normal_force_n=1e300
	extreme.reference_load_n=0.0
	extreme.rolling_speed_mps=1e300
	check("finite extreme presentation inputs pass stated normalized contract",a.observe_accepted(snap(40,[extreme])))
	render(a,40)
	var finite:=true
	for child:Node in a.get_children():
		var player:=child as AudioStreamPlayer3D
		finite=finite and is_finite(player.pitch_scale) and is_finite(player.volume_db) and player.pitch_scale>0.0 and player.pitch_scale<=1.18
	check("all resulting playback gains/pitches remain finite and bounded",finite)
	check("presentation pool remains bounded under extreme input",a.get_child_count()==4 and a.contact_slot_count==1)
	a.free()
	print("Independent accepted ground review: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
