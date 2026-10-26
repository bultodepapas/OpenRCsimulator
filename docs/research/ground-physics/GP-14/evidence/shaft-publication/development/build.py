from pathlib import Path
import hashlib, json

root = Path(__file__).resolve().parents[2]
home = Path(__file__).resolve().parent
source = root / 'app/sim/flight_session.gd'
raw = source.read_bytes()
(home/'flight_session.before.gd').write_bytes(raw)
text = raw.decode()
fixture = (root/'app/tests/test_shaft_coupled.gd').read_text()
fixture = fixture[fixture.index('func _legacy_static_fuel_p51'):fixture.index('## The standalone shaft helpers')]
fixture = fixture.replace('func _legacy_static_fuel_p51', 'func flight')
header = '''extends SceneTree
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
'''+fixture
(home/'fixture.gd').write_text(header, newline='\n')
capture = header + '''
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
	file.store_string(JSON.stringify(result,"  ")+"\\n");file.close()
	print("Shaft baseline: %d checks, %d failed"%[checks,failed]);quit(1 if failed else 0)
'''
(home/'capture.gd').write_text(capture,newline='\n')
(home/'before.json').write_text(json.dumps({'sha256':hashlib.sha256(raw).hexdigest()},indent=2)+'\n')
print('Prepared baseline capture and source snapshot')
