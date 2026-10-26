## Read-only source audit: observed configuration defects and preservation controls.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Field := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")
var checks := 0
var failed := 0
var output := ""
var observations: Array[Dictionary] = []

func check(label: String, value: bool) -> void:
    checks += 1
    if not value: failed += 1; printerr("FAIL ", label)

func flight() -> Node:
    var f := Flight.new()
    f.input_enabled = false
    f.crash_auto_restart = false
    f.setup()
    return f

func tracked(f: Node, name: String) -> Dictionary:
    var writer := Log.new(f)
    var path := output.path_join(name + ".orfl")
    check(name + " writer opens", writer.start(path) == OK)
    var counts := [0,0,0,0]
    f.resetting.connect(func(): counts[0] += 1)
    f.sim.paused_changed.connect(func(_p): counts[1] += 1)
    f.sim.stepped.connect(func(_k,_t,_s,_l,_i,_a): counts[2] += 1)
    f.statistics_lifecycle.connect(func(_r): counts[3] += 1)
    return {writer=writer,counts=counts,path=path,before=var_to_bytes(f.checkpoint()),model=f.sim.model,
        generation=f.statistics_generation,rects=f.ground_surfaces.duplicate(),airframe=f.airframe_surfaces.duplicate(),
        registry=var_to_bytes(f.environment.sample_support(PackedFloat64Array([0.0,0.0,-1.0]),PackedFloat64Array([0.0,0.0,0.0]),0.0))}

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
    Engine.physics_ticks_per_second = 240
    output=ProjectSettings.globalize_path("res://../tmp/config-publication-%d" % Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(output)
    var loaded := Field.load_from()
    check("authored field loads", loaded.ok)
    var f := flight()
    check("valid field installs", f.set_field(loaded.field))
    for i: int in 3: f.sim.step()
    var b := tracked(f,"field-refusal")
    var accepted: bool=f.set_field(loaded.field,"res://data/ground/missing-config-audit.json")
    var event: Dictionary={case="field-refusal",accepted=accepted,old_rect_count=b.rects.size(),new_rect_count=f.ground_surfaces.size(),
        old_airframe_count=b.airframe.size(),new_airframe_count=f.airframe_surfaces.size(),old_checkpoint_same=b.before==var_to_bytes(f.checkpoint()),
        checkpoint_available=not f.checkpoint().is_empty(),paused=f.sim.paused,signals=b.counts.duplicate(),writer_open=b.writer.recording,
        field_id=f.ground_field_id,runway_empty=f._runway_field.is_empty(),flyable=f.is_flyable(),surface_error=f.surface_error,
        same_model=b.model==f.sim.model,same_generation=f.statistics_generation==b.generation}
    observations.append(event)
    check("reproduced field refusal empties live physical tables", not accepted and b.rects.size()>0 and f.ground_surfaces.is_empty() and f.airframe_surfaces.is_empty())
    check("reproduced field refusal invalidates checkpoint and pauses old writer", not event.checkpoint_available and not event.old_checkpoint_same and event.paused and event.writer_open and event.signals==[0,1,0,0])
    check("refusal retains model/generation but loses accepted field", event.same_model and event.same_generation and event.runway_empty and event.field_id.is_empty() and not event.flyable)
    b.writer.stop("audit cleanup")
    f.free()

    f=flight()
    check("weather control field installs",f.set_field(loaded.field))
    for i: int in 3: f.sim.step()
    b=tracked(f,"live-weather-refusal")
    accepted=f.setup_weather(Weather.defaults())
    check("live weather refusal is silent and preserves old checkpoint/writer",not accepted and b.before==var_to_bytes(f.checkpoint()) and b.writer.recording and b.counts==[0,0,0,0])
    b.writer.stop("audit cleanup")
    f.free()

    f=flight()
    check("weather mutation field installs",f.set_field(loaded.field))
    b=tracked(f,"weather-listener")
    f.resetting.connect(func(): f.sim.mass=0.0)
    accepted=f.setup_weather(Weather.preset("cool-dense"))
    event={case="weather-listener",accepted=accepted,writer_open=b.writer.recording,mass=f.sim.mass,
        checkpoint_available=not f.checkpoint().is_empty(),pending=f._weather_pending_reset,signals=b.counts.duplicate(),
        new_weather=f.weather_configuration(),generation=f.statistics_generation}
    observations.append(event)
    check("reproduced weather notification precedes valid physical boundary",accepted and not event.writer_open and event.mass==0.0 and not event.checkpoint_available and event.pending and event.signals==[1,1,0,0])
    f.free()

    f=flight()
    check("accepted field control fixture installs",f.set_field(loaded.field))
    for i: int in 3:f.sim.step()
    b=tracked(f,"accepted-field-no-reset")
    accepted=f.set_field(loaded.field)
    check("accepted identical field intentionally has no reset/sample/pause or generation",accepted and b.before==var_to_bytes(f.checkpoint()) and b.writer.recording and b.counts==[0,0,0,0] and b.generation==f.statistics_generation)
    b.writer.stop("audit cleanup")
    f.free()
    var file:=FileAccess.open(output.path_join("observations.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(observations,"\t",true,true));file.close()
    print("Configuration audit: %d checks, %d failed; %s" % [checks,failed,output])
    quit(1 if failed else 0)
