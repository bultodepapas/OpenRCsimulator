extends SceneTree
const Detector := preload("res://statistics/detector.gd")
const Event := preload("res://statistics/flight_event.gd")
const Service := preload("res://statistics/service.gd")
var checks := 0
var failed := 0

func _initialize() -> void:
	_edges()
	_success()
	_accidents()
	_restore()
	_contract()
	_service()
	print("Ground flight events: %d checks, %d failed" % [checks,failed])
	quit(1 if failed else 0)

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ",label)

func profile() -> Dictionary:
	return {landing_available=true, generation_id="test-generation", aircraft_id="synthetic",
		configuration_hash="fixture", rules={liftoff_clearance_s=.2,stable_support_s=.2,full_stop_s=.4,rearm_clearance_s=.3}}

func sample(tick: int, ground := false, changes := {}) -> Dictionary:
	var value := {tick=tick,dt=.1,valid=true,supported=ground,ground_contact=ground,intended_support=ground,
		stop_support=ground,controlled=true,clearance_ok=not ground,ground_speed_3d=5.0,angular_speed=0.0,
		incident=false,gear_up_contact=false,terminal=false}
	value.merge(changes,true)
	return value

func semantic(events: Array, kind := "") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in events:
		if entry.get("type") == "semantic" and (kind.is_empty() or entry.event.type == kind): found.append(entry.event)
	return found

func active() -> RefCounted:
	var d := Detector.new()
	d.configure(profile())
	d.observe(sample(1,true))
	d.observe(sample(2))
	d.observe(sample(3))
	return d

func _edges() -> void:
	var d := Detector.new()
	d.configure(profile())
	check("spawn support produces no touchdown", semantic(d.observe(sample(1,true))).is_empty())
	check("departure pending does not emit takeoff", semantic(d.observe(sample(2))).is_empty())
	var start := semantic(d.observe(sample(3)),"TAKEOFF")
	check("confirmed actual departure retains first loss and confirmation",start.size()==1 and start[0].measurements.first_loss_support_tick==2 and start[0].accepted_tick==3)
	var touch := semantic(d.observe(sample(4,true)),"TOUCHDOWN")
	check("first physical contact emits one touchdown",touch.size()==1 and touch[0].measurements.first_contact_tick==4)
	check("duplicate accepted tick is silent",d.observe(sample(4,true)).is_empty())
	d.observe(sample(5))
	d.observe(sample(6))
	var bounce := semantic(d.observe(sample(7,true)),"BOUNCE")
	check("two unsupported samples emit one resolved hop",bounce.size()==1 and absf(bounce[0].measurements.unsupported_seconds-.2)<1e-15)
	check("bounce shares first touchdown episode",bounce.size()==1 and bounce[0].contact_episode_id==touch[0].contact_episode_id)
	check("persistent support does not retrigger",semantic(d.observe(sample(8,true))).is_empty())
	d.observe(sample(9))
	check("second hop has distinct event identity",semantic(d.observe(sample(10,true)),"BOUNCE")[0].event_id!=bounce[0].event_id)
	var air := Detector.new()
	air.configure(profile(),true)
	air.observe(sample(1))
	check("air start earns no semantic takeoff",semantic(air.observe(sample(2)),"TAKEOFF").is_empty())
	var unknown := Detector.new()
	unknown.configure(profile())
	unknown.observe(sample(1))
	check("unobserved prior support cannot invent departure",semantic(unknown.observe(sample(2)),"TAKEOFF").is_empty())
	var invalid := active()
	check("invalid sample emits no hop or touchdown",semantic(invalid.observe(sample(4,true,{valid=false}))).is_empty())
	check("lost continuity cannot invent later touchdown",semantic(invalid.observe(sample(5,true))).is_empty())
	var wheel_less := active()
	var normal := semantic(wheel_less.observe(sample(4,true,{gear_up_contact=false})))
	check("normal authored belly support need not be a crash",normal.size()==1 and normal[0].type=="TOUCHDOWN")

func _success() -> void:
	var d := active()
	var events: Array = []
	for tick in range(4,7): events.append_array(d.observe(sample(tick,true)))
	for tick in range(7,10): events.append_array(d.observe(sample(tick)))
	check("controlled rearm emits one success and touch-and-go",semantic(events,"LANDING_SUCCESS").size()==1 and semantic(events,"TOUCH_AND_GO").size()==1)
	check("departure is not a bounce without recontact",semantic(events,"BOUNCE").is_empty())
	check("touch-and-go preserves active flight",not d.flight.is_empty() and d.flight.touch_and_go==1)
	events.clear()
	for tick in range(10,19): events.append_array(d.observe(sample(tick,true,{ground_speed_3d=0.0})))
	check("full stop reports one physical rest and one success",semantic(events,"GROUND_STOP").size()==1 and semantic(events,"LANDING_SUCCESS").size()==1)
	check("full stop does not fabricate touch-and-go",semantic(events,"TOUCH_AND_GO").is_empty())
	check("closed flight remains quiet while resting",semantic(d.observe(sample(19,true,{ground_speed_3d=0.0}))).is_empty())

