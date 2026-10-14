# HELI-16/25: playable rotorcraft route, reusing the production world, camera and menus.
extends Node3D
const Session = preload("res://sim/helicopter_flight_session.gd")
const Builder = preload("res://aircraft/hx700_model.gd")
const RotorVisual = preload("res://render/rotor/heli_rotor_visual.gd")
const World = preload("res://render/world/world.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Frames = preload("res://render/frames.gd")
const PilotCamera = preload("res://render/pilot_camera.gd")
const CameraRig = preload("res://render/camera/camera_rig.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
const Recorder = preload("res://sim/rotorcraft_recorder.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const Preferences = preload("res://app_state/preferences.gd")
signal pause_requested
signal overlay_settings_changed(settings: Dictionary)
var aircraft_id: String="xcell-60-research"
var field_path: String=FieldLoader.DEFAULT_PATH
var field: Dictionary={}
var weather_config: Dictionary={}
var lighting_config: Dictionary={}
var night_options: Dictionary=Preferences.NIGHT_DEFAULTS.duplicate(true)
var start_choice: String="airborne"
var interactive_start: bool=false
var latency_marker_enabled: bool=false
var overlays_enabled: bool=false
var overlay_settings: Dictionary={}
var startup_error: String=""
var _note: String=""
var session: Node
var recorder: RefCounted
var _camera: Camera3D
var _rig: RefCounted
var _airplane: Dictionary={}
var _rotors: Node3D
var _environment: Environment
var _field_world_lighting: bool=false
var _overlays: RefCounted
var _hud_layer: CanvasLayer
var _hud: Label
var _capture: bool=false
var _rotor_state: Dictionary={}
var _injected_user_args: Variant=null

func _ready() -> void:
 var args: Dictionary=_user_args()
 field_path=str(args.get("field",field_path))
 var loaded: Dictionary=FieldLoader.load_from(field_path)
 if not loaded.ok: _refuse("; ".join(loaded.errors)); return
 field=loaded.field
 var checked: Dictionary=LightingConfig.validate(LightingConfig.defaults() if lighting_config.is_empty() else lighting_config)
 if not checked.ok: _refuse("; ".join(checked.errors)); return
 lighting_config=checked.config
 var night_result: Dictionary=Preferences.validate_night_options(night_options) if interactive_start \
  else Preferences.night_options_from_args(args)
 if not night_result.get("ok",false): _refuse("; ".join(night_result.errors)); return
 night_options=night_result.options.duplicate(true)
 var snapshot: Dictionary=Lighting.snapshot(lighting_config) if lighting_config.mode!="legacy" else {}
 var world: Dictionary=World.build(self,field,Callable(),{},snapshot,night_options)
 _environment=world.environment
 _airplane=Builder.build()
 if _airplane.is_empty(): _refuse("HX-700 visual import failed"); return
 add_child(_airplane.root)
 _camera=PilotCamera.create(self,field.pilot)
 _rig=CameraRig.new(_camera,1.55)
 # Rotorcraft orientation needs more screen coverage than the shared 30-pixel airplane minimum.
 _rig.pilot_zoom=.35
 _rig.set_view(str(args.get("view","pilot")))
 session=Session.new()
 session.physics_enabled=not args.has("trace") and not args.has("capture")
 if not session.setup() or not session.set_field(field): _refuse(session.start_error+session.surface_error); return
 if not weather_config.is_empty() and not session.setup_weather(weather_config): _refuse(session.weather_error); return
 if args.has("alt"): session.set_start_altitude(float(args.alt))
 add_child(session)
 recorder=Recorder.new(session.sim)
 session.resetting.connect(func() -> void:
  if recorder.recording: recorder.stop())
 if not session.reset(): _refuse(session.start_error); return
 Builder.align_main_rotor_radius(_airplane,session.aircraft.context.main_model.rotor_radius_m)
 Builder.align_tail_rotor_radius(_airplane,session.aircraft.context.tail_model.tail_rotor_radius_m)
 _rotors=RotorVisual.attach(_airplane,self)
 _build_hud()
 print("HELICOPTER READY: ",session.aircraft.qualification)
 if args.has("trace"):
  _write_trace(args)
  return
 if args.has("capture"):
  _capture=true
  session.input_enabled=false
  var ticks: int=int(round(float(args.get("t",1.5))*Engine.physics_ticks_per_second))
  session.sim.inputs=PackedFloat64Array([float(args.get("roll",0)),float(args.get("pitch",0)),float(args.get("yaw",0)),float(args.get("throttle",session.commands.throttle))])
  for i: int in ticks:
   session.sim.step()
   if not session.is_flyable(): break
  if not session.is_flyable():
   printerr("helicopter capture stopped: ",session.pause_reason)
   get_tree().quit(1)
   return
  _present(0.0)
  if _rotors!=null: _rotors.update(_rotor_state,session.sim.time())
  await RenderingServer.frame_post_draw
  await RenderingServer.frame_post_draw
  var path: String=str(args.get("out","user://helicopter.png"))
  var error: Error=get_viewport().get_texture().get_image().save_png(path)
  print("HELICOPTER CAPTURE ",path," error=",error)
  get_tree().quit(error)

func _refuse(reason: String) -> void:
 startup_error=reason
 printerr("Helicopter startup refused: ",reason)
 if session!=null and not session.is_inside_tree():
  session.free()
  session=null
 set_process(false)
 if not interactive_start: get_tree().quit(1)

func _build_hud() -> void:
 _hud_layer=CanvasLayer.new()
 add_child(_hud_layer)
 _hud=Label.new()
 _hud.position=Vector2(20,18)
 _hud.add_theme_font_size_override("font_size",17)
 _hud.add_theme_color_override("font_shadow_color",Color.BLACK)
 _hud.add_theme_constant_override("shadow_offset_x",1)
 _hud.add_theme_constant_override("shadow_offset_y",1)
 _hud_layer.add_child(_hud)

func _process(dt: float) -> void:
 if not _capture: _present(minf(dt,.1))

func _present(dt: float) -> void:
 if session==null or session.sim.state.is_empty(): return
 var s: PackedFloat64Array=session.sim.interpolated(Engine.get_physics_interpolation_fraction())
 var pos: Vector3=Frames.ned_to_render(s.slice(0,3))
 var body: Basis=Frames.quat_to_render(s.slice(6,10))
 _airplane.root.transform=Frames.root_transform(body,pos,_airplane.cg_model_m)
 var out: Dictionary=session.telemetry()
 var collective: float=float(out.get("controls",{}).get("collective_75_rad",0.0))
 _rotor_state={omega_rad_s=session.sim.continuous[0]*session.aircraft.context.main_model.rotation_sense,a1=session.sim.continuous[1],b1=session.sim.continuous[2],collective=collective,
  tail_omega_rad_s=session.sim.continuous[0]*session.aircraft.context.tail_model.tail_to_main_speed_ratio*session.aircraft.context.tail_model.rotation_sense}
 if _rotors!=null: _rotors.update(_rotor_state,0.0 if session.sim.paused else dt)
 _rig.update(pos,_airplane.root.global_transform,body,dt,session.sim.paused,_ground_height)
 var wind: PackedFloat64Array=session.wind_at(session.sim.time())
 World.update(_environment,session.sim.time(),Frames.ned_to_render(wind),pos,_camera)
 var speed: float=sqrt(s[3]*s[3]+s[4]*s[4]+s[5]*s[5])
 _hud.text="RC HELICOPTER · EXPERIMENTAL RESEARCH TRAINER\nX-Cell reference physics · HX-700 visual\nAltitude %.2f m  Speed %.2f m/s  Rotor %.0f rpm\nCollective %.0f%%  %s  %s\nArrows: cyclic · A/D: yaw · W/S: collective\nR: restart hover · P: pause/resume · C: camera · Esc: menu\nI: normal/idle-up · G: trainer · H: zero-drive hold\n%s" % [
  -s[2],speed,session.sim.aux[0],session.commands.throttle*100.0,
  session.flight_mode,"TRAINER" if session.trainer_enabled else "DIRECT CYCLIC",
  session.pause_reason if not session.pause_reason.is_empty() else ("ZERO DRIVE HOLD" if session.zero_drive_hold else _note)]
 var main: Dictionary=out.get("aero",{}).get("main_rotor",{})
 if not main.is_empty() and (not main.get("within_identified_advance_ratio",false) or not main.get("within_small_flap_angle_range",false)):
  _hud.text+="\nOutside the identified main-rotor envelope."
 if session.calibration!=null: _hud.text+="\n"+str(session.calibration.prompt())
 if recorder.recording: _hud.text+="\nRecording %.1f s · T: stop"%recorder.seconds()
 elif not recorder.note.is_empty(): _hud.text+="\n"+recorder.note

func _ground_height(x: float,z: float) -> float:
 return Terrain.sample(-z,x,session.ground_surfaces)[0]

func set_overlays_visible(on: bool) -> void:
 if _hud_layer!=null: _hud_layer.visible=on

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  _rig.zoom(1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1)
 elif event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_RIGHT: _rig.drag(event.relative)
 elif event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_R: session.reset()
   KEY_P:
    if session.sim.paused: session.resume()
    else: session.sim.set_paused(true); session.pause_reason="paused"
   KEY_ESCAPE:
    if session.calibration!=null: session.cancel_calibration()
    else: pause_requested.emit()
   KEY_C: _rig.cycle(1)
   KEY_1: _rig.set_view("pilot")
   KEY_2: _rig.set_view("chase")
   KEY_5: _rig.set_view("orbit")
   KEY_EQUAL: _rig.zoom(1)
   KEY_MINUS: _rig.zoom(-1)
   KEY_Z: _rig.toggle_auto_zoom()
   KEY_G: session.trainer_enabled=not session.trainer_enabled
   KEY_H: session.zero_drive_hold=not session.zero_drive_hold
   KEY_I: session.flight_mode="idle_up" if session.flight_mode=="normal" else "normal"
   KEY_K: session.start_calibration()
   KEY_ENTER,KEY_KP_ENTER: session.advance_calibration()
   KEY_T:
    if recorder.recording: recorder.stop()
    else: recorder.start(session.trace_meta())

func apply_lighting_config(_raw: Variant) -> Dictionary:
 return {ok=false,errors=["End the helicopter flight to select different lighting on Home."]}

func set_night_options(profile: String, campfire: bool) -> bool:
 var checked: Dictionary=Preferences.validate_night_options({"field_lighting":profile,"campfire":campfire})
 if not checked.get("ok",false): return false
 night_options=checked.options.duplicate(true)
 return World.set_night_options(profile,campfire)

func _user_args() -> Dictionary:
 var args: Dictionary={}
 var source: PackedStringArray=OS.get_cmdline_user_args() if _injected_user_args==null else _injected_user_args
 for arg: String in source:
  var pair: PackedStringArray=arg.trim_prefix("--").split("=",true,1)
  args[pair[0]]=pair[1] if pair.size()==2 else "1"
 return args

func set_user_args(args: PackedStringArray) -> void:
 _injected_user_args=args.duplicate()

func _write_trace(args: Dictionary) -> void:
 session.input_enabled=false
 session.sim.process_mode=Node.PROCESS_MODE_DISABLED
 var duration: float=float(args.get("t",10.0))
 if not is_finite(duration) or duration<0.0: get_tree().quit(1); return
 var ticks: int=int(round(duration*Engine.physics_ticks_per_second))
 recorder.start(session.trace_meta())
 if not recorder.recording: get_tree().quit(1); return
 for i: int in ticks:
  session.sim.step()
  if not session.is_flyable() or not recorder.recording:
   printerr("helicopter trace stopped: ",session.pause_reason)
   recorder.recording=false
   get_tree().quit(1)
   return
 if recorder.trace.row_count()!=ticks+1: get_tree().quit(1); return
 var error: Error=recorder.stop(str(args.trace))
 get_tree().quit(error)
