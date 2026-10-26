## Refused field replacement preserves accepted physical/observer ownership.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Field := preload("res://data/field_loader.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
var checks := 0
var failed := 0
var output := ""
var field: Dictionary

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1; printerr("FAIL ",label)

func _initialize() -> void: call_deferred("_run")

func flight() -> Node:
	var f := Flight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.soft_hull_contacts = true
	f.setup()
	return f

func sample(f: Node) -> Array:
	var values := []
	for position: PackedFloat64Array in [PackedFloat64Array([0.0,0.0,-1.0]),PackedFloat64Array([5.0,10.0,-0.1]),PackedFloat64Array([30000.0,0.0,-1.0])]:
		values.append(f.environment.sample_support(position,PackedFloat64Array([0.2,0.0,0.0]),f.sim.time()))
	return values

func active(f: Node) -> PackedByteArray:
	return var_to_bytes([f.checkpoint(),f.ground_surfaces,f.airframe_surfaces,f.ground_field_id,f._runway_field,
		f._hull_contact,f.environment._ground_support,sample(f),f.commands,f.raw,f.holds,f.sim.paused,
		f.pause_reason,f.surface_error,f.statistics_generation,f.contact_events()])

func signals(f: Node) -> Array:
	var counts := [0,0,0,0]
	f.resetting.connect(func(): counts[0]+=1)
	f.sim.paused_changed.connect(func(_p): counts[1]+=1)
	f.sim.stepped.connect(func(_k,_t,_s,_l,_i,_a): counts[2]+=1)
	f.statistics_lifecycle.connect(func(_receipt): counts[3]+=1)
	return counts

func _run() -> void:
	Engine.physics_ticks_per_second=240
	output=ProjectSettings.globalize_path("res://../tmp/field-replacement-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	var loaded:=Field.load_from()
	check("authored field loads",loaded.ok)
	field=loaded.field
	_initial_refusal()
	for held: bool in [false,true]:
		for kind: String in ["missing","table","surface"]:_replacement(kind,held)
	_empty_fixture()
	_accepted_changes()
	print("Field replacement: %d checks, %d failed; %s" % [checks,failed,output])
	quit(1 if failed else 0)

func bad_field() -> Dictionary:
	return {id="refused",surfaces=[{id="unsupported",type="ice"}]}

func _initial_refusal() -> void:
	var f:=flight()
	var counts:=signals(f)
	check("first invalid field remains fail closed",not f.set_field(field,"res://data/ground/missing-field-replacement.json")
		and not f.is_flyable() and f.checkpoint().is_empty() and f.sim.paused
		and f.surface_error==f.field_update_error and not f.surface_error.is_empty())
	check("initial refusal keeps legacy pause/no reset boundary",counts==[0,1,0,0] and f.ground_surfaces.is_empty()
		and f.airframe_surfaces.is_empty() and f.ground_field_id.is_empty())
	check("first valid correction clears both errors",f.set_field(field) and f.surface_error.is_empty()
		and f.field_update_error.is_empty() and f.is_flyable())
	f.free()

func _replacement(kind: String,held: bool) -> void:
	var f:=flight()
	var control:=flight()
	check("paired installed fields",f.set_field(field) and control.set_field(field))
	for i: int in 4:f.sim.step();control.sim.step()
	if held:f.hold("test-menu");control.hold("test-menu")
	check("paired starting checkpoints",var_to_bytes(f.checkpoint())==var_to_bytes(control.checkpoint()))
	sample(f)
	var before:=active(f)
	var model: RefCounted=f.sim.model
	var counts:=signals(f)
	var writer:=Log.new(f)
	var path:=output.path_join(kind+("-held" if held else "-moving")+".orfl")
	check("accepted old writer starts",writer.start(path)==OK)
	var events:=var_to_bytes(writer._events)
	var accepted:=false
	if kind=="missing":accepted=f.set_field(field,"res://data/ground/missing-field-replacement.json")
	elif kind=="surface":accepted=f.set_field(bad_field())
	else:
		var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Surfaces.DEFAULT_PATH))
		raw.surfaces.runway.friction_factor.value=2.0
		var table_path:=output.path_join("invalid-table.json")
		var table_file:=FileAccess.open(table_path,FileAccess.WRITE)
		table_file.store_string(JSON.stringify(raw));table_file.close()
		accepted=f.set_field(field,table_path)
	check("refused replacement has separate diagnostic",not accepted and not f.field_update_error.is_empty() and f.surface_error.is_empty())
	check("refusal preserves complete active context "+kind,active(f)==before and f.sim.model==model)
	check("refusal emits no reset/pause/sample/generation",counts==[0,0,0,0] and writer.recording and var_to_bytes(writer._events)==events)
	if held:f.holds.erase("test-menu");control.holds.erase("test-menu")
	for i: int in 32:f.sim.step();control.sim.step()
	check("32 subsequent accepted ticks match untouched paired model",f.sim.tick==36 and var_to_bytes(f.checkpoint())==var_to_bytes(control.checkpoint()))
	check("recording survives accepted continuation",writer.recording and counts==[0,0,32,0])
	var final_checkpoint:=var_to_bytes(f.checkpoint())
	writer.stop("fixture cleanup")
	var read: Dictionary=Reader.inspect(path)
	check("old writer finishes with exact retained-flight footer",read.ok and var_to_bytes(read.footer.checkpoint)==final_checkpoint)
	var before_correction:=var_to_bytes(f.checkpoint())
	check("successful correction clears only diagnostic",f.set_field(field) and f.field_update_error.is_empty()
		and f.surface_error.is_empty() and var_to_bytes(f.checkpoint())==before_correction and counts==[0,0,32,0])
	f.free();control.free()

func _empty_fixture() -> void:
	var f:=flight()
	check("empty fixture with empty ID is accepted",f.set_field({id="",surfaces=[]}) and f.ground_field_id.is_empty() and f.is_flyable())
	sample(f)
	var before:=active(f)
	var counts:=signals(f)
	check("empty fixture counts as installed for refusal preservation",not f.set_field(bad_field()) and active(f)==before
		and counts==[0,0,0,0] and f.surface_error.is_empty() and not f.field_update_error.is_empty())
	check("empty fixture correction clears observational error",f.set_field({id="",surfaces=[]}) and f.field_update_error.is_empty())
	f.free()

func _accepted_changes() -> void:
	var f:=flight()
	check("accepted changes start with installed field",f.set_field(field))
	for i: int in 3:f.sim.step()
	var counts:=signals(f)
	var state:=var_to_bytes([f.sim.checkpoint(),f.commands,f.raw,f.holds])
	var generation: int=f.statistics_generation
	var changed: Dictionary=field.duplicate(true)
	changed.id="replacement-field"
	changed.surfaces[0].center_north+=0.25
	check("different valid installation retains accepted no-reset semantics",f.set_field(changed)
		and counts==[0,0,0,0] and generation==f.statistics_generation
		and state==var_to_bytes([f.sim.checkpoint(),f.commands,f.raw,f.holds]) and f.ground_field_id=="replacement-field")
	var installed:=var_to_bytes(f.ground_surfaces)
	changed.surfaces[0].center_north+=20.0
	check("accepted description detached from caller mutation",var_to_bytes(f.ground_surfaces)==installed
		and f._runway_field.surfaces[0].center_north!=changed.surfaces[0].center_north)
	f.free()