func _accidents() -> void:
	var d := active()
	var facts := {gear_up_contact=true,intended_support=false,controlled=false}
	var events: Array = d.observe(sample(4,true,facts))
	check("gear-up contact emits touchdown, gear-up and crash",semantic(events,"TOUCHDOWN").size()==1 and semantic(events,"GEAR_UP_CONTACT").size()==1 and semantic(events,"CRASH").size()==1)
	var crash := semantic(events,"CRASH")[0]
	check("survivable crash remains nonterminal and unknown damage",not crash.terminal and crash.continuation=="continues" and crash.severity_status=="unknown")
	check("pilot command is not inferred as cause",crash.cause.classification=="unknown")
	check("all initial incident events share episode and accident",semantic(events,"TOUCHDOWN")[0].contact_episode_id==crash.contact_episode_id and semantic(events,"GEAR_UP_CONTACT")[0].accident_id==crash.accident_id)
	check("scraping does not register another crash",semantic(d.observe(sample(5,true,facts)),"CRASH").is_empty())
	d.observe(sample(6))
	check("damaged bounce does not register another crash",semantic(d.observe(sample(7,true,facts)),"CRASH").is_empty())
	var terminal := facts.duplicate(true)
	terminal.terminal=true
	var update := semantic(d.observe(sample(7,true,terminal)),"CRASH")
	check("same tick terminal escalation revises same accident",update.size()==1 and update[0].revision==1 and update[0].accident_id==crash.accident_id and update[0].terminal)
	check("terminal duplicate is silent",d.observe(sample(7,true,terminal)).is_empty())
	var terminal_hop := active()
	terminal_hop.observe(sample(4,true))
	terminal_hop.observe(sample(5))
	var terminal_events: Array = terminal_hop.observe(sample(6,true,{terminal=true}))
	var terminal_bounce := semantic(terminal_events,"BOUNCE")
	check("accepted terminal recontact retains factual bounce",terminal_bounce.size()==1 and terminal_bounce[0].terminal)
	check("terminal hop still emits one initial crash",semantic(terminal_events,"CRASH").size()==1)
	var pending_touch := active()
	pending_touch.observe(sample(4,false,{intended_support=true}))
	check("terminal first actual support retains touchdown",semantic(pending_touch.observe(sample(5,true,{terminal=true})),"TOUCHDOWN").size()==1)
	var invalid_terminal := active()
	var invalid_events: Array = invalid_terminal.observe(sample(4,true,{terminal=true,valid=false}))
	check("invalid terminal observation cannot invent touchdown",semantic(invalid_events,"TOUCHDOWN").is_empty())
	check("terminal outcome keeps explicit gap coverage",semantic(invalid_events,"CRASH")[0].evidence_coverage.has("discontinuous_observation"))
	check("terminal gap cannot claim valid endpoint interval",not semantic(invalid_events,"CRASH")[0].evidence_coverage.has("accepted_endpoint_support"))
	var duplicate_terminal := active()
	check("same-tick terminal guard cannot invent accepted support edge",semantic(duplicate_terminal.observe(sample(3,true,{terminal=true})),"TOUCHDOWN").is_empty())
	var stop := active()
	var all_events: Array = []
	facts.ground_speed_3d=0.0
	for tick in range(4,12): all_events.append_array(stop.observe(sample(tick,true,facts)))
	check("damaged hull rest has stop without landing success",semantic(all_events,"GROUND_STOP").size()==1 and semantic(all_events,"LANDING_SUCCESS").is_empty())
	var second := active()
	second.observe(sample(4,true,facts))
	for tick in range(5,8): second.observe(sample(tick))
	var later: Array = second.observe(sample(8,true,facts))
	check("new accident after rearm has semantic crash but no second M7",semantic(later,"CRASH").size()==1 and later.filter(func(e: Dictionary)->bool:return e.type=="crash").is_empty())

