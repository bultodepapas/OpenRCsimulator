# HELI-16/25: playable rotorcraft route, reusing the production world, camera and menus.
extends Node3D
var external_controller_selection: bool = false
const Session = preload("res://sim/helicopter_flight_session.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Builder = preload("res://aircraft/hx700_model.gd")
const RotorVisual = preload("res://render/rotor/heli_rotor_visual.gd")
const NightLights = preload("res://render/rotor/heli_night_lights.gd")
const CrashPresentation = preload("res://render/rotor/heli_crash_presentation.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
const MainRotor = preload("res://physics/rotorcraft/main_rotor.gd")
const Math3D = preload("res://physics/math3d.gd")
const World = preload("res://render/world/world.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Landscapes = preload("res://landscapes/catalog.gd")
const Frames = preload("res://render/frames.gd")
const PilotCamera = preload("res://render/pilot_camera.gd")
const CameraRig = preload("res://render/camera/camera_rig.gd")
const CameraSettings = preload("res://render/camera/camera_settings.gd")
const Magnifier = preload("res://render/camera/magnifier.gd")
const CameraCollision = preload("res://render/camera/camera_collision.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
const Recorder = preload("res://sim/rotorcraft_recorder.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const Preferences = preload("res://app_state/preferences.gd")
const ControllerActions = preload("res://input/controller_actions.gd")
const Prompts = preload("res://ui/controller_prompts.gd")
const HelicopterAudio = preload("res://audio/helicopter_audio.gd")
const SmokeSystem = preload("res://render/smoke/smoke_system.gd")
signal pause_requested
## UI-31 (UI-30 PS-7): R uses the shell's restart transaction, like the airplane route.
signal restart_requested
signal overlay_settings_changed(settings: Dictionary)
var aircraft_id: String="xcell-60-research"
var field_path: String=FieldLoader.DEFAULT_PATH
var landscape_id: String=Landscapes.DEFAULT_ID
var field: Dictionary={}
var weather_config: Dictionary={}
var lighting_config: Dictionary={}
var night_options: Dictionary=Preferences.NIGHT_DEFAULTS.duplicate(true)
var start_choice: String="ground"
var interactive_start: bool=false
var latency_marker_enabled: bool=false
## CAM-17: the player's camera settings from Home; empty on direct routes (--view keeps its meaning).
var camera_preferences: Dictionary={}
var overlays_enabled: bool=false
var overlay_settings: Dictionary={}
var startup_error: String=""
var _note: String=""
var session: Node
var recorder: RefCounted
var _camera: Camera3D
var _rig: RefCounted
var _magnifier: Magnifier # CAM-18
var _camera_obstacles: Dictionary={} # CAM-09: the scenery the cameras keep clear of
var _airplane: Dictionary={}
var _rotors: Node3D
var _night_kit: Node3D
var _crash_presentation: Node3D
var _aftermath_paused: bool=false
var _lighting_snapshot: Dictionary={}
var _environment: Environment
var _field_world_lighting: bool=false
var _overlays: RefCounted
var _hud_layer: CanvasLayer
var _hud: Label
var _capture: bool=false
var _rotor_state: Dictionary={}
var _rotor_state_previous: Dictionary={}
var _rotor_phase_previous := PackedFloat64Array([0.0, 0.0])
var _rotor_phase_current := PackedFloat64Array([0.0, 0.0])
var _rotor_omega_previous := PackedFloat64Array([0.0, 0.0])
var _rotor_phase_tick := -1
var _rotor_phase_rebase_pending := true
var _rotor_envelope_flags: Dictionary={
 "within_identified_advance_ratio": false,
 "within_small_flap_angle_range": false,
}
var _injected_user_args: Variant=null
var _soundscape_audio: Node

## HX-700 is a visual surrogate for the X-Cell reference. No verified engine
## outlet or show mount has been authored; rotor RPM cannot establish combustion.
## Keep the shared capability boundary explicit without guessing a physical exit.
func smoke_capabilities() -> Dictionary:
 return SmokeSystem.capabilities({}, "HX-700/X-Cell engine and outlet pairing is not established.")

func _ready() -> void:
 var args: Dictionary=_user_args()
 landscape_id=str(args.get("landscape",landscape_id))
 if not Landscapes.has(landscape_id): _refuse("Unknown landscape: "+landscape_id); return
 if field_path==FieldLoader.DEFAULT_PATH: field_path=Landscapes.entry(landscape_id).field_path
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
 if str(args.get("heli-lights","auto")) not in NightLights.MODES: _refuse("--heli-lights must be auto, all, nav or off"); return
 var snapshot: Dictionary=Lighting.snapshot(lighting_config) if lighting_config.mode!="legacy" else {}
 _lighting_snapshot=snapshot
 var build_field := func() -> void: add_child(Landscapes.build(landscape_id,field,snapshot))
 var world: Dictionary=World.build(self,field,build_field,{},snapshot,night_options)
 _environment=world.environment
 _airplane=Builder.build()
 if _airplane.is_empty(): _refuse("HX-700 visual import failed"); return
 add_child(_airplane.root)
 _camera=PilotCamera.create(self,field.pilot)
 _rig=CameraRig.new(_camera,1.55)
 # Rotorcraft orientation needs more screen coverage than the shared 30-pixel airplane minimum (Backspace keeps it).
 _rig.default_pilot_zoom=.35
 _rig.pilot_zoom=_rig.default_pilot_zoom
 _rig.set_view(str(args.get("view","pilot")))
 _magnifier=Magnifier.new()
 add_child(_magnifier)
 if not camera_preferences.is_empty(): CameraSettings.apply_at_start(_rig,camera_preferences)
 session=Session.new()
 session.external_controller_selection=external_controller_selection
 session.physics_enabled=not args.has("trace") and not args.has("capture")
 var selected: Dictionary=Catalog.entry(aircraft_id)
 if not Catalog.is_rotorcraft(aircraft_id) or not Catalog.can_fly(aircraft_id): _refuse("This helicopter has no qualified playable configuration."); return
 if not session.setup(str(selected.data),aircraft_id) or not session.set_field(field): _refuse(session.start_error+session.surface_error); return
 var obstacles: Dictionary=Landscapes.collision_world(landscape_id,field)
 if not obstacles.ok or not session.set_collision_world(obstacles.world):
  _refuse("Helicopter obstacle inventory refused: "+"; ".join(obstacles.errors)); return
 _camera_obstacles=obstacles.world
 # Existing technical captures/traces keep their explicit hover fixture unless a start is supplied.
 var requested_start: String=str(args.get("start","airborne" if args.has("trace") or args.has("capture") or args.has("alt") or not field.has("rotorcraft_pad") else start_choice))
 if not session.set_start_choice(requested_start): _refuse(session.start_error); return
 if args.has("alt") and session.start_choice=="ground": _refuse("Altitude applies only to the airborne helicopter start."); return
 if not weather_config.is_empty() and not session.setup_weather(weather_config): _refuse(session.weather_error); return
 if args.has("alt"): session.set_start_altitude(float(args.alt))
 add_child(session)
 recorder=Recorder.new(session.sim,session.trace_controls)
 session.resetting.connect(_on_session_resetting)
 session.sim.stepped.connect(_on_sim_stepped)
 if not session.reset(): _refuse(session.start_error); return
 Builder.align_main_rotor_radius(_airplane,session.aircraft.context.main_model.rotor_radius_m)
 Builder.align_tail_rotor_radius(_airplane,session.aircraft.context.tail_model.tail_rotor_radius_m)
 _crash_presentation=CrashPresentation.new()
 _crash_presentation.name="HelicopterCrashPresentation"
 add_child(_crash_presentation)
 if not _crash_presentation.configure(_airplane,session.aircraft.context):
  _refuse("Helicopter crash presentation could not prepare the source model."); return
 _crash_presentation.set_collision_world(obstacles.world)
 _rotors=RotorVisual.attach(_airplane,self)
 Magnifier.tag(_rotors) # CAM-18: rotor discs belong in the magnifier too
 _night_kit=NightLights.attach(_airplane)
 _night_kit.set_mode(str(args.get("heli-lights","auto")))
 _crash_presentation.set_night_kit(_night_kit)
 _build_hud()
 if str(args.get("soundscape","on")) != "off" and not args.has("trace") and not args.has("capture"):
  _soundscape_audio=HelicopterAudio.new()
  add_child(_soundscape_audio)
  _soundscape_audio.configure(self)
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
  _present(0.0, 1.0)
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

## CAM-09: share of a camera boom (render points) clear of the scenery's collision proxies.
func _camera_clearance(from: Vector3,to: Vector3) -> float:
 return CameraCollision.free_fraction(_camera_obstacles,from,to)

func _exit_tree() -> void:
 CameraRig.hold_cursor(false) # never leave the menus with a held cursor (CAM-29)

## CAM-17: Settings changed during a Home flight; the rig applies what changed.
func apply_camera_preferences(config: Dictionary) -> void:
 if camera_preferences.is_empty() or _rig==null: return
 CameraSettings.apply_changes(_rig,camera_preferences,config)
 camera_preferences=CameraSettings.normalized(config)

func _process(dt: float) -> void:
 CameraRig.release_cursor_if_up()
 if not _capture: _present(minf(dt,.1))

func _present(dt: float, requested_fraction: float=-1.0) -> void:
 if session==null or session.sim.state.is_empty(): return
 _ensure_rotor_phase_current()
 var fraction: float=clampf(requested_fraction if requested_fraction>=0.0 else Engine.get_physics_interpolation_fraction(),0.0,1.0)
 if session.sim.paused: fraction=1.0
 var s: PackedFloat64Array=session.sim.interpolated(fraction)
 var pos: Vector3=Frames.ned_to_render(s.slice(0,3))
 var body: Basis=Frames.quat_to_render(s.slice(6,10))
 _airplane.root.transform=Frames.root_transform(body,pos,_airplane.cg_model_m)
 var phase: PackedFloat64Array=_rotor_phase_at_fraction(fraction)
 var rotor_display: Dictionary=_rotor_state_at_fraction(fraction)
 if _rotors!=null: _rotors.update(rotor_display,phase[0],phase[1])
 var wind: PackedFloat64Array=session.wind_at(session.sim.time())
 var wreck_active: bool=not session.crash.is_empty() and _crash_presentation!=null
 var presentation_paused: bool=_aftermath_paused or not session.holds.is_empty()
 if wreck_active:
  if not _crash_presentation.active:
   _night_kit.update_visual(NightLights.sun_elevation(_lighting_snapshot,World.Atmosphere.state),World.Exposure.last,rotor_display,phase[0],phase[1],false,World.aircraft_local_seconds(lighting_config,session.sim.time()))
   var impact_body: PackedFloat64Array=session.crash.get("body",s)
   var impact_pose: Transform3D=Frames.root_transform(Frames.quat_to_render(impact_body.slice(6,10)),Frames.ned_to_render(impact_body.slice(0,3)),_airplane.cg_model_m)
   _crash_presentation.start(session.crash,impact_pose,_airplane.cg_model_m,Frames.ned_to_render(wind))
  _crash_presentation.update(dt,presentation_paused)
  _airplane.root.visible=false
  _rotors.visible=false
  _night_kit.visible=false
  pos=_crash_presentation.focus_position()
 # CAM-24: the chase settles its look-ahead from the state velocity (body FRD → render); a wreck focus has none.
 var velocity: Vector3=Vector3.INF if wreck_active else body*Frames.ned_to_render(s.slice(3,6))
 _rig.update(pos,Frames.root_transform(body,pos,_airplane.cg_model_m),body,dt,presentation_paused if wreck_active else session.sim.paused,_ground_height,velocity,
  _camera_clearance)
 if _magnifier!=null:
  _magnifier.mode=_rig.magnifier
  _magnifier.update(_camera,pos,1.55,_airplane.root,_rig.view=="pilot" and not wreck_active)
 World.update(_environment,session.sim.time(),Frames.ned_to_render(wind),pos,_camera)
 if _night_kit!=null and not wreck_active:
  _night_kit.update_visual(NightLights.sun_elevation(_lighting_snapshot,World.Atmosphere.state),World.Exposure.last,rotor_display,phase[0],phase[1],session.power.armed,World.aircraft_local_seconds(lighting_config,session.sim.time()))
 var speed: float=sqrt(s[3]*s[3]+s[4]*s[4]+s[5]*s[5])
 _hud.text=tr("RC HELICOPTER · EXPERIMENTAL RESEARCH TRAINER")+"\n"+tr("X-Cell reference physics · HX-700 visual")+"\n"
 _hud.text+=tr("Altitude %.2f m  Speed %.2f m/s  Rotor %.0f / %.0f rpm")%[-s[2],speed,session.sim.aux[0],session.aircraft.context.drive_model.governor_target_main_rad_s*60.0/(2.0*PI)]+"\n"
 _hud.text+=tr("Collective %.1f deg (stick %.0f%%) · %s · %s")%[session.collective_pitch()*180.0/PI,session.commands.throttle*100.0,session.flight_mode,tr(session.power_phase())]+"\n"
 if session.radio.connected:
  _hud.text+=controller_controls_text()+"\n"
 else:
  _hud.text+=tr("Arrows: cyclic · A/D: yaw · W/S: collective")+"\n"
  _hud.text+=tr("B: arm/disarm · H: hold/start · I: flight mode · G: trainer")+"\n"
 if _night_kit!=null:
  _hud.text+="L: "+tr("Night lights: "+_night_kit.active_mode)
  if _night_kit.mode=="auto": _hud.text+=" · "+tr("Night lights: auto")
  _hud.text+="\n"
 if not session.radio.connected: _hud.text+=tr("R: restart · P: pause/resume · C: camera · Esc: menu")+"\n"
 _hud.text+=tr("TRAINER") if session.trainer_enabled else tr("DIRECT CYCLIC")
 _hud.text+="\n"+(tr(session.pause_reason) if not session.pause_reason.is_empty() else _note)
 if wreck_active:
  _hud.text+="\n"+str(session.crash.component).replace("_"," ")+" · %.1f m/s · "%float(session.crash.normal_speed_mps)+tr("P: pause/resume wreck · R: restart")
 elif session.power_phase()=="DISARMED":
  _hud.text+="\n"+tr("Center cyclic/yaw and set zero pitch before arming; release hold and wait for governed RPM.")
 # Cold start/coast are expected lifecycle states; their low-RPM model label is
 # retained in telemetry without presenting normal startup as a pilot fault.
 if session.power_phase()=="GOVERNED" and (not _rotor_envelope_flags.within_identified_advance_ratio or not _rotor_envelope_flags.within_small_flap_angle_range):
  _hud.text+="\n"+tr("Outside the identified main-rotor envelope.")
 if session.calibration!=null: _hud.text+="\n"+str(session.calibration.prompt())
 if recorder.recording: _hud.text+="\nRecording %.1f s · T: stop"%recorder.seconds()
 elif not recorder.note.is_empty(): _hud.text+="\n"+recorder.note

func _ground_height(x: float,z: float) -> float:
 return Terrain.sample(-z,x,session.ground_surfaces)[0]

func _on_session_resetting() -> void:
 if _night_kit!=null: _night_kit.set_mode("auto")
 World.flow_to(0.0)
 if recorder!=null and recorder.recording: recorder.stop()
 _rotor_phase_rebase_pending=true
 _aftermath_paused=false
 if _crash_presentation!=null: _crash_presentation.reset()
 if _rig!=null: _rig.reset() # CAM-26: a restarted flight starts the chase settled, as on the airplane route
 if _airplane.get("root") is Node3D: _airplane.root.visible=true
 if _rotors!=null: _rotors.visible=true

func _on_sim_stepped(tick: int,t: float,body: PackedFloat64Array,_loads: PackedFloat64Array,inputs: PackedFloat64Array,_aux: PackedFloat64Array) -> void:
 if session==null or session.sim.continuous.size() not in [6,14] or body.size()!=13: return
 var omega: PackedFloat64Array=_rotor_shaft_speeds(session.sim.continuous)
 var rebase: bool=tick==0 or _rotor_phase_rebase_pending or tick!=_rotor_phase_tick+1
 var previous_telemetry: Dictionary=_rotor_state.duplicate()
 if rebase:
  _rotor_phase_previous=session.shaft_phase.duplicate()
  _rotor_phase_current=session.shaft_phase.duplicate()
  _rotor_omega_previous=omega
  _rotor_phase_tick=tick
  _rotor_phase_rebase_pending=false
 else:
  for index: int in 2:
   _rotor_phase_previous[index]=_rotor_phase_current[index]
   _rotor_phase_current[index]=session.shaft_phase[index]
  _rotor_omega_previous=omega
  _rotor_phase_tick=tick
 _cache_presentation_telemetry(body,session.sim.continuous,inputs,t)
 _rotor_state_previous=_rotor_state.duplicate() if rebase else previous_telemetry

func _ensure_rotor_phase_current() -> void:
 if session==null or session.sim.state.size()!=13 or session.sim.continuous.size() not in [6,14]: return
 if _rotor_phase_rebase_pending or _rotor_phase_tick!=session.sim.tick:
  _rotor_phase_previous=session.shaft_phase.duplicate()
  _rotor_phase_current=session.shaft_phase.duplicate()
  _rotor_omega_previous=_rotor_shaft_speeds(session.sim.continuous)
  _rotor_phase_tick=session.sim.tick
  _rotor_phase_rebase_pending=false
  _cache_presentation_telemetry(session.sim.state,session.sim.continuous,session.sim.inputs,session.sim.time())
  _rotor_state_previous=_rotor_state.duplicate()

func _rotor_state_at_fraction(fraction: float) -> Dictionary:
 var pose: Dictionary=_rotor_state.duplicate()
 var f: float=clampf(fraction,0.0,1.0)
 for key: String in pose:
  var current: float=float(pose[key])
  pose[key]=float(_rotor_state_previous.get(key,current))+(current-float(_rotor_state_previous.get(key,current)))*f
 return pose

func _rotor_phase_at_fraction(fraction: float) -> PackedFloat64Array:
 var f: float=clampf(fraction,0.0,1.0)
 return PackedFloat64Array([
  _rotor_phase_previous[0]+(_rotor_phase_current[0]-_rotor_phase_previous[0])*f,
  _rotor_phase_previous[1]+(_rotor_phase_current[1]-_rotor_phase_previous[1])*f,
 ])

func _rotor_shaft_speeds(continuous: PackedFloat64Array) -> PackedFloat64Array:
 var context: Dictionary=session.aircraft.context
 return PackedFloat64Array([
  continuous[0]*float(context.main_model.rotation_sense),
  continuous[0]*float(context.tail_model.tail_to_main_speed_ratio)*float(context.tail_model.rotation_sense),
 ])

func _cache_presentation_telemetry(body: PackedFloat64Array,continuous: PackedFloat64Array,inputs: PackedFloat64Array,t: float) -> void:
 var context: Dictionary=session.aircraft.context
 var state: PackedFloat64Array=body.duplicate()
 state.append_array(continuous.slice(0,6))
 var sticks: PackedFloat64Array=PackedFloat64Array([-inputs[1],inputs[0],inputs[2],2.0*inputs[3]-1.0])
 var controls: Dictionary=Electronics.fast_evaluate(context.electronics_model,state,sticks,session.flight_mode,session.trainer_enabled,session._trim)
 var collective: float=float(controls.get("collective_75_rad",0.0)) if controls.get("ok",false) else 0.0
 _rotor_state={
  "omega_rad_s":continuous[0]*float(context.main_model.rotation_sense),
  "tail_omega_rad_s":continuous[0]*float(context.tail_model.tail_to_main_speed_ratio)*float(context.tail_model.rotation_sense),
  "a1":continuous[1],"b1":continuous[2],"collective":collective,
 }
 _rotor_envelope_flags=main_rotor_envelope_flags(body,continuous,context,session.wind_at(t))

static func main_rotor_envelope_flags(body: PackedFloat64Array,continuous: PackedFloat64Array,context: Dictionary,wind_ned: PackedFloat64Array) -> Dictionary:
 var flags: Dictionary={
  "within_identified_advance_ratio":false,
  "within_small_flap_angle_range":false,
 }
 if body.size()!=13 or continuous.size() not in [6,14] or wind_ned.size()!=3 or not context.has("main_model"):
  return flags
 var q: PackedFloat64Array=PackedFloat64Array([body[6],body[7],body[8],body[9]])
 var norm_sq: float=q[0]*q[0]+q[1]*q[1]+q[2]*q[2]+q[3]*q[3]
 if not is_finite(norm_sq) or norm_sq<=1.0e-24:
  return flags
 var attitude: PackedFloat64Array=Math3D.q_normalized(q)
 var body_velocity: PackedFloat64Array=PackedFloat64Array([body[3],body[4],body[5]])
 var velocity_ned: PackedFloat64Array=Math3D.q_rotate(attitude,body_velocity)
 var air_velocity_body: PackedFloat64Array=Math3D.q_rotate(Math3D.q_conj(attitude),Math3D.sub(velocity_ned,wind_ned))
 var p: float=body[10]
 var q_rate: float=body[11]
 var r: float=body[12]
 var rotor: Dictionary=context.main_model
 var hub_air_x: float=air_velocity_body[0]+q_rate*float(rotor.hub_z_m)-r*float(rotor.hub_y_m)
 var hub_air_y: float=air_velocity_body[1]+r*float(rotor.hub_x_m)-p*float(rotor.hub_z_m)
 var omega: float=continuous[0]
 var radius: float=float(rotor.rotor_radius_m)
 if omega>0.0 and radius>0.0:
  var tip_speed: float=omega*radius
  if is_finite(tip_speed) and tip_speed>0.0:
   var mu_x: float=hub_air_x/tip_speed
   var mu_y: float=hub_air_y/tip_speed
   var crossflow: float=Math3D.sqrt_(hub_air_x*hub_air_x+hub_air_y*hub_air_y)
   flags.within_identified_advance_ratio=omega>=MainRotor.low_rpm_transition(rotor,crossflow)[1] and Math3D.sqrt_(mu_x*mu_x+mu_y*mu_y)<0.15
 flags.within_small_flap_angle_range=absf(continuous[1])<PI/18.0 and absf(continuous[2])<PI/18.0
 return flags

func set_overlays_visible(on: bool) -> void:
 if _hud_layer!=null: _hud_layer.visible=on

func controller_capabilities() -> Dictionary:
 return ControllerActions.HELICOPTER_CAPABILITIES.duplicate()

## Show the saved bindings, including raw radio channels, instead of keyboard-only instructions.
func controller_controls_text() -> String:
 var profile: Dictionary=session.radio.profile
 var bindings: Dictionary=ControllerActions.effective_bindings(profile,controller_capabilities())
 var family: String=str(profile.get("presentation",{}).get("glyph_family","auto"))
 var info: Dictionary={"name":session.radio.device_name}
 var lines: PackedStringArray=[]
 for group: Array in [["helicopter_arm","helicopter_hold"],["helicopter_mode","helicopter_trainer"],["camera_cycle","throttle_cut"],["restart_flight","pause"]]:
  var parts: PackedStringArray=[]
  for action: String in group:
   var binding: Dictionary=bindings.get(action,{"type":"unbound"})
   var prompt: String=Prompts.prompt(binding,family,info).text
   if profile.get("kind","")!="gamepad" and binding.get("type","")=="button":
    prompt=tr("Button %d")%int(binding.button)
   parts.append(prompt+": "+tr(str(ControllerActions.action_definition(action).label)))
  lines.append(" · ".join(parts))
 return "\n".join(lines)

func controller_action(action: String) -> bool:
 if session==null: return false
 match action:
  "lights_cycle": _cycle_night_lights()
  "helicopter_arm": session.toggle_motor_arm()
  "helicopter_hold": session.set_drive_hold(not session.zero_drive_hold)
  "helicopter_mode":
   if not session.sim.paused and session.holds.is_empty() and not session._controller_lost: session.request_flight_mode()
  "helicopter_trainer":
   if not session.sim.paused and session.holds.is_empty() and not session._controller_lost: session.trainer_enabled=not session.trainer_enabled
  "throttle_cut": session.set_controller_cut(true)
  "camera_cycle": _rig.cycle(1)
  "camera_previous": _rig.cycle(-1)
  "camera_pilot": _rig.set_view("pilot")
  "camera_chase": _rig.select_view("chase")
  "camera_orbit": _rig.set_view("orbit")
  "camera_zoom_in": _rig.zoom(1.0)
  "camera_zoom_out": _rig.zoom(-1.0)
  "camera_auto_zoom": _rig.toggle_auto_zoom()
  "view_reset": _rig.reset_view()
  "calibrate": session.start_calibration()
  "accept":
   if session.calibration!=null: session.advance_calibration()
   elif session.sim.paused: session.resume()
  "back","pause":
   if session.calibration!=null: session.cancel_calibration()
   else: pause_requested.emit()
  _: return false
 return true

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  # CAM-26: smooth wheels and trackpads send fractional notches, as on the airplane route.
  var notches: float=event.factor if event.factor>0.0 else 1.0
  _rig.zoom(notches if event.button_index==MOUSE_BUTTON_WHEEL_UP else -notches)
  get_viewport().set_input_as_handled()
 elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
  CameraRig.hold_cursor(event.pressed and _rig.view=="orbit") # CAM-29, as on the airplane route
 elif event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_RIGHT:
  _rig.drag(event.relative)
  get_viewport().set_input_as_handled()
 elif event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_R: _request_restart()
   KEY_P:
    if not session.crash.is_empty(): _aftermath_paused=not _aftermath_paused
    elif session.sim.paused: session.resume()
    else: session.sim.set_paused(true); session.pause_reason="paused"
   KEY_ESCAPE:
    session.cancel_calibration() # UI-31: Esc leaves a running wizard and shows Pause
    pause_requested.emit()
   KEY_C: _rig.cycle(-1 if event.shift_pressed else 1)
   KEY_1: _rig.set_view("pilot")
   KEY_2: _rig.select_view("chase") # again: 3D follow (CAM-09)
   KEY_4: _rig.set_view("flyby")
   KEY_5: _rig.set_view("orbit")
   KEY_EQUAL: _rig.zoom(1)
   KEY_MINUS: _rig.zoom(-1)
   KEY_BACKSPACE: _rig.reset_view()
   KEY_Z: _rig.toggle_auto_zoom()
   KEY_G: session.trainer_enabled=not session.trainer_enabled
   KEY_H: session.set_drive_hold(not session.zero_drive_hold)
   KEY_B: session.toggle_motor_arm()
   KEY_I: session.request_flight_mode()
   KEY_L: _cycle_night_lights()
   KEY_K: session.start_calibration()
   KEY_ENTER,KEY_KP_ENTER:
    if session.calibration!=null:
     session.advance_calibration()
     if session.calibration==null: pause_requested.emit() # UI-31: the result shows in Pause
   KEY_T:
    if recorder.recording: recorder.stop()
    else: recorder.start(session.trace_meta())

func _cycle_night_lights() -> void:
 if _night_kit!=null:
  _night_kit.cycle_mode()

func apply_lighting_config(_raw: Variant) -> Dictionary:
 return {ok=false,errors=["End the helicopter flight to select different lighting on Home."]}

func set_night_options(profile: String, campfire: bool, activation: String = "auto") -> bool:
 var checked: Dictionary=Preferences.validate_night_options({"field_lighting":profile,"field_activation":activation,"campfire":campfire})
 if not checked.get("ok",false): return false
 night_options=checked.options.duplicate(true)
 return World.set_night_options(profile,campfire,activation)

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

func _request_restart() -> void:
 if restart_requested.has_connections(): restart_requested.emit()
 else: session.reset() # standalone research scenes have no shell
