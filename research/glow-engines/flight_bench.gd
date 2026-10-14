## Paired installed-aircraft experiment. Numerical verification, not measured flight data.
extends SceneTree
const Session=preload("res://sim/flight_session.gd")
const FieldLoader=preload("res://data/field_loader.gd")
const M=preload("res://physics/math3d.gd")
const RB=preload("res://physics/rigid_body.gd")
var hz:=240
var output:=""
var results: Array=[]
var failed:=false
const SOURCE_PATHS := [
	"research/glow-engines/flight_bench.gd", "app/sim/flight_session.gd", "app/sim/simulation.gd",
	"app/data/field_loader.gd", "app/physics/aircraft_data.gd", "app/physics/glow/profile.gd",
	"app/physics/glow/installation.gd", "app/physics/glow/flight.gd", "app/physics/glow/lifecycle.gd",
	"app/physics/glow/source.gd", "app/physics/glow/two_stroke.gd", "app/physics/glow/four_stroke.gd",
	"app/physics/glow/thermal.gd", "app/physics/glow/fuel_mass.gd", "app/physics/glow/propeller.gd",
	"app/physics/glow/vibration.gd",
	"app/physics/dynamics.gd", "app/physics/propulsion.gd", "app/physics/glow/operating_point.gd",
	"app/physics/electric_battery_step.gd", "app/physics/math3d.gd", "app/physics/rigid_body.gd",
	"app/physics/rotor_coupling.gd", "app/physics/glow/fuel_feed.gd",
]

func source_hashes() -> Dictionary:
	var hashes: Dictionary={}
	for path: String in SOURCE_PATHS:
		var digest: String=FileAccess.get_sha256(ProjectSettings.globalize_path("res://..").path_join(path))
		if digest.length()!=64:
			failed=true
		hashes[path]=digest
	return hashes

func snapshot(f: Node) -> Dictionary:
	var t: Dictionary=f.glow_state()
	return {time_s=f.sim.time(),body=Array(f.sim.state),continuous=Array(f.sim.continuous),
		rpm=t.get("rpm",0.),fuel_kg=t.get("fuel_kg",0.),temperature_k=t.get("temperature_k",0.),
		shaft_work_j=t.get("shaft_work_j",0.),propeller_work_j=t.get("propeller_work_j",0.),
		thrust_work_j=t.get("thrust_work_j",0.),running=t.get("running",false),
		stop_reason=t.get("stop_reason",""),mass_kg=t.get("mass_properties",{}).get("mass_kg",0.),
		firing_fraction=t.get("firing_fraction",0.),fault=f.sim.fault_reason}

func record_mode_event(events: Array, f: Node, before: PackedFloat64Array, lower: float, kind: String) -> void:
	var after: PackedFloat64Array=f.sim.continuous
	if before[7]==after[7] and before[8]==after[8]: return
	events.append({kind=kind,lower_time_s=lower,upper_time_s=f.sim.time(),
		from_running=before[7]>0.5,from_reason=int(before[8]),
		to_running=after[7]>0.5,to_reason=int(after[8])})

func run_case(id: String, scenario: String) -> void:
	var f=Session.new()
	f.setup("res://data/aircraft/stik_glow_"+id+".json")
	f.input_enabled=false
	if not f.is_flyable():
		failed=true;f.free();return
	if scenario=="takeoff":
		f.set_field(FieldLoader.load_from().field)
		if not f.reset_on_runway(15.,-47.,PI/2.) or not f.glow_start():
			failed=true;f.free();return
	var initial: Dictionary=snapshot(f)
	var samples: Array=[initial]
	var mode_events: Array=[]
	var costs: Array=[]
	var duration: int=6 if scenario=="takeoff" else 3
	for tick in duration*hz:
		var before_command: PackedFloat64Array=f.sim.continuous.duplicate()
		if scenario=="takeoff":
			f.sim.inputs[3]=1.
			if tick>=3*hz: f.sim.inputs[1]=.18
		elif scenario=="steps":
			if tick==hz/2: f.sim.inputs[3]=1.
			if tick==hz+hz/2: f.sim.inputs[3]=.25
			if tick==2*hz: f.glow_cut()
		elif scenario=="rich":
			if tick==hz/2: f.glow_set_mixture(1.9)
		elif scenario=="lean":
			if tick==hz/2: f.glow_set_mixture(.1)
		elif scenario=="exhaustion":
			if tick==hz/2: f.sim.continuous[1]=1e-7
		record_mode_event(mode_events,f,before_command,f.sim.time(),"command")
		var before_step: PackedFloat64Array=f.sim.continuous.duplicate()
		var step_start_s: float=f.sim.time()
		var started: int=Time.get_ticks_usec()
		f.sim.step()
		costs.append(Time.get_ticks_usec()-started)
		record_mode_event(mode_events,f,before_step,step_start_s,"accepted_step")
		if not f.sim.fault_reason.is_empty():
			failed=true;break
		if (tick+1)%(hz/10)==0: samples.append(snapshot(f))
	costs.sort()
	results.append({engine=id,scenario=scenario,hz=hz,initial=initial,final=snapshot(f),samples=samples,mode_events=mode_events,
		cost_us={p50=costs[int(costs.size()*.5)],p95=costs[int(costs.size()*.95)],maximum=costs[-1]},
		configuration=f.trace_meta()})
	print(id," ",scenario," ",f.sim.tick," ticks; p95 ",costs[int(costs.size()*.95)]," us; ",f.sim.fault_reason)
	f.free()

func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=arg.trim_prefix("--hz=").to_int()
		if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
	if hz not in [240,480,960,1920] or output.is_empty(): quit(2);return
	var sources_before: Dictionary=source_hashes()
	Engine.physics_ticks_per_second=hz
	for id in ["55ax_2t","fs64v_4t"]:
		for scenario in ["cruise","steps","rich","lean","exhaustion","takeoff"]:
			run_case(id,scenario)
	if sources_before!=source_hashes():
		printerr("Flight benchmark source changed during execution; repeat from a stable snapshot")
		failed=true
	var file=FileAccess.open(output,FileAccess.WRITE)
	if file==null: quit(2);return
	file.store_string(JSON.stringify({format="openrc-glow-flight-experiment v3",ok=not failed,hz=hz,runs=results,source_sha256=sources_before},"\t",true,true)+"\n")
	quit(1 if failed else 0)
