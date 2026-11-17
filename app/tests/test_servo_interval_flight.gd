extends SceneTree
const Servo := preload("res://sim/servo_interval_flight.gd")
const Law := preload("res://physics/slew_trajectory.gd")
const Old := preload("res://physics/control_actuators.gd")
const Compose := preload("res://sim/electric_contact_step.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Loader := preload("res://workshop/creator/record_loader.gd")
const Session := preload("res://sim/flight_session.gd")
const Model := preload("res://sim/vehicle_model.gd")
const Sim := preload("res://sim/simulation.gd")
const Weather := preload("res://physics/wind_config.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
class TemporalSession:
	extends "res://sim/flight_session.gd"
	func wind_at(time_s: float, _state: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
		return PackedFloat64Array([time_s,0.0,0.0])
var checks := 0
var failures := 0

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL servo law: ",label)

func plan(a: float,b: float,r: float,dt: float) -> Dictionary:
	return Law.prepare(PackedFloat64Array([a]),PackedFloat64Array([b]),PackedFloat64Array([r]),dt)

func session(data: Dictionary,backend: String) -> Node:
	var s := Session.new()
	s.input_enabled=false
	s.physics_enabled=true
	s.crash_auto_restart=false
	s.start_choice=Session.START_AIRBORNE
	if not backend.is_empty():check("explicit backend selected",s.setup_stage_backend(backend))
	s.setup("",data.model.id,data)
	return s

func frame(s: Node) -> PackedByteArray:
	return var_to_bytes([s.sim.state,s.sim.continuous,s.sim.aux,s.sim.modes,s.sim.inputs,s.sim.tick])

func replay_check(flight: Node) -> void:
	var directory := "user://servo-law-replay-%d" % Time.get_ticks_usec()
	var path := directory.path_join("selected.orfl")
	var logger := Log.new(flight)
	var started: int = logger.start(path)
	check("new-law nonzero boundary recording starts",started==OK and flight.sim.tick>0)
	if started!=OK:return
	var header: Dictionary=logger.header.duplicate(true)
	var declaration: Dictionary=Reader.recorded_servo_declaration(header)
	check("recorded law/protocol/layout owners agree",declaration.ok and declaration.declared)
	for bad: Variant in [null,1,true,[],{}]:
		var malformed:=header.duplicate(true)
		malformed.checkpoint.format=bad
		check("malformed checkpoint format refused before dispatch",not Reader.recorded_stage_backend(malformed).ok and not Reader.prepare_replay(malformed).ok)
	for owner: String in ["metadata","checkpoint"]:
		for key: String in ["servo_integration_law","servo_interval_protocol","servo_interval_layout","servo_partition_policy"]:
			for bad: Variant in [null,1,true,[],"unknown"]:
				var damaged:=header.duplicate(true)
				damaged[owner][key]=bad
				check("malformed recorded declaration refused",not Reader.recorded_servo_declaration(damaged).ok)
	var damaged:=header.duplicate(true)
	damaged.erase("stage_backend")
	check("selected replay requires recorded reference choice",not Reader.recorded_servo_declaration(damaged).ok)
	damaged=header.duplicate(true)
	damaged.aircraft.model.controls.erase("servo_integration")
	check("partial model declaration refused",not Reader.recorded_servo_declaration(damaged).ok)
	damaged=header.duplicate(true)
	damaged.checkpoint.simulation.callback_protocol=Model.PROTOCOL_LEGACY
	check("partial simulation declaration refused",not Reader.recorded_servo_declaration(damaged).ok)
	var refused_candidate: Dictionary=Reader.prepare_replay(header,"not-a-candidate.json")
	check("versioned candidate replay stays explicitly unsupported",not refused_candidate.ok and refused_candidate.error=="Candidate replay of a servo checkpoint is not supported.")
	damaged=header.duplicate(true)
	damaged.aircraft.model.controls.erase("servo_integration")
	damaged.checkpoint.format="openrc-flight-checkpoint v6"
	for key: String in ["servo_integration_law","servo_interval_protocol","servo_interval_layout","servo_partition_policy","servo_physics_format"]:
		damaged.checkpoint.erase(key)
		damaged.metadata.erase(key)
	check("partial inner servo layout cannot masquerade as historical",not Reader.recorded_servo_declaration(damaged).ok)
	var historical := header.duplicate(true)
	historical.checkpoint.format = "openrc-flight-checkpoint v15"
	historical.checkpoint.erase("servo_partition_policy")
	historical.metadata.erase("servo_partition_policy")
	var historical_declaration: Dictionary = Reader.recorded_servo_declaration(historical)
	check("historical declaration stays readable and policy unrecorded", historical_declaration.ok and historical_declaration.declared
		and not historical_declaration.declaration.has("partition_policy"))
	check("historical exact replay cannot infer an integration policy", not Reader.prepare_replay(historical).ok)
	historical.metadata["servo_partition_policy"] = Servo.PARTITION_POLICY
	check("policy cannot be smuggled into a v15 carrier", not Reader.recorded_servo_declaration(historical).ok)
	for index: int in 12:
		flight.sim.inputs[0]=0.1 if index<4 else (-0.05 if index<8 else 0.0)
		flight.sim.inputs[1]=-0.03 if index<6 else 0.02
		flight.sim.step()
	check("recorded selected trajectory completes",flight.sim.fault_reason.is_empty())
	check("new-law recorder completes",logger.stop("servo law test")==OK)
	var reader:=Reader.new()
	reader.options={log=path,csv=directory.path_join("selected.csv"),report=directory.path_join("replay.json"),replay=true}
	reader.set("_automatic_native_macos_allowed",false)
	reader.call("_run")
	check("new-law exact replay verifies every row",reader.report.get("status")=="ok" and reader.report.get("complete")==true and reader.report.get("mode")=="exact" and reader.report.get("solver_changed")==false and reader.report.get("rows")==13 and reader.report.get("first_tick")==header.checkpoint.simulation.tick and reader.report.get("final_tick")==flight.sim.tick)
	check("replay report pins same law without migration",reader.report.get("servo_integration",{}).get("checkpoint_migration")=="none" and reader.report.get("servo_integration",{}).get("recorded")==declaration.declaration and reader.report.get("servo_integration",{}).get("replay")==declaration.declaration)
	reader.free()

func _initialize() -> void:
	Engine.physics_ticks_per_second=240
	var kernel:=Sim.new()
	var diagnostic: Dictionary=kernel._unpack_policy_result({failure="known refusal"},0.0)
	check("bounded failure diagnostic is retained",not diagnostic.ok and diagnostic.message=="known refusal")
	for receipt: Dictionary in [{failure=""},{failure="x".repeat(257)},{failure=1},{failure="no",state=PackedFloat64Array()}]:
		check("malformed/partial failure cannot become a success",not kernel._unpack_policy_result(receipt,0.0).ok)
	kernel.free()
	for sign: float in [1.0,-1.0]:
		var p := plan(-0.5*sign,0.5*sign,2.0,1.0)
		check("shared arrival and exact target",p.ok and p.offsets==PackedFloat64Array([0.5]) and p.endpoint[0]==0.5*sign)
		check("known quarter-stage value",Law.sample(p,0.25)[0]==0.0)
		var integral := 0.5*(Law.sample(p,0.0)[0]+Law.sample(p,0.5)[0])*0.5+Law.sample(p,1.0)[0]*0.5
		check("independent ramp/hold integral",integral==0.25*sign)
	var p := plan(0.25,0.75,0.5,0.25)
	check("no arrival known answer",p.ok and p.offsets.is_empty() and p.endpoint[0]==0.375 and 0.5*(0.25+p.endpoint[0])*0.25==0.078125)
	p=plan(0.0,0.5,2.0,0.25)
	check("exact endpoint is not an interior cut",p.ok and p.offsets.is_empty() and p.endpoint[0]==0.5)
	p=plan(0.015,-0.01,1.0/0.14,1.0/240.0)
	check("new law stores exact target rather than historical residual",p.ok and p.endpoint.to_byte_array()==PackedFloat64Array([-0.01]).to_byte_array() and p.endpoint[0]!=Old.rate_limit(0.015,-0.01,1.0/0.14,1.0/240.0))
	check("held next target has no residual arrival",plan(p.endpoint[0],-0.01,1.0/0.14,1.0/240.0).offsets.is_empty())
	p=plan(-0.0,0.0,1.0,1.0)
	check("numeric no motion retains signed start bits",Law.sample(p,0.0).to_byte_array()==PackedFloat64Array([-0.0]).to_byte_array() and Law.sample(p,0.5).to_byte_array()==PackedFloat64Array([-0.0]).to_byte_array() and p.endpoint.to_byte_array()==PackedFloat64Array([-0.0]).to_byte_array())
	for duration: float in [0.0,-1.0,NAN,INF]:check("invalid duration refused",not plan(0.0,0.5,1.0,duration).ok)
	check("out of bounds refused",not plan(1.1,0.5,1.0,1.0).ok)
	check("arrival underflow refused",not plan(0.0,1e-300,1e308,1.0).ok)
	var together:=Law.prepare(PackedFloat64Array([0.0,0.0,0.0]),PackedFloat64Array([0.25,-0.5,0.5]),PackedFloat64Array([1.0,2.0,2.0]),1.0)
	check("simultaneous arrivals share one cut",together.ok and together.offsets==PackedFloat64Array([0.25]))
	var nearby:=Law.prepare(PackedFloat64Array([0.0,0.0]),PackedFloat64Array([0.25,0.25+5.551115123125783e-17]),PackedFloat64Array([1.0,1.0]),1.0)
	check("distinct rounded arrivals remain distinct",nearby.ok and nearby.offsets.size()==2)
	var rate := 0.9395064301545154
	var dt := 1.0/240.0
	p=plan(0.0,rate*dt,rate,dt)
	check("division arithmetic owns the near-endpoint cut",p.ok and p.offsets.size()==1 and p.offsets[0]<dt)
	var compiled := Compiler.compile_candidate(Definition.template())
	check("historical definition still compiles",compiled.ok)
	if not compiled.ok:
		finish()
		return
	var raw: Dictionary=JSON.parse_string(compiled.value.raw_bytes().get_string_from_utf8())
	var old_data: Dictionary=compiled.value.flight_data()
	check("absent selector adds no normalized key",not old_data.model.controls.has("servo_integration"))
	var declaration:=Definition.template()
	declaration.format=Definition.SERVO_FORMAT
	declaration.servo_integration=Law.LAW
	var versioned:=Compiler.compile_candidate(declaration)
	check("v4 declaration compiles the selected law",versioned.ok and versioned.value.flight_data().model.controls.servo_integration==Law.LAW)
	if not versioned.ok:
		finish()
		return
	var versioned_text: String=versioned.value.raw_bytes().get_string_from_utf8()
	var selector_token: String=",\"servo_integration\":"+JSON.stringify(Law.LAW)
	check("only selected physical field changes historical record bytes",versioned_text.count(selector_token)==1 and versioned_text.replace(selector_token,"").to_utf8_buffer()==compiled.value.raw_bytes())
	check("v4 pins a distinct definition identity",versioned.value.definition_sha256()!=compiled.value.definition_sha256())
	for version: String in [Definition.FORMAT,Definition.SOURCE_FORMAT,Definition.INSTALLATION_FORMAT]:
		var invalid:=declaration.duplicate(true)
		invalid.format=version
		check("old definition version cannot select new law",not Definition.validate_complete(invalid).ok)
	for bad: Variant in [null,1,true,[],"unknown-law"]:
		var invalid:=declaration.duplicate(true)
		invalid.servo_integration=bad
		check("v4 rejects missing/invalid law",not Definition.validate_complete(invalid).ok)
	var missing:=declaration.duplicate(true)
	missing.erase("servo_integration")
	check("v4 requires explicit law",not Definition.validate_complete(missing).ok)
	raw.controls.servo_integration=Law.LAW
	var encoded := Bytes.encode(raw)
	check("selected record encoded",encoded.ok)
	var selected: Dictionary=Loader.load_bytes(encoded.value.bytes,raw.id)
	check("v2 selector survives exact byte loader",selected.ok and selected.model.controls.servo_integration==Law.LAW)
	if not selected.ok:
		finish()
		return
	for bad: Variant in [null,1,true,[],"unknown-law"]:
		var invalid:=raw.duplicate(true)
		invalid.controls.servo_integration=bad
		check("wrong selector spelling/type rejected",not AD.validate_and_derive(invalid).ok)
	var v1:=raw.duplicate(true)
	v1.format=AD.LEGACY_FORMAT
	check("legacy v1 cannot silently accept new selector",not AD.validate_and_derive(v1).ok)
	var legacy:=session(old_data,"")
	check("legacy remains ready with implicit historical reference",legacy._flight_ready() and legacy.sim.model.callback_protocol==Model.PROTOCOL_LEGACY and not legacy.trace_meta().has("servo_integration_law"))
	var old_cp: Dictionary=legacy.checkpoint()
	for backend: String in ["","native"]:
		var refused:=session(selected,backend)
		check("new law refuses implicit/native backend",not refused._flight_ready() and refused.checkpoint().is_empty())
		refused.free()
	var flight:=session(selected,"gdscript_reference")
	check("explicit new law installs complete model",flight._flight_ready() and flight.sim.model.callback_protocol==Model.PROTOCOL_JOINT_INTERVAL_LOCAL and flight.sim.continuous.size()==4)
	if not flight._flight_ready():
		flight.free()
		legacy.free()
		finish()
		return
	flight.sim.aux[2]=0.015
	flight.sim.inputs[1]=-0.01
	flight.sim.step()
	check("real session reaches target bits",flight.sim.fault_reason.is_empty() and flight.sim.tick==1 and PackedFloat64Array([flight.sim.aux[2]]).to_byte_array()==PackedFloat64Array([-0.01]).to_byte_array())
	flight.sim.step()
	check("real second tick has no historical residual fault",flight.sim.fault_reason.is_empty() and flight.sim.tick==2)
	var cp: Dictionary=flight.checkpoint()
	check("law and interval identity pinned in outer checkpoint",not cp.is_empty() and cp.format==Servo.CHECKPOINT_FORMAT and cp.servo_integration_law==Law.LAW and cp.servo_partition_policy==Servo.PARTITION_POLICY)
	var unbound := cp.duplicate(true)
	unbound.format = "openrc-flight-checkpoint v15"
	unbound.erase("servo_partition_policy")
	var policy_frame := frame(flight)
	check("unbound isolated v15 checkpoint refuses without policy inference", not flight.restore_checkpoint(unbound) and frame(flight) == policy_frame)
	var wrong_policy := cp.duplicate(true)
	wrong_policy.servo_partition_policy = "servo-arrivals-zero-half-local-v1"
	check("another known partition cannot restore into this policy", not flight.restore_checkpoint(wrong_policy) and frame(flight) == policy_frame)
	var stock_frame := frame(legacy)
	var old_policy := old_cp.duplicate(true)
	old_policy["servo_partition_policy"] = Servo.PARTITION_POLICY
	check("policy marker cannot enter a stock checkpoint", not legacy.restore_checkpoint(old_policy) and frame(legacy) == stock_frame)
	old_policy = old_cp.duplicate(true)
	old_policy.format = Servo.UNBOUND_CHECKPOINT_FORMAT
	check("bare unbound v15 cannot enter a stock session", not legacy.restore_checkpoint(old_policy) and frame(legacy) == stock_frame)
	old_policy = old_cp.duplicate(true)
	old_policy.simulation["servo_partition_policy"] = Servo.PARTITION_POLICY
	check("nested policy marker cannot enter a stock checkpoint", not legacy.restore_checkpoint(old_policy) and frame(legacy) == stock_frame)
	var stock_header := {metadata = legacy.trace_meta(), checkpoint = old_policy, aircraft = legacy.aircraft,
		stage_backend = legacy.stage_backend_identity(), layout = {state = 13, loads = 6, inputs = 4,
		aux = legacy.sim.aux.size(), continuous = legacy.sim.continuous.size(), modes = legacy.sim.modes.size()}}
	check("nested policy marker cannot hide in historical inspection", not Reader.recorded_servo_declaration(stock_header).ok)
	var wind:=Weather.defaults()
	wind.speed_mps=2.0
	var kept_frame:=frame(flight)
	check("unsupported weather setter refuses before mutation",not flight.setup_weather(wind) and frame(flight)==kept_frame and flight.weather_is_calm())
	var weather_build:=WeatherField.build(wind)
	var blocked:=session(selected,"gdscript_reference")
	var blocked_frame:=frame(blocked)
	check("unsupported weather is refused at tick zero",not blocked.setup_weather(wind) and frame(blocked)==blocked_frame and blocked.weather_is_calm())
	var published: Array[int]=[0]
	blocked.sim.stepped.connect(func(_k: int,_t: float,_b: PackedFloat64Array,_l: PackedFloat64Array,_i: PackedFloat64Array,_a: PackedFloat64Array) -> void:published[0]+=1)
	blocked.set("_weather",weather_build.field)
	blocked.reset()
	check("unsupported reset does not publish or change physical frame",frame(blocked)==blocked_frame and published[0]==0 and not blocked.start_error.is_empty())
	blocked.free()
	var wind_cp:=cp.duplicate(true)
	wind_cp.weather_config=wind
	wind_cp.configuration=flight._configuration_for_weather(weather_build.field)
	var resets: Array[int]=[0]
	var samples: Array[int]=[0]
	flight.resetting.connect(func() -> void: resets[0]+=1)
	flight.sim.stepped.connect(func(_k: int,_t: float,_b: PackedFloat64Array,_l: PackedFloat64Array,_i: PackedFloat64Array,_a: PackedFloat64Array) -> void:samples[0]+=1)
	check("unsupported restored weather is refused atomically",not flight.restore_checkpoint(wind_cp) and frame(flight)==kept_frame and flight.weather_is_calm())
	check("refused restore publishes no reset or recorder samples",resets[0]==0 and samples[0]==0)
	for field: String in ["servo_integration_law","servo_interval_protocol","servo_interval_layout","servo_partition_policy","servo_physics_format"]:
		for bad: Variant in [null,1,true,[],{}]:
			var malformed:=cp.duplicate(true)
			malformed[field]=bad
			check("malformed selected checkpoint refuses quietly and atomically",not flight.restore_checkpoint(malformed) and frame(flight)==kept_frame and resets[0]==0 and samples[0]==0)
	check("ordinary restore refuses historical law",not flight.restore_checkpoint(old_cp) and not legacy.restore_checkpoint(cp))
	var restored:=session(selected,"gdscript_reference")
	check("new law restores its own nonzero boundary",restored.restore_checkpoint(cp))
	flight.sim.step()
	restored.sim.step()
	check("restored new-law continuation is exact",flight.sim.fault_reason.is_empty() and restored.sim.fault_reason.is_empty() and frame(flight)==frame(restored))
	check("trace declares actual law/protocol",flight.trace_meta().servo_integration_law==Law.LAW and flight.trace_meta().servo_interval_protocol==Model.PROTOCOL_JOINT_INTERVAL_LOCAL)
	replay_check(restored)
	for tamper: String in ["token", "callback", "pre_tick", "stage_interval", "block_aux"]:
		var guarded := session(selected, "gdscript_reference")
		var guarded_frame := frame(guarded)
		var guarded_cp: Dictionary = guarded.checkpoint()
		var observed: Array[int] = [0]
		guarded.resetting.connect(func() -> void: observed[0] += 1)
		guarded.sim.stepped.connect(func(_k: int, _t: float, _b: PackedFloat64Array, _l: PackedFloat64Array,
			_i: PackedFloat64Array, _a: PackedFloat64Array) -> void: observed[0] += 1)
		if tamper == "token":
			guarded.sim.model.identity.servo_partition_policy = "tampered-policy"
		elif tamper == "callback":
			guarded.sim.model.step_policy_interval = func(_s: PackedFloat64Array, _t: float, _dt: float,
				_d: Callable, _f: PackedFloat64Array, _c: Dictionary) -> Variant: return _s.duplicate()
		elif tamper == "pre_tick":
			guarded.sim.model.pre_tick = func(_a: PackedFloat64Array, _i: PackedFloat64Array, _dt: float) -> PackedFloat64Array: return _a.duplicate()
		elif tamper == "stage_interval":
			guarded.sim.model.stage_interval = func(_b: PackedFloat64Array, _v: PackedFloat64Array, _at: float,
				_c: Dictionary, _origin: float, _end: float) -> Dictionary: return {}
		else:
			guarded.sim.model.block_aux = func(_v: PackedFloat64Array, _a: PackedFloat64Array) -> PackedFloat64Array: return _a.duplicate()
		check("live partition " + tamper + " mutation refuses checkpoint", guarded.checkpoint().is_empty())
		check("live partition " + tamper + " mutation refuses restore without publication", not guarded.restore_checkpoint(guarded_cp)
			and frame(guarded) == guarded_frame and observed[0] == 0)
		guarded.sim.step()
		check("live partition " + tamper + " mutation refuses before stepping", not guarded.sim.fault_reason.is_empty() and frame(guarded) == guarded_frame)
		guarded.free()
	for bad: Variant in [null, false, 1, [], {}, StringName(Servo.PARTITION_POLICY)]:
		var guarded := session(selected, "gdscript_reference")
		var guarded_frame := frame(guarded)
		var guarded_cp: Dictionary = guarded.checkpoint()
		guarded.sim.model.identity.servo_partition_policy = bad
		check("malformed live policy refuses checkpoint quietly", guarded.checkpoint().is_empty())
		check("malformed live policy refuses restore atomically", not guarded.restore_checkpoint(guarded_cp) and frame(guarded) == guarded_frame)
		guarded.sim.step()
		check("malformed live policy refuses the tick quietly", not guarded.sim.fault_reason.is_empty() and frame(guarded) == guarded_frame)
		guarded.free()
	for owner: String in ["model_identity", "aircraft_controls"]:
		for bad: Variant in [null, false, 1, [], {}, StringName(Law.LAW)]:
			var guarded := session(selected, "gdscript_reference")
			var guarded_frame := frame(guarded)
			var guarded_cp: Dictionary = guarded.checkpoint()
			if owner == "model_identity":
				guarded.sim.model.identity.servo_integration = bad
			else:
				guarded.aircraft.model.controls.servo_integration = bad
			check("malformed live law refuses checkpoint quietly", guarded.checkpoint().is_empty())
			check("malformed live law refuses restore atomically", not guarded.restore_checkpoint(guarded_cp) and frame(guarded) == guarded_frame)
			guarded.sim.step()
			check("malformed live law refuses the tick quietly", not guarded.sim.fault_reason.is_empty() and frame(guarded) == guarded_frame)
			guarded.free()
	var tiny:=session(selected,"gdscript_reference")
	for _i in 240: tiny.sim.step()
	var tiny_frame:=frame(tiny)
	tiny.sim.inputs[0]=tiny.sim.aux[1]+1e-15
	var tiny_target: float=tiny.sim.inputs[0]
	tiny.sim.step()
	check("sub-ULP absolute arrival advances on the local clock",tiny.sim.fault_reason.is_empty() and frame(tiny)!=tiny_frame and tiny.sim.aux[1]==tiny_target)
	tiny.free()
	var temporal:=TemporalSession.new()
	temporal.setup_stage_backend("gdscript_reference")
	check("time-dependent derived providers are outside this domain",not temporal.ServoFlight.admission(temporal,selected.model).ok)
	temporal.free()
	var changed_provider:=session(selected,"gdscript_reference")
	changed_provider.environment.turbulence=func(at: float) -> PackedFloat64Array:return PackedFloat64Array([at,0.0,0.0])
	check("time-dependent substituted provider refuses before flight",not changed_provider._flight_ready())
	changed_provider.free()
	var removed:=session(selected,"gdscript_reference")
	var removed_frame:=frame(removed)
	removed.aircraft.model.controls.erase("servo_integration")
	check("removing selector cannot relabel an installed law",not removed._flight_ready() and removed.checkpoint().is_empty())
	removed.sim.step()
	check("removed selector refuses the whole tick",not removed.sim.fault_reason.is_empty() and frame(removed)==removed_frame)
	removed.free()
	var before:=frame(flight)
	flight.aircraft.model.controls.servo_integration="changed-law"
	flight.sim.step()
	check("live law mutation refuses the whole tick",not flight.sim.fault_reason.is_empty() and frame(flight)==before and flight.checkpoint().is_empty())
	flight.free()
	restored.free()
	legacy.free()
	finish()

func finish() -> void:
	print("SERVO_INTERVAL_FLIGHT_TEST %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
