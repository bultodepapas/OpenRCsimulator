extends SceneTree

const Session = preload("res://sim/helicopter_flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Lake = preload("res://data/lake_loader.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
const Skids = preload("res://physics/rotorcraft/skid_contact.gd")
const Detector = preload("res://physics/rotorcraft/impact_detector.gd")
const Adapter = preload("res://sim/native/helicopter_stage_adapter.gd")
const NativeConfig = preload("res://sim/native/native_configuration.gd")
const Main = preload("res://helicopter_main.gd")
const Audio = preload("res://audio/helicopter_audio.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")

class MockNative extends RefCounted:
	func prepare_heli_stage(_snapshot: Dictionary,_weather: Dictionary) -> Dictionary: return {ok=true}
	func set_heli_tick_context(_context: Dictionary) -> bool: return true
	func heli_last_failure() -> String: return ""
	func stage(_body: PackedFloat64Array,_continuous: PackedFloat64Array,_time: float) -> Dictionary: return {}

var checks := 0
var failures := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void:
	_run.call_deferred()

func _new_session(field: Dictionary, lake: Dictionary, backend: String = "gdscript_reference") -> Node:
	var s := Session.new()
	s.physics_enabled = false
	s.input_enabled = false
	root.add_child(s)
	if not s.setup_stage_backend(backend) or not s.setup() or not s.set_field(field) or not s.set_lake_context(lake):
		return s
	return s

func _run() -> void:
	var field: Dictionary = Field.load_from().field
	var loaded: Dictionary = Lake.load_from()
	check("stock lake loads", loaded.ok)
	var lake: Dictionary = loaded.lake
	var s: Node = _new_session(field, lake)
	check("normalized stock lake installed", s.lake_context().get("identity") == lake.identity)
	var exposed: Dictionary = s.lake_context()
	exposed.water_level_down_m = 1.9
	check("lake snapshot is detached", s.lake_context().water_level_down_m != 1.9)
	var invalid: Dictionary = lake.duplicate(true)
	invalid.water_level_down_m = 1.9
	check("mutated identity refused without changing lake", not s.set_lake_context(invalid) and s.lake_context().identity == lake.identity)
	check("reference stock lake reset", s.reset(), s.start_error)
	var old: Dictionary = s.checkpoint()
	check("checkpoint binds contact law and lake", old.get("format") == Session.CHECKPOINT_FORMAT and old.get("contact_law") == Session.CONTACT_LAW and old.get("lake_identity") == lake.identity)
	for format: String in ["openrc-helicopter-checkpoint v6", "openrc-helicopter-checkpoint v7"]:
		var legacy: Dictionary = old.duplicate(true)
		legacy.format = format
		check("legacy contact checkpoint refused " + format, not s.restore_checkpoint(legacy).ok)
	var foreign: Dictionary = old.duplicate(true)
	foreign.lake_identity = "foreign"
	var before: PackedByteArray = var_to_bytes(s.sim.checkpoint())
	check("foreign lake rejected with rollback", not s.restore_checkpoint(foreign).ok and var_to_bytes(s.sim.checkpoint()) == before)
	for pair: PackedFloat64Array in [PackedFloat64Array([110.0,171.0]),PackedFloat64Array([112.0,79.0]),PackedFloat64Array([110.0,176.01]),PackedFloat64Array([112.0,73.99])]:
		var actual: PackedFloat64Array = s.environment.ground(pair[0],pair[1])
		var expected: PackedFloat64Array = Terrain.sample(pair[0],pair[1],s.ground_surfaces,lake)
		check("both bank sides and outer edges use composed height/slopes", actual.to_byte_array() == expected.to_byte_array())
	var witness: PackedFloat64Array = s.sim.state.duplicate()
	witness[0] = 110.0; witness[1] = 171.0; witness[2] = -0.085
	witness[3] = 0.0; witness[4] = 0.0; witness[5] = 1.2
	witness[6] = 1.0; witness[7] = 0.0; witness[8] = 0.0; witness[9] = 0.0
	witness[10] = 0.0; witness[11] = 0.0; witness[12] = 0.0
	var dry: Dictionary = Skids.evaluate(witness,s.aircraft.skids,s.ground_surfaces,true)
	var wet: Dictionary = Skids.evaluate(witness,s.aircraft.skids,s.ground_surfaces,true,PackedFloat64Array(),lake)
	check("A15 bank has no premature dry skid force", dry.ok and wet.ok and dry.contact_count > 0 and wet.contact_count == 0, str([dry,wet]))
	check("A15 bank witness remains admitted", not s._water_contact_possible(witness,witness))
	s.sim.state=witness.duplicate(); s.sim.previous=witness.duplicate()
	s.sim.continuous=PackedFloat64Array([0.0,0.0,0.0,0.0,0.0,0.0]); s.sim.aux=PackedFloat64Array([0.0])
	s._phase_omega=PackedFloat64Array([0.0,0.0]); s.shaft_phase=PackedFloat64Array([0.0,0.0])
	s.sim._remember_valid_state(); s.sim.step()
	check("A15 constructed real tick avoids dry-bank false crash", s.sim.tick==1 and s.sim.fault_reason.is_empty() and s.crash.is_empty(), s.pause_reason)
	var distant: PackedFloat64Array = witness.duplicate()
	distant[0]=82.0; distant[1]=169.0
	check("dry corner inside shoreline AABB remains admitted", not s._water_contact_possible(distant,distant))
	var point:=PackedFloat64Array([110.0,173.0,0.2])
	var sample: Dictionary=Detector._terrain_sample(point,PackedFloat64Array([0.0,0.0,0.0]),s.ground_surfaces,Terrain.max_height_validated(s.ground_surfaces),0.0,lake)
	var composed: PackedFloat64Array=s.environment.ground(point[0],point[1])
	check("impact sample uses composed bank height and slopes", sample.ok and sample.terrain.to_byte_array()==composed.to_byte_array() and absf(sample.normal_world_ned[0]+composed[1]/sqrt(1.0+composed[1]*composed[1]+composed[2]*composed[2]))<1e-12)
	var first_impact: Dictionary={}
	var lower: PackedFloat64Array=witness.duplicate(); lower[1]=173.0; lower[2]=-1.0
	for index: int in 40:
		var upper: PackedFloat64Array=lower.duplicate(); upper[2]+=0.05
		var hit: Dictionary=Detector.evaluate(lower,upper,PackedFloat64Array([0.0,0.0,0.0,0.0,0.0,0.0]),s.aircraft.context,s.aircraft.skids,s.ground_surfaces,PackedFloat64Array([0.0,0.0]),{},s._impact_geometry,lake)
		if not hit.ok: break
		if not hit.impact.is_empty(): first_impact=hit.impact; break
		lower=upper
	var contact_ok: bool=false
	if not first_impact.is_empty():
		var pos: PackedFloat64Array=first_impact.point_world_ned
		var ground: PackedFloat64Array=s.environment.ground(pos[0],pos[1])
		var norm: float=sqrt(1.0+ground[1]*ground[1]+ground[2]*ground[2])
		var depth: float=pos[2]+ground[0]
		var expected_depth: float=0.04 if str(first_impact.component).begins_with("skid_") else 0.0
		contact_ok=absf(depth-expected_depth)<1e-6 and absf(first_impact.normal_world_ned[0]+ground[1]/norm)<1e-10 and absf(first_impact.normal_world_ned[1]+ground[2]/norm)<1e-10
	check("first terminal bank contact reports composed surface and normal", contact_ok, str(first_impact))
	var joined: PackedFloat64Array=witness.duplicate(); joined.append_array(s.sim.continuous)
	var offset: PackedFloat64Array=s._hub_offset(joined)
	var h: float=s.environment.ground(joined[0]+offset[0],joined[1]+offset[1])[0]
	check("ground effect reads the same composed hub height", s._ground_under_hub(joined)==h and s._height_over_radius(joined)==(-joined[2]-offset[2]-h)/s.aircraft.context.main_model.rotor_radius_m)
	var scene:=Main.new(); scene.session=s
	check("camera uses same bank height", scene._ground_height(173.0,-110.0)==s.environment.ground(110.0,173.0)[0])
	check("camera clears the bounded wave above the lake bed", scene._ground_height(125.0,-110.0) \
		== -float(lake.water_level_down_m)+float(lake.wave_bounds.max_amplitude_m) \
		and scene._ground_height(125.0,-110.0)>s.environment.ground(110.0,125.0)[0])
	s.sim.state=witness.duplicate()
	var audio:=Audio.new(); audio.flight=scene
	scene.field=field
	var audio_contacts: Array=audio.contact_snapshot()
	check("audio reports the composed skid support", audio_contacts.size()==4 and audio_contacts.all(func(c: Dictionary) -> bool: return c.normal_force_n==0.0))
	audio.free()
	scene.free()
	var water: PackedFloat64Array=witness.duplicate(); water[0]=110.0; water[1]=125.0; water[2]=0.0
	check("water entry explicitly unsupported", s._water_contact_possible(water,water))
	var high: PackedFloat64Array=water.duplicate(); high[2]=-4.0
	check("high overflight remains admitted", not s._water_contact_possible(high,high))
	check("direct native adapter rejects lake", not Adapter.prepare(s,null).ok)
	check("direct native configuration rejects lake", not NativeConfig.prepare_helicopter(s).ok)
	check("compatible lake checkpoint restores", s.restore_checkpoint(old).ok)
	var in_water: Dictionary=old.duplicate(true)
	in_water.simulation.state=water.duplicate(); in_water.simulation.previous=water.duplicate()
	before=var_to_bytes(s.sim.checkpoint())
	check("water checkpoint refused before publication", not s.restore_checkpoint(in_water).ok and var_to_bytes(s.sim.checkpoint())==before)
	var geometry: Dictionary=s._impact_geometry
	var stale: Dictionary=geometry.duplicate(true)
	var source_geometry: PackedFloat64Array=stale.source_main_geometry
	source_geometry[0]+=1.0; stale.source_main_geometry=source_geometry
	s._impact_geometry=stale
	var stale_before: PackedByteArray=s.sim.state.to_byte_array()
	var stale_tick: int=s.sim.tick
	s.sim.step()
	check("stale contact geometry refuses and rolls back the real tick", s.sim.tick==stale_tick \
		and s.sim.state.to_byte_array()==stale_before and s.pause_reason.contains("geometry") and s._pending_impact.is_empty(),s.pause_reason)
	s._impact_geometry=geometry
	check("valid checkpoint recovers after stale-geometry refusal", s.restore_checkpoint(old).ok)
	var original_projection: Callable=s.sim.model.block_aux
	s.sim.model.block_aux=func(_continuous: PackedFloat64Array,_aux: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array()
	var body_before: PackedByteArray=s.sim.state.to_byte_array()
	var tick_before: int=s.sim.tick
	s.sim.step()
	check("late projection refusal clears pending preflight and rolls back", s.sim.tick==tick_before and s.sim.state.to_byte_array()==body_before and not s.sim.fault_reason.is_empty() and s._pending_impact.is_empty())
	s.sim.model.block_aux=original_projection
	check("lake survives restart", s.reset() and s.lake_context().identity==lake.identity)
	check("disabled lake returns dry geometry", s.set_lake_context({}) and s.environment.ground(110.0,173.0).to_byte_array()==Terrain.sample(110.0,173.0,s.ground_surfaces).to_byte_array())
	check("dry restart succeeds", s.reset())
	check("lake checkpoint cannot restore on dry field", not s.restore_checkpoint(old).ok)
	var mock:=MockNative.new()
	var installed: Dictionary=Adapter.install(s,mock)
	check("direct native dry adapter installs", installed.ok, str(installed))
	if installed.ok:
		s.environment.lake=lake.duplicate(true)
		var rejected: Variant=s.sim.model.pre_tick.call(s.sim.aux,s.sim.inputs,s.sim.dt())
		check("direct installed native rejects later lake mutation", rejected is PackedFloat64Array and rejected.is_empty() and not installed.context.ok)
		s.environment.lake={}; installed.restore.call()
	s.free()
	var native: Node=_new_session(field,lake,"native")
	check("native requested lake falls back before preparation", native.reset() and native.stage_backend_status().identity.backend=="gdscript_reference" and native.stage_backend_error.contains("does not support lakes"), native.stage_backend_error)
	native.free()
	var translated: Dictionary=lake.duplicate(true)
	for key: String in ["shoreline_ne_m","bank_ne_m"]:
		var polygon: PackedFloat64Array=translated[key]
		for i: int in range(0,polygon.size(),2): polygon[i]+=200.0; polygon[i+1]-=100.0
		translated[key]=polygon
	translated.origin_north_m+=200.0; translated.origin_east_m-=100.0
	translated.identity=Lake.identity(translated)
	var custom: Node=_new_session(field,translated)
	check("custom normalized lake installs and starts", custom.lake_context().identity==translated.identity and custom.reset())
	check("custom geometry translated without reverting to stock", custom.environment.ground(310.0,73.0).to_byte_array()==Terrain.sample(310.0,73.0,custom.ground_surfaces,translated).to_byte_array())
	custom.free()
	var pad_lake: Dictionary=lake.duplicate(true)
	for key: String in ["shoreline_ne_m","bank_ne_m"]:
		var polygon: PackedFloat64Array=pad_lake[key]
		for i: int in range(0,polygon.size(),2): polygon[i]-=104.0; polygon[i+1]-=125.0
		pad_lake[key]=polygon
	pad_lake.origin_north_m-=104.0; pad_lake.origin_east_m-=125.0; pad_lake.identity=Lake.identity(pad_lake)
	var pad: Node=_new_session(field,pad_lake)
	check("custom overlapping lake accepted as geometry", pad.lake_context().identity==pad_lake.identity)
	check("airborne start over water at safe height works", pad.reset(), pad.start_error)
	check("ground selection invalidates the previous start", pad.set_start_choice("ground") and not pad.is_flyable())
	var reset_events: Array[int]=[0]
	pad.resetting.connect(func() -> void: reset_events[0]+=1)
	var owner_before: PackedByteArray=var_to_bytes([pad.sim.checkpoint(),pad.sim.paused,pad._ready_to_fly,
		pad.start_choice,pad.commands,pad.power,pad.shaft_phase,pad.crash])
	check("overlapping pad reset preserves the post-selection owner and publishes nothing", not pad.reset() \
		and pad.start_error.contains("overlaps") and reset_events[0]==0 \
		and var_to_bytes([pad.sim.checkpoint(),pad.sim.paused,pad._ready_to_fly,pad.start_choice,
			pad.commands,pad.power,pad.shaft_phase,pad.crash])==owner_before)
	pad.free()
	var rollback: Node=_new_session(field,lake)
	rollback._start=PackedFloat64Array([110.0,125.0,-3.0])
	check("water rollback fixture starts above lake", rollback.reset(), rollback.start_error)
	var falling: PackedFloat64Array=rollback.sim.state.duplicate()
	falling[0]=110.0; falling[1]=125.0; falling[2]=-0.29
	falling[3]=0.0; falling[4]=0.0; falling[5]=30.0
	falling[6]=1.0; falling[7]=0.0; falling[8]=0.0; falling[9]=0.0
	falling[10]=0.0; falling[11]=0.0; falling[12]=0.0
	rollback.sim.state=falling.duplicate(); rollback.sim.previous=falling.duplicate(); rollback.sim._remember_valid_state()
	var prior: PackedByteArray=rollback.sim.state.to_byte_array()
	rollback.sim.step()
	check("water-entry tick is refused and rolled back", rollback.sim.tick==0 and rollback.sim.state.to_byte_array()==prior and rollback.pause_reason.contains("water contact") and rollback._pending_impact.is_empty(), rollback.pause_reason)
	rollback.free()
	var h05: Node=_new_session(field,{})
	check("A15 rotor sweep session starts", h05.reset())
	h05.ground_surfaces=PackedFloat64Array([-INF,INF,-INF,INF,0.8,7.5])
	h05.sim.state=RB.make_state(M.v3(200.0,200.274,-0.245),M.v3(0.0,0.0,-1.68), \
		PackedFloat64Array([0.0,1.0,0.0,0.0]),M.v3(0.0,0.0,0.0))
	h05.sim.previous=h05.sim.state.duplicate()
	h05.sim.continuous[0]=167.0; h05.sim.continuous[1]=0.0; h05.sim.continuous[2]=0.0
	h05.sim._remember_valid_state(); h05.sim.step()
	check("A15 real tick reports bounded rotor witness", h05.sim.tick==1 and h05.sim.fault_reason.is_empty() \
		and h05.crash.get("component","")=="main_rotor" and h05.crash.get("disc_onset_interval",false) \
		and float(h05.crash.get("time_fraction_uncertainty",INF))<=1.0/65536.0, h05.pause_reason)
	h05.free()
	var ambiguous: Node=_new_session(field,{})
	check("ambiguous contact rollback fixture starts", ambiguous.reset())
	var blocked: PackedFloat64Array=ambiguous.sim.state.duplicate()
	blocked[0]=6.0; blocked[1]=0.0
	var attitude: PackedFloat64Array=M.q_from_euler(PI/2.0,0.4,PI)
	for i: int in 4: blocked[6+i]=attitude[i]
	blocked[2]=-0.65; blocked[3]=0.0; blocked[4]=0.0; blocked[5]=2.5
	blocked[10]=0.0; blocked[11]=0.0; blocked[12]=0.0
	ambiguous.sim.state=blocked.duplicate(); ambiguous.sim.previous=blocked.duplicate()
	ambiguous.sim.continuous[0]=168.0; ambiguous.sim.continuous[1]=0.0; ambiguous.sim.continuous[2]=0.0
	var body_rate:=PackedFloat64Array(); body_rate.resize(13); body_rate[2]=0.15/ambiguous.sim.dt()
	var rotor_rate:=PackedFloat64Array(); rotor_rate.resize(6)
	ambiguous.sim.model.stage=func(_body: PackedFloat64Array,_continuous: PackedFloat64Array,_t: float) -> Dictionary:
		return {loads=PackedFloat64Array([0,0,0,0,0,0]),body_derivative=body_rate.duplicate(),
			derivative=rotor_rate.duplicate(),rotor_momentum=PackedFloat64Array([0,0,0])}
	ambiguous.sim._remember_valid_state()
	var before_ambiguous: PackedByteArray=var_to_bytes([ambiguous.sim.tick,ambiguous.sim.state,ambiguous.sim.continuous,ambiguous.shaft_phase])
	var accepted_signals: Array[int]=[0]
	ambiguous.sim.stepped.connect(func(_tick: int,_t: float,_body: PackedFloat64Array,_loads: PackedFloat64Array,_inputs: PackedFloat64Array,_aux: PackedFloat64Array) -> void: accepted_signals[0]+=1)
	ambiguous.sim.step()
	check("ambiguous disc and body ordering refuses before publication", ambiguous.pause_reason.contains("ordering is unresolved") \
		and accepted_signals[0]==0 and ambiguous._pending_impact.is_empty() \
		and var_to_bytes([ambiguous.sim.tick,ambiguous.sim.state,ambiguous.sim.continuous,ambiguous.shaft_phase])==before_ambiguous, ambiguous.pause_reason)
	ambiguous.free()
	print("HELI lake context: %d checks, %d failed" % [checks,failures])
	quit(1 if failures else 0)
