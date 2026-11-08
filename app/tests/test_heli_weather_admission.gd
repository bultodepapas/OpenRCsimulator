extends SceneTree
const Session=preload("res://sim/helicopter_flight_session.gd")
const Weather=preload("res://physics/wind_config.gd")
const WeatherField=preload("res://physics/wind_field.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
 Engine.physics_ticks_per_second=240
 _run.call_deferred()

func check(label: String,ok: bool,detail: String="") -> void:
 checks+=1
 if not ok:
  failures+=1
  printerr("FAIL ",label," ",detail)

func _run() -> void:
 var session=Session.new()
 session.physics_enabled=false
 session.input_enabled=false
 root.add_child(session)
 check("airborne session starts",session.setup() and session.reset(),session.start_error)
 var cases: Array=[
  {name="calm",settings=Weather.preset("calm"),code="ok",error=""},
  {name="steady",settings=Weather.preset("steady"),code="ok",error=""},
  {name="gusty",settings=Weather.preset("gusty"),code="ok",error=""},
  {name="uniform atmosphere",settings=Weather.preset("hot-high"),code="ok",error=""},
  {name="malformed",settings={},code="invalid",error=""},
  {name="spatial",settings=Weather.preset("spatial-gusty-v1"),code="spatial",error="Spatial weather is not qualified for rotorcraft. Choose a uniform weather preset."},
  {name="vertical",settings=Weather.preset("standard-column"),code="vertical",error="Rotorcraft vertical atmosphere integration is not qualified; choose reference or uniform field conditions."},
  {name="turbulence",settings=Weather.preset("turbulent"),code="turbulence",error="Rotorcraft turbulence integration is not qualified; choose calm, steady wind or gusts."},
 ]
 for sample: Dictionary in cases:
  var source: Variant=sample.settings
  var original: PackedByteArray=var_to_bytes(source)
  var before: PackedByteArray=var_to_bytes(session.checkpoint())
  var old_weather: Dictionary=session.weather_configuration()
  var checked: Dictionary=Session.validate_weather_selection(source)
  var expected_error: String=sample.error
  if sample.code=="invalid": expected_error="; ".join(WeatherField.build(source).errors)
  check(sample.name+" static admission code and error",checked.size()==4 and checked.get("code")==sample.code and checked.get("error")==expected_error and checked.get("ok")==bool(sample.code=="ok"))
  check(sample.name+" admission is read only",original==var_to_bytes(source) and before==var_to_bytes(session.checkpoint()) and session.weather_configuration()==old_weather)
  check(sample.name+" admitted field is only returned on success",(checked.field!=null)==checked.ok)
  var accepted: bool=session.setup_weather(source)
  check(sample.name+" session agrees with admission",accepted==checked.ok and session.weather_error==expected_error)
  if checked.ok:
   check(sample.name+" session uses the validated canonical field",session.weather_configuration()==checked.field.configuration())
   check(sample.name+" can return to calm and reset",session.setup_weather(Weather.preset("calm")) and session.reset(),session.start_error)
  else:
   check(sample.name+" refusal preserves the live checkpoint",before==var_to_bytes(session.checkpoint()) and session.weather_configuration()==old_weather)
 var spatial: Dictionary=Weather.preset("spatial-gusty-v1")
 spatial.atmosphere_mode="standard_column"
 var both: Dictionary=Session.validate_weather_selection(spatial)
 check("spatial refusal takes precedence over vertical",both.code=="spatial",str(both))
 var column_turbulence: Dictionary=Weather.upgrade_column(Weather.preset("turbulent"),{atmosphere_mode="standard_column"})
 both=Session.validate_weather_selection(column_turbulence)
 check("vertical refusal takes precedence over turbulence",both.code=="vertical",str(both))
 session.sim.step()
 var at_tick: int=session.sim.tick
 var saved_weather: Dictionary=session.weather_configuration()
 var saved: PackedByteArray=var_to_bytes(session.checkpoint())
 check("static valid admission is independent of live tick",Session.validate_weather_selection(Weather.preset("steady")).ok)
 check("session rejects valid weather after advancing",not session.setup_weather(Weather.preset("steady")) and session.weather_error=="Weather changes require a new helicopter flight." and session.sim.tick==at_tick and session.weather_configuration()==saved_weather and var_to_bytes(session.checkpoint())==saved)
 check("invalid weather error precedes live-tick refusal",not session.setup_weather({}) and session.weather_error=="; ".join(WeatherField.build({}).errors) and var_to_bytes(session.checkpoint())==saved)
 session.free()
 print("HELI F13 weather admission: %d checks, %d failures"%[checks,failures])
 quit(1 if failures else 0)
