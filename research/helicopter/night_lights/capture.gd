extends SceneTree
const World=preload("res://render/world/world.gd")
const Model=preload("res://aircraft/hx700_model.gd")
const Lights=preload("res://render/rotor/heli_night_lights.gd")
const Rotors=preload("res://render/rotor/heli_rotor_visual.gd")
const Field=preload("res://data/field_loader.gd")
const Home=preload("res://ui/home_scene.gd")
const Config=preload("res://environment/time_of_day_config.gd")
# Presentation fixtures only: no flight/handling or physical photometry claim.
var directory="user://heli-night-captures"
var fixed_night:=false
func _initialize() -> void:
 run.call_deferred()
func run() -> void:
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--out-dir="): directory=arg.trim_prefix("--out-dir=")
  if arg=="--fixed-night": fixed_night=true
 directory=ProjectSettings.globalize_path(directory)
 DirAccess.make_dir_recursive_absolute(directory)
 var scene=Node3D.new()
 root.add_child(scene)
 var field: Dictionary=Field.load_from(Field.DEFAULT_PATH).field
 var snapshot: Dictionary={}
 if fixed_night:
  var config: Dictionary=Config.defaults()
  config.mode="astronomical"; config.local_seconds=0
  snapshot=Home.TimeOfDayLighting.snapshot(config)
 var env: Environment=World.build(scene,field,Callable(),{},snapshot,{field_lighting="airfield",campfire=false}).environment
 var model: Dictionary=Model.build()
 scene.add_child(model.root)
 var rotor=Rotors.attach(model,scene)
 var kit=Lights.attach(model)
 var camera=Camera3D.new()
 scene.add_child(camera)
 camera.current=true
 camera.near=.025
 camera.fov=32.0
 var cases=[
  {id="close-ground",height=0.0,eye=Vector3(2.1,.9,-1.8),speed=0.0},
  {id="close-hover",height=2.5,eye=Vector3(2.5,1.2,-1.8),speed=167.0},
  {id="upper-hover",height=2.5,eye=Vector3(-2.0,1.7,-2.0),speed=167.0},
  {id="lower-hover",height=2.5,eye=Vector3(-2.0,-1.5,-2.0),speed=167.0},
  {id="slow-spool",height=0.0,eye=Vector3(-2.0,1.7,-2.0),speed=12.0},
  {id="navigation",height=2.5,eye=Vector3(-2.0,1.7,-2.0),speed=167.0,mode="nav"},
  {id="lights-off",height=2.5,eye=Vector3(-2.0,1.7,-2.0),speed=167.0,mode="off"},
  {id="distance-50m",height=5.0,eye=Vector3(-35.0,0.0,-35.0),speed=167.0},
  {id="distance-100m",height=5.0,eye=Vector3(-70.0,0.0,-70.0),speed=167.0},
 ]
 for c: Dictionary in cases:
  model.root.position=Vector3(0,c.height,-6)
  var focus: Vector3=model.root.position+Vector3(0,.18,.25)
  camera.position=focus+c.eye
  camera.look_at(focus)
  var state={omega_rad_s=c.speed,tail_omega_rad_s=c.speed*4.66,a1=0.0,b1=0.0,theta_0=0.0}
  rotor.update(state,.7,1.1)
  World.update(env,1.03,Vector3.ZERO,focus,camera)
  kit.set_mode(c.get("mode","auto"))
  kit.update_visual(Lights.sun_elevation(snapshot,World.Atmosphere.state),World.Exposure.last,state,.7,1.1,c.speed>0)
  await RenderingServer.frame_post_draw
  await RenderingServer.frame_post_draw
  var error=root.get_texture().get_image().save_png(directory+"/"+c.id+".png")
  print("NIGHT CAPTURE ",c.id," exposure=",World.Exposure.last," error=",error)
 scene.free()
 if fixed_night: quit(); return
 var home=Home.new("xcell-60-research")
 root.add_child(home)
 await RenderingServer.frame_post_draw
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+"/home-night.png")
 home.free()
 for hour: int in [0,12]:
  var config: Dictionary=Config.defaults()
  config.mode="astronomical"
  config.local_seconds=hour*3600
  var fixed_home=Home.new("xcell-60-research",Field.DEFAULT_PATH,config)
  root.add_child(fixed_home)
  var fixed_kit: Node3D=fixed_home.airplane.root.get_node("HelicopterNightKit")
  print("FIXED ",hour," elevation=",Lights.sun_elevation(fixed_home._lighting)," exposure=",World.Exposure.last," active=",fixed_kit.active_mode)
  await RenderingServer.frame_post_draw
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(directory+"/fixed-"+str(hour)+".png")
  fixed_home.free()
 quit()