func _restore() -> void:
	var d := active()
	d.observe(sample(4,true))
	d.observe(sample(5))
	var snap: Dictionary = JSON.parse_string(JSON.stringify(d.snapshot()))
	var restored := Detector.new()
	check("v3 JSON checkpoint restores mid-hop",restored.restore(snap))
	var expected: Array = d.observe(sample(6,true))
	check("restored hop preserves exact IDs and semantics",JSON.stringify(restored.observe(sample(6,true)))==JSON.stringify(expected))
	for name: String in ["semantic_sequence","hop_seconds","hop_first_tick","episode_supported","episode_open","last_tick","excess_duration","before_episode"]:
		var bad := snap.duplicate(true)
		match name:
			"semantic_sequence":bad[name]=-1
			"hop_seconds":bad[name]=-1
			"hop_first_tick":bad[name]=1000
			"episode_supported":bad[name]=true
			"episode_open":bad[name]=false
			"last_tick":bad[name]="bad"
			"excess_duration":bad.hop_seconds=1000.0
			"before_episode":bad.hop_first_tick=2
		var before := var_to_bytes(restored.snapshot())
		check("malformed semantic snapshot rejects atomically: "+name,not restored.restore(bad) and before==var_to_bytes(restored.snapshot()))
	var supported_snapshot: Dictionary = restored.snapshot()
	supported_snapshot.episode_contact_seen=false
	check("supported semantic snapshot requires witnessed contact",not restored.restore(supported_snapshot))
	var legacy := snap.duplicate(true)
	legacy.version=2
	var old := Detector.new()
	check("historical v2 restores",old.restore(legacy))
	check("historical unknown hop is not fabricated",semantic(old.observe(sample(6,true))).is_empty())
	check("old snapshot remains upgradeable",restored.restore(old.snapshot()))
	var incident := active()
	incident.observe(sample(4,true,{gear_up_contact=true}))
	var older: Dictionary = incident.snapshot()
	older.version=2
	check("v2 preserves accident state through v3 migration",old.restore(older) and old.snapshot().accident_id==older.accident_id)

func _contract() -> void:
	var d := active()
	var event := semantic(d.observe(sample(4,true)))[0]
	check("closed event envelope validates",Event.valid(event))
	for key: String in Event.KEYS:
		var bad := event.duplicate(true)
		bad.erase(key)
		check("required event field "+key,not Event.valid(bad))
	var mutated := event.duplicate(true)
	mutated.measurements.speed_mps=12.0
	check("unqualified measurement cannot be smuggled",not Event.valid(mutated))
	mutated=event.duplicate(true)
	mutated.cause.classification="pilot_command"
	check("unsupported causal certainty is rejected",not Event.valid(mutated))

	for primitive: Variant in [null, true, 1, 1.0, [], {}]:
		for selector: String in ["format", "version", "rules_version", "type", "continuation", "severity_status", "classification", "uncertainty"]:
			# Integer version 1 is the valid control; all other replacements refuse.
			if selector == "version" and typeof(primitive) == TYPE_INT: continue
			var malformed := event.duplicate(true)
			if selector in ["classification", "uncertainty"]: malformed.cause[selector] = primitive
			else: malformed[selector] = primitive
			check("primitive event selector cleanly refuses " + selector, not Event.valid(malformed))

func _service() -> void:
	var service := Service.new()
	check("nonpersistent service initializes",service.setup("",false))
	service._ensure_session()
	service._generation="test-generation"
	service._aircraft_id="synthetic"
	service._aircraft_name="Synthetic"
	var d := Detector.new()
	d.configure(profile())
	var batches: Array = []
	service.flight_events_accepted.connect(func(batch: Array)->void:
		batches.append(batch.duplicate(true))
		var mutable := batch.duplicate(true)
		mutable.clear())
	service._ingest(d.observe(sample(1,true)))
	service._ingest(d.observe(sample(2)))
	service._ingest(d.observe(sample(3)))
	check("service publishes ordered semantic batch",batches.size()==1 and batches[0][0].type=="TAKEOFF")
	var immutable := Event.frozen_batch(batches[0])
	check("shared batch is recursively immutable",immutable.is_read_only() and immutable[0].is_read_only()
		and immutable[0].measurements.is_read_only() and immutable[0].cause.is_read_only() and immutable[0].cause.evidence_ids.is_read_only())
	service._ingest(d.observe(sample(4,true)))
	check("subscriber mutation leaves persisted detail intact",service._active_record.metadata.events.any(func(e: Dictionary)->bool:return e.type=="TOUCHDOWN"))
	var tick:=4
	for i in 180:
		tick+=1
		service._ingest(d.observe(sample(tick)))
		tick+=1
		service._ingest(d.observe(sample(tick,true)))
	check("detailed event history is bounded",service._active_record.metadata.events.size()<=128 and service._active_record.metadata.get("events_omitted",0)>0)
	check("bounded metadata fits native store byte contract",var_to_bytes(service._active_record.metadata).size()<64*1024)
	check("overflow does not drop shared subscriber events",batches.size()==182)
	service.free()
