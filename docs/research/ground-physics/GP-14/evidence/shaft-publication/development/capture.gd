extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const AD := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Weather := preload("res://physics/wind_config.gd")
var checks := 0
var failed := 0
func check(label:String, passed:bool)->void:
	checks+=1
	if not passed: failed+=1; printerr("FAIL ",label)
func _initialize()->void: call_deferred("_run")
func flight(mode: String = "auto") -> Node:
	var raw_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(P51_PATH))
	if not raw_value is Dictionary:
		return null
	var raw: Dictionary = raw_value
	raw.propulsion.erase("fuel_consumption")
	raw.capabilities.energy = "prescribed_fuel"
	var checked: Dictionary = AD.validate_and_derive(raw)
	if not checked.get("ok", false):
		return null
	var profiled: Dictionary = WheelProfiles.apply_to_model(checked.model)
	if not profiled.get("ok", false):
		return null
	checked.model = profiled.model
	checked.wheel_profile_identity = profiled.identity
	var flight: Node = Flight.new()
	# setup() creates the simulation before _apply() refits the in-memory legacy contract.
	flight.setup(P51_PATH)
	if not flight._apply(checked):
		flight.free()
		return null
	if mode != "auto" and not flight.setup_shaft_integrator(mode):
		flight.free()
		return null
	flight.input_enabled = false
	flight.reset()
	return flight



func _run()->void:
	Engine.physics_ticks_per_second=240
	var result:Dictionary={}
	for initial:String in ["split","coupled-rk4"]:
		var f:=flight(initial)
		check("legacy fixture starts",f!=null)
		if f==null:continue
		var target:="split" if initial=="coupled-rk4" else "coupled-rk4"
		check("opposite mode accepts",f.setup_shaft_integrator(target))
		f.reset()
		var hash:=HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
		for tick:int in 25:
			check("complete baseline checkpoint",not f.checkpoint().is_empty())
			hash.update(var_to_bytes(f.checkpoint()))
			if tick<24:f.sim.step()
		result[target]=hash.finish().hex_encode()
		f.free()
	var broken:=flight("split")
	broken.resetting.connect(func(): broken.sim.mass=0.0)
	var accepted:bool=broken.setup_shaft_integrator("coupled-rk4")
	result.observer_defect={accepted=accepted,mass=broken.sim.mass,mode=broken.shaft_integrator(),pending=broken._shaft_pending_reset}
	check("old unguarded observer defect reproduced",accepted and broken.sim.mass==0.0 and broken._shaft_pending_reset)
	broken.free()
	var file:=FileAccess.open("res://../tmp/gp-shaft-publication/baseline.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	print("Shaft baseline: %d checks, %d failed"%[checks,failed]);quit(1 if failed else 0)
